import Foundation
import CryptoKit
@testable import RelaySessionPanel

/// Fictional DATA only. These values never issue a source or inference permit.
enum HistoryNotesFixtures {
    static let record="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let capture="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let note="cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    static let gaps=["sourceUnavailable","sequenceGap","capacity","storageFailure","savingStopped","interrupted","captureFailure","sourceDeleted","invalidObservation","unfinishedSpeech","captureEndUnknown"]
    static func id(_ i:Int=1)->String{"\(capture):1:2:1:\(i)"}
    static func encode(_ value:[String:Any])throws->Data{
        try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])
    }
    static func source(_ texts:[String] = ["  A stable original quote.\n"])->[String:Any]{
        let rows=texts.enumerated().map{["id":id($0.offset+1),"revision":"1","source":"selected_app_audio","text":$0.element]}
        return ["schemaVersion":1,"recordID":record,"recordRevision":"7","selection":["kind":"full_saved_transcript","totalSavedRows":rows.count,"includedRows":rows.count,"firstRowID":id(),"lastRowID":id(rows.count)],"recordState":"completed","gaps":[],"rows":rows]
    }
    static func output(quote:String="original quote")->[String:Any]{
        ["schemaVersion":1,"summary":[["text":"The discussion used a queue.","citations":[["rowID":id(),"quote":quote]]]],"decisions":[],"nextSteps":[]]
    }
    static func document(_ source:[String:Any],output:[String:Any]?=nil)throws->[String:Any]{
        let raw=try encode(source),rows=source["rows"] as! [[String:String]]
        var domain=Data("relay.notes.source.v1\n".utf8);domain.append(raw)
        func hash(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
        return ["schemaVersion":1,"noteID":note,"noteRevision":"1","recordID":record,"sourceRecordRevision":"7","savedAtRecordRevision":"8",
            "selection":source["selection"]!,"sourceState":source["recordState"]!,"sourceGaps":source["gaps"]!,"sourceDigest":hash(domain),
            "sourceRows":rows.map{["rowID":$0["id"]!,"revision":"1","textDigest":hash(Data($0["text"]!.utf8))]},
            "origin":"generated","modelID":"fictional-model-DATA-only","promptPolicy":"notes_source_v1",
            "generation":["scopeID":record,"scopeEpoch":"1","operationID":note,"requestID":capture,"requestSequence":"1","transferID":note,"completedAt":"2026-10-24T10:00:00.000Z"],"editedAt":NSNull(),"notes":output ?? self.output()]
    }
}
