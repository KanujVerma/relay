import Foundation
import XCTest
import RelayNativeSession
import RelayProfile
import GRDB
@testable import RelaySessionPanel

private struct HistoryTestKey:ProfileKeyProvider{
    func key(createIfMissing:Bool)throws->Data{Data(repeating:61,count:32)}
}
private final class HistoryTestClock:@unchecked Sendable{
    private let lock=NSLock();private var date=Date(timeIntervalSince1970:1_800_000_000)
    func now()->Date{lock.withLock{date}}
    func advance(_ interval:TimeInterval){lock.withLock{date.addTimeInterval(interval)}}
}
private final class FailingHistoryStorage:ProtectedSnapshotStorage,@unchecked Sendable {
    let real:any ProtectedSnapshotStorage
    var fail=false
    init(_ real:any ProtectedSnapshotStorage){self.real=real}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ payload:Data,createKey:Bool)throws{if fail{throw ProfileError.unavailable};try real.save(payload,createKey:createKey)}
}

/// Fictional packets pass the actual existing transcript validator; no direct
/// stored-row constructor substitutes for the producer-issued observation.
@MainActor struct HistoryTestEvents {
    var session=UUID(),epoch:UInt64=1,sequence:UInt64=0
    let clock:WireValue = .object(["hostTicksAtAnchor":.uint(0),"uptimeNsAtAnchor":.uint(0),"nsNumer":.uint(1),"nsDenom":.uint(1)])
    mutating func event(_ kind:SessionEventKind,source:UInt32?=nil,payload:[String:WireValue]=[:])->NativeSessionEvent{
        sequence+=1
        return NativeSessionEvent(captureSessionID:session,sessionEpoch:epoch,eventSequence:sequence,presentationGeneration:2,
            kind:kind,sourceCode:source,streamGeneration:source==nil ? nil:1,emittedUptimeNanoseconds:1_000_000_000,payload:payload)
    }
    mutating func start(_ store:SessionTranscriptStore){
        store.observe(event(.sessionStarted,payload:["selectedBundleID":.string("com.example.fixture"),"microphoneEnabled":.bool(true)]))
    }
    mutating func final(_ index:UInt64,text:String,source:UInt32=2,into store:SessionTranscriptStore){
        store.observe(event(.speechStarted,source:source,payload:["activityID":.uint(index),"startHostTime":.uint(index*100),"detectedUptimeNanoseconds":.uint(1000),"timebase":clock]))
        store.observe(event(.speechEnded,source:source,payload:["activityID":.uint(index),"endHostTime":.uint(index*100+50),"lastSpeechInputSequence":.uint(index*2),"timebase":clock]))
        let inner:[String:WireValue] = ["version":.uint(1),"status":.string("final"),"sourceCode":.uint(UInt64(source)),"streamGeneration":.uint(1),"segmentID":.uint(index),"revision":.uint(1),"startHostTime":.uint(index*100),"endHostTime":.uint(index*100+50),"finalizedUptimeNanoseconds":.uint(1_000_000),"receivedUptimeNanoseconds":.uint(1_000_001),"text":.string(text),"confidence":.null,"timebase":clock]
        store.observe(event(.eou,source:source,payload:["event":.object(inner),"activityID":.uint(index),"firstInputSequence":.uint(index*2-1),"lastInputSequence":.uint(index*2),"lastSpeechInputSequence":.uint(index*2),"activityClosed":.bool(true)]))
    }
}

@MainActor final class HistoryStoreTests:XCTestCase {
    private func storage()throws->(URL,ProtectedSnapshotVault){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-store-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return(root,ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:HistoryTestKey()))
    }
    private func stream()->(SessionTranscriptStore,[ValidatedTranscriptObservation]){
        let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)}
        var events=HistoryTestEvents();events.start(transcript)
        events.final(1,text:"A fictional C++ queue question. 👩🏽‍💻",into:transcript)
        events.final(2,text:"My fictional microphone reply.",source:1,into:transcript)
        return(transcript,observations)
    }
    func testActualIssuedFinalsAndManualNotesSurviveEncryptedRestartWithOriginalIdentities()async throws{
        let(root,vault)=try storage(),clock=HistoryTestClock(),store=HistoryStore(storage:vault,clock:clock.now)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Relay").path))
        try store.open(create:true)
        let record=try store.createRecord(),(_,observations)=stream()
        for observation in observations{try store.append(observation,to:record.id)}
        var detail=try store.detail(record.id)
        _=try store.edit(record.id,expectedRevision:detail.record.revision,title:"Fictional practice",note:"User notes, not approved biography.\nReview C++.")
        try store.finish(record.id,outcome:.completed)
        detail=try store.detail(record.id)
        XCTAssertEqual(detail.rows.map(\.text),["A fictional C++ queue question. 👩🏽‍💻","My fictional microphone reply."])
        XCTAssertEqual(detail.rows.map(\.source.label),["Selected app audio","Microphone"])
        XCTAssertEqual(detail.rows[0].eventSequence.value,4)
        XCTAssertEqual(detail.rows[0].captureSessionID,observations.first?.event.captureSessionID)
        XCTAssertEqual(detail.record.state,.completed)
        let file=root.appendingPathComponent("Relay/History/history.relayvault"),cipher=try Data(contentsOf:file)
        XCTAssertNil(cipher.range(of:Data("Fictional practice".utf8)))
        XCTAssertNil(cipher.range(of:Data("fictional C++".utf8)))
        try store.close()
        let fresh=HistoryStore(storage:vault,clock:clock.now);try fresh.open(create:false)
        let restored=try fresh.detail(record.id)
        XCTAssertEqual(restored,detail)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:file.deletingLastPathComponent().path),["history.relayvault"])
        try fresh.close()
    }
    func testFailedCandidateSavePreservesActualCanonicalAndPreviousCiphertext()async throws{
        let(root,vault)=try storage(),port=FailingHistoryStorage(vault),store=HistoryStore(storage:port)
        try store.open(create:true);let record=try store.createRecord()
        let file=root.appendingPathComponent("Relay/History/history.relayvault"),before=try Data(contentsOf:file)
        port.fail=true
        XCTAssertThrowsError(try store.edit(record.id,expectedRevision:record.revision,title:"Must not publish",note:"unsaved"))
        XCTAssertEqual(try store.detail(record.id).record,record)
        XCTAssertEqual(try Data(contentsOf:file),before)
        try store.close()
    }
    func testExpiryPurgesBeforeAccessAndCrashRecoveryNeverClaimsCompletion()async throws{
        let(_,vault)=try storage(),clock=HistoryTestClock(),store=HistoryStore(storage:vault,clock:clock.now)
        try store.open(create:true);let record=try store.createRecord();try store.close()
        let recovered=HistoryStore(storage:vault,clock:clock.now);try recovered.open(create:false)
        XCTAssertEqual(try recovered.detail(record.id).record.state,.interrupted)
        XCTAssertNil(try recovered.detail(record.id).record.endedAt)
        clock.advance(30*24*60*60+1)
        XCTAssertTrue(try recovered.list().records.isEmpty)
        XCTAssertThrowsError(try recovered.detail(record.id))
        try recovered.close()
        let again=HistoryStore(storage:vault,clock:clock.now);try again.open(create:false)
        XCTAssertTrue(try again.list().records.isEmpty);try again.close()
    }
    func testExactSourceDeleteKeepsOtherRowsAndCASPreventsStaleNoteOverwrite()async throws{
        let(_,vault)=try storage(),store=HistoryStore(storage:vault)
        try store.open(create:true);let record=try store.createRecord(),(_,observations)=stream()
        for observation in observations{try store.append(observation,to:record.id)}
        let before=try store.detail(record.id)
        _=try store.edit(record.id,expectedRevision:before.record.revision,title:"Fictional",note:"kept note")
        XCTAssertThrowsError(try store.edit(record.id,expectedRevision:before.record.revision,title:"stale",note:"overwrite"))
        let current=try store.detail(record.id)
        try store.deleteSource(record.id,expectedRevision:current.record.revision,captureID:current.captures[0].id,source:.selectedAppAudio)
        let after=try store.detail(record.id)
        XCTAssertEqual(after.rows.map(\.source),[.microphone]);XCTAssertEqual(after.record.note,"kept note")
        XCTAssertTrue(after.record.gaps.contains(.sourceDeleted))
        try store.delete(record.id,expectedRevision:after.record.revision)
        XCTAssertThrowsError(try store.append(observations.last!,to:record.id))
        XCTAssertTrue(try store.list().records.isEmpty);try store.close()
    }
    func testObserverRetainsMoreThanTransientRingAndRejectsInvalidOrRetiredFinals()async throws{
        let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)}
        var events=HistoryTestEvents();events.start(transcript)
        transcript.observe(events.event(.eou,source:2,payload:["event":.object(["text":.string("invalid")])]))
        for n in 1...70{events.final(UInt64(n),text:"Fictional row \(n)",into:transcript)}
        XCTAssertEqual(observations.filter{$0.final != nil}.count,70)
        XCTAssertEqual(transcript.snapshot.rows.count,64)
        let before=observations.filter{$0.final != nil}.count
        transcript.pause();events.final(71,text:"late",into:transcript)
        XCTAssertEqual(observations.filter{$0.final != nil}.count,before)
        XCTAssertEqual(observations.first?.event.eventSequence,1)
    }
    func testCountersRoundTripAsStringsAndExportNeverPromotesNotesToFacts()async throws{
        let max=HistoryCounter(UInt64.max),data=try JSONEncoder().encode(max)
        XCTAssertEqual(String(data:data,encoding:.utf8),"\"18446744073709551615\"")
        XCTAssertEqual(try JSONDecoder().decode(HistoryCounter.self,from:data).value,UInt64.max)
        for invalid in ["1","true","\"01\"","\"-1\"","\"18446744073709551616\""]{
            XCTAssertThrowsError(try JSONDecoder().decode(HistoryCounter.self,from:Data(invalid.utf8)))
        }
        let(_,vault)=try storage(),store=HistoryStore(storage:vault)
        try store.open(create:true);let record=try store.createRecord(),(_,observations)=stream()
        for observation in observations{try store.append(observation,to:record.id)}
        let current=try store.detail(record.id)
        _=try store.edit(record.id,expectedRevision:current.record.revision,title:"<Fictional>",note:"<script>fictional</script>")
        let detail=try store.detail(record.id),markdown=try HistoryExport.encode(detail,format:.markdown),json=try HistoryExport.encode(detail,format:.json)
        XCTAssertTrue(String(decoding:markdown,as:UTF8.self).contains("User notes"))
        XCTAssertFalse(String(decoding:markdown,as:UTF8.self).contains("<script>"))
        XCTAssertTrue(String(decoding:json,as:UTF8.self).contains("\"eventSequence\" : \"4\""))
        XCTAssertFalse(String(decoding:json,as:UTF8.self).contains("confirmed_fact"))
        try store.close()
    }
    func testExistingExpiredRecordsArePurgedDuringOpenBeforeAnyRead()async throws{
        let(_,vault)=try storage(),clock=HistoryTestClock(),old=HistoryStore(storage:vault,clock:clock.now)
        try old.open(create:true);_=try old.createRecord();try old.close()
        clock.advance(HistoryBounds.retention+1)
        let fresh=HistoryStore(storage:vault,clock:clock.now);try fresh.open(create:false)
        XCTAssertTrue(try fresh.list().records.isEmpty);try fresh.close()
    }
    func testCompletedRecordCannotBeReopenedByAnOldLifecycleCall()async throws{
        let(_,vault)=try storage(),store=HistoryStore(storage:vault)
        try store.open(create:true);let record=try store.createRecord()
        try store.finish(record.id,outcome:.completed)
        XCTAssertThrowsError(try store.finish(record.id,outcome:.recording))
        XCTAssertEqual(try store.detail(record.id).record.state,.completed);try store.close()
    }
    func testForeignCaptureControlCannotMutateAnOtherwiseCurrentRecord()async throws{
        let(_,vault)=try storage(),store=HistoryStore(storage:vault)
        try store.open(create:true);let record=try store.createRecord(),(_,owned)=stream()
        for observation in owned{try store.append(observation,to:record.id)}
        let transcript=SessionTranscriptStore();var foreign:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={foreign.append($0)}
        var other=HistoryTestEvents();other.start(transcript)
        transcript.observe(other.event(.sourceUnavailable,source:2,payload:["reasonCode":.string("consent_revoked")]))
        let before=try store.detail(record.id)
        XCTAssertThrowsError(try store.append(foreign.last!,to:record.id))
        XCTAssertEqual(try store.detail(record.id),before);try store.close()
    }
    func testSourceDeletionRebuildsWithoutDeletedSourceIdentityOrText()async throws{
        let(_,vault)=try storage(),store=HistoryStore(storage:vault)
        try store.open(create:true);let record=try store.createRecord(),(_,observations)=stream()
        for observation in observations{try store.append(observation,to:record.id)}
        let before=try store.detail(record.id)
        try store.deleteSource(record.id,expectedRevision:before.record.revision,captureID:before.captures[0].id,source:.selectedAppAudio)
        let after=try store.detail(record.id)
        XCTAssertNil(after.captures[0].selectedBundleID)
        let snapshot=try vault.load()
        XCTAssertNil(snapshot.range(of:Data("com.example.fixture".utf8)))
        XCTAssertNil(snapshot.range(of:Data("A fictional C++ queue question.".utf8)))
        XCTAssertEqual(after.rows.map(\.source),[.microphone])
        let transcript=SessionTranscriptStore();var next:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={next.append($0)};var resumed=HistoryTestEvents()
        resumed.start(transcript);resumed.final(1,text:"Must not restore deleted source",into:transcript)
        try store.append(next[0],to:record.id)
        XCTAssertThrowsError(try store.append(next[1],to:record.id))
        XCTAssertTrue(try store.detail(record.id).captures.allSatisfy{$0.selectedBundleID==nil})
        try store.close()
    }
    func testStrictSnapshotSchemaAndCanonicalPayloadRejectWithoutReplacingCiphertext()async throws{
        for poison in 0..<4{
            let(_,vault)=try storage(),store=HistoryStore(storage:vault)
            try store.open(create:true);_=try store.createRecord();try store.close()
            let q=try HistorySnapshotCodec.decode(vault.load())
            try await q.write{db in
                switch poison{
                case 0:try db.execute(sql:"PRAGMA user_version=99")
                case 1:try db.execute(sql:"CREATE TABLE unexpected_private_index(value TEXT)")
                case 2:try db.execute(sql:"UPDATE history_record SET created_at='not a timestamp'")
                default:
                    let raw=try Data.fetchOne(db,sql:"SELECT payload FROM history_record")!
                    var object=try JSONSerialization.jsonObject(with:raw) as! [String:Any];object["unknown"]=true
                    try db.execute(sql:"UPDATE history_record SET payload=?",arguments:[try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])])
                }
            }
            try vault.save(HistorySnapshotCodec.encode(q));try q.close()
            let ciphertext=try vault.load(),fresh=HistoryStore(storage:vault)
            XCTAssertThrowsError(try fresh.open(create:false))
            XCTAssertEqual(try vault.load(),ciphertext);XCTAssertThrowsError(try fresh.list())
        }
    }
    func testRecordAndWholeUTF8TextBoundsLeaveLastCompletePrefixIntact()async throws{
        let(_,vault)=try storage(),store=HistoryStore(storage:vault)
        try store.open(create:true)
        for _ in 0..<HistoryBounds.records{_=try store.createRecord()}
        XCTAssertThrowsError(try store.createRecord());try store.deleteAll()
        let record=try store.createRecord(),transcript=SessionTranscriptStore()
        var observations:[ValidatedTranscriptObservation]=[];transcript.onHistoryObservation={observations.append($0)}
        var events=HistoryTestEvents();events.epoch=UInt64.max;events.start(transcript)
        let text=String(repeating:"🙂",count:1200)
        for n in 1...55{events.final(UInt64(n),text:text,into:transcript)}
        for observation in observations.dropLast(){try store.append(observation,to:record.id)}
        let before=try store.detail(record.id,all:true)
        XCTAssertEqual(before.rows.count,54);XCTAssertEqual(before.rows[0].sessionEpoch.value,UInt64.max)
        XCTAssertThrowsError(try store.append(observations.last!,to:record.id))
        XCTAssertEqual(try store.detail(record.id,all:true),before);try store.close()
    }
    func testContentLimitLeavesRealSpaceForPartialFinalization()async throws{
        let(_,vault)=try storage(),store=HistoryStore(storage:vault,contentLimitBytes:96*1024)
        try store.open(create:true);let record=try store.createRecord(),transcript=SessionTranscriptStore()
        var observations:[ValidatedTranscriptObservation]=[];transcript.onHistoryObservation={observations.append($0)}
        var events=HistoryTestEvents();events.start(transcript)
        for n in 1...8{events.final(UInt64(n),text:String(repeating:"🙂",count:1200),into:transcript)}
        var accepted=0,rejected=false
        for observation in observations{
            do{try store.append(observation,to:record.id);if observation.final != nil{accepted+=1}}
            catch HistoryError.capacity{rejected=true;break}
        }
        XCTAssertTrue(rejected);XCTAssertGreaterThan(accepted,0);XCTAssertLessThan(accepted,8)
        try store.finish(record.id,outcome:.completed,gap:.capacity)
        let detail=try store.detail(record.id,all:true)
        XCTAssertEqual(detail.record.state,.partial);XCTAssertEqual(detail.rows.count,accepted)
        try store.close()
        let fresh=HistoryStore(storage:vault);try fresh.open(create:false)
        XCTAssertEqual(try fresh.detail(record.id,all:true),detail);try fresh.close()
    }
}
