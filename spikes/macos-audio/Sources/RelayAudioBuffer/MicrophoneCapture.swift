import AVFoundation
import Foundation

/// Explicit-consent microphone-only smoke test, adapted from the MIT-licensed
/// SystemAudioKit microphone capture pattern. The adaptation replaces its
/// WAV writer with an owned, bounded in-memory PCM queue.
///
/// This does NOT capture Zoom/system audio. That is a separate later slice.
@MainActor
public final class MicrophoneCapture {
    private let queue: OwnedPCMQueue
    private var engine: AVAudioEngine?
    private var generation: UInt64 = 0

    public enum CaptureError: Error {
        case alreadyRunning
        case authorizationDenied
        case unsupportedAudioFormat
    }

    public init(queue: OwnedPCMQueue) {
        self.queue = queue
    }

    public var isRunning: Bool { engine != nil }

    /// The CLI must have received an explicit user --mic request before
    /// calling this method. No background capture or implicit start.
    @discardableResult
    public func start() async throws -> UInt64 {
        guard engine == nil else { throw CaptureError.alreadyRunning }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw CaptureError.authorizationDenied
            }
        case .denied, .restricted:
            throw CaptureError.authorizationDenied
        @unknown default:
            throw CaptureError.authorizationDenied
        }

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        let numberOfChannels = Int(format.channelCount)
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              (1...2).contains(numberOfChannels),
              format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw CaptureError.unsupportedAudioFormat
        }

        generation &+= 1
        let currentGeneration = generation
        let queue = self.queue

        // Callback is on Core Audio's capture path: copy first, return fast.
        // Do not allocate audio arrays, write files, resample, lock or run ASR.
        input.installTap(
            onBus: 0, bufferSize: 1024, format: format
        ) { buffer, time in
            guard let channels = buffer.floatChannelData else { return }
            let right: UnsafePointer<Float>? = numberOfChannels == 2
                ? UnsafePointer(channels[1]) : nil
            _ = queue.enqueuePlanar(
                first: UnsafePointer(channels[0]),
                second: right,
                frames: Int(buffer.frameLength),
                sampleRate: format.sampleRate,
                hostTime: time.isHostTimeValid ? time.hostTime : 0,
                streamGeneration: currentGeneration
            )
        }
        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        engine = newEngine
        return generation
    }

    public func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }
}
