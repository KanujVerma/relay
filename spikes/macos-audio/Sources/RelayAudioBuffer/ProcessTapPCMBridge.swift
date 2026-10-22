import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Checked once, *before* an IOProc starts. No format conversion or allocations
/// on a Core Audio callback. ASR resampling belongs on a separate worker.
public struct ProcessTapPCMFormat: Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let isInterleaved: Bool

    public init(_ description: AudioStreamBasicDescription) throws {
        let flags = description.mFormatFlags
        guard description.mFormatID == kAudioFormatLinearPCM,
              (flags & kAudioFormatFlagIsFloat) != 0,
              (flags & kAudioFormatFlagIsBigEndian) == 0,
              description.mBitsPerChannel == 32,
              (1...2).contains(Int(description.mChannelsPerFrame)),
              description.mSampleRate.isFinite,
              description.mSampleRate > 0 else {
            throw ProcessTapError.unsupportedFormat
        }
        sampleRate = description.mSampleRate
        channelCount = Int(description.mChannelsPerFrame)
        isInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) == 0
    }
}

public enum ProcessTapError: LocalizedError {
    case invalidBundleID
    case usageDescriptionMissing
    case noMatchingProcesses
    case unsupportedFormat
    case alreadyCapturing
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidBundleID: return "Choose one explicit app bundle ID."
        case .usageDescriptionMissing:
            return "Missing NSAudioCaptureUsageDescription in the app bundle."
        case .noMatchingProcesses:
            return "No running Core Audio processes found for this app."
        case .unsupportedFormat:
            return "Selected process tap was not Float32 mono/stereo PCM."
        case .alreadyCapturing:
            return "A process audio capture is already active."
        case .unavailable:
            return "Selected app audio source is unavailable."
        }
    }
}

/// Only copies a borrowed AudioBufferList into the OWNED per-source ring.
/// No allocations, AVAudioPCMBuffer wrappers, file I/O or locks in the IOProc.
/// The callback's borrowed pointers MUST NOT escape this method.
public enum ProcessTapPCMBridge {
    @discardableResult
    public static func publish(
        _ input: UnsafePointer<AudioBufferList>,
        format: ProcessTapPCMFormat,
        queue: OwnedPCMQueue,
        hostTime: UInt64,
        generation: UInt64
    ) -> (accepted: Int, dropped: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: input)
        )
        let channels = format.channelCount
        let sampleBytes = MemoryLayout<Float>.stride
        guard channels == 1 || channels == 2 else { return (0, 1) }

        let frameCount: Int
        let first: UnsafePointer<Float>
        var second: UnsafePointer<Float>? = nil
        if format.isInterleaved {
            guard buffers.count == 1, let data = buffers[0].mData else {
                return (0, 1)
            }
            let bytesPerFrame = sampleBytes * channels
            guard Int(buffers[0].mDataByteSize) % bytesPerFrame == 0 else {
                return (0, 1)
            }
            frameCount = Int(buffers[0].mDataByteSize) / bytesPerFrame
            first = data.assumingMemoryBound(to: Float.self)
        } else {
            guard buffers.count == channels, let data = buffers[0].mData else {
                return (0, 1)
            }
            let bytes = Int(buffers[0].mDataByteSize)
            guard bytes % sampleBytes == 0 else { return (0, 1) }
            frameCount = bytes / sampleBytes
            first = data.assumingMemoryBound(to: Float.self)
            if channels == 2 {
                guard Int(buffers[1].mDataByteSize) == bytes,
                      let other = buffers[1].mData else { return (0, 1) }
                second = other.assumingMemoryBound(to: Float.self)
            }
        }
        if frameCount == 0 { return (0, 0) } // silence/no frames is not permission.
        // Bound untrusted hardware sizes before pointer math or packet copying.
        guard frameCount > 0, frameCount <= 262_144 else { return (0, 1) }
        var accepted = 0
        var dropped = 0
        var offset = 0
        while offset < frameCount {
            let frames = min(queue.maximumFrames, frameCount - offset)
            let ticks = AVAudioTime.hostTime(
                forSeconds: Double(offset) / format.sampleRate
            )
            let timestamp = hostTime == 0 ? 0 : hostTime &+ ticks
            let success: Bool
            if format.isInterleaved {
                success = queue.enqueueInterleaved(
                    samples: first.advanced(by: offset * channels),
                    frames: frames,
                    channels: channels,
                    sampleRate: format.sampleRate,
                    hostTime: timestamp,
                    streamGeneration: generation
                )
            } else {
                success = queue.enqueuePlanar(
                    first: first.advanced(by: offset),
                    second: second?.advanced(by: offset),
                    frames: frames,
                    sampleRate: format.sampleRate,
                    hostTime: timestamp,
                    streamGeneration: generation
                )
            }
            if success { accepted += 1 } else { dropped += 1 }
            offset += frames
        }
        return (accepted, dropped)
    }
}
