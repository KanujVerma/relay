import Combine
import Foundation
import RelaySessionPanel

struct HistoryNoteDraftSnapshot:Equatable {
    var bindingID:UUID?
    var workspaceEpoch:UUID?
    var recordID:UUID?
    var expectedRevision:Int64?
    var title="",note=""
    var isDirty=false,isSaving=false
    var canSave:Bool{recordID != nil && isDirty && !isSaving && !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
}

/// One app-owned, bounded, unsaved editor. Its fields are display data, never
/// storage or request authority; saves still use the actual History CAS.
@MainActor final class HistoryNoteDraft:ObservableObject {
    @Published private(set) var snapshot=HistoryNoteDraftSnapshot()
    private var state=HistoryNoteDraftSnapshot()
    private var savedTitle="",savedNote=""
    private var editID=UUID(),publishing=false,pending=false
    private func publish(){
        pending=true;guard !publishing else{return}
        publishing=true;defer{publishing=false}
        while pending{pending=false;snapshot=state}
    }
    @discardableResult func stage(record:HistoryRecord,epoch:UUID,discardingChanges:Bool=false)->Bool{
        if state.workspaceEpoch==epoch,state.recordID==record.id,state.expectedRevision==record.revision{return true}
        guard !state.isSaving,(!state.isDirty || discardingChanges) else{return false}
        savedTitle=record.title;savedNote=record.note;editID=UUID()
        state=HistoryNoteDraftSnapshot(bindingID:UUID(),workspaceEpoch:epoch,recordID:record.id,
            expectedRevision:record.revision,title:record.title,note:record.note)
        publish();return state.workspaceEpoch==epoch && state.recordID==record.id
    }
    func editTitle(_ value:String){guard state.recordID != nil else{return};state.title=bounded(value,HistoryBounds.title);changed()}
    func editNote(_ value:String){guard state.recordID != nil else{return};state.note=bounded(value,HistoryBounds.note);changed()}
    private func changed(){editID=UUID();state.isDirty=state.title != savedTitle || state.note != savedNote;publish()}
    func discard(){guard state.recordID != nil else{return};state.title=savedTitle;state.note=savedNote;changed()}
    func invalidate(_ event:HistoryRecordsUnavailable){
        guard state.workspaceEpoch==event.retiredEpoch,let id=state.recordID,event.recordIDs?.contains(id) ?? true else{return}
        savedTitle="";savedNote="";editID=UUID();state=HistoryNoteDraftSnapshot();publish()
    }
    func save(using history:SessionHistoryCoordinator)async throws{
        try Task.checkCancellation()
        guard state.canSave,let binding=state.bindingID,let epoch=state.workspaceEpoch,let id=state.recordID,
              let revision=state.expectedRevision,history.allowsManualNoteDraft(id,revision:revision,epoch:epoch) else{throw HistoryError.stale}
        let capturedTitle=state.title,capturedNote=state.note,capturedEdit=editID
        state.isSaving=true;publish()
        do{
            guard state.bindingID==binding,history.allowsManualNoteDraft(id,revision:revision,epoch:epoch) else{throw HistoryError.stale}
            let receipt=try await history.saveNotes(id,expectedRevision:revision,title:capturedTitle,note:capturedNote)
            guard state.bindingID==binding,receipt.epoch==epoch,receipt.recordID==id,
                  receipt.title==capturedTitle,receipt.note==capturedNote,
                  history.allowsManualNoteDraft(id,revision:receipt.revision,epoch:epoch) else{throw HistoryError.stale}
            savedTitle=receipt.title;savedNote=receipt.note;state.expectedRevision=receipt.revision
            if editID==capturedEdit{state.title=receipt.title;state.note=receipt.note}
            state.isSaving=false;state.isDirty=state.title != savedTitle || state.note != savedNote;publish()
            guard state.bindingID==binding else{throw HistoryError.stale}
        }catch{
            if state.bindingID==binding{state.isSaving=false;publish()}
            throw error
        }
    }
    private func bounded(_ value:String,_ limit:Int)->String{
        var result="",size=0
        for scalar in value.unicodeScalars{let n=scalar.utf8.count;guard size+n<=limit else{break};result.unicodeScalars.append(scalar);size+=n}
        return result
    }
}
