import AVFoundation
import FluidAudio
import Foundation

/// A thin adapter around FluidAudio's *existing* 120M Parakeet EOU CoreML
/// implementation. Model loading is explicit, never hidden in a CI/test path.
/// The model WEIGHTS use the NVIDIA Open Model License, independent of the
/// Apache-2.0 FluidAudio Swift SDK. See THIRD_PARTY_NOTICES.md.
public actor FluidEouRecognizer: LocalEouRecognizer {
    public enum ModelError: LocalizedError {
        case licenseNotAcknowledged
        case modelDirectoryMissing
        case notPrepared
        case invalidAudio

        public var errorDescription: String? {
            switch self {
            case .licenseNotAcknowledged:
                return "An explicit NVIDIA Open Model License acknowledgment is " +
                       "required before model weights may be downloaded."
            case .modelDirectoryMissing:
                return "Expected local 320ms model bundles are missing. " +
                       "Use --download-model --accept-nvidia-license intentionally."
            case .notPrepared:
                return "Load the local model before starting capture."
            case .invalidAudio:
                return "Expected bounded, finite 16 kHz mono Float32 audio."
            }
        }
    }

    private let manager: StreamingEouAsrManager
    private var prepared = false

    /// 320ms mode uses a 630ms encoder window and is a quality/latency
    /// starting point, NOT a promise of 320ms end-to-end transcript delivery.
    public init() {
        manager = StreamingEouAsrManager(
            chunkSize: .ms320, eouDebounceMs: 1280
        )
    }

    /// A local directory is required. The HF downloader is used ONLY when
    /// explicitly permitted, after the caller acknowledges the model license.
    /// Offline load uses the actual pinned FluidAudio repo.folderName.
    public func load(
        root: URL, allowDownload: Bool,
        nvidiaModelLicenseAccepted: Bool
    ) async throws {
        guard root.isFileURL else { throw ModelError.modelDirectoryMissing }
        if allowDownload {
            guard nvidiaModelLicenseAccepted else {
                throw ModelError.licenseNotAcknowledged
            }
            try await manager.loadModels(to: root)
        } else {
            let leaf = root
                .appendingPathComponent("parakeet-eou-streaming")
                .appendingPathComponent("320ms")
            let required = [
                "streaming_encoder.mlmodelc",
                "decoder.mlmodelc",
                "joint_decision.mlmodelc",
                "vocab.json"
            ]
            guard required.allSatisfy({
                FileManager.default.fileExists(
                    atPath: leaf.appendingPathComponent($0).path
                )
            }) else {
                throw ModelError.modelDirectoryMissing
            }
            try await manager.loadModels(from: leaf)
        }
        prepared = true
    }

    /// EOU manager.process() returns EMPTY TEXT. It only reports an EOU flag;
    /// actual final text is returned by manager.finish(). No fabricated partials.
    public func accept(_ mono16kSamples: [Float]) async throws -> Bool {
        guard prepared else { throw ModelError.notPrepared }
        guard !mono16kSamples.isEmpty, mono16kSamples.count <= 32_000,
              mono16kSamples.allSatisfy(\.isFinite),
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(mono16kSamples.count)
              ),
              let data = buffer.floatChannelData else {
            throw ModelError.invalidAudio
        }
        buffer.frameLength = AVAudioFrameCount(mono16kSamples.count)
        mono16kSamples.withUnsafeBufferPointer { src in
            data[0].update(from: src.baseAddress!, count: mono16kSamples.count)
        }
        _ = try await manager.process(audioBuffer: buffer)
        return await manager.eouDetected
    }

    public func finish() async throws -> String {
        guard prepared else { throw ModelError.notPrepared }
        return try await manager.finish()
    }

    public func reset() async {
        await manager.reset()
    }
}
