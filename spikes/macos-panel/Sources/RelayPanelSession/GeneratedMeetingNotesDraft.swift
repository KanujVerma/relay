import Combine
import Foundation
import RelaySessionPanel

struct GeneratedMeetingNotesDraftSnapshot {
    var bindingID:UUID?
    var target:GeneratedMeetingNotesSnapshot?
    var summary:[String]=[],decisions:[String]=[],nextSteps:[String]=[]
    var isSaving=false,message:String?
    var isDirty:Bool{
        guard let note=target?.document else{return false}
        return summary != note.notes.summary.map(\.text) || decisions != note.notes.decisions.map(\.text) || nextSteps != note.notes.nextSteps.map(\.text)
    }
}
/// App-owned bounded wording draft. It neither opens source data nor grants
/// persistence: the model still owns actual source and record/note CAS.
@MainActor final class GeneratedMeetingNotesDraft:ObservableObject {
    @Published private(set) var snapshot=GeneratedMeetingNotesDraftSnapshot()
    private var state=GeneratedMeetingNotesDraftSnapshot(),publishing=false,pending=false
    private func publish(){
        pending=true;guard !publishing else{return};publishing=true;defer{publishing=false}
        while pending{pending=false;snapshot=state}
    }
    @discardableResult func stage(_ target:GeneratedMeetingNotesSnapshot)->Bool{
        guard let note=target.document,target.workspaceEpoch != nil,target.recordID==note.recordID,target.recordRevision != nil else{return false}
        if let old=state.target,old.workspaceEpoch==target.workspaceEpoch,old.recordID==target.recordID,
            old.recordRevision==target.recordRevision,old.document?.noteID==note.noteID,old.document?.noteRevision==note.noteRevision{return true}
        guard !state.isSaving,!state.isDirty else{return false}
        state=GeneratedMeetingNotesDraftSnapshot(bindingID:UUID(),target:target,summary:note.notes.summary.map(\.text),decisions:note.notes.decisions.map(\.text),nextSteps:note.notes.nextSteps.map(\.text))
        publish();return state.target?.recordID==target.recordID
    }
    /// Reopening an existing editor preserves its original save version even
    /// when another window has advanced the currently displayed note.
    @discardableResult func prepareEditor(_ displayed:GeneratedMeetingNotesSnapshot)->Bool{
        if let original=state.target,displayed.document != nil,
           original.workspaceEpoch==displayed.workspaceEpoch,original.recordID==displayed.recordID,
           original.document?.noteID==displayed.document?.noteID{return true}
        return stage(displayed)
    }
    func edit(_ value:String,group:Int,index:Int){
        guard !state.isSaving,state.target != nil else{return}
        var result="",bytes=0
        for scalar in value.unicodeScalars{let n=scalar.utf8.count;guard bytes+n<=768 else{break};result.unicodeScalars.append(scalar);bytes+=n}
        if group==0,state.summary.indices.contains(index){state.summary[index]=result}
        else if group==1,state.decisions.indices.contains(index){state.decisions[index]=result}
        else if group==2,state.nextSteps.indices.contains(index){state.nextSteps[index]=result}
        else{return}
        state.message=nil;publish()
    }
    func discard(){state=GeneratedMeetingNotesDraftSnapshot();publish()}
    func invalidate(_ notice:HistorySourceDenial){
        guard let target=state.target,let epoch=target.workspaceEpoch,let id=target.recordID else{return}
        switch notice{
        case .workspace(let original,let reason):
            guard original==epoch,[.locked,.ownerRetired,.deleted,.expired].contains(reason) else{return}
        case .record(let original,let record,let reason):
            guard original==epoch,record==id,[.deleted,.expired].contains(reason) else{return}
        case .source(let original,let record,let capture,let source):
            guard original==epoch,record==id,target.document?.sourceRows.contains(where:{$0.rowID.hasPrefix(capture+":"+String(source.rawValue)+":")})==true else{return}
        }
        discard()
    }
    func save(using operation:@escaping @MainActor @Sendable (GeneratedMeetingNotesSnapshot,HistoryNotesEditedTexts)async throws->Void)async throws{
        guard state.isDirty,!state.isSaving,let binding=state.bindingID,let target=state.target else{throw HistoryError.stale}
        let changes=HistoryNotesEditedTexts(summary:state.summary,decisions:state.decisions,nextSteps:state.nextSteps)
        state.isSaving=true;state.message=nil;publish()
        guard state.bindingID==binding else{throw HistoryError.stale}
        do{
            try await operation(target,changes)
            guard state.bindingID==binding else{throw HistoryError.stale}
            discard()
            guard state.bindingID==nil else{throw HistoryError.stale}
        }catch{
            if state.bindingID==binding{state.isSaving=false;state.message="The save could not be confirmed. Your draft is kept; reopen this session before trying again.";publish()}
            throw error
        }
    }
}
