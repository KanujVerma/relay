import Foundation
import RelayNativeSession
import RelayContextComposition

public struct SessionPanelSnapshot: Sendable {
    public init() {}
    public var responsePreferencesRevision:UUID?
    public var question:String?;public var card:SessionCard?;public var status="Ready";public var replacement:UInt64=0
}

/// The reducer and native lease check commit synchronously on MainActor.
/// Native source invalidation happens before queued helper/UI delivery.
@MainActor public final class SessionPanelController {
    public private(set) var snapshot=SessionPanelSnapshot()
    public let latency=ResponseLatencyRecorder()
    private let authority:SessionPresentationAuthority
    private var session:(UUID,UInt64)?
    private var bound:PanelRequestBinding?;private var identity:(PythonTurnIdentity,String)?
    private var terminal=false;private var pending=false
    private var deadline:UInt64=0
    public var onChange: (() -> Void)?
    public init(authority:SessionPresentationAuthority) { self.authority=authority }
    public func observe(_ event:NativeSessionEvent) {
        if event.sourceCode==1 { return }
        latency.observeNative(event)
        switch event.kind {
        case .eou:
            if let request=PanelRequestBinding(event) { bind(request) }
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
    /// An issued manual binding follows the same reducer and actual lease gate.
    public func bind(_ request:PanelRequestBinding) {
        _=authority.withCurrentLease(request.lease) {
            latency.begin(request)
            session=(request.lease.captureSessionID,request.lease.sessionEpoch)
            bound=request;identity=nil;terminal=false;pending=false
            deadline=DispatchTime.now().uptimeNanoseconds+15_000_000_000
            snapshot.question=nil;snapshot.card=nil;snapshot.responsePreferencesRevision=nil;snapshot.status="Thinking";snapshot.replacement &+= 1;onChange?()
        }
        Task { [weak self] in
            try? await Task.sleep(for:.seconds(15));self?.expire(requestID:request.requestID)
        }
    }
    public func clear(status:String="Stopped") {
        latency.retire(outcome:"retired")
        bound=nil;identity=nil;terminal=true;pending=false;snapshot.question=nil;snapshot.card=nil;snapshot.responsePreferencesRevision=nil;snapshot.status=status;snapshot.replacement &+= 1;onChange?()
    }
    /// Negative-content-only updates may be reentrant from onChange while the
    /// positive commit holds authority. Keep the original binding/visible
    /// question; never reacquire authority or permit an old answer here.
    public func showPendingStatus(for request:PanelRequestBinding,status:String) {
        guard bound==request,!terminal,snapshot.card==nil else{return}
        snapshot.status=status;snapshot.replacement &+= 1;onChange?()
    }
    public func withholdGuideAnswer(for request:PanelRequestBinding,status:String) {
        guard bound==request else{return}
        latency.retire(outcome:"withheld")
        terminal=true;pending=false;snapshot.card=nil;snapshot.responsePreferencesRevision=nil
        snapshot.status=status;snapshot.replacement &+= 1;onChange?()
    }
    public func expire(requestID:UUID) {
        guard let bound,bound.requestID==requestID,!terminal else { return }
        latency.retire(outcome:"timeout")
        terminal=true;snapshot.card=nil;snapshot.responsePreferencesRevision=nil;snapshot.status="Answer timed out";snapshot.replacement &+= 1;onChange?()
    }
    @discardableResult public func accept(_ data:Data) throws -> Bool {
        let d=try SessionAnswerDecision(data:data)
        guard let b=bound,!terminal,d.sessionID==b.lease.captureSessionID,d.epoch==b.lease.sessionEpoch,d.generation==b.lease.presentationGeneration,d.requestID==b.requestID,d.eventSequence==b.eventSequence else { return false }
        if DispatchTime.now().uptimeNanoseconds>=deadline { expire(requestID:d.requestID);return false }
        if let identity,identity.0 != d.token || identity.1 != d.displayID { throw PanelBridgeError.malformed }
        if d.disposition=="pending",pending { return false }
        return authority.withCurrentLease(b.lease) {
            if let token=d.token,let displayID=d.displayID { identity=(token,displayID) }
            if d.disposition=="pending" { pending=true } else { terminal=true }
            snapshot.question=d.question.isEmpty ? nil:d.question;snapshot.card=d.card;snapshot.responsePreferencesRevision=d.responsePreferencesRevision
            switch d.disposition {
            case "answer":snapshot.status="Talking points"
            case "pending":snapshot.status="Thinking"
            case "clarify":
                switch d.reason {
                case "task_context_unresolved":snapshot.status="Clarify the updated task constraint"
                case "task_context_overflow":snapshot.status="Summarize the current problem and requirements"
                default:snapshot.status="Add confirmed background to answer this question"
                }
            case "abstain":snapshot.status=d.reason=="response_preferences_changed" ? "Response guide changed. Ask again.":["no_question","blank_question"].contains(d.reason) ? "Listening":d.reason=="manual_context_unavailable" ? "Ask a question first" : d.reason=="inference_disabled" ? "AI requests are off" : "No reliable answer available"
            default:snapshot.status="Answer unavailable"
            }
            snapshot.replacement &+= 1
            latency.accepted(d,binding:b,replacement:snapshot.replacement)
            onChange?()
        }
    }
}
