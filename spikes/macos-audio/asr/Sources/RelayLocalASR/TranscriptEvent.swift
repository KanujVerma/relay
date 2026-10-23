import Foundation
import RelayAudioBuffer

/// Generated transcript text is unverified, even if the recognizer reports EOU.
/// This is not a verified user fact, interviewer identity or a trusted instruction.
public struct FinalTranscriptEvent: Sendable, Equatable {
    public enum Status: String, Sendable {
        case final
        case discontinuity
        case unavailable
    }

    public let status: Status
    public let source: PCMSource
    public let streamGeneration: UInt64
    public let segmentID: UInt64
    public let revision: UInt64
    public let startHostTime: UInt64?
    public let endHostTime: UInt64?
    public let finalizedUptimeNanoseconds: UInt64
    public let text: String?
    /// This EOU adapter does NOT have a calibrated word-confidence score.
    public let confidence: Double?

    /// A completed EOU without recognized words is a distinct terminal
    /// *outcome*, never silence or permission to keep an old answer visible.
    /// The versioned native wire decoder maps final + nil/blank text into
    /// blank_final. The real authorized host/turn bridge is still separate.
    public var isBlankEOUTerminal: Bool {
        status == .final
            && (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public init(
        status: Status, source: PCMSource, streamGeneration: UInt64,
        segmentID: UInt64, revision: UInt64 = 1,
        startHostTime: UInt64?, endHostTime: UInt64?,
        finalizedUptimeNanoseconds: UInt64,
        text: String? = nil, confidence: Double? = nil
    ) {
        self.status = status
        self.source = source
        self.streamGeneration = streamGeneration
        self.segmentID = segmentID
        self.revision = revision
        self.startHostTime = startHostTime
        self.endHostTime = endHostTime
        self.finalizedUptimeNanoseconds = finalizedUptimeNanoseconds
        self.text = status == .final ? text : nil
        self.confidence = confidence
    }
}

/// FluidAudio EOU returns text only at finish(), not from process().
/// A fake actor implementing this protocol enables tests with zero model files.
public protocol LocalEouRecognizer: Actor {
    func accept(_ mono16kSamples: [Float]) async throws -> Bool
    func finish() async throws -> String
    func reset() async
}
