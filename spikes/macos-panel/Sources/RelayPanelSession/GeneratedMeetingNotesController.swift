import Combine
import Dispatch
import Foundation
import RelaySessionPanel

private final class NotesActionDenial:@unchecked Sendable {
    private let lock=NSLock();private var denied=false
    var allowed:Bool{lock.withLock{!denied}}
    func deny(){lock.withLock{denied=true}}
}

/// App-owned actions over actual History and the existing owned helper. The
/// preparation port cannot replace source ownership or the typed save grant.
@MainActor final class GeneratedMeetingNotesController:ObservableObject {
    typealias Preparation = @MainActor (UUID,@escaping @MainActor ()->Bool)async throws->HelperTransport
    private enum Kind {case load,generate,edit,delete,citation}
    private struct ViewState {
        let epoch:UUID,id:UUID
        var revision:Int64,document:HistoryNotesDocumentData?,selection:HistoryNotesSelection = .fullSavedTranscript
    }
    private final class Work {
        let id=UUID(),kind:Kind,target:GeneratedMeetingNotesSnapshot,gate=NotesActionDenial(),deadline:UInt64
        var task:Task<Void,Error>?,source:HistoryNotesSource?,native:NativeNotesSessionController?,completion:NotesCompletedOperation?
        var acceptedRevision:Int64?,citation:HistoryFinal?
        var preparingHelper=false
        init(_ kind:Kind,_ target:GeneratedMeetingNotesSnapshot){self.kind=kind;self.target=target;deadline=DispatchTime.now().uptimeNanoseconds+30_000_000_000}
    }
    @Published private(set) var snapshot=GeneratedMeetingNotesSnapshot()
    private let history:SessionHistoryCoordinator,prepareHelper:Preparation,mayOfferGeneration:@MainActor ()->Bool
    private var view:ViewState?,work:Work?,phase:GeneratedMeetingNotesPhase = .idle,message:String?
    private var publishing=false,pending=false
    var isBusy:Bool{work != nil}
    init(history:SessionHistoryCoordinator,prepareHelper:@escaping Preparation,mayOfferGeneration:@escaping @MainActor ()->Bool){
        self.history=history;self.prepareHelper=prepareHelper;self.mayOfferGeneration=mayOfferGeneration
    }
    private func publish(){
        pending=true;guard !publishing else{return};publishing=true;defer{publishing=false}
        while pending{
            pending=false
            let selected=history.snapshot.selected,valid=view.map{history.snapshot.epoch==$0.epoch && selected?.record.id==$0.id && selected?.record.revision==$0.revision && history.snapshot.phase == .ready} ?? false
            let document=view?.document,source=work?.source?.data
            snapshot=GeneratedMeetingNotesSnapshot(workspaceEpoch:view?.epoch,recordID:view?.id,recordRevision:view?.revision,operationID:work?.id,
                phase:phase,document:document,selection:view?.selection ?? .fullSavedTranscript,
                totalSavedRows:valid ? (selected?.totalRows ?? 0):(document?.selection.totalSavedRows ?? 0),
                includedRows:source?.selection.includedRows ?? document?.selection.includedRows,
                sourceState:source?.recordState ?? document?.sourceState ?? selected?.record.state.rawValue,
                sourceGaps:source?.gaps ?? document?.sourceGaps ?? selected?.record.gaps.map(\.rawValue) ?? [],message:message,
                canGenerate:valid && !isBusy && mayOfferGeneration(),canCancel:isBusy,
                canEdit:valid && !isBusy && document != nil,canDelete:valid && !isBusy && document != nil)
        }
    }
    private func matches(_ target:GeneratedMeetingNotesSnapshot)->Bool{
        guard let view,history.snapshot.phase == .ready,history.snapshot.epoch==view.epoch,
              history.snapshot.selected?.record.id==view.id,history.snapshot.selected?.record.revision==view.revision else{return false}
        return target.workspaceEpoch==view.epoch && target.recordID==view.id && target.recordRevision==view.revision
            && target.operationID==work?.id && target.document?.noteID==view.document?.noteID
            && target.document?.noteRevision==view.document?.noteRevision
    }
    /// Only the original private intent and current read view are consulted.
    /// Actual History ownership is checked independently by prepare/commit.
    private func current(_ original:Work)->Bool{
        guard work === original,original.gate.allowed,original.task?.isCancelled != true,
              DispatchTime.now().uptimeNanoseconds<original.deadline,history.snapshot.phase == .ready,
              history.snapshot.epoch==original.target.workspaceEpoch,
              history.snapshot.selected?.record.id==original.target.recordID else{return false}
        let revision=history.snapshot.selected?.record.revision
        return revision==original.target.recordRevision || revision==original.acceptedRevision
            || revision==original.completion?.actualCommittedOutcome?.receipt.savedAtRecordRevision
    }
    private func check(_ original:Work)throws{try Task.checkCancellation();guard current(original) else{throw HistoryError.stale};try Task.checkCancellation()}
    private func begin(_ kind:Kind,_ target:GeneratedMeetingNotesSnapshot,body:@escaping @MainActor (Work)async throws->Void)throws->Work{
        guard work==nil,kind == .load || matches(target) else{throw HistoryError.stale}
        let original=Work(kind,target);work=original;phase = .preparing;message=nil
        original.task=Task{[self,original] in
            do{
                try check(original);try await body(original)
                await finish(original,error:nil)
            }catch{
                original.gate.deny();original.native?.cancel()
                await finish(original,error:error);throw error
            }
        }
        publish();return original
    }
    private func finish(_ original:Work,error:(any Error)?)async{
        if let native=original.native{await native.waitForQuiescence()}
        if let source=original.source{history.retireNotesSource(source)}
        guard work === original else{return};work=nil
        if let error{
            phase = .unavailable
            message=error is CancellationError ? "Stopped. Your saved notes are unchanged unless a save was already confirmed.":"The operation could not be confirmed. Reopen this saved session before trying again."
        }else{phase = .ready;message=nil}
        publish()
    }
    private func awaitOwned(_ original:Work)async throws{
        guard let task=original.task else{throw HistoryError.stale};let gate=original.gate
        try await withTaskCancellationHandler(operation:{try await task.value;try Task.checkCancellation()},onCancel:{gate.deny();task.cancel()})
    }
    private func cancel(_ original:Work){original.gate.deny();original.native?.cancel();original.task?.cancel()}
    func cancel(_ target:GeneratedMeetingNotesSnapshot){
        guard let original=work,target.operationID==original.id,target.workspaceEpoch==original.target.workspaceEpoch,
              target.recordID==original.target.recordID else{return};cancel(original);phase = .cancelling;publish()
    }
    func retireForOwnerChange(){if let original=work{cancel(original);phase = .cancelling;publish()}}
    func waitForQuiescence()async{while let original=work,let task=original.task{_=await task.result}}
    func retireAndWait()async{retireForOwnerChange();await waitForQuiescence()}
    /// The helper-only account retirement may be called from this exact
    /// preparer. It must not cancel or await itself before source admission.
    func retireHelperDependents(excludingPreparation intentID:UUID?)async{
        if let original=work,original.id==intentID,original.kind == .generate,original.preparingHelper,
           original.source==nil,original.native==nil,original.completion==nil,current(original){return}
        await retireAndWait()
    }

    /// Called only by an explicit record-open/refresh action, not rendering.
    func loadSelectedRecord()async throws{
        guard work==nil,history.snapshot.phase == .ready,let selected=history.snapshot.selected else{throw HistoryError.stale}
        let target=GeneratedMeetingNotesSnapshot(workspaceEpoch:history.snapshot.epoch,recordID:selected.record.id,recordRevision:selected.record.revision)
        view=ViewState(epoch:history.snapshot.epoch,id:selected.record.id,revision:selected.record.revision,document:nil)
        let original=try begin(.load,target){[self] original in
            let document=try await history.generatedNotes(selected.record.id,expectedRevision:selected.record.revision,epoch:original.target.workspaceEpoch!)
            try check(original);view?.document=document
        }
        try await awaitOwned(original)
    }
    func generate(_ target:GeneratedMeetingNotesSnapshot,selection:HistoryNotesSelection){
        guard mayOfferGeneration(),matches(target),work==nil else{return}
        do{
            _=try begin(.generate,target){[self] original in
                let helper:HelperTransport
                original.preparingHelper=true
                do{
                    helper=try await prepareHelper(original.id,{[weak self,weak original] in guard let self,let original else{return false};return self.current(original)})
                    original.preparingHelper=false
                }catch{original.preparingHelper=false;throw error}
                try check(original)
                guard let id=target.recordID,let revision=target.recordRevision else{throw HistoryError.stale}
                let source=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:selection,intentID:original.id,
                    isCurrent:{[weak self,weak original] in guard let self,let original else{return false};return self.current(original)},
                    onRetired:{[weak self] source in self?.sourceRetired(source)})
                original.source=source;try check(original)
                let native=NativeNotesSessionController(history:history,source:source,helper:helper,deadline:original.deadline,
                    isCurrent:{[weak self,weak original] in guard let self,let original else{return false};return self.current(original)},
                    onProgress:{[weak self,weak original] value in guard let self,let original,self.current(original) else{return};self.phase=value;self.publish()})
                original.native=native;original.completion=try await native.generate();try check(original)
                phase = .saving;publish();try check(original)
                let outcome=try await history.commitGeneratedNotes(original.completion!)
                original.acceptedRevision=outcome.receipt.savedAtRecordRevision;try check(original)
                guard outcome.cleanupComplete else{throw HistoryError.unavailable}
                view?.revision=outcome.receipt.savedAtRecordRevision;view?.document=outcome.document;view?.selection=selection
            }
        }catch{phase = .unavailable;message="Choose the current saved session before generating notes.";publish()}
    }
    private func sourceRetired(_ source:HistoryNotesSource){
        guard let original=work,original.source === source || (original.source==nil && source.intentID==original.id) else{return}
        original.native?.sourceRetired(source)
        // This is actual durable evidence only. Privacy events below still
        // deny the intent and no painting is permitted from this alone.
        if original.completion?.actualCommittedOutcome != nil{return}
        cancel(original)
    }
    func saveEdits(_ target:GeneratedMeetingNotesSnapshot,_ texts:HistoryNotesEditedTexts)async throws{
        guard let note=target.document,let id=target.recordID,let revision=target.recordRevision,let epoch=target.workspaceEpoch else{throw HistoryError.stale}
        let original=try begin(.edit,target){[self] original in
            phase = .saving;publish();try check(original)
            let outcome=try await history.editGeneratedNotes(id,expectedRecordRevision:revision,noteID:note.noteID,expectedNoteRevision:note.noteRevision,texts:texts,epoch:epoch,operationID:original.id)
            original.acceptedRevision=outcome.receipt.savedAtRecordRevision;try check(original)
            guard outcome.cleanupComplete else{throw HistoryError.unavailable}
            view?.revision=outcome.receipt.savedAtRecordRevision;view?.document=outcome.document
        }
        try await awaitOwned(original)
    }
    func deleteGenerated(_ target:GeneratedMeetingNotesSnapshot)async throws{
        guard let note=target.document,let id=target.recordID,let revision=target.recordRevision,let epoch=target.workspaceEpoch else{throw HistoryError.stale}
        let original=try begin(.delete,target){[self] original in
            phase = .saving;publish();try check(original)
            let outcome=try await history.deleteGeneratedNotes(id,expectedRecordRevision:revision,noteID:note.noteID,expectedNoteRevision:note.noteRevision,epoch:epoch,operationID:original.id)
            original.acceptedRevision=outcome.receipt.savedAtRecordRevision;try check(original)
            guard outcome.cleanupComplete else{throw HistoryError.unavailable}
            view?.revision=outcome.receipt.savedAtRecordRevision;view?.document=nil
        }
        try await awaitOwned(original)
    }
    func revealCitation(_ target:GeneratedMeetingNotesSnapshot,_ citation:HistoryNotesCitationData)async throws->HistoryFinal{
        guard work==nil,matches(target),let note=view?.document,
              (note.notes.summary+note.notes.decisions+note.notes.nextSteps).contains(where:{$0.citations.contains(citation)}) else{throw HistoryError.stale}
        let original=try begin(.citation,target){[self] original in
            for _ in 0..<16{
                try check(original)
                if let row=history.snapshot.selected?.rows.first(where:{$0.id==citation.rowID}){
                    guard row.text.contains(citation.quote) else{throw HistoryError.stale};original.citation=row;return
                }
                guard history.snapshot.selected?.nextOffset != nil else{throw HistoryError.stale}
                try await history.loadMoreTranscript();try check(original)
            }
            throw HistoryError.capacity
        }
        try await awaitOwned(original);guard let row=original.citation else{throw HistoryError.stale};return row
    }
    func handleSourceDenial(_ notice:HistorySourceDenial){
        let epoch:UUID,id:UUID?,privacy:Bool
        switch notice{
        case .workspace(let original,let reason):epoch=original;id=nil;privacy=[.locked,.ownerRetired,.deleted,.expired,.unavailable].contains(reason)
        case .record(let original,let record,let reason):epoch=original;id=record;privacy=[.deleted,.expired].contains(reason)
            if reason == .recordChanged,let original=work,original.target.workspaceEpoch==epoch,original.target.recordID==id,
               original.kind == .edit || original.kind == .delete || original.completion?.actualCommittedOutcome != nil{return}
        case .source(let original,let record,_,_):epoch=original;id=record;privacy=true
        }
        if let original=work,original.target.workspaceEpoch==epoch,id==nil || original.target.recordID==id{cancel(original)}
        if let current=view,current.epoch==epoch,id==nil || current.id==id{
            if privacy{view=nil};phase = .unavailable;message="This saved session changed. Open it again to continue.";publish()
        }
    }
}
