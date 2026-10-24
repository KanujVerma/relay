import Foundation
import XCTest
import GRDB
import RelayProfile
import RelayContextComposition
@testable import RelaySessionPanel

private struct LearningLedgerKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:119,count:32)}}
private final class LearningLedgerClock:@unchecked Sendable {
    private let lock=NSLock();private var date=Date(timeIntervalSince1970:1_800_000_000)
    func now()->Date{lock.withLock{date}}
    func advance(_ amount:TimeInterval){lock.withLock{date.addTimeInterval(amount)}}
}
private final class LearningLedgerStorage:HistoryOwnedSnapshotStorage,@unchecked Sendable {
    enum Failure:Equatable {case none,before,after}
    let real:HistoryVaultStorage,file:URL
    private let lock=NSLock();private var failure:Failure = .none
    init(_ root:URL){real=HistoryVaultStorage(directory:root,keys:LearningLedgerKey());file=root.appendingPathComponent("history.relayvault")}
    func arm(_ mode:Failure){lock.withLock{failure=mode}}
    func beginAccess(create:Bool)throws{try real.beginAccess(create:create)}
    func endAccess()throws{try real.endAccess()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ bytes:Data,createKey:Bool)throws{
        let mode=lock.withLock{let result=failure;failure = .none;return result}
        if mode == .before{throw HistoryError.unavailable};try real.save(bytes,createKey:createKey)
        if mode == .after{throw HistoryError.unavailable}
    }
}

@MainActor final class LearningLedgerTests:XCTestCase {
    private func fixture()throws->(HistoryStore,LearningLedgerStorage,ProtectedSnapshotVault,LearningLedgerClock){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-learning-ledger-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let directory=root.appendingPathComponent("Relay/History"),port=LearningLedgerStorage(directory),clock=LearningLedgerClock()
        let store=HistoryStore(storage:port,clock:clock.now),vault=ProtectedSnapshotVault(directory:directory,purpose:.history,keys:LearningLedgerKey())
        try store.open(create:true)
        addTeardownBlock{try? store.close();try? FileManager.default.removeItem(at:root)}
        return(store,port,vault,clock)
    }
    private func add(_ store:HistoryStore,recordID:UUID?=nil,complete:Bool=true)throws->LearningEpisode{
        let record:HistoryRecord
        if let recordID{try store.finish(recordID,outcome:.recording);record=try store.detail(recordID).record}
        else{record=try store.createRecord()}
        let memory=LearningSessionMemory(),transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0);memory.observe($0)}
        var e=LearningTestEvents();e.start(transcript);e.final(1,text:"How should bounded queues handle overload?",into:transcript)
        memory.available(binding:PanelRequestBinding(lease:e.lease,requestID:UUID(),eventSequence:e.sequence),replacement:1,
            lead:"Explain bounded queues, then make overload explicit.",points:["Keep each request inside a fixed capacity and discuss the rejection policy."],guideRevision:nil,visible:true,at:250_000_000)
        e.final(3,text:"Keep bounded queues and make overload explicit.",source:1,into:transcript);e.final(4,text:"What about null items?",into:transcript)
        transcript.observe(e.event(.stopping,payload:["reasonCode":.string("user_stop")]))
        transcript.observe(e.event(.stopped,payload:["reasonCode":.string("user_stop"),"quiesced":.bool(true)]))
        for observation in observations{try store.append(observation,to:record.id)}
        try store.finish(record.id,outcome:complete ? .completed:.paused)
        return try XCTUnwrap(memory.episodes.first).retained(recordID:record.id,expiresAt:record.expiresAt)
    }
    private func enabled(_ store:HistoryStore)throws->LearningControlRecord{
        let prior=try store.learningArchive().control
        let target=LearningControlRecord(revision:UUID(),enabled:true,suppressedRuleIDs:prior?.suppressedRuleIDs ?? [])
        let outcome=try store.mutateLearning(.control(LearningPendingControl(target:target,expectedRevision:prior?.revision,clearExamples:false)))
        XCTAssertTrue(outcome.cleanupComplete);XCTAssertEqual(outcome.archive.control,target);return target
    }
    private func version(_ vault:ProtectedSnapshotVault)throws->Int{
        let queue=try HistorySnapshotCodec.decode(vault.load());defer{try? queue.close()}
        return try queue.read{try Int.fetchOne($0,sql:"PRAGMA user_version")!}
    }
    private func notes(_ store:HistoryStore,_ id:UUID)throws->HistoryNotesDocumentData{
        let source=try store.readNotesSource(id,expectedRevision:store.detail(id).record.revision,selection:.fullSavedTranscript,intentID:UUID(),admission:{true})
        let row=source.sourceData.rows[0]
        let output=try HistoryNotesData.output(HistoryNotesFixtures.encode(["schemaVersion":1,"summary":[["text":"A fictional bounded queue discussion.","citations":[["rowID":row.rowID,"quote":"bounded queues"]]]],"decisions":[],"nextSteps":[]]),source:source.sourceData)
        let generation=HistoryNotesGenerationData(scopeID:UUID(),scopeEpoch:1,operationID:source.intentID,requestID:UUID(),requestSequence:1,transferID:UUID(),completedAt:"2027-01-15T08:00:00.000Z")
        return try store.saveGeneratedNotes(output,provenance:generation,modelID:"synthetic-notes-fixture",source:source,operationID:source.intentID,admission:{true}).document
    }
    func testReadIsInertForV1AndV2AndExplicitControlMigrationPreservesNotesAndRecordCAS()async throws{
        let(store,port,vault,_)=try fixture(),episode=try add(store),id=try XCTUnwrap(episode.recordID)
        let first=try Data(contentsOf:port.file);XCTAssertEqual(try version(vault),1)
        XCTAssertNil(try store.learningArchive().control);XCTAssertEqual(try Data(contentsOf:port.file),first)
        let note=try notes(store,id),before=try store.detail(id).record
        XCTAssertEqual(try version(vault),2);let second=try Data(contentsOf:port.file)
        XCTAssertTrue(try store.learningArchive().episodes.isEmpty);XCTAssertEqual(try Data(contentsOf:port.file),second)
        _=try enabled(store);XCTAssertEqual(try version(vault),3)
        XCTAssertEqual(try store.generatedNotes(id),note);XCTAssertEqual(try store.detail(id).record,before)
        _=try store.mutateLearning(.save(episode));XCTAssertEqual(try store.detail(id).record,before)
        XCTAssertEqual(try store.generatedNotes(id),note)
        _=try notes(store,id);XCTAssertEqual(try version(vault),3)
    }
    func testActualEncryptedRestartKeepsThreeOriginalExamplesAcrossTwoSessionsAndConsentRevision()async throws{
        let(store,port,vault,clock)=try fixture(),first=try add(store,complete:false),record=try XCTUnwrap(first.recordID)
        let second=try add(store,recordID:record),third=try add(store),control=try enabled(store)
        for episode in [first,second,third]{_=try store.mutateLearning(.save(episode))}
        let archive=try store.learningArchive();XCTAssertEqual(archive.episodes.count,3);XCTAssertEqual(archive.control,control)
        XCTAssertEqual(archive.rules.first?.sessionCount,2)
        let projection=LearningDerivation.project(archive,question:"bounded queues null items",now:clock.now().timeIntervalSince1970)
        XCTAssertEqual(projection.adjustments,[.conciseLead]);XCTAssertFalse(projection.examples.isEmpty)
        let ciphertext=try Data(contentsOf:port.file)
        XCTAssertNil(ciphertext.range(of:Data("Explain bounded queues".utf8)));XCTAssertNil(ciphertext.range(of:Data("make overload explicit".utf8)))
        XCTAssertFalse(ciphertext.starts(with:Data("SQLite format 3".utf8)))
        try store.close();let restored=HistoryStore(storage:port,clock:clock.now);defer{try? restored.close()};try restored.open(create:false)
        XCTAssertEqual(try restored.learningArchive(),archive);XCTAssertEqual(try version(vault),3)
    }
    func testExactSourceDeleteAndExpiryRemoveDependentExamplesAndRebuildWithoutOldRules()async throws{
        let(store,_,_,clock)=try fixture(),first=try add(store,complete:false),record=try XCTUnwrap(first.recordID)
        let second=try add(store,recordID:record),third=try add(store);_=try enabled(store)
        for episode in [first,second,third]{_=try store.mutateLearning(.save(episode))}
        let before=try store.detail(record)
        _=try store.edit(record,expectedRevision:before.record.revision,title:"Keep manual title",note:"Keep manual note")
        let current=try store.detail(record)
        try store.deleteSource(record,expectedRevision:current.record.revision,captureID:first.reply.captureID,source:.microphone)
        let after=try store.learningArchive();XCTAssertEqual(Set(after.episodes.map(\.id)),Set([second.id,third.id]))
        XCTAssertTrue(after.rules.isEmpty);XCTAssertEqual(try store.detail(record).record.note,"Keep manual note")
        clock.advance(HistoryBounds.retention+1)
        let expired=try store.learningArchive();XCTAssertTrue(expired.episodes.isEmpty);XCTAssertTrue(expired.rules.isEmpty)
        XCTAssertTrue(try store.list().records.isEmpty)
    }
    func testWrongRecordAndMutatedOriginalTextAreRejectedWithoutChangingActualCiphertext()async throws{
        let(store,port,_,_)=try fixture(),first=try add(store),other=try add(store);_=try enabled(store)
        let before=try Data(contentsOf:port.file)
        let foreign=try first.retained(recordID:XCTUnwrap(other.recordID),expiresAt:XCTUnwrap(other.expiresAt))
        XCTAssertThrowsError(try store.mutateLearning(.save(foreign)))
        let data=try HistoryJSON.encode(first);var raw=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var reply=raw["reply"] as! [String:Any];reply["text"]="Invented replacement must never be source evidence.";raw["reply"]=reply
        let forged=try JSONDecoder().decode(LearningEpisode.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertThrowsError(try store.mutateLearning(.save(forged)));XCTAssertEqual(try Data(contentsOf:port.file),before)
    }
    func testControlSuppressionResetAndStaleControlCASPreserveOriginalHistory()async throws{
        let(store,_,_,_)=try fixture(),episodes=try [add(store),add(store),add(store)],on=try enabled(store)
        for episode in episodes{_=try store.mutateLearning(.save(episode))}
        let suppressed=LearningControlRecord(revision:UUID(),enabled:true,suppressedRuleIDs:["technical:concise_lead"])
        let old=LearningPendingControl(target:suppressed,expectedRevision:on.revision,clearExamples:false)
        _=try store.mutateLearning(.control(old));XCTAssertTrue(try store.learningArchive().rules.first?.suppressed==true)
        let reset=LearningControlRecord(revision:UUID(),enabled:true,suppressedRuleIDs:[])
        _=try store.mutateLearning(.control(LearningPendingControl(target:reset,expectedRevision:suppressed.revision,clearExamples:true)))
        XCTAssertTrue(try store.learningArchive().episodes.isEmpty);XCTAssertTrue(try store.learningArchive().rules.isEmpty)
        XCTAssertEqual(try store.list().records.count,3);XCTAssertThrowsError(try store.mutateLearning(.control(old)))
    }
    func testIndeterminateWritesDenyCachedLearningUntilActualOwnedReopen()async throws{
        for mode in [LearningLedgerStorage.Failure.before,.after]{
            let(store,port,_,clock)=try fixture(),episode=try add(store);_=try enabled(store)
            let before=try Data(contentsOf:port.file);port.arm(mode)
            XCTAssertThrowsError(try store.mutateLearning(.save(episode)))
            XCTAssertThrowsError(try store.learningArchive())
            if mode == .before{XCTAssertEqual(try Data(contentsOf:port.file),before)}
            try store.close();let recovered=HistoryStore(storage:port,clock:clock.now);defer{try? recovered.close()};try recovered.open(create:false)
            XCTAssertEqual(try recovered.learningArchive().episodes.count,mode == .after ? 1:0)
        }
    }
}
