import Foundation
import GRDB

/// Same owned in-memory SQLite candidate as History and Notes. No path,
/// plaintext index, second connection owner or provider call is introduced.
enum LearningLedger {
    static let controlID="__learning_control_v1__"
    static let tables:[String:String]=[
        "learning_episode":"CREATE TABLE learning_episode (id TEXT PRIMARY KEY, record_id TEXT NOT NULL REFERENCES history_record(id) ON DELETE CASCADE, payload BLOB NOT NULL CHECK(typeof(payload)='blob' AND length(payload)<=65536))",
        "learning_rule":"CREATE TABLE learning_rule (id TEXT PRIMARY KEY, payload BLOB NOT NULL CHECK(typeof(payload)='blob' AND length(payload)<=8192))"
    ]
    static func install(_ db:Database)throws{for key in ["learning_episode","learning_rule"]{try db.execute(sql:tables[key]!)}}
    static func validateSources(_ db:Database,_ episode:LearningEpisode,now:TimeInterval?=nil)throws{
        try episode.validate()
        guard let id=episode.recordID,let expires=episode.expiresAt,
              let raw=try Data.fetchOne(db,sql:"SELECT payload FROM history_record WHERE id=?",arguments:[id.uuidString.lowercased()]) else{throw HistoryError.stale}
        let record=try HistoryJSON.decode(HistoryRecord.self,raw);try record.validate()
        guard record.id==id,record.expiresAt==expires,now.map({$0.isFinite && $0<expires}) ?? true else{throw HistoryError.stale}
        for final in [episode.question,episode.reply,episode.continuation]{
            guard let actual=try Data.fetchOne(db,sql:"SELECT payload FROM history_final WHERE id=? AND record_id=?",arguments:[final.id,id.uuidString.lowercased()]),
                  try actual==HistoryJSON.encode(final) else{throw HistoryError.stale}
        }
    }
    static func read(_ db:Database)throws->LearningArchive{
        let rows=try Row.fetchAll(db,sql:"SELECT id,record_id,payload FROM learning_episode ORDER BY id")
        guard rows.count<=LearningBounds.episodes else{throw HistoryError.capacity}
        var episodes:[LearningEpisode]=[],total=0
        for row in rows{
            let raw=try row.decode(Data.self,forColumn:"payload");total+=raw.count
            guard raw.count<=65536,total<=LearningBounds.retainedBytes else{throw HistoryError.capacity}
            let episode=try HistoryJSON.decode(LearningEpisode.self,raw)
            guard try row.decode(String.self,forColumn:"id")==episode.id.uuidString.lowercased(),
                  try row.decode(String.self,forColumn:"record_id")==episode.recordID?.uuidString.lowercased() else{throw HistoryError.invalid}
            try validateSources(db,episode);episodes.append(episode)
        }
        let stored=try Row.fetchAll(db,sql:"SELECT id,payload FROM learning_rule ORDER BY id")
        // Fixed bound explicitly includes one content-free control row.
        guard stored.count<=LearningBounds.rules+1 else{throw HistoryError.capacity}
        var control:LearningControlRecord?,rules:[LearningRule]=[]
        for row in stored{
            let id=try row.decode(String.self,forColumn:"id"),raw=try row.decode(Data.self,forColumn:"payload")
            if id==controlID{
                guard control==nil,raw.count<=2048 else{throw HistoryError.invalid}
                control=try HistoryJSON.decode(LearningControlRecord.self,raw);try control!.validate()
            }else{
                guard raw.count<=8192,LearningControlRecord.knownRuleIDs.contains(id) else{throw HistoryError.invalid}
                let rule=try HistoryJSON.decode(LearningRule.self,raw);guard rule.id==id else{throw HistoryError.invalid};rules.append(rule)
            }
        }
        guard let control else{throw HistoryError.invalid}
        let archive=LearningArchive(episodes:episodes,rules:rules,control:control);try archive.validate();return archive
    }
    static func write(_ archive:LearningArchive,to db:Database)throws{
        try archive.validate();guard let control=archive.control else{throw HistoryError.invalid}
        try db.execute(sql:"DELETE FROM learning_episode");try db.execute(sql:"DELETE FROM learning_rule")
        for episode in archive.episodes{
            let raw=try HistoryJSON.encode(episode)
            guard raw.count<=65536,let record=episode.recordID else{throw HistoryError.capacity}
            try db.execute(sql:"INSERT INTO learning_episode VALUES(?,?,?)",arguments:[episode.id.uuidString.lowercased(),record.uuidString.lowercased(),raw])
        }
        let metadata=try HistoryJSON.encode(control);guard metadata.count<=2048 else{throw HistoryError.capacity}
        try db.execute(sql:"INSERT INTO learning_rule VALUES(?,?)",arguments:[controlID,metadata])
        for rule in archive.rules{let raw=try HistoryJSON.encode(rule);guard raw.count<=8192 else{throw HistoryError.capacity};try db.execute(sql:"INSERT INTO learning_rule VALUES(?,?)",arguments:[rule.id,raw])}
    }
    static func applying(_ mutation:LearningMutation,to prior:LearningArchive,in db:Database,now:TimeInterval)throws->LearningArchive{
        try prior.validate();guard now.isFinite else{throw HistoryError.invalid}
        switch mutation{
        case .control(let pending):return try pending.applying(to:prior)
        case .save(let episode):
            guard let control=prior.control,control.enabled else{throw HistoryError.unavailable}
            try validateSources(db,episode,now:now)
            if let old=prior.episodes.first(where:{$0.id==episode.id}){guard old==episode else{throw HistoryError.invalid};return prior}
            let episodes=(prior.episodes+[episode]).sorted{$0.id.uuidString<$1.id.uuidString}
            let result=LearningArchive(episodes:episodes,rules:try LearningDerivation.rebuild(episodes,suppressed:control.suppressedRuleIDs),control:control)
            try result.validate();return result
        case .suppress,.reset:throw HistoryError.invalid // User controls require the exact consent/control CAS.
        }
    }
    static func copySurviving(from source:Database,to destination:Database)throws{
        let old=try read(source)
        let surviving=try old.episodes.filter{episode in
            do{try validateSources(destination,episode);return true}
            catch HistoryError.stale{return false}
        }
        guard let control=old.control else{throw HistoryError.invalid}
        let archive=LearningArchive(episodes:surviving,rules:try LearningDerivation.rebuild(surviving,suppressed:control.suppressedRuleIDs),control:control)
        try write(archive,to:destination)
    }
}

public enum LearningStoreCommitError:Error,Sendable{case indeterminate}
struct LearningStoreMutationOutcome:Sendable {
    let archive:LearningArchive,controlReceipt:LearningStoredControlReceipt?,cleanupComplete:Bool
}
