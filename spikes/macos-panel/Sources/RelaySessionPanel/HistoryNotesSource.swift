import Foundation

public enum HistorySourceDenialReason:Sendable,Equatable{
    case locked,savingDisabled,ownerRetired,sessionStarting,recordChanged,deleted,expired,unavailable
}
/// Denial only. Receivers must never reconstruct membership or readiness from
/// these identifiers; original source/store ownership is checked separately.
public enum HistorySourceDenial:Sendable,Equatable{
    case workspace(retiredEpoch:UUID,reason:HistorySourceDenialReason)
    case record(retiredEpoch:UUID,recordID:UUID,reason:HistorySourceDenialReason)
    case source(retiredEpoch:UUID,recordID:UUID,captureID:String,source:TranscriptSource)
}

/// Only the original coordinator can install this store-issued read. No public
/// initializer, serialization, notification or DATA parser issues one.
@MainActor public final class HistoryNotesSource {
    public let data:HistoryNotesSourceData
    public let intentID:UUID
    let read:HistoryNotesStoreRead,store:HistoryStore,workspaceEpoch:UUID,selectionEpoch:UUID,gate:HistoryAdmission
    let current:@MainActor ()->Bool
    private let onRetired:@MainActor (HistoryNotesSource)->Void
    private var retired=false,notified=false
    init(read:HistoryNotesStoreRead,store:HistoryStore,workspaceEpoch:UUID,selectionEpoch:UUID,gate:HistoryAdmission,
         current:@escaping @MainActor ()->Bool,onRetired:@escaping @MainActor (HistoryNotesSource)->Void){
        self.read=read;self.store=store;self.workspaceEpoch=workspaceEpoch;self.selectionEpoch=selectionEpoch;self.gate=gate
        data=read.sourceData;intentID=read.intentID;self.current=current;self.onRetired=onRetired
    }
    func deny(){gate.retire();retired=true}
    func notifyRetired(){guard retired,!notified else{return};notified=true;onRetired(self)}
}
