import Foundation
import RelayNativeSession

/// Real host seams for an already controller-issued action. These closures do
/// not grant inference or image authority; original native/helper gates do.
@MainActor public struct ExplicitContextForwardingPorts {
    let shouldCapture:(NativeUserQuestionRequest)->Bool
    let capture:(NativeUserQuestionRequest)async->[Data]
    let retire:(PanelRequestBinding)throws->Void
    let sendQuestion:(NativeUserQuestionRequest,[Data])throws->Void
    let sendCancellation:(NativeAnswerCancelRequest)throws->Void
    public init(shouldCapture:@escaping(NativeUserQuestionRequest)->Bool,
                capture:@escaping(NativeUserQuestionRequest)async->[Data],
                retire:@escaping(PanelRequestBinding)throws->Void,
                sendQuestion:@escaping(NativeUserQuestionRequest,[Data])throws->Void,
                sendCancellation:@escaping(NativeAnswerCancelRequest)throws->Void) {
        self.shouldCapture=shouldCapture;self.capture=capture;self.retire=retire
        self.sendQuestion=sendQuestion;self.sendCancellation=sendCancellation
    }
}

public extension PanelRequestBinding {
    /// Deny-only evidence for this original binding, never a new request lease.
    func retirementJSON()throws->Data {
        let bytes=try JSONEncoder().encode(WireValue.object([
            "schemaVersion":.uint(1),"kind":.string("answer_request_retired"),
            "captureSessionID":.string(lease.captureSessionID.uuidString.lowercased()),
            "sessionEpoch":.uint(lease.sessionEpoch),"presentationGeneration":.uint(lease.presentationGeneration),
            "requestID":.string(requestID.uuidString.lowercased()),"reasonCode":.string("request_retired")]))
        guard bytes.count<=16_384 else{throw ContextForwardingError.oversizedContext}
        return bytes
    }
}
