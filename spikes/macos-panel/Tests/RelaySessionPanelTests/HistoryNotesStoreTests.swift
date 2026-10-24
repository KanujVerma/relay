import Foundation
import XCTest
import GRDB
import GRDBSQLite
import RelayProfile
@testable import RelaySessionPanel

private struct NotesStoreKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:89,count:32)}}
private final class NotesStoreClock:@unchecked Sendable{
    private let lock=NSLock();private var value=Date(timeIntervalSince1970:1_800_000_000)
    func now()->Date{lock.withLock{value}}
    func advance(_ seconds:TimeInterval){lock.withLock{value.addTimeInterval(seconds)}}
}
private final class NotesFaultStorage:HistoryOwnedSnapshotStorage,@unchecked Sendable{
    enum Failure:Equatable{case none,beforeWrite,afterWrite}
    let real:HistoryVaultStorage,fileURL:URL
    private let lock=NSLock();private var failure:Failure = .none
    init(_ real:HistoryVaultStorage,fileURL:URL){self.real=real;self.fileURL=fileURL}
    func rawCiphertext()throws->Data{try Data(contentsOf:fileURL)}
    func arm(_ mode:Failure){lock.withLock{failure=mode}}
    func beginAccess(create:Bool)throws{try real.beginAccess(create:create)}
    func endAccess()throws{try real.endAccess()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ bytes:Data,createKey:Bool)throws{
        let mode=lock.withLock{let value=failure;failure = .none;return value}
        if mode == .beforeWrite{throw ProfileError.unavailable}
        try real.save(bytes,createKey:createKey)
        if mode == .afterWrite{throw ProfileError.unavailable}
    }
}
/// Owns this fixture's real unmanaged SQLite statement across queue calls.
/// No pointer is captured by a Sendable closure or exposed to production code.
private final class NotesHeldSQLiteStatement:@unchecked Sendable{
    private let lock=NSLock();private var value:OpaquePointer?
    func prepare(_ db:Database)throws{
        try lock.withLock{
            guard value==nil,sqlite3_prepare_v2(db.sqliteConnection,"SELECT id FROM history_record",-1,&value,nil)==SQLITE_OK,
                  sqlite3_step(value)==SQLITE_ROW else{throw HistoryError.invalid}
        }
    }
    func finish(){lock.withLock{if let value{sqlite3_finalize(value);self.value=nil}}}
}

@MainActor final class HistoryNotesStoreTests:XCTestCase{
    private func fixture()throws->(HistoryStore,NotesFaultStorage,ProtectedSnapshotVault,UUID,NotesStoreClock){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-store-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let location=directory.appendingPathComponent("Relay/History"),key=NotesStoreKey(),clock=NotesStoreClock()
        let port=NotesFaultStorage(HistoryVaultStorage(directory:location,keys:key),fileURL:location.appendingPathComponent("history.relayvault")),vault=ProtectedSnapshotVault(directory:location,purpose:.history,keys:key)
        let store=HistoryStore(storage:port,clock:clock.now);try store.open(create:true)
        addTeardownBlock{try? store.close();try? FileManager.default.removeItem(at:directory)}
        let record=try store.createRecord(),transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)};var events=HistoryTestEvents();events.start(transcript)
        events.final(1,text:"Fictional original question about a queue.",into:transcript)
        events.final(2,text:"Fictional original microphone reply about bounded storage.",source:1,into:transcript);events.stop(into:transcript)
        for observation in observations{try store.append(observation,to:record.id)}
        try store.finish(record.id,outcome:.completed)
        return(store,port,vault,record.id,clock)
    }
    private func source(_ store:HistoryStore,_ id:UUID,selection:HistoryNotesSelection = .fullSavedTranscript)throws->HistoryNotesStoreRead{
        try store.readNotesSource(id,expectedRevision:store.detail(id).record.revision,selection:selection,intentID:UUID(),admission:{true})
    }
    private func output(_ source:HistoryNotesStoreRead)throws->HistoryNotesOutputData{
        let row=source.sourceData.rows[0]
        return try HistoryNotesData.output(HistoryNotesFixtures.encode(["schemaVersion":1,"summary":[["text":"A fictional queue discussion.","citations":[["rowID":row.rowID,"quote":"Fictional original"]]]],"decisions":[],"nextSteps":[]]),source:source.sourceData)
    }
    private func provenance(_ source:HistoryNotesStoreRead)->HistoryNotesGenerationData{
        .init(scopeID:UUID(),scopeEpoch:1,operationID:source.intentID,requestID:UUID(),requestSequence:1,transferID:UUID(),completedAt:"2027-01-15T08:00:00.000Z")
    }
    private func save(_ store:HistoryStore,_ source:HistoryNotesStoreRead)throws->HistoryNotesCommitOutcome{
        try store.saveGeneratedNotes(output(source),provenance:provenance(source),modelID:"fictional-declared-model-DATA",source:source,operationID:source.intentID,admission:{true})
    }
    private func version(_ vault:ProtectedSnapshotVault)throws->Int{
        let q=try HistorySnapshotCodec.decode(vault.load());defer{try? q.close()};return try q.read{try Int.fetchOne($0,sql:"PRAGMA user_version")!}
    }
    func testV1SourceAndOrdinaryWritesStayV1UntilActualExplicitGeneratedSave()async throws{
        let(store,port,vault,id,_)=try fixture(),before=try port.rawCiphertext()
        XCTAssertEqual(try version(vault),1);XCTAssertNil(try store.generatedNotes(id));_=try source(store,id)
        XCTAssertEqual(try port.rawCiphertext(),before)
        let r=try store.detail(id).record
        _=try store.edit(id,expectedRevision:r.revision,title:"Original user title",note:"Original user-only note")
        XCTAssertEqual(try version(vault),1)
        let original=try source(store,id),outcome=try save(store,original)
        XCTAssertTrue(outcome.cleanupComplete);XCTAssertEqual(try version(vault),2)
        XCTAssertEqual(outcome.receipt.operationID,original.intentID);XCTAssertEqual(outcome.receipt.sourceRecordRevision,original.sourceData.recordRevision)
        XCTAssertEqual(outcome.receipt.savedAtRecordRevision,original.sourceData.recordRevision+1)
        XCTAssertEqual(outcome.receipt.noteRevision,1);XCTAssertEqual(outcome.document.origin,"generated")
        XCTAssertEqual(try store.detail(id).record.note,"Original user-only note")
        XCTAssertEqual(try store.detail(id).record.title,"Original user title")
    }
    func testActualEncryptedRestartKeepsTypedDerivedSourceAndCannotReplayOriginalRead()async throws{
        let(store,port,vault,id,clock)=try fixture(),read=try source(store,id),outcome=try save(store,read)
        let ciphertext=try port.rawCiphertext()
        XCTAssertNil(ciphertext.range(of:Data("A fictional queue discussion.".utf8)))
        XCTAssertNil(ciphertext.range(of:Data("Fictional original".utf8)))
        XCTAssertFalse(ciphertext.starts(with:Data("SQLite format 3".utf8)))
        XCTAssertThrowsError(try save(store,read))
        try store.close();let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        XCTAssertEqual(try fresh.generatedNotes(id),outcome.document);XCTAssertEqual(try version(vault),2)
        XCTAssertEqual(outcome.document.sourceRows.count,2)
    }
    func testStaleForeignStoreAndRetiredAdmissionCannotReplaceTheExistingNote()async throws{
        let(store,port,_,id,_)=try fixture(),first=try save(store,source(store,id)),stale=try source(store,id)
        let r=try store.detail(id).record;_=try store.edit(id,expectedRevision:r.revision,title:"New user title",note:"new manual draft")
        let before=try port.rawCiphertext();XCTAssertThrowsError(try save(store,stale));XCTAssertEqual(try port.rawCiphertext(),before)
        XCTAssertEqual(try store.generatedNotes(id),first.document)
        let current=try source(store,id),(other,_,_,_,_)=try fixture()
        XCTAssertThrowsError(try save(other,current))
        XCTAssertThrowsError(try store.saveGeneratedNotes(output(current),provenance:provenance(current),modelID:"fictional",source:current,operationID:current.intentID,admission:{false}))
        XCTAssertEqual(try port.rawCiphertext(),before)
    }
    func testGeneratedUserEditUsesRecordAndNoteCASAndPreservesOriginalCitations()async throws{
        let(store,_,_,id,clock)=try fixture(),first=try save(store,source(store,id)),r=try store.detail(id).record
        clock.advance(-3600)
        let edited=try store.editGeneratedNotes(id,expectedRecordRevision:r.revision,noteID:first.document.noteID,expectedNoteRevision:1,
            texts:HistoryNotesEditedTexts(summary:["A shorter user-edited explanation."],decisions:[],nextSteps:[]),operationID:UUID(),admission:{true})
        XCTAssertEqual(edited.document.noteID,first.document.noteID);XCTAssertEqual(edited.document.noteRevision,2)
        XCTAssertEqual(edited.document.origin,"generated_user_edited");XCTAssertNotNil(edited.document.editedAt)
        XCTAssertLessThan(try XCTUnwrap(edited.document.editedAt),first.document.generation.completedAt)
        XCTAssertEqual(edited.document.generation,first.document.generation)
        XCTAssertEqual(edited.document.sourceRows,first.document.sourceRows)
        XCTAssertEqual(edited.document.notes.summary[0].citations,first.document.notes.summary[0].citations)
        XCTAssertThrowsError(try store.editGeneratedNotes(id,expectedRecordRevision:r.revision,noteID:first.document.noteID,expectedNoteRevision:1,texts:.init(summary:["stale"],decisions:[],nextSteps:[]),operationID:UUID(),admission:{true}))
        let latest=try store.detail(id).record
        XCTAssertThrowsError(try store.editGeneratedNotes(id,expectedRecordRevision:latest.revision,noteID:first.document.noteID,expectedNoteRevision:2,texts:.init(summary:[],decisions:[],nextSteps:[]),operationID:UUID(),admission:{true}))
    }
    func testDeletingIncludedSourceRemovesEvenEditedDerivedNotesButKeepsManualNotes()async throws{
        let(store,_,_,id,_)=try fixture(),first=try save(store,source(store,id)),r=try store.detail(id).record
        _=try store.editGeneratedNotes(id,expectedRecordRevision:r.revision,noteID:first.document.noteID,expectedNoteRevision:1,texts:.init(summary:["Edited derived text"],decisions:[],nextSteps:[]),operationID:UUID(),admission:{true})
        let detail=try store.detail(id)
        _=try store.edit(id,expectedRevision:detail.record.revision,title:"Keep title",note:"Keep manual note")
        let latest=try store.detail(id)
        try store.deleteSource(id,expectedRevision:latest.record.revision,captureID:latest.captures[0].id,source:.microphone)
        XCTAssertNil(try store.generatedNotes(id));XCTAssertEqual(try store.detail(id).record.note,"Keep manual note")
    }
    func testDeletingUnincludedSourcePreservesAnExactEarlierExcerptAcrossRestore()async throws{
        let(store,port,_,id,clock)=try fixture(),detail=try store.detail(id),row=detail.rows[0]
        let selected=try source(store,id,selection:.excerpt(firstRowID:row.id,lastRowID:row.id)),first=try save(store,selected)
        let latest=try store.detail(id);try store.deleteSource(id,expectedRevision:latest.record.revision,captureID:latest.captures[0].id,source:.microphone)
        XCTAssertEqual(try store.generatedNotes(id),first.document)
        try store.close();let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        XCTAssertEqual(try fresh.generatedNotes(id)?.selection.totalSavedRows,2)
        XCTAssertEqual(try fresh.generatedNotes(id)?.selection.includedRows,1)
    }
    func testThrowingAfterDurableWriteIsIndeterminateAndRequiresActualOwnedReopen()async throws{
        let(store,port,_,id,clock)=try fixture(),read=try source(store,id)
        port.arm(.afterWrite)
        XCTAssertThrowsError(try save(store,read)){XCTAssertTrue($0 is HistoryNotesCommitError)}
        XCTAssertThrowsError(try store.generatedNotes(id));XCTAssertThrowsError(try save(store,read))
        try store.close();let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        XCTAssertNotNil(try fresh.generatedNotes(id))
        XCTAssertEqual(try fresh.detail(id).record.revision,read.sourceData.recordRevision+1)
    }
    func testKnownBeforeWriteFailureLeavesCiphertextButDoesNotAuthorizeCachedRetry()async throws{
        let(store,port,_,id,clock)=try fixture(),before=try port.rawCiphertext(),read=try source(store,id)
        port.arm(.beforeWrite);XCTAssertThrowsError(try save(store,read));XCTAssertEqual(try port.rawCiphertext(),before)
        XCTAssertThrowsError(try store.generatedNotes(id))
        try store.close();let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        XCTAssertNil(try fresh.generatedNotes(id));XCTAssertEqual(try fresh.detail(id).record.revision,read.sourceData.recordRevision)
    }
    func testMaximumActualRestoredStoreIssuesAll1024OriginalRowsAndPersistsAllProofs()async throws{
        let(store,port,vault,id,clock)=try fixture(),detail=try store.detail(id)
        let transcript=SessionTranscriptStore();var actual:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={actual.append($0)}
        var events=HistoryTestEvents();events.session=detail.captures[0].captureSessionID;events.start(transcript)
        for index in 1...1024{events.final(UInt64(index),text:String(repeating:"\u{1}",count:256),into:transcript)}
        events.stop(into:transcript)
        let finals=actual.compactMap(\.final);XCTAssertEqual(finals.count,1024)
        // This resource-bound restore fixture uses only actual validator-issued
        // originals. The fresh production store validates every persisted row;
        // this does not claim 1024 incremental app writes or source authority.
        let q=try HistorySnapshotCodec.decode(vault.load())
        var capture=detail.captures[0]
        capture.stop=try HistoryCaptureStop(actual.last!.event,now:clock.now().timeIntervalSince1970)
        let finishedCapture=capture
        try await q.write{db in
            try db.execute(sql:"DELETE FROM history_final WHERE record_id=?",arguments:[id.uuidString.lowercased()])
            try db.execute(sql:"UPDATE history_capture SET payload=? WHERE id=?",arguments:[try HistoryJSON.encode(finishedCapture),finishedCapture.id])
            for row in finals{
                try db.execute(sql:"INSERT INTO history_final VALUES(?,?,?,?,?,?,?)",arguments:[row.id,id.uuidString.lowercased(),row.captureID,row.source.rawValue,row.startUptimeNanoseconds.sortBytes,row.text.utf8.count,try HistoryJSON.encode(row)])
            }
        }
        let full=try HistorySnapshotCodec.encode(q);try q.close();try store.close();try vault.save(full,createKey:false)
        let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        let read=try source(fresh,id)
        XCTAssertEqual(read.sourceData.rows.map(\.rowID),finals.map(\.id))
        XCTAssertEqual(read.sourceData.rows.reduce(0){$0+$1.text.utf8.count},262144)
        XCTAssertEqual(read.sourceData.selection.includedRows,1024);XCTAssertLessThan(read.sourceData.rawBytes.count,2*1024*1024)
        let output=try HistoryNotesData.output(HistoryNotesFixtures.encode(["schemaVersion":1,"summary":[["text":"Fictional maximum source.","citations":[["rowID":finals[0].id,"quote":"\u{1}"]]]],"decisions":[],"nextSteps":[]]),source:read.sourceData)
        let outcome=try fresh.saveGeneratedNotes(output,provenance:provenance(read),modelID:"fictional",source:read,operationID:read.intentID,admission:{true})
        XCTAssertEqual(outcome.document.sourceRows.count,1024);XCTAssertGreaterThan(outcome.document.canonicalBytes.count,100000)
        XCTAssertLessThanOrEqual(outcome.document.canonicalBytes.count,262144)
        XCTAssertEqual(try fresh.generatedNotes(id),outcome.document)
    }
    func testPositiveSaveReturnsReceiptWhenActualOldSQLiteCloseFails()async throws{
        let(store,port,_,id,clock)=try fixture(),read=try source(store,id)
        // Inspect this test's own private queue solely to hold a real unmanaged
        // SQLite statement. No production hook or receipt is fabricated.
        let wrapped=try XCTUnwrap(Mirror(reflecting:store).children.first{$0.label=="queue"}?.value)
        let old=try XCTUnwrap(Mirror(reflecting:wrapped).children.first?.value as? DatabaseQueue)
        let statement=NotesHeldSQLiteStatement()
        try await old.read{db in try statement.prepare(db)}
        defer{statement.finish()}
        let outcome=try save(store,read)
        XCTAssertFalse(outcome.cleanupComplete);XCTAssertEqual(outcome.receipt.noteRevision,1)
        XCTAssertThrowsError(try store.generatedNotes(id))
        let other=HistoryStore(storage:HistoryVaultStorage(directory:port.fileURL.deletingLastPathComponent(),keys:NotesStoreKey()),clock:clock.now)
        XCTAssertThrowsError(try other.open(create:false))
        statement.finish();try store.close()
        let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        XCTAssertEqual(try fresh.generatedNotes(id),outcome.document)
    }
    func testCapacityFailureBeforeSaveKeepsPreviousCanonicalAndVersion()async throws{
        let(store,port,vault,id,clock)=try fixture(),before=try vault.load(),cipher=try port.rawCiphertext();try store.close()
        let bounded=HistoryStore(storage:port,clock:clock.now,contentLimitBytes:before.count);defer{try? bounded.close()}
        try bounded.open(create:false);let read=try source(bounded,id)
        XCTAssertThrowsError(try save(bounded,read))
        XCTAssertEqual(try vault.load(),before);XCTAssertEqual(try port.rawCiphertext(),cipher);XCTAssertNil(try bounded.generatedNotes(id));XCTAssertEqual(try version(vault),1)
    }
    func testUnknownSchemaOrChangedStoredMembershipRejectsRestoreWithoutHealing()async throws{
        let(store,port,vault,id,clock)=try fixture();_=try save(store,source(store,id));let original=try vault.load();try store.close()
        for mutation in 0..<3{
            let q=try HistorySnapshotCodec.decode(original)
            try await q.write{db in
                if mutation==0{try db.execute(sql:"PRAGMA user_version=3")}
                else if mutation==1{try db.execute(sql:"CREATE TABLE unknown_notes_shape(x)")}
                else{
                    let data=try Data.fetchOne(db,sql:"SELECT payload FROM history_generated_note WHERE record_id=?",arguments:[id.uuidString.lowercased()])!
                    var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
                    var proofs=object["sourceRows"] as! [[String:String]];proofs[0]["textDigest"]=String(repeating:"0",count:64);object["sourceRows"]=proofs
                    try db.execute(sql:"UPDATE history_generated_note SET payload=? WHERE record_id=?",arguments:[try HistoryNotesFixtures.encode(object),id.uuidString.lowercased()])
                }
            }
            let invalid=try HistorySnapshotCodec.encode(q);try q.close();try vault.save(invalid,createKey:false)
            let before=try port.rawCiphertext(),fresh=HistoryStore(storage:port,clock:clock.now)
            XCTAssertThrowsError(try fresh.open(create:false));try fresh.close();XCTAssertEqual(try port.rawCiphertext(),before)
        }
    }

    func testDeleteOnlyGeneratedNotesKeepsOriginalTranscriptAndManualFields()async throws{
        let(store,_,vault,id,_)=try fixture()
        let old=try store.detail(id).record;_=try store.edit(id,expectedRevision:old.revision,title:"Keep the title",note:"Keep my manual wording.")
        let saved=try save(store,source(store,id)),before=try store.detail(id)
        let operation=UUID(),outcome=try store.deleteGeneratedNotes(id,expectedRecordRevision:before.record.revision,
            noteID:saved.document.noteID,expectedNoteRevision:saved.document.noteRevision,operationID:operation,admission:{true})
        XCTAssertTrue(outcome.cleanupComplete);XCTAssertEqual(outcome.receipt.operationID,operation)
        XCTAssertEqual(outcome.receipt.noteID,saved.document.noteID);XCTAssertEqual(outcome.receipt.deletedNoteRevision,saved.document.noteRevision)
        XCTAssertEqual(outcome.receipt.savedAtRecordRevision,before.record.revision+1)
        let after=try store.detail(id);XCTAssertEqual(after.rows,before.rows);XCTAssertEqual(after.captures,before.captures)
        XCTAssertEqual(after.record.title,"Keep the title");XCTAssertEqual(after.record.note,"Keep my manual wording.")
        XCTAssertNil(try store.generatedNotes(id));XCTAssertEqual(try version(vault),2)
    }
    func testDeleteRejectsMissingV1AndEveryStaleNoteRecordOrRetiredGateWithoutAWrite()async throws{
        let(store,port,vault,id,_)=try fixture(),v1=try port.rawCiphertext(),revision=try store.detail(id).record.revision
        XCTAssertThrowsError(try store.deleteGeneratedNotes(id,expectedRecordRevision:revision,noteID:UUID(),expectedNoteRevision:1,operationID:UUID(),admission:{true}))
        XCTAssertEqual(try port.rawCiphertext(),v1);XCTAssertEqual(try version(vault),1)
        let saved=try save(store,source(store,id)),before=try port.rawCiphertext(),current=try store.detail(id).record.revision
        for (record,note,noteRevision,allowed) in [(current-1,saved.document.noteID,saved.document.noteRevision,true),
            (current,UUID(),saved.document.noteRevision,true),(current,saved.document.noteID,saved.document.noteRevision+1,true),
            (current,saved.document.noteID,saved.document.noteRevision,false)]{
            XCTAssertThrowsError(try store.deleteGeneratedNotes(id,expectedRecordRevision:record,noteID:note,expectedNoteRevision:noteRevision,operationID:UUID(),admission:{allowed}))
            XCTAssertEqual(try port.rawCiphertext(),before)
        }
        XCTAssertEqual(try store.generatedNotes(id),saved.document)
    }
    func testDeleteUnknownAfterWriteHasNoReceiptAndRequiresActualReopen()async throws{
        let(store,port,_,id,clock)=try fixture(),saved=try save(store,source(store,id)),current=try store.detail(id).record.revision
        port.arm(.afterWrite)
        do{_=try store.deleteGeneratedNotes(id,expectedRecordRevision:current,noteID:saved.document.noteID,expectedNoteRevision:saved.document.noteRevision,operationID:UUID(),admission:{true});XCTFail("Unknown deletion issued a receipt")}
        catch HistoryNotesCommitError.indeterminate{}catch{XCTFail("Expected typed unknown outcome")}
        XCTAssertThrowsError(try store.generatedNotes(id));try store.close()
        let fresh=HistoryStore(storage:port,clock:clock.now);defer{try? fresh.close()};try fresh.open(create:false)
        XCTAssertNil(try fresh.generatedNotes(id));XCTAssertEqual(try fresh.detail(id).rows.count,2)
    }
    func testPositiveDeleteReceiptSurvivesActualOldQueueCloseFailure()async throws{
        let(store,_,_,id,_)=try fixture(),saved=try save(store,source(store,id)),current=try store.detail(id).record.revision
        let wrapped=try XCTUnwrap(Mirror(reflecting:store).children.first{$0.label=="queue"}?.value)
        let old=try XCTUnwrap(Mirror(reflecting:wrapped).children.first?.value as? DatabaseQueue),statement=NotesHeldSQLiteStatement()
        try await old.read{db in try statement.prepare(db)};defer{statement.finish()}
        let outcome=try store.deleteGeneratedNotes(id,expectedRecordRevision:current,noteID:saved.document.noteID,expectedNoteRevision:saved.document.noteRevision,operationID:UUID(),admission:{true})
        XCTAssertFalse(outcome.cleanupComplete);XCTAssertEqual(outcome.receipt.noteID,saved.document.noteID)
        XCTAssertThrowsError(try store.generatedNotes(id));statement.finish();try store.close()
    }
}
