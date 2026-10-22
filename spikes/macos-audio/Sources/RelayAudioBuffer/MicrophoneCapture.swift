import AVFoundation
import Foundation

/// Publishes an AVAudioPCMBuffer as bounded owned PCM chunks.
///
/// Audio hardware may deliver larger buffers than requested in installTap.
/// It is incorrect to simply pass the full frameLength to a fixed 2048-frame
/// ring packet and silently discard every callback. No dynamic arrays,
/// blocking, disk I/O or inference occur in this function.
public enum MicrophonePCMBridge {
    /// Construct the audio tap callback outside MicrophoneCapture's @MainActor
    /// isolation. AVAudioEngine calls the tap from a realtime audio thread,
    /// NOT the main actor, so a closure created directly in start() can cause
    /// Swift 6's dynamic actor executor check to report a data race.
    ///
    /// The explicit @Sendable type prevents inheriting main-actor isolation.
    /// Only the preallocated owned PCM queue and numeric generation are captured.
    public static func makeTapHandler(
        queue: OwnedPCMQueue,
        streamGeneration: UInt64
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, time in
            _ = publish(
                buffer: buffer,
                time: time,
                queue: queue,
                generation: streamGeneration
            )
        }
    }

    @discardableResult
    public static func publish(
        buffer: AVAudioPCMBuffer,
        time: AVAudioTime,
        queue: OwnedPCMQueue,
        generation: UInt64
    ) -> (accepted: Int, dropped: Int) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved,
              let data = buffer.floatChannelData,
              (1...2).contains(Int(buffer.format.channelCount)),
              buffer.format.sampleRate > 0 else {
            return (0, 1)
        }
        let totalFrames = Int(buffer.frameLength)
        let numberOfChannels = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate

        var accepted = 0
        var dropped = 0
        var offset = 0
        while offset < totalFrames {
            let count = min(queue.maximumFrames, totalFrames - offset)
            // Offset timestamps must reflect the real location in the source
            // buffer so later channel alignment can use host-clock timing.
            let hostTime: UInt64 = time.isHostTimeValid
                ? time.hostTime &+ AVAudioTime.hostTime(
                    forSeconds: Double(offset) / sampleRate
                ) : 0
            let right: UnsafePointer<Float>? = numberOfChannels == 2
                ? UnsafePointer(data[1].advanced(by: offset)) : nil
            let saved = queue.enqueuePlanar(
                first: UnsafePointer(data[0].advanced(by: offset)),
                second: right,
                frames: count,
                sampleRate: sampleRate,
                hostTime: hostTime,
                streamGeneration: generation
            )
            if saved { accepted += 1 } else { dropped += 1 }
            offset += count
        }
        return (accepted, dropped)
    }
}

/// Explicit-consent microphone-only smoke test, adapted from the MIT-licensed
/// SystemAudioKit microphone capture pattern. The adaptation replaces its
/// WAV writer with an owned, bounded in-memory PCM queue.
/// Full license and exact upstream SHA: ../../THIRD_PARTY_NOTICES.md
///
/// This does NOT capture Zoom/system audio. That is a separate later slice.
@MainActor
public final class MicrophoneCapture {
    private let queue: OwnedPCMQueue
    private var engine: AVAudioEngine?
    private var generation: UInt64 = 0

    public enum CaptureError: LocalizedError {
        case alreadyRunning
        case authorizationDenied
        case usageDescriptionMissing
        case unsupportedAudioFormat

        public var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "Microphone capture is already running."
            case .authorizationDenied:
                return "Microphone access was denied or restricted."
            case .usageDescriptionMissing:
                return "The executable is missing NSMicrophoneUsageDescription. " +
                       "Build and launch Packaging/RelayAudioSpike.app first."
            case .unsupportedAudioFormat:
                return "Only non-interleaved Float32 mono/stereo input is supported."
            }
        }
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

        // macOS can terminate unbundled command-line tools attempting the
        // first microphone permission request without this purpose key.
        // Fail closed with a useful error instead of invoking TCC unsafely.
        guard let purpose = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) as? String, !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CaptureError.usageDescriptionMissing
        }

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
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              (1...2).contains(Int(format.channelCount)),
              format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw CaptureError.unsupportedAudioFormat
        }

        generation &+= 1
        let currentGeneration = generation
        // Build a non-actor-isolated @Sendable callback before installing it.
        // The Core Audio callback must never be an @MainActor closure.
        let handler = MicrophonePCMBridge.makeTapHandler(
            queue: self.queue, streamGeneration: currentGeneration
        )
        input.installTap(
            onBus: 0, bufferSize: 1024, format: format, block: handler
        )
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
