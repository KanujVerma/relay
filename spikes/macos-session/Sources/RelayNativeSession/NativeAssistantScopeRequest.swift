import Foundation

public enum AssistantScopeAction:String,Sendable {case open,close}

/// A native noncapture control. The presentation lease uses the existing
/// identity representation; it never describes an audio source or event.
public struct NativeAssistantScopeRequest:Sendable,Equatable {
    public let action:AssistantScopeAction
    public let lease:PresentationLease
    public let requestID:UUID
    public let controlSequence:UInt64
    public let emittedUptimeNanoseconds:UInt64
    public var assistantSessionID:UUID{lease.captureSessionID}

    public func encodedJSON()throws->Data {
        let fields:[String:WireValue]=[
            "schemaVersion":.uint(1),"kind":.string("assistant_scope_request"),"action":.string(action.rawValue),
            "requestID":.string(requestID.uuidString.lowercased()),
            "assistantSessionID":.string(assistantSessionID.uuidString.lowercased()),
            "sessionEpoch":.uint(lease.sessionEpoch),"presentationGeneration":.uint(lease.presentationGeneration),
            "controlSequence":.uint(controlSequence),"emittedUptimeNanoseconds":.uint(emittedUptimeNanoseconds)]
        let data=try JSONEncoder().encode(WireValue.object(fields))
        guard !data.isEmpty,data.count<=16_384 else{throw NativeSessionError.frameTooLarge}
        return data
    }
}
