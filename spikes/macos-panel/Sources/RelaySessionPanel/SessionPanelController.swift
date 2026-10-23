import Foundation
import RelayNativeSession

public struct SessionPanelSnapshot: Sendable {
    public init() {}
    public var question:String?;public var card:SessionCard?;public var status="Ready";public var replacement:UInt64=0
}

/// The reducer and native lease check commit synchronously on MainActor.
/// Native source invalidation happens before queued helper/UI delivery.
@MainActor public final class SessionPanelController {
    public private(set) var snapshot=SessionPanelSnapshot()
    private let authority:SessionPresentationAuthority
    private var session:(UUID,UInt64)?
    private var bound:NativeSessionEvent?;private var identity:(PythonTurnIdentity,String)?
    private var terminal=false;private var pending=false
    private var deadline:UInt64=0
    public var onChange: (() -> Void)?
    public init(authority:SessionPresentationAuthority) { self.authority=authority }
    public func observe(_ event:NativeSessionEvent) {
        if event.sourceCode==1 { return }
        switch event.kind {
        case .eou:
            guard event.requestID != nil else { return }
            _=authority.withCurrentLease(event.lease) {
                session=(event.captureSessionID,event.sessionEpoch)
                bound=event;identity=nil;terminal=false;pending=false
                deadline=DispatchTime.now().uptimeNanoseconds+15_000_000_000
                snapshot.question=nil;snapshot.card=nil;snapshot.status="Thinking";snapshot.replacement &+= 1;onChange?()
            }
            Task { [weak self] in
                try? await Task.sleep(for:.seconds(15))
                self?.expire(requestID:event.requestID!)
            }
        case .speechStarted,.sessionStarted:
            _=authority.withCurrentLease(event.lease) {
                session=(event.captureSessionID,event.sessionEpoch);clear(status:"Listening")
            }
        case .sourceUnavailable,.discontinuity,.stopping,.stopped:
            guard let session,session.0==event.captureSessionID,session.1==event.sessionEpoch else { return }
            clear(status:"Stopped")
        case .speechEnded: break
        }
    }
    public func clear(status:String="Stopped") {
        bound=nil;identity=nil;terminal=true;pending=false;snapshot.question=nil;snapshot.card=nil;snapshot.status=status;snapshot.replacement &+= 1;onChange?()
    }
    public func expire(requestID:UUID) {
        guard let bound,bound.requestID==requestID,!terminal else { return }
        terminal=true;snapshot.card=nil;snapshot.status="Answer timed out";snapshot.replacement &+= 1;onChange?()
    }
    @discardableResult public func accept(_ data:Data) throws -> Bool {
        let d=try SessionAnswerDecision(data:data)
        guard let b=bound,!terminal,d.sessionID==b.captureSessionID,d.epoch==b.sessionEpoch,d.generation==b.presentationGeneration,d.requestID==b.requestID,d.eventSequence==b.eventSequence else { return false }
        if DispatchTime.now().uptimeNanoseconds>=deadline { expire(requestID:d.requestID);return false }
        if let identity,identity.0 != d.token || identity.1 != d.displayID { throw PanelBridgeError.malformed }
        if d.disposition=="pending",pending { return false }
        return authority.withCurrentLease(b.lease) {
            if let token=d.token,let displayID=d.displayID { identity=(token,displayID) }
            if d.disposition=="pending" { pending=true } else { terminal=true }
            snapshot.question=d.question.isEmpty ? nil:d.question;snapshot.card=d.card
            switch d.disposition {
            case "answer":snapshot.status="Talking points"
            case "pending":snapshot.status="Thinking"
            case "clarify":snapshot.status="Add confirmed background to answer this question"
            case "abstain":snapshot.status=["no_question","blank_question"].contains(d.reason) ? "Listening":d.reason=="inference_disabled" ? "AI requests are off" : "No reliable answer available"
            default:snapshot.status="Answer unavailable"
            }
            snapshot.replacement &+= 1;onChange?()
        }
    }
}
