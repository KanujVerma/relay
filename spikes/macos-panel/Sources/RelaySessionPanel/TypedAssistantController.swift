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
    public fileprivate(set) var canSendAsNew=false
    public fileprivate(set) var canHelpCurrent=false
    public fileprivate(set) var canStop=false
    public fileprivate(set) var isPreparing=false
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
            retirePreparation()
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
    private let preparationPorts:TypedSessionPreparationPorts?
    private final class Preparation {
        let id=UUID()
        let revision:UInt64
        let text:String
        let originalBasis:TypedQuestionBasis?
        let submissionBasis:TypedQuestionBasis?
        var retired=false
        var task:Task<Void,Never>?
        init(revision:UInt64,text:String,basis:TypedQuestionBasis?,asNew:Bool) {
            self.revision=revision;self.text=text;originalBasis=basis;submissionBasis=asNew ? nil:basis
        }
    }
    private var preparation:Preparation?
    private var status=""
    private var transcriptVisible=false
    private var publishingSnapshot=false
    private var queuedSnapshot:TypedAssistantSnapshot?
    private var scope:(UUID,UInt64)?
    private var records:[UUID:TypedQuestionBasis]=[:];private var order:[UUID]=[]
    private var chosen:TypedQuestionBasis?;private var missing:Set<UUID>=[]
    private var draftRevision:UInt64=0;private var restoring=false
    private var pending:UUID?;private var cancelling:Set<UUID>=[]
    private struct Submitted {let binding:PanelRequestBinding;let text:String;let basis:TypedQuestionBasis?;let clearedRevision:UInt64}
    private var submitted:[UUID:Submitted]=[:];private var submittedOrder:[UUID]=[]
    public init(session:@escaping()->PresentationLease?,currentRequest:@escaping()->PanelRequestBinding?,
                issue:@escaping(UserQuestionIntent,String?,UUID?)throws->NativeUserQuestionRequest,
                cancel:@escaping(PanelRequestBinding)async throws->AnswerCancellationResponse,
                preparation:TypedSessionPreparationPorts?=nil) {
        self.session=session;self.currentRequest=currentRequest;self.issue=issue;self.cancel=cancel
        preparationPorts=preparation
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
    private func makeSnapshot()->TypedAssistantSnapshot {
        let lease=synchronize()
        var next=TypedAssistantSnapshot()
        next.status=status;next.transcriptVisible=transcriptVisible;next.isPreparing=preparation != nil
        next.basis=chosen
        next.basisState=chosen.map{basis in
            guard let lease,sameSession(basis.binding,lease),records[basis.requestID] != nil,!missing.contains(basis.requestID) else{return .unavailable}
            return .retained
        } ?? .none
        let current=currentRequest()
        next.canSendAsNew=preparation == nil && (lease != nil || preparationPorts?.canPrepareSession() == true)
            && !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
            && draft.utf8.count<=500
            && !draft.unicodeScalars.contains(where:{disallowedTextScalar($0)})
        next.canSend=next.canSendAsNew && next.basisState != .unavailable
        next.canHelpCurrent=preparation == nil && lease != nil && current?.lease==lease && current.map{records[$0.requestID] != nil} == true
        next.canStop=lease != nil && current?.lease==lease && current?.requestID==pending
            && current.map{!cancelling.contains($0.requestID)} == true
        return next
    }
    public func refresh() {
        queuedSnapshot=makeSnapshot()
        guard !publishingSnapshot else{return}
        publishingSnapshot=true
        // @Published observers can synchronously issue a new command. Drain its
        // newer state after the current publication rather than overwriting it.
        while let next=queuedSnapshot{queuedSnapshot=nil;snapshot=next}
        publishingSnapshot=false
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
        pending=binding.requestID;status="Thinking";refresh()
    }
    public func observeNative(_ event:NativeSessionEvent){transcript.observe(event);refresh()}
    public func submitDraft(){submit(asNew:false)}
    private func submit(asNew:Bool) {
        let state=makeSnapshot()
        // Repeated Send coalesces with the original preparation, including its
        // cleanup. It cannot replace its text or silently rebase a newer edit.
        guard preparation==nil else{return}
        guard asNew ? state.canSendAsNew:state.canSend else{
            status=state.basisState == .unavailable ? "The original context is unavailable. Send as a new question.":"Enter a short question when the assistant is available."
            refresh();return
        }
        let text=draft,basis=asNew ? nil:chosen,revision=draftRevision
        guard session() != nil else{
            guard let ports=preparationPorts else{return}
            let owned=Preparation(revision:revision,text:text,basis:chosen,asNew:asNew)
            preparation=owned;status="Preparing assistant";refresh()
            owned.task=Task{[weak self] in await self?.performPreparation(owned,ports:ports)}
            return
        }
        do{try issueDraft(text:text,basis:basis,revision:revision)}
        catch{status="The question could not be sent. Your draft was kept.";refresh()}
    }
    private func issueDraft(text:String,basis:TypedQuestionBasis?,revision:UInt64)throws {
        let request=try issue(.ask,text,basis?.requestID)
        // Basis changes only after successful native issuance. This applies to
        // both direct and prepared Send as new, including issuer errors.
        if revision==draftRevision{restoring=true;chosen=nil;draft="";restoring=false}
        let binding=PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence)
        submitted[request.requestID]=Submitted(binding:binding,text:text,basis:basis,clearedRevision:draftRevision)
        submittedOrder.append(request.requestID)
        while submittedOrder.count>8{submitted.removeValue(forKey:submittedOrder.removeFirst())}
        observeRequest(binding)
    }
    private func preparationIsCurrent(_ owned:Preparation)->Bool {
        preparation === owned && !owned.retired && draftRevision==owned.revision
            && draft==owned.text && chosen==owned.originalBasis
    }
    private func performPreparation(_ owned:Preparation,ports:TypedSessionPreparationPorts)async {
        var ready:PresentationLease?
        var issued=false
        do {
            guard preparationIsCurrent(owned) else{throw CancellationError()}
            let lease=try await ports.prepareSession(owned.id,{[weak self,weak owned] in
                guard let self,let owned else{return false};return self.preparationIsCurrent(owned)
            })
            ready=lease
            try Task.checkCancellation()
            guard preparationIsCurrent(owned),session()==lease else{throw CancellationError()}
            try issueDraft(text:owned.text,basis:owned.submissionBasis,revision:owned.revision)
            issued=true
        }catch{
            if preparation === owned {
                status=owned.retired ? "Preparation cancelled. Your draft was kept.":"The assistant could not be prepared. Your draft was kept."
            }
        }
        if !issued,let ready{await ports.retireUnusedSession(owned.id,ready)}
        if preparation === owned{preparation=nil;refresh()}
        owned.task=nil
    }
    private func retirePreparation() {
        guard let preparation else{return}
        preparation.retired=true;preparation.task?.cancel()
    }
    public func cancelPreparation() {
        guard preparation != nil else{return}
        retirePreparation();status="Cancelling assistant preparation";refresh()
    }
    /// Waits for the original operation and any returned unused ready scope to
    /// actually close. Task cancellation alone never clears the busy state.
    public func waitForPreparationQuiescence()async {
        let task=preparation?.task;await task?.value
    }
    public func useLatestQuestionForDraft(){
        refresh()
        guard let current=currentRequest(),let basis=records[current.requestID] else{
            status="There is no new current question. Your original basis was kept.";refresh();return
        }
        retirePreparation();draftRevision &+= 1;chosen=basis;refresh()
    }
    public func sendDraftAsNewQuestion(){
        submit(asNew:true)
    }
    public func requestCurrentQuestionHelp() {
        guard makeSnapshot().canHelpCurrent,let current=currentRequest() else{return}
        do {
            let request=try issue(.helpCurrent,nil,current.requestID)
            observeRequest(PanelRequestBinding(lease:request.lease,requestID:request.requestID,eventSequence:request.anchorEventSequence))
        }catch{status="The current question changed. Try Help again.";refresh()}
    }
    public func observeDecision(_ decision:SessionAnswerDecision) {
        guard let lease=synchronize() else{return}
        let recovered=recoverUnavailableDraft(decision)
        guard let current=currentRequest(),current.lease==lease,matches(decision,current) else{
            if recovered{refresh()};return
        }
        if !decision.question.isEmpty{recordQuestion(current,question:decision.question)}
        if decision.disposition != "pending"{if pending==decision.requestID{pending=nil}}
        if !recovered{status=decision.disposition == "pending" ? "Thinking":decision.disposition == "answer" ? "Ready":"Answer unavailable"}
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
        status="The original context is unavailable. Your draft was kept."
        return true
    }
    public func cancelCurrentResponse()async {
        guard makeSnapshot().canStop,let target=currentRequest() else{return}
        cancelling.insert(target.requestID);status="Stopping response";refresh()
        defer{cancelling.remove(target.requestID);refresh()}
        do {
            let response=try await cancel(target)
            guard response.targetRequestID==target.requestID,response.captureSessionID==target.lease.captureSessionID,
                  response.sessionEpoch==target.lease.sessionEpoch,let lease=synchronize(),
                  response.captureSessionID==lease.captureSessionID,response.sessionEpoch==lease.sessionEpoch,
                  response.presentationGeneration==lease.presentationGeneration,
                  currentRequest()==nil || currentRequest()?.requestID==target.requestID else{return}
            if pending==target.requestID{pending=nil};status="Response stopped"
        }catch{
            if currentRequest()?.requestID==target.requestID{status="The response could not be stopped."}
        }
    }
    public func setTranscriptVisible(_ visible:Bool){transcriptVisible=visible;refresh()}
}
