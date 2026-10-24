import Foundation

public enum HistoryNotesCommitError:Error,Sendable{case indeterminate}
public struct HistoryNotesEditedTexts:Sendable{
    public let summary:[String],decisions:[String],nextSteps:[String]
    public init(summary:[String],decisions:[String],nextSteps:[String]){self.summary=summary;self.decisions=decisions;self.nextSteps=nextSteps}
}

/// Pure construction/reconstruction. Only HistoryStore can issue a save receipt.
enum HistoryNotesDocuments {
    static func selection(_ value:HistoryNotesSelectionData)->JSONNode{
        .object(["kind":.string(value.kind),"totalSavedRows":.number(String(value.totalSavedRows)),"includedRows":.number(String(value.includedRows)),"firstRowID":.string(value.firstRowID),"lastRowID":.string(value.lastRowID)])
    }
    static func make(_ output:HistoryNotesOutputData,source:HistoryNotesSourceData,noteID:UUID,noteRevision:Int64,savedAt:Int64,
                     generation:HistoryNotesGenerationData,modelID:String,origin:String="generated",editedAt:String?=nil)throws->HistoryNotesDocumentData{
        let g=generation
        let value:JSONNode = .object(["schemaVersion":.number("1"),"noteID":.string(noteID.uuidString.lowercased()),"noteRevision":.string(String(noteRevision)),
            "recordID":.string(source.recordID.uuidString.lowercased()),"sourceRecordRevision":.string(String(source.recordRevision)),"savedAtRecordRevision":.string(String(savedAt)),
            "selection":selection(source.selection),"sourceState":.string(source.recordState),"sourceGaps":.array(source.gaps.map{.string($0)}),"sourceDigest":.string(source.sourceDigest),
            "sourceRows":.array(source.rows.map{.object(["rowID":.string($0.rowID),"revision":.string(String($0.revision)),"textDigest":.string($0.textDigest)])}),
            "origin":.string(origin),"modelID":.string(modelID),"promptPolicy":.string("notes_source_v1"),
            "generation":.object(["scopeID":.string(g.scopeID.uuidString.lowercased()),"scopeEpoch":.string(String(g.scopeEpoch)),"operationID":.string(g.operationID.uuidString.lowercased()),"requestID":.string(g.requestID.uuidString.lowercased()),"requestSequence":.string(String(g.requestSequence)),"transferID":.string(g.transferID.uuidString.lowercased()),"completedAt":.string(g.completedAt)]),
            "editedAt":editedAt.map{.string($0)} ?? .null,"notes":try HistoryNotesJSON.decode(output.canonicalBytes,limit:HistoryNotesData.outputBytes)])
        return try HistoryNotesData.document(HistoryNotesData.canonical(value,limit:HistoryNotesData.documentBytes),source:source)
    }
    static func restore(_ raw:Data,record:HistoryRecord,rows:[HistoryFinal])throws->(HistoryNotesDocumentData,HistoryNotesSourceData){
        let node=try HistoryNotesJSON.decode(raw,limit:HistoryNotesData.documentBytes)
        guard case .object(let v)=node,case .array(let proofs)=v["sourceRows"],!proofs.isEmpty,proofs.count<=1024,
              case .string(let capturedRevision)=v["sourceRecordRevision"],case .string(let sourceState)=v["sourceState"],let gaps=v["sourceGaps"],let selected=v["selection"] else{throw HistoryError.invalid}
        let ids=try proofs.map{proof->String in
            let p=try proof.object(["rowID","revision","textDigest"])
            guard case .string(let id)=p["rowID"] else{throw HistoryError.invalid};return id
        }
        guard Set(ids).count==ids.count else{throw HistoryError.invalid}
        let wanted=Set(ids),actual=rows.filter{wanted.contains($0.id)}
        guard actual.map(\.id)==ids else{throw HistoryError.invalid}
        let sourceNode:JSONNode = .object(["schemaVersion":.number("1"),"recordID":.string(record.id.uuidString.lowercased()),"recordRevision":.string(capturedRevision),"selection":selected,
            "recordState":.string(sourceState),"gaps":gaps,
            "rows":.array(actual.map{.object(["id":.string($0.id),"revision":.string(String($0.revision.value)),"source":.string($0.source == .microphone ? "microphone":"selected_app_audio"),"text":.string($0.text)])})])
        let source=try HistoryNotesData.source(HistoryNotesData.canonical(sourceNode,limit:HistoryNotesData.sourceBytes))
        let document=try HistoryNotesData.document(raw,source:source)
        guard document.canonicalBytes==raw,document.recordID==record.id,document.savedAtRecordRevision<=record.revision else{throw HistoryError.invalid}
        return(document,source)
    }
    static func edited(_ texts:HistoryNotesEditedTexts,previous:HistoryNotesDocumentData,source:HistoryNotesSourceData)throws->HistoryNotesOutputData{
        let old=[previous.notes.summary,previous.notes.decisions,previous.notes.nextSteps],new=[texts.summary,texts.decisions,texts.nextSteps]
        guard zip(old,new).allSatisfy({pair in pair.0.count==pair.1.count}) else{throw HistoryError.invalid}
        var value:[String:JSONNode]=["schemaVersion":.number("1")]
        for (index,name) in ["summary","decisions","nextSteps"].enumerated(){
            value[name] = .array(zip(old[index],new[index]).map{item,text in .object(["text":.string(text),"citations":.array(item.citations.map{.object(["rowID":.string($0.rowID),"quote":.string($0.quote)])})])})
        }
        return try HistoryNotesData.output(HistoryNotesData.canonical(.object(value),limit:HistoryNotesData.outputBytes),source:source)
    }
    static func timestamp(_ date:Date)throws->String{
        guard date.timeIntervalSince1970.isFinite else{throw HistoryError.invalid}
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return try HistoryNotesData.timestamp(.string(formatter.string(from:date)))
    }
}
