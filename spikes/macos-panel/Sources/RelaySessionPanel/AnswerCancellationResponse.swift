import Foundation
import RelayNativeSession

public struct AnswerCancellationResponse:Sendable,Equatable {
    public let requestID:UUID
    public let targetRequestID:UUID
    public let captureSessionID:UUID
    public let sessionEpoch:UInt64
    public let presentationGeneration:UInt64
    public let reasonCode:String
    public let quiesced:Bool
    public init(data:Data)throws {
        let fields=try StrictJSON.decode(data).object(["schemaVersion","kind","requestID","targetRequestID",
            "captureSessionID","sessionEpoch","presentationGeneration","resultRevision","reasonCode","quiesced"])
        guard try fields["schemaVersion"]!.uint()==1,try fields["kind"]!.string()=="answer_cancel_response",
              try fields["resultRevision"]!.uint()==2,try fields["quiesced"]!.boolean(),
              let id=UUID(uuidString:try fields["requestID"]!.string()),
              let target=UUID(uuidString:try fields["targetRequestID"]!.string()),
              let session=UUID(uuidString:try fields["captureSessionID"]!.string()) else{throw PanelBridgeError.malformed}
        let reason=try fields["reasonCode"]!.string(80)
        guard ["request_cancelled","already_finished"].contains(reason) else{throw PanelBridgeError.malformed}
        requestID=id;targetRequestID=target;reasonCode=reason;quiesced=true
        captureSessionID=session;sessionEpoch=try fields["sessionEpoch"]!.uint()
        presentationGeneration=try fields["presentationGeneration"]!.uint()
    }
}

/// Ownership is registered before the original issued action enters the queue.
public final class PendingAnswerCancellation:@unchecked Sendable {
    private let lock=NSLock()
    private var result:Result<AnswerCancellationResponse,any Error>?
    private var waiter:CheckedContinuation<AnswerCancellationResponse,any Error>?
    init(){}
    public func value()async throws->AnswerCancellationResponse {
        try await withCheckedThrowingContinuation{continuation in
            let ready=lock.withLock{()->Result<AnswerCancellationResponse,any Error>? in
                if let result{return result}
                guard waiter==nil else{return .failure(PanelBridgeError.malformed)}
                waiter=continuation;return nil
            }
            if let ready{continuation.resume(with:ready)}
        }
    }
    func finish(_ result:Result<AnswerCancellationResponse,any Error>) {
        let pending=lock.withLock{()->CheckedContinuation<AnswerCancellationResponse,any Error>? in
            guard self.result==nil else{return nil};self.result=result
            let pending=waiter;waiter=nil;return pending
        }
        pending?.resume(with:result)
    }
}
