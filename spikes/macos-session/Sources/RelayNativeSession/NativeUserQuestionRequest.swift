import Foundation

public enum UserQuestionIntent:String, Sendable { case ask, helpCurrent = "help_current" }

/// Controller-issued user input. It is never a transcript or source observation.
public struct NativeUserQuestionRequest:Sendable,Equatable {
    public let lease:PresentationLease
    public let requestID:UUID
    public let anchorEventSequence:UInt64
    public let emittedUptimeNanoseconds:UInt64
    public let intent:UserQuestionIntent
    public let question:String?
    public let baseRequestID:UUID?
    public func encodedJSON()throws->Data {
        try boundedActionJSON([
            "schemaVersion":.uint(1),"kind":.string("user_question_request"),
            "captureSessionID":.string(lease.captureSessionID.uuidString.lowercased()),
            "sessionEpoch":.uint(lease.sessionEpoch),"presentationGeneration":.uint(lease.presentationGeneration),
            "requestID":.string(requestID.uuidString.lowercased()),"anchorEventSequence":.uint(anchorEventSequence),
            "emittedUptimeNanoseconds":.uint(emittedUptimeNanoseconds),"intent":.string(intent.rawValue),
            "question":question.map(WireValue.string) ?? .null,
            "baseRequestID":baseRequestID.map{.string($0.uuidString.lowercased())} ?? .null])
    }
}

/// New cancellation lease plus the original target evidence for deny-only retirement.
public struct NativeAnswerCancelRequest:Sendable,Equatable {
    public let lease:PresentationLease
    public let requestID:UUID
    public let anchorEventSequence:UInt64
    public let emittedUptimeNanoseconds:UInt64
    public let targetRequestID:UUID
    public let targetLease:PresentationLease
    public func encodedJSON()throws->Data {
        try boundedActionJSON([
            "schemaVersion":.uint(1),"kind":.string("answer_cancel_request"),
            "captureSessionID":.string(lease.captureSessionID.uuidString.lowercased()),
            "sessionEpoch":.uint(lease.sessionEpoch),"presentationGeneration":.uint(lease.presentationGeneration),
            "requestID":.string(requestID.uuidString.lowercased()),"targetRequestID":.string(targetRequestID.uuidString.lowercased()),
            "anchorEventSequence":.uint(anchorEventSequence),"emittedUptimeNanoseconds":.uint(emittedUptimeNanoseconds)])
    }
    public func retirementJSON()throws->Data {
        try boundedActionJSON([
            "schemaVersion":.uint(1),"kind":.string("answer_request_retired"),
            "captureSessionID":.string(targetLease.captureSessionID.uuidString.lowercased()),
            "sessionEpoch":.uint(targetLease.sessionEpoch),"presentationGeneration":.uint(targetLease.presentationGeneration),
            "requestID":.string(targetRequestID.uuidString.lowercased()),"reasonCode":.string("request_retired")])
    }
}

private func boundedActionJSON(_ fields:[String:WireValue])throws->Data {
    let data=try JSONEncoder().encode(WireValue.object(fields))
    guard !data.isEmpty,data.count<=16_384 else{throw NativeSessionError.frameTooLarge}
    return data
}
