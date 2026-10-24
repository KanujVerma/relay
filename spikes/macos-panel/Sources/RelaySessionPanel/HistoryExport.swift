import Foundation

public enum HistoryExportFormat:String,Sendable{case json,markdown}
public enum HistoryExport {
    /// A complete, revision-bound immutable detail is required. Export never
    /// silently turns the first page into a purported whole-session transcript.
    public static func encode(_ detail:HistoryDetail,format:HistoryExportFormat,generatedNotes:HistoryNotesDocumentData?=nil)throws->Data{
        guard detail.nextOffset==nil,detail.rows.count==detail.totalRows else{throw HistoryError.invalid}
        if let generatedNotes{
            let actual=try HistoryNotesDocuments.restore(generatedNotes.canonicalBytes,record:detail.record,rows:detail.rows).0
            guard actual==generatedNotes else{throw HistoryError.invalid}
        }
        let data:Data
        switch format{
        case .markdown:
            var parts=["# "+safe(detail.record.title),"Status: "+detail.record.state.rawValue,
                       "Created: "+date(detail.record.createdAt),"Transcript text only. No audio recording is included."]
            if !detail.record.gaps.isEmpty{parts.append("History gaps: "+detail.record.gaps.map(\.label).joined(separator:"; "))}
            parts.append("## User notes\n\n"+quote(detail.record.note))
            if let generatedNotes{parts.append(generatedSection(generatedNotes,rows:detail.rows))}
            parts.append("## Audio captures")
            for capture in detail.captures{
                parts.append("Capture: `\(capture.captureSessionID.uuidString.lowercased())` · Epoch: `\(capture.sessionEpoch)`")
                parts.append(capture.observedEndUptimeNanoseconds == nil ? "Capture cleanup end not recorded.":"Capture cleanup observed at original native uptime `\(capture.observedEndUptimeNanoseconds!)` ns. This is not a measured audio duration.")
            }
            parts.append("## Audio transcript")
            for row in detail.rows{
                parts.append("### "+row.source.label+"\n\n"+quote(row.text))
                parts.append("Capture: `\(row.captureSessionID.uuidString.lowercased())` · Epoch: `\(row.sessionEpoch)` · Original event: `\(row.eventSequence)`")
            }
            data=Data((parts.joined(separator:"\n\n")+"\n").utf8)
        case .json:
            let captures=try detail.captures.map{capture->[String:Any] in
                guard var value=try object(StrictJSON.decode(HistoryJSON.encode(capture))) as? [String:Any] else{throw HistoryError.invalid}
                value["cleanupEndStatus"]=capture.observedEndUptimeNanoseconds == nil ? "unknown":"observed"
                value["observedEndUptimeNanoseconds"]=capture.observedEndUptimeNanoseconds?.description as Any? ?? NSNull()
                if let stop=capture.stop{
                    value["stop"]=["observedWallTime":date(stop.observedWallTime),"quiesced":stop.quiesced,
                        "originalNativeEvidence":try object(StrictJSON.decode(stop.originalEventJSON))]
                }
                return value
            }
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
            var root:[String:Any]=["schemaVersion":1,"kind":"local_session_history_export",
                "recordID":detail.record.id.uuidString.lowercased(),"recordRevision":String(detail.record.revision),
                "title":detail.record.title,"state":detail.record.state.rawValue,
                "createdAt":date(detail.record.createdAt),"expiresAt":date(detail.record.expiresAt),
                "endedAt":detail.record.endedAt.map(date) as Any? ?? NSNull(),
                "gaps":detail.record.gaps.map(\.rawValue),"userNotes":["origin":"user","text":detail.record.note],
                "captures":captures,"transcript":rows]
            if let generatedNotes{
                root["schemaVersion"]=2
                root["generatedMeetingNotes"]=try JSONSerialization.jsonObject(with:generatedNotes.canonicalBytes)
            }
            data=try JSONSerialization.data(withJSONObject:root,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
        }
        guard data.count<=HistoryBounds.snapshot else{throw HistoryError.capacity};return data
    }
    private static func generatedSection(_ document:HistoryNotesDocumentData,rows:[HistoryFinal])->String{
        var parts=["## AI-generated meeting notes",
            document.origin=="generated_user_edited" ? "Origin: AI-generated, then edited locally by the user.":"Origin: AI-generated.",
            "These notes are not approved personal facts.","Model: "+safe(document.modelID),
            "Source snapshot: record revision "+String(document.sourceRecordRevision)+"; "+safe(document.sourceState)+".",
            (document.selection.kind=="explicit_excerpt" ? "Explicit excerpt":"Full saved transcript at generation")+" · "+String(document.selection.includedRows)+" of "+String(document.selection.totalSavedRows)+" passages."]
        if !document.sourceGaps.isEmpty{parts.append("Source gaps: "+document.sourceGaps.map(safe).joined(separator:"; "))}
        let sources=Dictionary(uniqueKeysWithValues:rows.map{($0.id,$0.source.label)})
        for (title,items) in [("Summary",document.notes.summary),("Decisions",document.notes.decisions),("Next steps",document.notes.nextSteps)]{
            guard !items.isEmpty else{continue};parts.append("### "+title)
            for item in items{
                parts.append("- "+safe(item.text))
                for citation in item.citations{
                    parts.append("Source: "+safe(sources[citation.rowID] ?? "Source unavailable")+" · `"+citation.rowID+"`\n\n"+quote(visibleSource(citation.quote)))
                }
            }
        }
        return parts.joined(separator:"\n\n")
    }
    /// Same display-only escaping as the accepted Notes presentation. JSON
    /// retains literal originals; Markdown makes nonprinting source visible.
    private static func visibleSource(_ value:String)->String{
        value.unicodeScalars.map{scalar in
            switch scalar.properties.generalCategory{
            case .control,.format,.lineSeparator,.paragraphSeparator,.surrogate:
                return scalar=="\n" || scalar=="\t" ? String(scalar):"\\u{\(String(scalar.value,radix:16))}"
            default:return String(scalar)
            }
        }.joined()
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
