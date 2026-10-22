import Foundation

/// Source-channel labels, NOT biometric speaker identification.
/// The remote channel may contain several people.
public enum PCMSource: UInt32, Sendable {
    case microphone = 1
    case remoteAudio = 2
}

/// A *detached copy* of audio, no dependence on a Core Audio callback pointer.
public struct PCMFrame: Sendable, Equatable {
    public let source: PCMSource
    public let streamGeneration: UInt64
    public let sequence: UInt64
    public let hostTime: UInt64
    public let sampleRate: Double
    public let channelCount: Int
    public let frameCount: Int

    /// Frame-interleaved Float32 in the source's native sampling rate.
    /// Resampling/downmixing belongs on a worker, NEVER in the audio callback.
    public let interleavedSamples: [Float]
}

/// The queue is single-producer/single-consumer, and each microphone and
/// selected remote app must have its OWN queue. Never attach two producers.
public enum PCMQueueError: Error, Equatable {
    case invalidConfiguration
    case allocationFailed
}

/// Plain-data header stored before a PCM packet inside TPCircularBuffer.
/// Packet byte counts are 8-byte aligned so subsequent headers stay aligned.
struct PacketHeader {
    static let magicConstant: UInt32 = 0x524C5941 // "RLYA"

    var magic: UInt32
    var totalBytes: UInt32
    var sequence: UInt64
    var hostTime: UInt64
    var generation: UInt64
    var sampleRate: Double
    var sourceCode: UInt32
    var channelCount: UInt32
    var frameCount: UInt32
    var reserved: UInt32

    static var bytes: Int { MemoryLayout<Self>.stride }
}
