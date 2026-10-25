import Foundation

/// Strict parsed DATA. Only a registered original HelperTransport operation
/// can subsequently issue a private completed-operation receipt.
public struct NotesScopeResponseData:Sendable,Equatable {
    public let scopeID:UUID,scopeEpoch:UInt64,operationID:UUID
    public let action:String,status:String,quiesced:Bool?,reasonCode:String
}
public struct NotesResultData:Sendable,Equatable {
    public let scopeID:UUID,scopeEpoch:UInt64,requestID:UUID,requestSequence:UInt64,transferID:UUID
    public let recordID:UUID,recordRevision:Int64,sourceDigest:String,resultRevision:UInt64
    public let status:String,reasonCode:String,notes:HistoryNotesOutputData?
}

public enum NativeNotesWire {
    static let reasons:Set<String>=["busy","stale","source_unavailable","source_expired","source_budget",
        "inference_disabled","account_unavailable","request_unavailable","output_invalid","cancelled","transport_closed"]
    private static func uuid(_ node:JSONNode)throws->UUID {
        let value=try node.string(36)
        guard let id=UUID(uuidString:value),id.uuidString.lowercased()==value else{throw PanelBridgeError.malformed}
        return id
    }
    private static func revision(_ node:JSONNode)throws->Int64 {
        let value=try node.string(19)
        guard let first=value.utf8.first,(49...57).contains(first),value.utf8.allSatisfy({(48...57).contains($0)}),
              let number=Int64(value),number>0 else{throw PanelBridgeError.malformed};return number
    }
    private static func digest(_ node:JSONNode)throws->String {
        let value=try node.string(64)
        guard value.utf8.count==64,value.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw PanelBridgeError.malformed}
        return value
    }
    public static func scopeResponse(_ raw:Data)throws->NotesScopeResponseData {
        let v=try StrictJSON.decode(raw).object(["schemaVersion","kind","scopeID","scopeEpoch","operationID","action","status","quiesced","reasonCode"])
        guard try v["schemaVersion"]!.uint()==1,try v["kind"]!.string()=="notes_scope_response" else{throw PanelBridgeError.malformed}
        let action=try v["action"]!.string(8),status=try v["status"]!.string(16),reason=try v["reasonCode"]!.string(32)
        let quiesced:Bool?=v["quiesced"]!.isNull ? nil:try v["quiesced"]!.boolean()
        guard ["open","close"].contains(action),
              (action=="open" && status=="ready" && quiesced==nil && reason=="ok")
              || (action=="close" && status=="closed" && quiesced==true && reason=="ok")
              || (status=="unavailable" && quiesced==false && reasons.contains(reason)) else{throw PanelBridgeError.malformed}
        return NotesScopeResponseData(scopeID:try uuid(v["scopeID"]!),scopeEpoch:try v["scopeEpoch"]!.uint(),operationID:try uuid(v["operationID"]!),
            action:action,status:status,quiesced:quiesced,reasonCode:reason)
    }
    public static func result(_ raw:Data,source:HistoryNotesSourceData)throws->NotesResultData {
        let v=try StrictJSON.decode(raw).object(["schemaVersion","kind","scopeID","scopeEpoch","requestID","requestSequence","transferID",
            "recordID","recordRevision","sourceDigest","resultRevision","status","reasonCode","notes"])
        guard try v["schemaVersion"]!.uint()==1,try v["kind"]!.string()=="notes_result",try v["requestSequence"]!.uint()==1 else{throw PanelBridgeError.malformed}
        let record=try uuid(v["recordID"]!),recordRevision=try revision(v["recordRevision"]!),hash=try digest(v["sourceDigest"]!)
        guard record==source.recordID,recordRevision==source.recordRevision,hash==source.sourceDigest else{throw PanelBridgeError.malformed}
        let status=try v["status"]!.string(16),reason=try v["reasonCode"]!.string(32),resultRevision=try v["resultRevision"]!.uint()
        let output:HistoryNotesOutputData?
        switch status {
        case "pending":
            guard resultRevision==1,reason=="generating",v["notes"]!.isNull else{throw PanelBridgeError.malformed};output=nil
        case "completed":
            guard resultRevision==2,reason=="ok",!v["notes"]!.isNull else{throw PanelBridgeError.malformed}
            output=try HistoryNotesData.output(HistoryNotesData.canonical(v["notes"]!,limit:HistoryNotesData.outputBytes),source:source)
        case "cancelled","unavailable":
            guard resultRevision==2,v["notes"]!.isNull,reasons.contains(reason),status != "cancelled" || reason=="cancelled" else{throw PanelBridgeError.malformed};output=nil
        default:throw PanelBridgeError.malformed
        }
        return NotesResultData(scopeID:try uuid(v["scopeID"]!),scopeEpoch:try v["scopeEpoch"]!.uint(),requestID:try uuid(v["requestID"]!),requestSequence:1,
            transferID:try uuid(v["transferID"]!),recordID:record,recordRevision:recordRevision,sourceDigest:hash,resultRevision:resultRevision,
            status:status,reasonCode:reason,notes:output)
    }
}
