import Combine
import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

@MainActor private final class NotesReadPreferences:HistorySavingPreferences{var savingEnabled=false}
private struct NotesReadKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:91,count:32)}}
private final class NotesReadClock:@unchecked Sendable{
    private let lock=NSLock();private var value=Date(timeIntervalSince1970:1_800_000_000)
    func now()->Date{lock.withLock{value}}
    func advance(_ interval:TimeInterval){lock.withLock{value.addTimeInterval(interval)}}
}
private final class NotesReadStorage:HistoryOwnedSnapshotStorage,@unchecked Sendable{
    let real:HistoryVaultStorage
    private let lock=NSLock(),gate=DispatchSemaphore(value:0)
    private var armed=false,entered=false,count=0
    init(_ real:HistoryVaultStorage){self.real=real}
    var isHeld:Bool{lock.withLock{entered}}
    var calls:Int{lock.withLock{count}}
    func holdNextLoad(){lock.withLock{armed=true}}
    func release(){gate.signal()}
    func beginAccess(create:Bool)throws{lock.withLock{count+=1};try real.beginAccess(create:create)}
    func endAccess()throws{lock.withLock{count+=1};try real.endAccess()}
    func exists()throws->Bool{lock.withLock{count+=1};return try real.exists()}
    func load()throws->Data{
        let hold=lock.withLock{count+=1;if armed{armed=false;entered=true;return true};return false}
        if hold{guard gate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable};lock.withLock{entered=false}}
        return try real.load()
    }
    func save(_ bytes:Data,createKey:Bool)throws{lock.withLock{count+=1};try real.save(bytes,createKey:createKey)}
}

@MainActor final class HistoryNotesCoordinatorTests:XCTestCase{
    private func until(_ predicate:()->Bool)async throws{
        let limit=ContinuousClock.now+Duration.seconds(5)
        while !predicate(){guard ContinuousClock.now<limit else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
    }
    private func fixture()throws->(SessionHistoryCoordinator,NotesReadStorage,UUID,NotesReadClock){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-owner-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let clock=NotesReadClock(),port=NotesReadStorage(HistoryVaultStorage(directory:root.appendingPathComponent("Relay/History"),keys:NotesReadKey()))
        let store=HistoryStore(storage:port,clock:clock.now);try store.open(create:true);let record=try store.createRecord()
        let transcript=SessionTranscriptStore();var observations:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={observations.append($0)};var events=HistoryTestEvents();events.start(transcript)
        events.final(1,text:"Fictional original question.",into:transcript);events.final(2,text:"Fictional microphone reply.",source:1,into:transcript);events.stop(into:transcript)
        for observation in observations{try store.append(observation,to:record.id)}
        try store.finish(record.id,outcome:.completed);try store.close()
        let history=SessionHistoryCoordinator(storageFactory:{port},preferences:NotesReadPreferences(),canEnable:{true},clock:clock.now)
        addTeardownBlock{port.release();await history.lock();await history.waitForQuiescence();try? FileManager.default.removeItem(at:root)}
        return(history,port,record.id,clock)
    }
    private func opened(_ history:SessionHistoryCoordinator,_ id:UUID)async throws->Int64{
        try await history.openExisting();try await history.openRecord(id)
        return try XCTUnwrap(history.snapshot.selected?.record.revision)
    }
    func testLockedDefaultCannotCreateOrIssueSourceEvenWithCallerCurrentTrue()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-locked-"+UUID().uuidString)
        let port=NotesReadStorage(HistoryVaultStorage(directory:root.appendingPathComponent("Relay/History"),keys:NotesReadKey()))
        let history=SessionHistoryCoordinator(storageFactory:{port},preferences:NotesReadPreferences(),canEnable:{true})
        do{_=try await history.prepareNotesSource(recordID:UUID(),expectedRevision:1,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in});XCTFail("Locked source must not issue")}
        catch{}
        XCTAssertEqual(port.calls,0);XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testActualSourceIsOriginalOwnedObjectAndStaleRetireCannotClearReplacement()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var retired:[ObjectIdentifier]=[]
        let first=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{retired.append(ObjectIdentifier($0))})
        XCTAssertTrue(history.ownsNotesSource(first));XCTAssertEqual(first.data.rows.count,2)
        history.retireNotesSource(first);XCTAssertFalse(history.ownsNotesSource(first))
        let next=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{retired.append(ObjectIdentifier($0))})
        history.retireNotesSource(first)
        XCTAssertTrue(history.ownsNotesSource(next));XCTAssertEqual(retired,[ObjectIdentifier(first)])
    }
    func testCallerCancellationJoinsActualHeldReadAndDoesNotIssueAReplacementEarly()async throws{
        let(history,port,id,_)=try fixture(),revision=try await opened(history,id)
        port.holdNextLoad()
        let task=Task{try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in XCTFail("Unissued source cannot retire")})}
        try await until{port.isHeld};task.cancel();try await Task.sleep(for:.milliseconds(20))
        XCTAssertTrue(history.isBusy)
        port.release()
        do{_=try await task.value;XCTFail("Cancelled original read issued a source")}catch{}
        await history.waitForQuiescence();XCTAssertFalse(history.isBusy)
        let next=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in})
        XCTAssertTrue(history.ownsNotesSource(next))
    }
    func testLockDuringHeldReadDeniesImmediatelyAndJoinsBeforeReopen()async throws{
        let(history,port,id,_)=try fixture(),revision=try await opened(history,id)
        port.holdNextLoad()
        let task=Task{try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in})}
        try await until{port.isHeld};history.lock()
        XCTAssertNil(history.snapshot.selected);XCTAssertTrue(history.isBusy)
        port.release();_=await task.result;await history.waitForQuiescence()
        XCTAssertEqual(history.snapshot.phase,.locked)
        let current=try await opened(history,id)
        let source=try await history.prepareNotesSource(recordID:id,expectedRevision:current,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in})
        XCTAssertTrue(history.ownsNotesSource(source))
    }
    func testRetirementCallbackRunsAfterDenialAndSupportsReentrantLock()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var calls=0,denials=0
        history.onSourceDenial={_ in denials+=1}
        let source=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{original in
            calls+=1;XCTAssertFalse(history.ownsNotesSource(original));history.lock()
        })
        history.stopSaving();await history.waitForQuiescence()
        XCTAssertEqual(calls,1);XCTAssertGreaterThan(denials,0)
        XCTAssertFalse(history.ownsNotesSource(source));XCTAssertEqual(history.snapshot.phase,.locked)
    }
    func testReadyPublicationReentryCannotReturnARevokedSource()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var armed=false,locked=false
        let observer=history.$snapshot.sink{snapshot in
            if armed,!snapshot.isBusy,snapshot.phase == .ready,snapshot.selected?.record.id==id{
                armed=false;locked=true;history.lock()
            }
        }
        defer{observer.cancel()};armed=true
        do{_=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in});XCTFail("Reentrant Lock returned source")}
        catch{}
        await history.waitForQuiescence();XCTAssertTrue(locked);XCTAssertEqual(history.snapshot.phase,.locked)
    }
    func testManualMutationAndOriginalSourceDeletionRetireBeforeTheirActualWrites()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var calls=0,notices:[HistorySourceDenial]=[]
        history.onSourceDenial={notices.append($0)}
        let source=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{original in
            calls+=1;XCTAssertFalse(history.ownsNotesSource(original))
        })
        _=try await history.saveNotes(id,expectedRevision:revision,title:"User title",note:"User manual note")
        XCTAssertEqual(calls,1);XCTAssertFalse(history.ownsNotesSource(source));XCTAssertFalse(notices.isEmpty)
        let detail=try XCTUnwrap(history.snapshot.selected)
        let next=try await history.prepareNotesSource(recordID:id,expectedRevision:detail.record.revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in calls+=1})
        let deletion=history.deleteSource(id,expectedRevision:detail.record.revision,captureID:detail.captures[0].id,source:.microphone)
        XCTAssertFalse(history.ownsNotesSource(next));XCTAssertEqual(calls,2)
        try await deletion.value;XCTAssertEqual(history.snapshot.selected?.record.note,"User manual note")
    }
    func testStaleStartCannotDenyAnActuallyIssuedCurrentNotesSource()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var retired=0,denials=0
        let source=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in retired+=1})
        history.onSourceDenial={_ in denials+=1}
        XCTAssertTrue(history.ownsNotesSource(source))
        do{_=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{false});XCTFail("Stale start was admitted")}catch{}
        XCTAssertTrue(history.ownsNotesSource(source));XCTAssertEqual(retired,0);XCTAssertEqual(denials,0)
    }
    func testAlreadyCancelledStartCannotDenyCurrentNotesSource()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var retired=0
        let source=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in retired+=1})
        let start=Task{try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})};start.cancel()
        do{_=try await start.value;XCTFail("Cancelled start was admitted")}catch{}
        XCTAssertTrue(history.ownsNotesSource(source));XCTAssertEqual(retired,0)
    }
    func testPreviouslyFinishedActualPermitCannotDenyANewerNotesSource()async throws{
        let(history,_,_,_)=try fixture();try await history.enableSaving()
        let started=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})
        let permit=try XCTUnwrap(started)
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation=history.observe
        var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Fictional earlier audio question.",into:transcript);events.stop(into:transcript)
        try await history.finishSession(permit,paused:false);await history.waitForQuiescence()
        try await history.openRecord(permit.recordID);let revision=try XCTUnwrap(history.snapshot.selected?.record.revision);var retired=0
        let source=try await history.prepareNotesSource(recordID:permit.recordID,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in retired+=1})
        XCTAssertTrue(history.ownsNotesSource(source))
        try await history.finishSession(permit,paused:false)
        XCTAssertTrue(history.ownsNotesSource(source));XCTAssertEqual(retired,0)
    }
    func testValidCurrentStartStillDeniesOriginalSourceBeforeReturning()async throws{
        let(history,_,id,_)=try fixture(),revision=try await opened(history,id);var retired=0
        let source=try await history.prepareNotesSource(recordID:id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{original in
            retired+=1;XCTAssertFalse(history.ownsNotesSource(original))
        })
        let result=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true});XCTAssertNil(result)
        XCTAssertFalse(history.ownsNotesSource(source));XCTAssertEqual(retired,1)
    }
}
