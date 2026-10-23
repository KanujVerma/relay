import CoreML
import FluidAudio
import Foundation
import RelayLocalASR
import RelayNativeSession

/// One recognizer actor per capture source. FluidAudio process() continues
/// ingesting after eouDetected; finish() returns all accumulated token IDs.
/// Ignore early EOU hints and finalize only after native VAD activity closure.
public actor FluidClosedActivityRecognizer: ActivityRecognizer {
    private let backend: any LocalEouRecognizer
    private var busy = false
    public init(backend: any LocalEouRecognizer) { self.backend = backend }
    public static func local(root: URL) async throws -> FluidClosedActivityRecognizer {
        let backend = FluidEouRecognizer()
        try await backend.load(root: root, allowDownload: false, nvidiaModelLicenseAccepted: true)
        return FluidClosedActivityRecognizer(backend: backend)
    }
    public func recognize(_ samples: [Float]) async throws -> String {
        guard !busy, !samples.isEmpty, samples.count <= NativeSessionLimits.maximumActivitySamples, samples.allSatisfy(\.isFinite) else {
            throw NativeSessionError.invalidFrame
        }
        busy = true; defer { busy = false }
        await backend.reset()
        do {
            var offset = 0
            while offset < samples.count {
                try Task.checkCancellation()
                let end = min(offset + 5120, samples.count)
                _ = try await backend.accept(Array(samples[offset..<end]))
                offset = end
            }
            try Task.checkCancellation()
            let text = try await backend.finish()
            await backend.reset()
            try Task.checkCancellation()
            return text
        } catch {
            // This method retains single-flight ownership across reset. No
            // cancellation path resets CoreML underneath an active accept.
            await backend.reset()
            throw error
        }
    }
}

/// Real pinned Silero VAD API. Its probability remains speech probability and
/// never enters the transcript confidence field. No default VadManager init is
/// used: that API can download models even when a local directory is supplied.
public actor FluidSpeechActivityDetector: SpeechActivityDetector {
    public nonisolated let chunkSamples = VadManager.chunkSize
    private let manager: VadManager
    private var state: VadStreamState
    private var busy = false
    private init(manager: VadManager, state: VadStreamState) { self.manager = manager; self.state = state }
    public static func local(compiledModel: URL) async throws -> FluidSpeechActivityDetector {
        guard compiledModel.isFileURL, compiledModel.pathExtension == "mlmodelc",
              FileManager.default.fileExists(atPath: compiledModel.path) else { throw NativeSessionError.modelUnavailable }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: compiledModel, configuration: configuration)
        let manager = VadManager(config: VadConfig(debugMode: false), vadModel: model)
        return FluidSpeechActivityDetector(manager: manager, state: await manager.makeStreamState())
    }
    public func accept(_ samples: [Float]) async throws -> [SpeechBoundary] {
        guard !busy, samples.count == chunkSamples, samples.allSatisfy(\.isFinite) else {
            throw NativeSessionError.invalidFrame
        }
        busy = true; defer { busy = false }
        let result = try await manager.processStreamingChunk(samples, state: state, returnSeconds: false)
        state = result.state
        guard let event = result.event, event.sampleIndex >= 0 else { return [] }
        return [SpeechBoundary(kind: event.isStart ? .start : .end, sampleIndex: UInt64(event.sampleIndex))]
    }
}
