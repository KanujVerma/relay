import Combine
import Foundation
import RelayNativeSession
import RelayContextComposition

public struct TypedQuestionBasis:Sendable,Equatable {
    public let binding:PanelRequestBinding
    public let question:String
    public var requestID:UUID{binding.requestID}
}
public enum DraftBasisState:Sendable {case none,retained,unavailable}
public struct TypedAssistantSnapshot:Sendable {
    public fileprivate(set) var canSend=false
    public fileprivate(set) var canHelpCurrent=false
    public fileprivate(set) var canStop=false
    public fileprivate(set) var basis:TypedQuestionBasis?
    public fileprivate(set) var basisState:DraftBasisState = .none
    public fileprivate(set) var status=""
    public fileprivate(set) var transcriptVisible=false
}

/// Presentation of real issued ports. Draft/context records carry no source,
/// account, inference or publication authority. Construction performs no reads.
@MainActor public final class TypedAssistantController:ObservableObject {
    @Published public var draft="" {didSet{
        draftRevision &+= 1
        if !restoring {
            if draft.isEmpty{chosen=nil}
            else if oldValue.isEmpty{chosen=currentRequest().flatMap{records[$0.requestID]}}
        }
        refresh()
    }}
    @Published public private(set) var snapshot=TypedAssistantSnapshot()
    public let transcript=SessionTranscriptStore()
    private let session:()->PresentationLease?
    private let currentRequest:()->PanelRequestBinding?
    private let issue:(UserQuestionIntent,String?,UUID?)throws->NativeUserQuestionRequest
    private let cancel:(PanelRequestBinding)async throws->AnswerCancellationResponse
    private var scope:(UUID,UInt64)?
    private var records:[UUID:TypedQuestionBasis]=[:];private var order:[UUID]=[]
    private var chosen:TypedQuestionBasis?;private var missing:Set<UUID>=[]
    private var draftRevision:UInt64=0;private var restoring=false
    private var pending:UUID?;private var cancelling:Set<UUID>=[]
    private struct Submitted {let binding:PanelRequestBinding;let text:String;let basis:TypedQuestionBasis?;let clearedRevision:UInt64}
    private var submitted:[UUID:Submitted]=[:];private var submittedOrder:[UUID]=[]
    public init(session:@escaping()->PresentationLease?,currentRequest:@escaping()->PanelRequestBinding?,
                issue:@escaping(UserQuestionIntent,String?,UUID?)throws->NativeUserQuestionRequest,
                cancel:@escaping(PanelRequestBinding)async throws->AnswerCancellationResponse) {
        self.session=session;self.currentRequest=currentRequest;self.issue=issue;self.cancel=cancel
    }
    @discardableResult private func synchronize()->PresentationLease? {
        let lease=session()
        if scope?.0 != lease?.captureSessionID || scope?.1 != lease?.sessionEpoch {
            records.removeAll();order=[];missing=[];submitted.removeAll();submittedOrder=[];pending=nil
            scope=lease.map{($0.captureSessionID,$0.sessionEpoch)}
        }
        return lease
    }
    private func sameSession(_ binding:PanelRequestBinding,_ lease:PresentationLease)->Bool {
        binding.lease.captureSessionID==lease.captureSessionID && binding.lease.sessionEpoch==lease.sessionEpoch
    }
    public func refresh() {
        let lease=synchronize()
        snapshot.basis=chosen
        snapshot.basisState=chosen.map{basis in
            guard let lease,sameSession(basis.binding,lease),records[basis.requestID] != nil,!missing.contains(basis.requestID) else{return .unavailable}
            return .retained
        } ?? .none
        let current=currentRequest()
        snapshot.canSend=lease != nil && !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
            && draft.utf8.count<=500 && snapshot.basisState != .unavailable
            && !draft.unicodeScalars.contains(where:{disallowedTextScalar($0)})
        snapshot.canHelpCurrent=lease != nil && current?.lease==lease && current.map{records[$0.requestID] != nil} == true
        snapshot.canStop=lease != nil && current?.lease==lease && current?.requestID==pending
            && current.map{!cancelling.contains($0.requestID)} == true
    }
    public func recordQuestion(_ binding:PanelRequestBinding,question:String) {
        guard let lease=synchronize(),sameSession(binding,lease),!question.isEmpty,question.utf8.count<=500 else{return}
        if records[binding.requestID]==nil{order.append(binding.requestID)}
        records[binding.requestID]=TypedQuestionBasis(binding:binding,question:question)
        while order.count>8{let id=order.removeFirst();records.removeValue(forKey:id);missing.remove(id);submitted.removeValue(forKey:id)}
        refresh()
    }
    public func observeRequest(_ binding:PanelRequestBinding) {
        guard let lease=synchronize(),binding.lease==lease else{return}
        pending=binding.requestID;snapshot.status="Thinking";refresh()
    }
    public func observeNative(_ event:NativeSessionEvent){transcript.observe(event);refresh()}
    public func submitDraft() {
        refresh()
        guard snapshot.canSend else{
            snapshot.status=snapshot.basisState == .unavailable ? "The original context is unavailable. Send as a new question.":"Start a session and enter a short question."
            return
        }
        let text=draft,basis=chosen,revision=draftRevision
        do {
            let request=try issue(.ask,text,basis?.requestID)
            if revision==draftRevision{draft=""}
            let binding=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
            submitted[request.requestID]=Submitted(binding:binding,text:text,basis:basis,clearedRevision:draftRevision)
            submittedOrder.append(request.requestID)
            while submittedOrder.count>8{submitted.removeValue(forKey:submittedOrder.removeFirst())}
            observeRequest(binding)
        } catch {snapshot.status="The question could not be sent. Your draft was kept.";refresh()}
    }
    public func useLatestQuestionForDraft(){
        refresh()
        guard let current=currentRequest(),let basis=records[current.requestID] else{
            snapshot.status="There is no new current question. Your original basis was kept.";return
        }
        chosen=basis;refresh()
    }
    public func sendDraftAsNewQuestion(){chosen=nil;submitDraft()}
    public func requestCurrentQuestionHelp() {
        refresh();guard snapshot.canHelpCurrent,let current=currentRequest() else{return}
        do {
            let request=try issue(.helpCurrent,nil,current.requestID)
            observeRequest(PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence))
        }catch{snapshot.status="The current question changed. Try Help again.";refresh()}
    }
    public func observeDecision(_ decision:SessionAnswerDecision) {
        guard let lease=synchronize() else{return}
        let recovered=recoverUnavailableDraft(decision)
        guard let current=currentRequest(),current.lease==lease,matches(decision,current) else{
            if recovered{refresh()};return
        }
        if !decision.question.isEmpty{recordQuestion(current,question:decision.question)}
        if decision.disposition != "pending"{if pending==decision.requestID{pending=nil}}
        if !recovered{snapshot.status=decision.disposition == "pending" ? "Thinking":decision.disposition == "answer" ? "Ready":"Answer unavailable"}
        refresh()
    }
    private func matches(_ decision:SessionAnswerDecision,_ binding:PanelRequestBinding)->Bool {
        decision.sessionID==binding.lease.captureSessionID && decision.epoch==binding.lease.sessionEpoch
            && decision.generation==binding.lease.presentationGeneration && decision.requestID==binding.requestID
            && decision.eventSequence==binding.eventSequence
    }
    private func recoverUnavailableDraft(_ decision:SessionAnswerDecision)->Bool {
        guard decision.disposition=="abstain",decision.reason=="user_request_context_unavailable",
              let sent=submitted[decision.requestID],matches(decision,sent.binding) else{return false}
        submitted.removeValue(forKey:decision.requestID)
        if let basis=sent.basis{missing.insert(basis.requestID)}
        if draft.isEmpty,draftRevision==sent.clearedRevision {
            restoring=true;chosen=sent.basis;draft=sent.text;restoring=false
        }
        snapshot.status="The original context is unavailable. Your draft was kept."
        return true
    }
    public func cancelCurrentResponse()async {
        refresh();guard snapshot.canStop,let target=currentRequest() else{return}
        cancelling.insert(target.requestID);snapshot.status="Stopping response";refresh()
        defer{cancelling.remove(target.requestID);refresh()}
        do {
            let response=try await cancel(target)
            guard response.targetRequestID==target.requestID,response.captureSessionID==target.lease.captureSessionID,
                  response.sessionEpoch==target.lease.sessionEpoch,let lease=synchronize(),
                  response.captureSessionID==lease.captureSessionID,response.sessionEpoch==lease.sessionEpoch,
                  response.presentationGeneration==lease.presentationGeneration,
                  currentRequest()==nil || currentRequest()?.requestID==target.requestID else{return}
            if pending==target.requestID{pending=nil};snapshot.status="Response stopped"
        }catch{
            if currentRequest()?.requestID==target.requestID{snapshot.status="The response could not be stopped."}
        }
    }
    public func setTranscriptVisible(_ visible:Bool){snapshot.transcriptVisible=visible}
}
