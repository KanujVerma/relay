import Foundation
import GRDB
import RelayProfile

/// Issued only by the actual locked source read below. Parsed DATA or a
/// serialized UUID cannot construct this proof or substitute another store.
final class HistoryNotesStoreRead:@unchecked Sendable {
    fileprivate let store:HistoryStore
    let sourceData:HistoryNotesSourceData
    let intentID:UUID
    let expiresAt:TimeInterval
    fileprivate var consumed=false
    fileprivate init(store:HistoryStore,data:HistoryNotesSourceData,intentID:UUID,expiresAt:TimeInterval){
        self.store=store;sourceData=data;self.intentID=intentID;self.expiresAt=expiresAt
    }
}

/// One serialized canonical ledger and at most one bounded candidate. Callers
/// run storage off the UI actor and retain/join actual operations on retirement.
/// No database path, plaintext index, audio bytes or helper lifetime is used.
final class HistoryStore:@unchecked Sendable {
    private let storage:any ProtectedSnapshotStorage
    private let clock:@Sendable()->Date
    private let contentLimitBytes:Int
    private let lock=NSLock()
    private var queue:DatabaseQueue?
    private var retiringQueue:DatabaseQueue?
    private var ownsStorage=false
    // One bounded destructive-mutation receipt, consumed by the sole workspace
    // flight after this store's lock is released; never a persistent registry.
    private var expiredRecordIDs:Set<UUID>?=[]
    func takeExpiredRecordIDs()->Set<UUID>?{lock.withLock{
        let result=expiredRecordIDs;expiredRecordIDs=[];return result
    }}
    init(storage:any ProtectedSnapshotStorage,clock:@escaping @Sendable()->Date={Date()},contentLimitBytes:Int=HistoryBounds.softSnapshot){
        self.storage=storage;self.clock=clock;self.contentLimitBytes=contentLimitBytes
    }
    private static let tables:[String:String]=[
        "history_record":"CREATE TABLE history_record (id TEXT PRIMARY KEY, created_at REAL NOT NULL, expires_at REAL NOT NULL, payload BLOB NOT NULL CHECK(typeof(payload)='blob'))",
        "history_capture":"CREATE TABLE history_capture (id TEXT PRIMARY KEY, record_id TEXT NOT NULL REFERENCES history_record(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, payload BLOB NOT NULL CHECK(typeof(payload)='blob'), UNIQUE(record_id,ordinal))",
        "history_final":"CREATE TABLE history_final (id TEXT PRIMARY KEY, record_id TEXT NOT NULL REFERENCES history_record(id) ON DELETE CASCADE, capture_id TEXT NOT NULL REFERENCES history_capture(id) ON DELETE CASCADE, source INTEGER NOT NULL CHECK(source IN (1,2)), sort_ticks BLOB NOT NULL, text_bytes INTEGER NOT NULL, payload BLOB NOT NULL CHECK(typeof(payload)='blob'))"
    ]
    private static let index="CREATE INDEX history_final_order ON history_final(record_id,capture_id,sort_ticks,id)"
    private static func schema(_ q:DatabaseQueue)throws{
        try q.write{db in
            for name in ["history_record","history_capture","history_final"]{try db.execute(sql:tables[name]!)}
            try db.execute(sql:index);try db.execute(sql:"PRAGMA user_version=1")
        }
    }
    private static func key(_ id:UUID)->String{id.uuidString.lowercased()}
    private func required()throws->DatabaseQueue{guard retiringQueue==nil,let queue else{throw HistoryError.closed};return queue}
    private static func record(_ db:Database,_ id:UUID)throws->HistoryRecord{
        guard let data=try Data.fetchOne(db,sql:"SELECT payload FROM history_record WHERE id=?",arguments:[key(id)]) else{throw HistoryError.missing}
        guard data.count<=16_384 else{throw HistoryError.invalid}
        let r=try HistoryJSON.decode(HistoryRecord.self,data);try r.validate();return r
    }
    private static func put(_ db:Database,_ r:HistoryRecord)throws{
        try r.validate()
        try db.execute(sql:"INSERT INTO history_record(id,created_at,expires_at,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
                       arguments:[key(r.id),r.createdAt,r.expiresAt,try HistoryJSON.encode(r)])
    }
    private static func bumped(_ record:HistoryRecord)throws->HistoryRecord{
        guard record.revision<Int64.max else{throw HistoryError.capacity};var r=record;r.revision+=1;return r
    }
    private func commit<T>(content:Bool=false,admission:@Sendable()->Bool={true},_ body:(Database)throws->T)throws->T{
        guard admission() else{throw HistoryError.stale}
        let source=try required(),candidate=try HistorySnapshotCodec.makeQueue()
        do{
            try source.backup(to:candidate)
            let value=try candidate.write{db in try body(db)}
            try Self.validate(candidate)
            let data=try HistorySnapshotCodec.encode(candidate)
            guard !content || data.count<=contentLimitBytes else{throw HistoryError.capacity}
            guard admission() else{throw HistoryError.stale}
            try storage.save(data,createKey:false)
            queue=candidate;retiringQueue=source;try source.close();retiringQueue=nil;return value
        }catch{if queue !== candidate{try? candidate.close()};throw error}
    }
    /// Retained rows are copied into the fixed schema, not a VACUUM/temp file.
    private static func copyRows(_ source:DatabaseQueue,to destination:DatabaseQueue,
                                 excludingRecords:Set<String>=[],excludingSource:(String,UInt32)?=nil)throws{
        try schema(destination)
        try source.read{from in try destination.write{to in
            for table in ["history_record","history_capture","history_final"]{
                for row in try Row.fetchAll(from,sql:"SELECT * FROM \(table)"){
                    let recordID=try row.decode(String.self,forColumn:table == "history_record" ? "id":"record_id")
                    if excludingRecords.contains(recordID){continue}
                    if table == "history_record"{
                        try to.execute(sql:"INSERT INTO history_record VALUES(?,?,?,?)",arguments:[recordID,try row.decode(Double.self,forColumn:"created_at"),try row.decode(Double.self,forColumn:"expires_at"),try row.decode(Data.self,forColumn:"payload")])
                    }else if table == "history_capture"{
                        let id=try row.decode(String.self,forColumn:"id")
                        var payload=try row.decode(Data.self,forColumn:"payload")
                        if let excluded=excludingSource,id==excluded.0,let source=TranscriptSource(rawValue:excluded.1){
                            payload=try HistoryJSON.encode(HistoryJSON.decode(HistoryCapture.self,payload).redacting([source]))
                        }
                        try to.execute(sql:"INSERT INTO history_capture VALUES(?,?,?,?)",arguments:[id,recordID,try row.decode(Int.self,forColumn:"ordinal"),payload])
                    }else{
                        let capture=try row.decode(String.self,forColumn:"capture_id"),source=try row.decode(UInt32.self,forColumn:"source")
                        if let excluded=excludingSource,capture==excluded.0,source==excluded.1{continue}
                        try to.execute(sql:"INSERT INTO history_final VALUES(?,?,?,?,?,?,?)",arguments:[try row.decode(String.self,forColumn:"id"),recordID,capture,source,try row.decode(Data.self,forColumn:"sort_ticks"),try row.decode(Int.self,forColumn:"text_bytes"),try row.decode(Data.self,forColumn:"payload")])
                    }
                }
            }
        }}
    }
    private func remove(records:Set<String>=[],source:(String,UInt32)?=nil,
                        admission:@Sendable()->Bool={true},change:((Database)throws->Void)?=nil)throws{
        guard admission() else{throw HistoryError.stale}
        let old=try required(),candidate=try HistorySnapshotCodec.makeQueue()
        do{
            try Self.copyRows(old,to:candidate,excludingRecords:records,excludingSource:source)
            if let change{try candidate.write{try change($0)}}
            try Self.validate(candidate);let data=try HistorySnapshotCodec.encode(candidate)
            guard admission() else{throw HistoryError.stale}
            try storage.save(data,createKey:false);queue=candidate;retiringQueue=old;try old.close();retiringQueue=nil
        }catch{if queue !== candidate{try? candidate.close()};throw error}
    }
    func open(create:Bool,admission:@Sendable()->Bool={true})throws{
        try lock.withLock{
            guard (16_384...HistoryBounds.softSnapshot).contains(contentLimitBytes) else{throw HistoryError.invalid}
            guard admission() else{throw HistoryError.stale}
            if queue != nil{
                // A warm private queue is not proof that its existing vault is
                // still available/current. Start must not overwrite corruption
                // or a different owner's snapshot using cached plaintext.
                let current=try required()
                guard try storage.exists() else{throw HistoryError.missing}
                guard admission() else{throw HistoryError.stale}
                let actual=try storage.load()
                guard try actual==HistorySnapshotCodec.encode(current) else{throw HistoryError.invalid}
                guard admission() else{throw HistoryError.stale}
                return
            }
            guard !ownsStorage else{throw HistoryError.closed}
            if let owner=storage as? any HistoryOwnedSnapshotStorage{try owner.beginAccess(create:create);ownsStorage=true}
            do{try openCold(create:create,admission:admission)}catch{
                if queue==nil,retiringQueue==nil,ownsStorage,let owner=storage as? any HistoryOwnedSnapshotStorage{
                    do{try owner.endAccess();ownsStorage=false}catch{}
                }
                throw error
            }
        }
    }
    private func openCold(create:Bool,admission:@Sendable()->Bool)throws{
            guard admission() else{throw HistoryError.stale}
            let exists=try storage.exists()
            guard admission() else{throw HistoryError.stale}
            let candidate:DatabaseQueue
            if exists{candidate=try HistorySnapshotCodec.decode(storage.load())}
            else{
                guard create else{throw HistoryError.missing}
                candidate=try HistorySnapshotCodec.makeQueue()
                do{try Self.schema(candidate);guard admission() else{throw HistoryError.stale};try storage.save(HistorySnapshotCodec.encode(candidate),createKey:true)}
                catch{try? candidate.close();throw error}
            }
            do{
                try Self.validate(candidate);guard admission() else{throw HistoryError.stale};queue=candidate
                try expire(admission:admission)
                let repairs=try required().read{db in
                    try Data.fetchAll(db,sql:"SELECT payload FROM history_record").compactMap{data->HistoryRecord? in
                        var r=try HistoryJSON.decode(HistoryRecord.self,data),changed=false
                        if r.state == .recording || r.state == .paused{
                            r.state = .interrupted;if !r.gaps.contains(.interrupted){r.gaps.append(.interrupted)};changed=true
                        }
                        if try Self.hasUnknownCaptureEnd(db,r.id){
                            if !r.gaps.contains(.captureEndUnknown){r.gaps.append(.captureEndUnknown);changed=true}
                            if r.state == .completed{r.state = .partial;changed=true}
                        }
                        if changed{return try Self.bumped(r)};return nil
                    }
                }
                if !repairs.isEmpty{try commit(admission:admission){db in for r in repairs{try Self.put(db,r)}}}
            }catch{if let q=queue{try? q.close()};queue=nil;try? candidate.close();throw error}
    }
    func close()throws{try lock.withLock{
        if let old=retiringQueue{try old.close();retiringQueue=nil}
        if let q=queue{try q.close();queue=nil}
        if ownsStorage,let owner=storage as? any HistoryOwnedSnapshotStorage{try owner.endAccess();ownsStorage=false}
    }}
    private func expire(admission:@Sendable()->Bool={true})throws{
        let now=clock().timeIntervalSince1970
        guard now.isFinite else{throw HistoryError.invalid}
        let ids=try required().read{try String.fetchAll($0,sql:"SELECT id FROM history_record WHERE expires_at<=?",arguments:[now])}
        if !ids.isEmpty{
            try remove(records:Set(ids),admission:admission)
            if let previous=expiredRecordIDs{
                let removed=Set(ids.compactMap(UUID.init(uuidString:))),combined=previous.union(removed)
                expiredRecordIDs=combined.count<=HistoryBounds.records ? combined:nil
            }
        }
    }
    func createRecord(id:UUID=UUID(),admission:@Sendable()->Bool={true})throws->HistoryRecord{
        try lock.withLock{
            try expire(admission:admission)
            let q=try required()
            guard try q.read({try Int.fetchOne($0,sql:"SELECT count(*) FROM history_record") ?? 0})<HistoryBounds.records,
                  try HistorySnapshotCodec.encode(q).count<contentLimitBytes else{throw HistoryError.capacity}
            let now=clock().timeIntervalSince1970
            let record=HistoryRecord(id:id,revision:1,createdAt:now,expiresAt:now+HistoryBounds.retention,endedAt:nil,state:.recording,title:"Session",note:"",gaps:[],blockedSources:[])
            return try commit(content:true,admission:admission){db in try Self.put(db,record);return record}
        }
    }
    func append(_ observation:ValidatedTranscriptObservation,to id:UUID,admission:@Sendable()->Bool={true})throws{
        try lock.withLock{
            try expire(admission:admission)
            try commit(content:observation.event.kind == .sessionStarted || observation.final != nil,admission:admission){db in
                var r=try Self.record(db,id)
                guard r.state == .recording || r.state == .paused else{throw HistoryError.stale}
                if observation.event.kind != .sessionStarted{
                    let original=HistoryCapture.identity(observation.event.captureSessionID,observation.event.sessionEpoch)
                    guard try Int.fetchOne(db,sql:"SELECT count(*) FROM history_capture WHERE id=? AND record_id=?",arguments:[original,Self.key(id)])==1 else{throw HistoryError.stale}
                }
                if observation.sequenceGap{
                    if !r.gaps.contains(.sequenceGap){r.gaps.append(.sequenceGap)}
                    if observation.event.kind != .stopped{try Self.put(db,Self.bumped(r));return}
                }
                if observation.event.kind == .sessionStarted{
                    let capture=try HistoryCapture(observation.event,now:clock().timeIntervalSince1970).redacting(r.blockedSources)
                    if let old=try Data.fetchOne(db,sql:"SELECT payload FROM history_capture WHERE id=? AND record_id=?",arguments:[capture.id,Self.key(id)]){
                        guard try HistoryJSON.decode(HistoryCapture.self,old).captureSessionID==capture.captureSessionID else{throw HistoryError.invalid};return
                    }
                    let count=try Int.fetchOne(db,sql:"SELECT count(*) FROM history_capture WHERE record_id=?",arguments:[Self.key(id)]) ?? 0
                    guard count<HistoryBounds.captures else{throw HistoryError.capacity}
                    try db.execute(sql:"INSERT INTO history_capture VALUES(?,?,?,?)",arguments:[capture.id,Self.key(id),count,try HistoryJSON.encode(capture)])
                }else if observation.event.kind == .stopped{
                    let captureID=HistoryCapture.identity(observation.event.captureSessionID,observation.event.sessionEpoch)
                    guard let bytes=try Data.fetchOne(db,sql:"SELECT payload FROM history_capture WHERE id=? AND record_id=?",arguments:[captureID,Self.key(id)]) else{throw HistoryError.stale}
                    var capture=try HistoryJSON.decode(HistoryCapture.self,bytes)
                    let stop=try HistoryCaptureStop(observation.event,now:clock().timeIntervalSince1970)
                    if let old=capture.stop{guard old.originalEventJSON==stop.originalEventJSON else{throw HistoryError.invalid};return}
                    capture.stop=stop;try capture.validate()
                    // Actual cleanup can complete after an audio fault. Keep
                    // its original end evidence without claiming complete text.
                    if stop.reason != .userStop,!r.gaps.contains(.captureFailure){r.gaps.append(.captureFailure)}
                    try db.execute(sql:"UPDATE history_capture SET payload=? WHERE id=? AND record_id=?",arguments:[try HistoryJSON.encode(capture),captureID,Self.key(id)])
                }else if let final=observation.final{
                    guard r.state == .recording,!r.blockedSources.contains(final.source) else{throw HistoryError.stale};try final.validate()
                    if let old=try Data.fetchOne(db,sql:"SELECT payload FROM history_final WHERE id=?",arguments:[final.id]){
                        guard old == (try HistoryJSON.encode(final)) else{throw HistoryError.invalid};return
                    }
                    guard let bytes=try Data.fetchOne(db,sql:"SELECT payload FROM history_capture WHERE id=? AND record_id=?",arguments:[final.captureID,Self.key(id)]) else{throw HistoryError.stale}
                    let capture=try HistoryJSON.decode(HistoryCapture.self,bytes)
                    guard capture.stop==nil,(final.source == .microphone ? capture.microphoneEnabled:capture.selectedBundleID != nil) else{throw HistoryError.invalid}
                    let count=try Int.fetchOne(db,sql:"SELECT count(*) FROM history_final WHERE record_id=?",arguments:[Self.key(id)]) ?? 0
                    let text=try Int.fetchOne(db,sql:"SELECT coalesce(sum(text_bytes),0) FROM history_final WHERE record_id=?",arguments:[Self.key(id)]) ?? 0
                    guard count<HistoryBounds.rows,text+final.text.utf8.count<=HistoryBounds.text else{throw HistoryError.capacity}
                    try db.execute(sql:"INSERT INTO history_final VALUES(?,?,?,?,?,?,?)",arguments:[final.id,Self.key(id),final.captureID,final.source.rawValue,final.startUptimeNanoseconds.sortBytes,final.text.utf8.count,try HistoryJSON.encode(final)])
                }else if [.sourceUnavailable,.discontinuity].contains(observation.event.kind){
                    var updated=try Self.bumped(r);if !updated.gaps.contains(.sourceUnavailable){updated.gaps.append(.sourceUnavailable)};try Self.put(db,updated);return
                }else{return}
                try Self.put(db,Self.bumped(r))
            }
        }
    }
    private static func hasUnknownCaptureEnd(_ db:Database,_ id:UUID)throws->Bool{
        try Data.fetchAll(db,sql:"SELECT payload FROM history_capture WHERE record_id=?",arguments:[key(id)])
            .contains{try HistoryJSON.decode(HistoryCapture.self,$0).stop?.quiesced != true}
    }
    func finish(_ id:UUID,outcome:HistoryRecordState,gap:HistoryGap?=nil,admission:@Sendable()->Bool={true})throws{
        try lock.withLock{
            try expire(admission:admission)
            try commit(admission:admission){db in
                let old=try Self.record(db,id)
                guard old.state == .recording || old.state == .paused else{
                    if old.state==outcome,gap==nil{return};throw HistoryError.stale
                }
                if outcome == .recording{guard old.state == .paused else{throw HistoryError.stale}}
                var r=try Self.bumped(old)
                if let gap,!r.gaps.contains(gap){r.gaps.append(gap)}
                if outcome != .recording,try Self.hasUnknownCaptureEnd(db,id),!r.gaps.contains(.captureEndUnknown){r.gaps.append(.captureEndUnknown)}
                r.state=outcome == .completed && !r.gaps.isEmpty ? .partial:outcome
                if outcome != .recording && outcome != .paused{r.endedAt=clock().timeIntervalSince1970}
                try Self.put(db,r)
            }
        }
    }
    @discardableResult func edit(_ id:UUID,expectedRevision:Int64,title:String,note:String,admission:@Sendable()->Bool={true})throws->HistoryRecord{
        try lock.withLock{
            try expire(admission:admission)
            return try commit(content:true,admission:admission){db in
                let old=try Self.record(db,id);guard old.revision==expectedRevision else{throw HistoryError.stale}
                var r=try Self.bumped(old);r.title=title;r.note=note;try Self.put(db,r);return r
            }
        }
    }
    func list(offset:Int=0)throws->HistoryPage{
        try lock.withLock{
            guard (0...HistoryBounds.records).contains(offset) else{throw HistoryError.invalid};try expire()
            return try required().read{db in
                let rows=try Data.fetchAll(db,sql:"SELECT payload FROM history_record ORDER BY created_at DESC,id LIMIT 21 OFFSET ?",arguments:[offset])
                let records=try rows.prefix(20).map{try HistoryJSON.decode(HistoryRecord.self,$0)}
                return HistoryPage(records:records,nextOffset:rows.count>20 ? offset+20:nil)
            }
        }
    }
    func detail(_ id:UUID,offset:Int=0,all:Bool=false)throws->HistoryDetail{
        try lock.withLock{
            guard (0...HistoryBounds.rows).contains(offset) else{throw HistoryError.invalid};try expire()
            return try required().read{try Self.detail($0,id,offset:offset,all:all)}
        }
    }
    private static func detail(_ db:Database,_ id:UUID,offset:Int=0,all:Bool=false)throws->HistoryDetail{
                let record=try Self.record(db,id)
                let captures=try Data.fetchAll(db,sql:"SELECT payload FROM history_capture WHERE record_id=? ORDER BY ordinal",arguments:[Self.key(id)])
                    .map{try HistoryJSON.decode(HistoryCapture.self,$0)}
                let data=try Data.fetchAll(db,sql:"SELECT f.payload FROM history_final f JOIN history_capture c ON f.capture_id=c.id WHERE f.record_id=? ORDER BY c.ordinal,f.sort_ticks,f.id LIMIT ? OFFSET ?",arguments:[Self.key(id),all ? HistoryBounds.rows:HistoryBounds.pageRows,offset])
                var rows:[HistoryFinal]=[],size=0
                for bytes in data{
                    let row=try HistoryJSON.decode(HistoryFinal.self,bytes)
                    if !all && size+row.text.utf8.count>HistoryBounds.pageBytes{break}
                    rows.append(row);size+=row.text.utf8.count
                }
                let count=try Int.fetchOne(db,sql:"SELECT count(*) FROM history_final WHERE record_id=?",arguments:[Self.key(id)]) ?? 0
                return HistoryDetail(record:record,captures:captures,rows:rows,nextOffset:offset+rows.count<count ? offset+rows.count:nil,totalRows:count)
    }
    /// Reads the complete actual bounded record, never the selected view page.
    /// No vault/open/key is created and no schema migration occurs here.
    func readNotesSource(_ id:UUID,expectedRevision:Int64,selection:HistoryNotesSelection,intentID:UUID,
                         admission:@Sendable()->Bool)throws->HistoryNotesStoreRead{
        try lock.withLock{
            guard admission() else{throw HistoryError.stale}
            let original=try required()
            guard try storage.exists(),try storage.load()==HistorySnapshotCodec.encode(original) else{throw HistoryError.invalid}
            guard admission() else{throw HistoryError.stale}
            try expire(admission:admission)
            let current=try required();try Self.validate(current)
            let all=try current.read{try Self.detail($0,id,all:true)},record=all.record
            let now=clock().timeIntervalSince1970
            guard now.isFinite,now<record.expiresAt,record.revision==expectedRevision,record.revision<Int64.max,
                  record.state != .recording,!all.rows.isEmpty,all.rows.count==all.totalRows else{throw HistoryError.stale}
            let rows:[HistoryFinal],kind:String
            switch selection{
            case .fullSavedTranscript:rows=all.rows;kind="full_saved_transcript"
            case .excerpt(let first,let last):
                guard let a=all.rows.firstIndex(where:{$0.id==first}),let z=all.rows.firstIndex(where:{$0.id==last}),a<=z else{throw HistoryError.invalid}
                rows=Array(all.rows[a...z]);kind="explicit_excerpt"
            }
            let value:[String:Any]=["schemaVersion":1,"recordID":Self.key(record.id),"recordRevision":String(record.revision),
                "selection":["kind":kind,"totalSavedRows":all.totalRows,"includedRows":rows.count,"firstRowID":rows[0].id,"lastRowID":rows[rows.count-1].id],
                "recordState":record.state.rawValue,"gaps":HistoryNotesData.gaps.filter{record.gaps.map(\.rawValue).contains($0)},
                "rows":rows.map{["id":$0.id,"revision":String($0.revision.value),"source":$0.source == .microphone ? "microphone":"selected_app_audio","text":$0.text]}]
            let raw=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])
            let data=try HistoryNotesData.source(raw)
            guard admission(),clock().timeIntervalSince1970<record.expiresAt else{throw HistoryError.stale}
            return HistoryNotesStoreRead(store:self,data:data,intentID:intentID,expiresAt:record.expiresAt)
        }
    }
    func deleteSource(_ id:UUID,expectedRevision:Int64,captureID:String,source:TranscriptSource,admission:@Sendable()->Bool={true})throws{
        try lock.withLock{
            try expire(admission:admission)
            let record=try required().read{db in
                let r=try Self.record(db,id);guard r.revision==expectedRevision,
                    try Int.fetchOne(db,sql:"SELECT count(*) FROM history_capture WHERE record_id=? AND id=?",arguments:[Self.key(id),captureID])==1 else{throw HistoryError.stale};return r
            }
            try remove(source:(captureID,source.rawValue),admission:admission){db in
                var r=try Self.bumped(record);if !r.gaps.contains(.sourceDeleted){r.gaps.append(.sourceDeleted)}
                if !r.blockedSources.contains(source){r.blockedSources.append(source)}
                if r.state == .completed{r.state = .partial};try Self.put(db,r)
            }
        }
    }
    func delete(_ id:UUID,expectedRevision:Int64,admission:@Sendable()->Bool={true})throws{
        try lock.withLock{
            try expire(admission:admission)
            guard try required().read({try Self.record($0,id).revision})==expectedRevision else{throw HistoryError.stale}
            try remove(records:[Self.key(id)],admission:admission)
        }
    }
    func deleteAll(admission:@Sendable()->Bool={true})throws{
        try lock.withLock{try remove(records:Set(try required().read{try String.fetchAll($0,sql:"SELECT id FROM history_record")}),admission:admission)}
    }
    private static func validate(_ q:DatabaseQueue)throws{
        try q.read{db in
            guard try Int.fetchOne(db,sql:"PRAGMA user_version")==1 else{throw HistoryError.invalid}
            var expected=tables;expected["history_final_order"]=index
            for row in try Row.fetchAll(db,sql:"SELECT type,name,tbl_name,sql FROM sqlite_schema"){
                let name=try row.decode(String.self,forColumn:"name"),table=try row.decode(String.self,forColumn:"tbl_name")
                let sql=try row.decode(String?.self,forColumn:"sql")
                if sql==nil,name.hasPrefix("sqlite_autoindex_"),tables[table] != nil{continue}
                guard let actual=sql,expected.removeValue(forKey:name)==actual else{throw HistoryError.invalid}
            }
            guard expected.isEmpty,try Row.fetchAll(db,sql:"PRAGMA foreign_key_check").isEmpty else{throw HistoryError.invalid}
            let recordRows=try Row.fetchAll(db,sql:"SELECT * FROM history_record")
            guard recordRows.count<=HistoryBounds.records else{throw HistoryError.capacity}
            var records:[String:HistoryRecord]=[:]
            for row in recordRows{
                let data=try row.decode(Data.self,forColumn:"payload");guard data.count<=16_384 else{throw HistoryError.invalid}
                let r=try HistoryJSON.decode(HistoryRecord.self,data);try r.validate()
                let id=try row.decode(String.self,forColumn:"id")
                guard id==key(r.id),try row.decode(Double.self,forColumn:"created_at")==r.createdAt,
                      try row.decode(Double.self,forColumn:"expires_at")==r.expiresAt else{throw HistoryError.invalid};records[id]=r
            }
            let captureRows=try Row.fetchAll(db,sql:"SELECT * FROM history_capture")
            guard captureRows.count<=HistoryBounds.records*HistoryBounds.captures else{throw HistoryError.capacity}
            var captures:[String:(String,HistoryCapture)]=[:],captureCount:[String:Int]=[:]
            for row in captureRows{
                let data=try row.decode(Data.self,forColumn:"payload");guard data.count<=2048 else{throw HistoryError.invalid}
                let c=try HistoryJSON.decode(HistoryCapture.self,data);try c.validate()
                let id=try row.decode(String.self,forColumn:"id"),owner=try row.decode(String.self,forColumn:"record_id"),ordinal=try row.decode(Int.self,forColumn:"ordinal")
                guard id==c.id,records[owner] != nil,(0..<HistoryBounds.captures).contains(ordinal) else{throw HistoryError.invalid}
                if let reason=c.stop?.reason,reason != .userStop,records[owner]?.gaps.contains(.captureFailure) != true{throw HistoryError.invalid}
                captureCount[owner,default:0]+=1;guard captureCount[owner]!<=HistoryBounds.captures else{throw HistoryError.capacity};captures[id]=(owner,c)
            }
            let finalRows=try Row.fetchAll(db,sql:"SELECT * FROM history_final")
            guard finalRows.count<=HistoryBounds.records*HistoryBounds.rows else{throw HistoryError.capacity}
            var rowCount:[String:Int]=[:],textCount:[String:Int]=[:]
            for row in finalRows{
                let data=try row.decode(Data.self,forColumn:"payload");guard data.count<=32_768 else{throw HistoryError.invalid}
                let f=try HistoryJSON.decode(HistoryFinal.self,data);try f.validate()
                let owner=try row.decode(String.self,forColumn:"record_id"),captureID=try row.decode(String.self,forColumn:"capture_id")
                guard try row.decode(String.self,forColumn:"id")==f.id,captureID==f.captureID,
                      let capture=captures[captureID],capture.0==owner,
                      try row.decode(UInt32.self,forColumn:"source")==f.source.rawValue,
                      try row.decode(Data.self,forColumn:"sort_ticks")==f.startUptimeNanoseconds.sortBytes,
                      try row.decode(Int.self,forColumn:"text_bytes")==f.text.utf8.count,
                      f.source == .microphone ? capture.1.microphoneEnabled:capture.1.selectedBundleID != nil else{throw HistoryError.invalid}
                try capture.1.stop?.follows(f)
                rowCount[owner,default:0]+=1;textCount[owner,default:0]+=f.text.utf8.count
                guard rowCount[owner]!<=HistoryBounds.rows,textCount[owner]!<=HistoryBounds.text else{throw HistoryError.capacity}
            }
        }
    }
}
