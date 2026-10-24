import Foundation
import RelayNativeSession

public enum AssistantScopeStatus:String,Sendable {case ready,busy,unavailable,closed}

/// This is a receipt for an already issued native scope action. It cannot open
/// native admission; only its original controller can confirm the owned ticket.
public struct AssistantScopeResponse:Sendable,Equatable {
    public let action:AssistantScopeAction
    public let requestID:UUID
    public let assistantSessionID:UUID
    public let sessionEpoch:UInt64
    public let presentationGeneration:UInt64
    public let controlSequence:UInt64
    public let status:AssistantScopeStatus
    public let quiesced:Bool?
    public init(data:Data)throws {
        let node=try StrictJSON.decode(data)
        guard case .object(let raw)=node,let actionNode=raw["action"],
              let action=AssistantScopeAction(rawValue:try actionNode.string(16)) else{throw PanelBridgeError.malformed}
        var keys:Set<String>=["schemaVersion","kind","action","requestID","assistantSessionID",
            "sessionEpoch","presentationGeneration","controlSequence","status"]
        if action == .close{keys.insert("quiesced")}
        let fields=try node.object(keys)
        guard try fields["schemaVersion"]!.uint()==1,try fields["kind"]!.string()=="assistant_scope_response",
              let requestID=UUID(uuidString:try fields["requestID"]!.string()),
              let sessionID=UUID(uuidString:try fields["assistantSessionID"]!.string()),
              let status=AssistantScopeStatus(rawValue:try fields["status"]!.string(32)) else{throw PanelBridgeError.malformed}
        let epoch=try fields["sessionEpoch"]!.uint(),generation=try fields["presentationGeneration"]!.uint()
        let sequence=try fields["controlSequence"]!.uint()
        let quiesced=try fields["quiesced"]?.boolean()
        switch action {
        case .open:
            guard sequence==1,[.ready,.busy,.unavailable].contains(status) else{throw PanelBridgeError.malformed}
        case .close:
            guard sequence==2,(status == .closed && quiesced == true) || (status == .unavailable && quiesced == false) else{throw PanelBridgeError.malformed}
        }
        self.action=action;self.requestID=requestID;assistantSessionID=sessionID
        sessionEpoch=epoch;presentationGeneration=generation;controlSequence=sequence
        self.status=status;self.quiesced=quiesced
    }
}

/// One bounded owned response, registered before ordered ingress enqueue.
/// Cancellation of a caller is not a helper cleanup receipt.
public final class PendingAssistantScopeResponse:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<AssistantScopeResponse,any Error>?
    private var waiter:CheckedContinuation<AssistantScopeResponse,any Error>?
    init(){}
    public func value()async throws->AssistantScopeResponse {
        try await withCheckedThrowingContinuation{continuation in
            let ready=lock.withLock{()->Result<AssistantScopeResponse,any Error>? in
                if let result{return result}
                guard waiter==nil else{return .failure(PanelBridgeError.malformed)}
                waiter=continuation;return nil
            }
            if let ready{continuation.resume(with:ready)}
        }
    }
    func finish(_ result:Result<AssistantScopeResponse,any Error>) {
        let pending=lock.withLock{()->CheckedContinuation<AssistantScopeResponse,any Error>? in
            guard self.result==nil else{return nil}
            self.result=result;let pending=waiter;waiter=nil;return pending
        }
        pending?.resume(with:result)
    }
}
