import Foundation

public enum GeneratedMeetingNotesPhase:Sendable,Equatable {
    case idle,preparing,generating,saving,ready,cancelling,unavailable
}

/// Display state only. Actions always recheck original source and operation
/// ownership; these booleans cannot authorize generation or persistence.
public struct GeneratedMeetingNotesSnapshot:Sendable,Equatable {
    public let workspaceEpoch:UUID?,recordID:UUID?,recordRevision:Int64?,operationID:UUID?
    public let phase:GeneratedMeetingNotesPhase
    public let document:HistoryNotesDocumentData?
    public let selection:HistoryNotesSelection
    public let totalSavedRows:Int,includedRows:Int?
    public let sourceState:String?,sourceGaps:[String],message:String?
    public let canGenerate:Bool,canCancel:Bool,canEdit:Bool,canDelete:Bool
    public init(workspaceEpoch:UUID?=nil,recordID:UUID?=nil,recordRevision:Int64?=nil,operationID:UUID?=nil,
                phase:GeneratedMeetingNotesPhase = .idle,document:HistoryNotesDocumentData?=nil,
                selection:HistoryNotesSelection = .fullSavedTranscript,totalSavedRows:Int=0,includedRows:Int?=nil,
                sourceState:String?=nil,sourceGaps:[String]=[],message:String?=nil,
                canGenerate:Bool=false,canCancel:Bool=false,canEdit:Bool=false,canDelete:Bool=false) {
        self.workspaceEpoch=workspaceEpoch;self.recordID=recordID;self.recordRevision=recordRevision;self.operationID=operationID
        self.phase=phase;self.document=document;self.selection=selection
        self.totalSavedRows=totalSavedRows;self.includedRows=includedRows;self.sourceState=sourceState
        self.sourceGaps=sourceGaps;self.message=message;self.canGenerate=canGenerate;self.canCancel=canCancel
        self.canEdit=canEdit;self.canDelete=canDelete
    }
}
