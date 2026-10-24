import Foundation

public enum HistoryExportFormat:String,Sendable{case json,markdown}
public enum HistoryExport {
    /// A complete, revision-bound immutable detail is required. Export never
    /// silently turns the first page into a purported whole-session transcript.
    public static func encode(_ detail:HistoryDetail,format:HistoryExportFormat)throws->Data{
        guard detail.nextOffset==nil,detail.rows.count==detail.totalRows else{throw HistoryError.invalid}
        let data:Data
        switch format{
        case .markdown:
            var parts=["# "+safe(detail.record.title),"Status: "+detail.record.state.rawValue,
                       "Created: "+date(detail.record.createdAt),"Transcript text only. No audio recording is included."]
            if !detail.record.gaps.isEmpty{parts.append("History gaps: "+detail.record.gaps.map(\.label).joined(separator:"; "))}
            parts.append("## User notes\n\n"+quote(detail.record.note))
            parts.append("## Audio transcript")
            for row in detail.rows{
                parts.append("### "+row.source.label+"\n\n"+quote(row.text))
                parts.append("Capture: `\(row.captureSessionID.uuidString.lowercased())` · Epoch: `\(row.sessionEpoch)` · Original event: `\(row.eventSequence)`")
            }
            data=Data((parts.joined(separator:"\n\n")+"\n").utf8)
        case .json:
            let captures=try detail.captures.map{try object(StrictJSON.decode(HistoryJSON.encode($0)))}
            let rows=try detail.rows.map{row->[String:Any] in
                ["id":row.id,"captureSessionID":row.captureSessionID.uuidString.lowercased(),
                 "sessionEpoch":row.sessionEpoch.description,"eventSequence":row.eventSequence.description,
                 "sourceCode":String(row.source.rawValue),"sourceLabel":row.source.label,
                 "streamGeneration":row.streamGeneration.description,"activityID":row.activityID.description,
                 "segmentID":row.segmentID.description,"revision":row.revision.description,
                 "startUptimeNanoseconds":row.startUptimeNanoseconds.description,
                 "endUptimeNanoseconds":row.endUptimeNanoseconds.description,"text":row.text,
                 "originalNativeEvidence":try object(StrictJSON.decode(row.originalEventJSON))]
            }
            let root:[String:Any]=["schemaVersion":1,"kind":"local_session_history_export",
                "recordID":detail.record.id.uuidString.lowercased(),"recordRevision":String(detail.record.revision),
                "title":detail.record.title,"state":detail.record.state.rawValue,
                "createdAt":date(detail.record.createdAt),"expiresAt":date(detail.record.expiresAt),
                "endedAt":detail.record.endedAt.map(date) as Any? ?? NSNull(),
                "gaps":detail.record.gaps.map(\.rawValue),"userNotes":["origin":"user","text":detail.record.note],
                "captures":captures,"transcript":rows]
            data=try JSONSerialization.data(withJSONObject:root,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
        }
        guard data.count<=HistoryBounds.snapshot else{throw HistoryError.capacity};return data
    }
    private static func object(_ node:JSONNode)throws->Any{
        switch node{
        case .object(let fields):return try fields.mapValues{try object($0)}
        case .array(let values):return try values.map{try object($0)}
        case .string(let string),.number(let string):return string
        case .bool(let value):return value
        case .null:return NSNull()
        }
    }
    private static func date(_ time:TimeInterval)->String{ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:time))}
    private static func safe(_ s:String)->String{
        var result=s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;")
        result=result.replacingOccurrences(of:"\\",with:"\\\\")
        for c in ["`","*","_","[","]","!"]{result=result.replacingOccurrences(of:c,with:"\\"+c)}
        return result
    }
    private static func quote(_ s:String)->String{safe(s).components(separatedBy:"\n").map{"> "+$0}.joined(separator:"\n")}
}
