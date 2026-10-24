import CryptoKit
import Foundation

/// Parsed DATA only. None of these values issue source, inference or save authority.
public enum HistoryNotesSelection:Sendable,Equatable {
    case fullSavedTranscript
    case excerpt(firstRowID:String,lastRowID:String)
}
public struct HistoryNotesSelectionData:Sendable,Equatable {
    public let kind:String,totalSavedRows:Int,includedRows:Int,firstRowID:String,lastRowID:String
}
public struct HistoryNotesRowData:Sendable,Equatable {
    public let rowID:String,revision:UInt64,source:String,text:String,textDigest:String
}
public struct HistoryNotesSourceData:Sendable,Equatable,CustomStringConvertible {
    public let recordID:UUID,recordRevision:Int64,selection:HistoryNotesSelectionData,recordState:String,gaps:[String],rows:[HistoryNotesRowData],rawBytes:Data,sourceDigest:String
    public var description:String{"HistoryNotesSourceData(<redacted>)"}
}
public struct HistoryNotesCitationData:Sendable,Equatable {public let rowID:String,quote:String}
public struct HistoryNotesItemData:Sendable,Equatable {public let text:String,citations:[HistoryNotesCitationData]}
public struct HistoryNotesOutputData:Sendable,Equatable,CustomStringConvertible {
    public let summary:[HistoryNotesItemData],decisions:[HistoryNotesItemData],nextSteps:[HistoryNotesItemData],canonicalBytes:Data
    public var description:String{"HistoryNotesOutputData(<redacted>)"}
}
public struct HistoryNotesRowProofData:Sendable,Equatable {public let rowID:String,revision:UInt64,textDigest:String}
public struct HistoryNotesGenerationData:Sendable,Equatable {
    public let scopeID:UUID,scopeEpoch:UInt64,operationID:UUID,requestID:UUID,requestSequence:UInt64,transferID:UUID,completedAt:String
}
public struct HistoryNotesDocumentData:Sendable,Equatable,CustomStringConvertible {
    public let noteID:UUID,noteRevision:Int64,recordID:UUID,sourceRecordRevision:Int64,savedAtRecordRevision:Int64
    public let selection:HistoryNotesSelectionData,sourceState:String,sourceGaps:[String],sourceDigest:String,sourceRows:[HistoryNotesRowProofData]
    public let origin:String,modelID:String,promptPolicy:String,generation:HistoryNotesGenerationData,editedAt:String?,notes:HistoryNotesOutputData,canonicalBytes:Data
    public var description:String{"HistoryNotesDocumentData(<redacted>)"}
}

public enum HistoryNotesData {
    public static let sourceBytes=2*1024*1024,documentBytes=256*1024,outputBytes=8192
    static let gaps=["sourceUnavailable","sequenceGap","capacity","storageFailure","savingStopped","interrupted","captureFailure","sourceDeleted","invalidObservation","unfinishedSpeech","captureEndUnknown"]
    private static let sourceSpace:Set<UInt32>=[9,10,11,12,13,32,0x85,0xa0,0x1680,0x2000,0x2001,0x2002,0x2003,0x2004,0x2005,0x2006,0x2007,0x2008,0x2009,0x200a,0x2028,0x2029,0x202f,0x205f,0x3000]
    static func digest(_ bytes:Data)->String{SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()}
    static func sourceDigest(_ raw:Data)->String{var domain=Data("relay.notes.source.v1\n".utf8);domain.append(raw);return digest(domain)}
    private static func rawString(_ node:JSONNode?,limit:Int)throws->String{
        guard case .string(let s)=node,s.utf8.count<=limit else{throw HistoryError.invalid};return s
    }
    private static func text(_ node:JSONNode?,limit:Int,quoted:Bool=false,code:Bool=false)throws->String{
        let s=try rawString(node,limit:limit)
        guard !s.isEmpty,!s.contains("\0"),s.unicodeScalars.contains(where:{!sourceSpace.contains($0.value)}),
              quoted || !s.unicodeScalars.contains(where:{disallowedTextScalar($0,code:code)}) else{throw HistoryError.invalid};return s
    }
    private static func decimal(_ node:JSONNode?,maximum:UInt64=UInt64.max)throws->UInt64{
        let s=try rawString(node,limit:20)
        guard let first=s.utf8.first,(49...57).contains(first),s.utf8.allSatisfy({(48...57).contains($0)}),let n=UInt64(s),n<=maximum else{throw HistoryError.invalid};return n
    }
    private static func uuid(_ node:JSONNode?)throws->UUID{
        let s=try rawString(node,limit:36)
        guard s.utf8.count==36,let id=UUID(uuidString:s),id.uuidString.lowercased()==s else{throw HistoryError.invalid};return id
    }
    private static func hash(_ node:JSONNode?)throws->String{
        let s=try rawString(node,limit:64)
        guard s.utf8.count==64,s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw HistoryError.invalid};return s
    }
    private static func integer(_ node:JSONNode?,maximum:Int)throws->Int{
        guard let node else{throw HistoryError.invalid};let n=try node.uint()
        guard n<=UInt64(maximum) else{throw HistoryError.invalid};return Int(n)
    }
    private static func schema(_ node:JSONNode?)throws{guard try integer(node,maximum:1)==1 else{throw HistoryError.invalid}}
    private static func array(_ node:JSONNode?,maximum:Int)throws->[JSONNode]{guard let node else{throw HistoryError.invalid};return try node.array(maximum)}
    private static func rowID(_ node:JSONNode?)throws->(String,String){
        let s=try rawString(node,limit:101),parts=s.split(separator:":",omittingEmptySubsequences:false).map(String.init)
        guard parts.count==5 else{throw HistoryError.invalid}
        _=try uuid(.string(parts[0]));_=try decimal(.string(parts[1]));_=try decimal(.string(parts[3]));_=try decimal(.string(parts[4]))
        guard ["1","2"].contains(parts[2]) else{throw HistoryError.invalid};return(s,parts[2])
    }
    private static func gapList(_ node:JSONNode?,state:String)throws->[String]{
        let values=try array(node,maximum:gaps.count).map{try rawString($0,limit:40)}
        guard ["paused","completed","partial","interrupted"].contains(state),Set(values).count==values.count,
              values==gaps.filter({values.contains($0)}),state != "completed" || values.isEmpty else{throw HistoryError.invalid};return values
    }
    private static func selection(_ node:JSONNode?,ids:[String])throws->HistoryNotesSelectionData{
        guard let node,let first=ids.first,let last=ids.last else{throw HistoryError.invalid}
        let v=try node.object(["kind","totalSavedRows","includedRows","firstRowID","lastRowID"])
        let kind=try rawString(v["kind"],limit:32),total=try integer(v["totalSavedRows"],maximum:1024),included=try integer(v["includedRows"],maximum:total)
        guard ["full_saved_transcript","explicit_excerpt"].contains(kind),included==ids.count,
              try rawString(v["firstRowID"],limit:101)==first,try rawString(v["lastRowID"],limit:101)==last,
              kind != "full_saved_transcript" || total==included else{throw HistoryError.invalid}
        return HistoryNotesSelectionData(kind:kind,totalSavedRows:total,includedRows:included,firstRowID:first,lastRowID:last)
    }
    public static func source(_ raw:Data)throws->HistoryNotesSourceData{
        do{
            let v=try HistoryNotesJSON.decode(raw,limit:sourceBytes).object(["schemaVersion","recordID","recordRevision","selection","recordState","gaps","rows"])
            try schema(v["schemaVersion"]);let record=try uuid(v["recordID"]),revision=try decimal(v["recordRevision"],maximum:UInt64(Int64.max))
            let state=try rawString(v["recordState"],limit:16),g=try gapList(v["gaps"],state:state),input=try array(v["rows"],maximum:1024)
            guard !input.isEmpty else{throw HistoryError.invalid};var rows:[HistoryNotesRowData]=[],seen:Set<String>=[],bytes=0
            for node in input{
                let row=try node.object(["id","revision","source","text"]),identity=try rowID(row["id"])
                guard seen.insert(identity.0).inserted,try rawString(row["revision"],limit:1)=="1" else{throw HistoryError.invalid}
                let source=try rawString(row["source"],limit:24),value=try text(row["text"],limit:4800,quoted:true)
                guard source==(identity.1=="1" ? "microphone":"selected_app_audio"),value.unicodeScalars.count<=1200 else{throw HistoryError.invalid}
                bytes+=value.utf8.count;guard bytes<=256*1024 else{throw HistoryError.invalid}
                rows.append(HistoryNotesRowData(rowID:identity.0,revision:1,source:source,text:value,textDigest:digest(Data(value.utf8))))
            }
            return HistoryNotesSourceData(recordID:record,recordRevision:Int64(revision),selection:try selection(v["selection"],ids:rows.map(\.rowID)),recordState:state,gaps:g,rows:rows,rawBytes:raw,sourceDigest:sourceDigest(raw))
        }catch{throw HistoryError.invalid}
    }
    private static func notes(_ node:JSONNode,source:HistoryNotesSourceData)throws->HistoryNotesOutputData{
        let v=try node.object(["schemaVersion","summary","decisions","nextSteps"]);try schema(v["schemaVersion"])
        let byID=Dictionary(uniqueKeysWithValues:source.rows.map{($0.rowID,$0)});var groups:[[HistoryNotesItemData]]=[]
        for (name,minimum,maximum) in [("summary",1,8),("decisions",0,4),("nextSteps",0,4)]{
            let values=try array(v[name],maximum:maximum);guard values.count>=minimum else{throw HistoryError.invalid};var items:[HistoryNotesItemData]=[]
            for value in values{
                let item=try value.object(["text","citations"]),body=try text(item["text"],limit:768,code:true),refs=try array(item["citations"],maximum:3)
                guard !refs.isEmpty else{throw HistoryError.invalid};var citations:[HistoryNotesCitationData]=[],seen:Set<String>=[]
                for reference in refs{
                    let ref=try reference.object(["rowID","quote"]),id=try rawString(ref["rowID"],limit:101),quote=try text(ref["quote"],limit:240,quoted:true)
                    guard let row=byID[id],Data(row.text.utf8).range(of:Data(quote.utf8)) != nil,
                          seen.insert(id+"\0"+quote).inserted else{throw HistoryError.invalid}
                    citations.append(HistoryNotesCitationData(rowID:id,quote:quote))
                }
                items.append(HistoryNotesItemData(text:body,citations:citations))
            }
            groups.append(items)
        }
        guard groups.reduce(0,{$0+$1.count})<=16 else{throw HistoryError.invalid}
        return HistoryNotesOutputData(summary:groups[0],decisions:groups[1],nextSteps:groups[2],canonicalBytes:try canonical(node,limit:outputBytes))
    }
    public static func output(_ raw:Data,source:HistoryNotesSourceData)throws->HistoryNotesOutputData{
        do{return try notes(HistoryNotesJSON.decode(raw,limit:outputBytes),source:source)}catch{throw HistoryError.invalid}
    }
    static func timestamp(_ node:JSONNode?)throws->String{
        let s=try rawString(node,limit:24),b=Array(s.utf8)
        guard b.count==24,b[4]==45,b[7]==45,b[10]==84,b[13]==58,b[16]==58,b[19]==46,b[23]==90,
              b.enumerated().allSatisfy({[4,7,10,13,16,19,23].contains($0.offset)||(48...57).contains($0.element)}) else{throw HistoryError.invalid}
        func n(_ a:Int,_ z:Int)->Int{b[a..<z].reduce(0){$0*10+Int($1-48)}}
        let y=n(0,4),m=n(5,7),d=n(8,10),days=[31,(y%4==0 && (y%100 != 0 || y%400==0)) ? 29:28,31,30,31,30,31,31,30,31,30,31]
        guard y>0,(1...12).contains(m),(1...days[m-1]).contains(d),n(11,13)<24,n(14,16)<60,n(17,19)<60 else{throw HistoryError.invalid};return s
    }
    private static func generation(_ node:JSONNode?)throws->HistoryNotesGenerationData{
        guard let node else{throw HistoryError.invalid}
        let v=try node.object(["scopeID","scopeEpoch","operationID","requestID","requestSequence","transferID","completedAt"])
        guard try rawString(v["requestSequence"],limit:1)=="1" else{throw HistoryError.invalid}
        return HistoryNotesGenerationData(scopeID:try uuid(v["scopeID"]),scopeEpoch:try decimal(v["scopeEpoch"]),operationID:try uuid(v["operationID"]),requestID:try uuid(v["requestID"]),requestSequence:1,transferID:try uuid(v["transferID"]),completedAt:try timestamp(v["completedAt"]))
    }
    public static func document(_ raw:Data,source:HistoryNotesSourceData)throws->HistoryNotesDocumentData{
        do{
            let node=try HistoryNotesJSON.decode(raw,limit:documentBytes)
            let v=try node.object(["schemaVersion","noteID","noteRevision","recordID","sourceRecordRevision","savedAtRecordRevision","selection","sourceState","sourceGaps","sourceDigest","sourceRows","origin","modelID","promptPolicy","generation","editedAt","notes"])
            try schema(v["schemaVersion"])
            let id=try uuid(v["noteID"]),revision=try decimal(v["noteRevision"],maximum:UInt64(Int64.max)),record=try uuid(v["recordID"]),captured=try decimal(v["sourceRecordRevision"],maximum:UInt64(Int64.max)),saved=try decimal(v["savedAtRecordRevision"],maximum:UInt64(Int64.max))
            guard record==source.recordID,captured==UInt64(source.recordRevision),saved>captured,
                  try rawString(v["sourceState"],limit:16)==source.recordState,
                  try gapList(v["sourceGaps"],state:source.recordState)==source.gaps,
                  try hash(v["sourceDigest"])==source.sourceDigest else{throw HistoryError.invalid}
            let chosen=try selection(v["selection"],ids:source.rows.map(\.rowID));guard chosen==source.selection else{throw HistoryError.invalid}
            let members=try array(v["sourceRows"],maximum:1024);guard members.count==source.rows.count else{throw HistoryError.invalid};var proofs:[HistoryNotesRowProofData]=[]
            for (member,row) in zip(members,source.rows){
                let proof=try member.object(["rowID","revision","textDigest"])
                guard try rawString(proof["rowID"],limit:101)==row.rowID,try rawString(proof["revision"],limit:1)=="1",try hash(proof["textDigest"])==row.textDigest else{throw HistoryError.invalid}
                proofs.append(HistoryNotesRowProofData(rowID:row.rowID,revision:1,textDigest:row.textDigest))
            }
            let origin=try rawString(v["origin"],limit:32),edited:String?
            if origin=="generated"{guard v["editedAt"]?.isNull==true else{throw HistoryError.invalid};edited=nil}
            else{guard origin=="generated_user_edited" else{throw HistoryError.invalid};edited=try timestamp(v["editedAt"])}
            guard try rawString(v["promptPolicy"],limit:32)=="notes_source_v1",let output=v["notes"] else{throw HistoryError.invalid}
            return HistoryNotesDocumentData(noteID:id,noteRevision:Int64(revision),recordID:record,sourceRecordRevision:Int64(captured),savedAtRecordRevision:Int64(saved),selection:chosen,sourceState:source.recordState,sourceGaps:source.gaps,sourceDigest:source.sourceDigest,sourceRows:proofs,origin:origin,modelID:try text(v["modelID"],limit:256),promptPolicy:"notes_source_v1",generation:try generation(v["generation"]),editedAt:edited,notes:try notes(output,source:source),canonicalBytes:try canonical(node,limit:documentBytes))
        }catch{throw HistoryError.invalid}
    }
    static func canonical(_ node:JSONNode,limit:Int)throws->Data{
        func value(_ n:JSONNode)throws->Any{
            switch n{
            case .object(let v):return try v.mapValues{try value($0)}
            case .array(let v):return try v.map{try value($0)}
            case .string(let v):return v
            case .number(let v):guard let number=UInt64(v) else{throw HistoryError.invalid};return NSNumber(value:number)
            case .bool(let v):return v
            case .null:return NSNull()
            }
        }
        let bytes=try JSONSerialization.data(withJSONObject:value(node),options:[.sortedKeys,.withoutEscapingSlashes])
        guard bytes.count<=limit else{throw HistoryError.invalid};return bytes
    }
}

/// Narrow local adaptation of reviewed StrictJSON at History8ea. Shared wire
/// limits stay unchanged. Notes alone admits 2MiB/1024 rows, depth8/8192 values.
private enum HistoryNotesJSON {
    static func decode(_ data:Data,limit:Int)throws->JSONNode{
        guard !data.isEmpty,data.count<=limit,String(data:data,encoding:.utf8) != nil else{throw HistoryError.invalid}
        var parser=Parser(bytes:Array(data));let value=try parser.value(1);parser.space()
        guard parser.index==parser.bytes.count else{throw HistoryError.invalid};return value
    }
    private struct Parser {
        let bytes:[UInt8];var index=0,nodes=0
        mutating func space(){while index<bytes.count && [9,10,13,32].contains(bytes[index]){index+=1}}
        mutating func consume(_ b:UInt8)throws{space();guard index<bytes.count,bytes[index]==b else{throw HistoryError.invalid};index+=1}
        mutating func text()throws->String{
            space();let start=index;try consume(34);var escaped=false
            while index<bytes.count{
                let b=bytes[index];index+=1
                if !escaped && b==34{return try JSONDecoder().decode(String.self,from:Data(bytes[start..<index]))}
                if !escaped && b<32{throw HistoryError.invalid}
                if escaped{escaped=false}else if b==92{escaped=true}
            }
            throw HistoryError.invalid
        }
        mutating func value(_ depth:Int)throws->JSONNode{
            nodes+=1;guard depth<=8,nodes<=8192 else{throw HistoryError.invalid};space();guard index<bytes.count else{throw HistoryError.invalid}
            let b=bytes[index]
            if b==34{return .string(try text())}
            if b==123{
                index+=1;space();var result:[String:JSONNode]=[:]
                if index<bytes.count,bytes[index]==125{index+=1;return .object(result)}
                while true{
                    let key=try text();guard result[key]==nil else{throw HistoryError.invalid};try consume(58)
                    result[key]=try value(depth+1);space();guard index<bytes.count else{throw HistoryError.invalid}
                    if bytes[index]==125{index+=1;return .object(result)};try consume(44)
                }
            }
            if b==91{
                index+=1;space();var result:[JSONNode]=[]
                if index<bytes.count,bytes[index]==93{index+=1;return .array(result)}
                while true{
                    guard result.count<8192 else{throw HistoryError.invalid};result.append(try value(depth+1));space()
                    guard index<bytes.count else{throw HistoryError.invalid}
                    if bytes[index]==93{index+=1;return .array(result)};try consume(44)
                }
            }
            for (literal,node) in [("true",JSONNode.bool(true)),("false",.bool(false)),("null",.null)]{
                let token=Array(literal.utf8);if bytes[index...].starts(with:token){index+=token.count;return node}
            }
            let start=index
            while index<bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]){index+=1}
            guard start<index else{throw HistoryError.invalid};let raw=String(decoding:bytes[start..<index],as:UTF8.self)
            guard raw.range(of:#"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#,options:.regularExpression) != nil else{throw HistoryError.invalid};return .number(raw)
        }
    }
}
