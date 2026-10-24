import Foundation

/// Issued under the capture controller lock. This is an explicit current-task
/// request, never an audio event or ASR transcript. No public initializer exists.
public struct NativeManualHelpRequest: Sendable, Equatable, Encodable {
    public let lease: PresentationLease
    public let requestID: UUID
    public let anchorEventSequence: UInt64
    public let emittedUptimeNanoseconds: UInt64
    public let question: String
    public func encode(to encoder: any Encoder) throws {
        try WireValue.object([
            "schemaVersion":.uint(1),"kind":.string("manual_help_request"),
            "captureSessionID":.string(lease.captureSessionID.uuidString.lowercased()),
            "sessionEpoch":.uint(lease.sessionEpoch),"presentationGeneration":.uint(lease.presentationGeneration),
            "requestID":.string(requestID.uuidString.lowercased()),"anchorEventSequence":.uint(anchorEventSequence),
            "emittedUptimeNanoseconds":.uint(emittedUptimeNanoseconds),"question":.string(question)
        ]).encode(to:encoder)
    }
    public func encodedJSON() throws -> Data {
        let data=try JSONEncoder().encode(self)
        guard !data.isEmpty,data.count<=16_384 else { throw NativeSessionError.frameTooLarge }
        return data
    }
}
