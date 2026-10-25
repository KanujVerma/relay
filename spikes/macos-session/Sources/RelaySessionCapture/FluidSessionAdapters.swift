import CoreML
import FluidAudio
import Foundation
import RelayLocalASR
import RelayNativeSession

/// One recognizer actor per capture source. FluidAudio process() continues
/// ingesting after eouDetected; finish() returns all accumulated token IDs.
/// Ignore early EOU hints and finalize only after native VAD activity closure.
public actor FluidClosedActivityRecognizer: IncrementalActivityRecognizer {
    private let backend: any LocalEouRecognizer
    private var busy = false
    private var activeKey:RecognitionActivityKey?
    private var nextSample:UInt64=0
    public init(backend: any LocalEouRecognizer) { self.backend = backend }
    public static func local(root: URL) async throws -> FluidClosedActivityRecognizer {
        let backend = FluidEouRecognizer()
        try await backend.load(root: root, allowDownload: false, nvidiaModelLicenseAccepted: true)
        return FluidClosedActivityRecognizer(backend: backend)
    }
    public func recognize(_ samples: [Float]) async throws -> String {
        guard !busy,activeKey==nil, !samples.isEmpty, samples.count <= NativeSessionLimits.maximumActivitySamples, samples.allSatisfy(\.isFinite) else {
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
    public func begin(_ key:RecognitionActivityKey)async throws{
        guard !busy,activeKey==nil,[1,2].contains(key.sourceCode),key.generation>0,key.activityID>0 else{
            throw NativeSessionError.invalidFrame
        }
        busy=true;defer{busy=false}
        try Task.checkCancellation();await backend.reset();try Task.checkCancellation()
        activeKey=key;nextSample=key.startSample
    }
    public func append(_ samples:[Float],firstSample:UInt64,for key:RecognitionActivityKey)async throws{
        let (end,overflow)=firstSample.addingReportingOverflow(UInt64(samples.count))
        guard !busy,activeKey==key,!overflow,firstSample==nextSample,!samples.isEmpty,samples.count<=5120,
              samples.allSatisfy(\.isFinite),end>=key.startSample,
              end-key.startSample<=UInt64(NativeSessionLimits.maximumActivitySamples) else{throw NativeSessionError.invalidFrame}
        busy=true;defer{busy=false}
        try Task.checkCancellation()
        _=try await backend.accept(samples) // An early EOU hint never closes the native activity.
        try Task.checkCancellation();nextSample=end
    }
    public func finish(_ key:RecognitionActivityKey,endSample:UInt64)async throws->String{
        guard !busy,activeKey==key,nextSample==endSample,endSample>key.startSample else{throw NativeSessionError.invalidFrame}
        busy=true;defer{busy=false}
        var reset=false
        do{
            try Task.checkCancellation();let text=try await backend.finish()
            await backend.reset();reset=true;activeKey=nil;nextSample=0
            try Task.checkCancellation();return text
        }catch{
            if !reset{await backend.reset()};activeKey=nil;nextSample=0;throw error
        }
    }
    public func abort(_ key:RecognitionActivityKey)async throws{
        guard !busy,activeKey==key else{throw NativeSessionError.invalidFrame}
        busy=true;defer{busy=false}
        // Cleanup intentionally runs even when its original worker is cancelled.
        await backend.reset();activeKey=nil;nextSample=0
    }
}

/// Real pinned Silero VAD API. Its probability remains speech probability and
/// never enters the transcript confidence field. No default VadManager init is
/// used: that API can download models even when a local directory is supplied.
public actor FluidSpeechActivityDetector: RecognitionWatermarkDetector {
    public nonisolated let chunkSamples = VadManager.chunkSize
    private let manager: VadManager
    private var state: VadStreamState
    private var busy = false
    private let segmentation=VadSegmentationConfig.default
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
        let observation=try await observe(samples);return observation.boundaries
    }
    public func observe(_ samples:[Float])async throws->SpeechActivityObservation{
        guard !busy, samples.count == chunkSamples, samples.allSatisfy(\.isFinite) else {
            throw NativeSessionError.invalidFrame
        }
        busy = true; defer { busy = false }
        let result = try await manager.processStreamingChunk(samples, state: state,config:segmentation,returnSeconds:false)
        state = result.state
        var boundaries:[SpeechBoundary]=[]
        if let event=result.event{
            guard event.sampleIndex>=0 else{throw NativeSessionError.invalidFrame}
            boundaries=[SpeechBoundary(kind:event.isStart ? .start:.end,sampleIndex:UInt64(event.sampleIndex))]
        }
        let safe=try Self.recognitionSafeEnd(state:state,event:result.event,config:segmentation)
        return SpeechActivityObservation(boundaries:boundaries,processedSamples:UInt64(state.processedSamples),safePrefixEnd:safe)
    }
    /// Derived from the same pinned returned state/config, not a fixed lag guess.
    /// A pending candidate can survive arbitrarily long hysteresis-band input.
    static func recognitionSafeEnd(state:VadStreamState,event:VadStreamEvent?,config:VadSegmentationConfig)throws->UInt64?{
        let chunk=VadManager.chunkSize,processed=state.processedSamples
        let scaledPadding=config.speechPadding*Double(VadManager.sampleRate)
        guard processed>=chunk,processed%chunk==0,scaledPadding.isFinite,scaledPadding>=0,
              scaledPadding<Double(Int.max)-Double(chunk) else{throw NativeSessionError.invalidFrame}
        if let event,event.isEnd{
            guard !state.triggered,state.tempEndSample==nil else{throw NativeSessionError.invalidFrame}
            return nil
        }
        guard state.triggered else{
            guard state.tempEndSample==nil else{throw NativeSessionError.invalidFrame};return nil
        }
        var safe=processed-chunk
        if let candidate=state.tempEndSample{
            guard candidate>=chunk,candidate<=processed,candidate%chunk==0 else{throw NativeSessionError.invalidFrame}
            let (padded,overflow)=candidate.addingReportingOverflow(Int(scaledPadding))
            guard !overflow else{throw NativeSessionError.invalidFrame}
            safe=min(safe,padded-chunk)
        }
        return UInt64(safe)
    }
}
