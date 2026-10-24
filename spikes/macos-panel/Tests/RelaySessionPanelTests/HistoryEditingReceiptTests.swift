import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

private struct EditingReceiptKey:ProfileKeyProvider{
    func key(createIfMissing:Bool)throws->Data{Data(repeating:121,count:32)}
}
private final class EditingReceiptClock:@unchecked Sendable{
    private let lock=NSLock();private var value=Date(timeIntervalSince1970:1_800_000_000)
    func now()->Date{lock.withLock{value}}
    func expire(){lock.withLock{value.addTimeInterval(HistoryBounds.retention+1)}}
}
private final class EditingReceiptStorage:ProtectedSnapshotStorage,@unchecked Sendable{
    private let real:any ProtectedSnapshotStorage,lock=NSLock(),gate=DispatchSemaphore(value:0)
    private var armed=false,held=false,inside=false
    init(_ real:any ProtectedSnapshotStorage){self.real=real}
    var isHeld:Bool{lock.withLock{held}}
    var inStorage:Bool{lock.withLock{inside}}
    func holdNextSave(){lock.withLock{armed=true}}
    func release(){gate.signal()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ data:Data,createKey:Bool)throws{
        let wait=lock.withLock{inside=true;if armed{armed=false;held=true;return true};return false}
        defer{lock.withLock{inside=false;held=false}}
        if wait{guard gate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable}}
        try real.save(data,createKey:createKey)
    }
}
@MainActor final class HistoryEditingReceiptTests:XCTestCase{
    private func rig()async throws->(SessionHistoryCoordinator,EditingReceiptStorage,EditingReceiptClock,HistoryDetail){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-edit-receipt-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let clock=EditingReceiptClock(),port=EditingReceiptStorage(ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:EditingReceiptKey()))
        let history=SessionHistoryCoordinator(storageFactory:{port},preferences:HistoryFixturePreferences(),canEnable:{true},clock:clock.now)
        addTeardownBlock{port.release();await history.closeForOwnerRetirement();try? FileManager.default.removeItem(at:root)}
        try await history.enableSaving();let permit=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})!
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation=history.observe
        var events=HistoryTestEvents();events.start(transcript);events.final(1,text:"Fictional retained source.",into:transcript)
        history.retireCurrentSession();events.stop(into:transcript);try await history.finishSession(permit,paused:false)
        try await history.openRecord(permit.recordID)
        return(history,port,clock,try XCTUnwrap(history.snapshot.selected))
    }
    private func until(_ predicate:()->Bool)async throws{
        for _ in 0..<1600{if predicate(){return};try await Task.sleep(for:.milliseconds(3))};throw HistoryError.unavailable
    }
    func testManualSaveReturnsOnlyActualMatchingCASReceiptAndStaleCASDoesNotIssueOne()async throws{
        let(history,_,_,detail)=try await rig(),epoch=history.snapshot.epoch
        let receipt=try await history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"Fictional notes",note:"User wrote this.")
        XCTAssertEqual(receipt.epoch,epoch);XCTAssertEqual(receipt.recordID,detail.record.id)
        XCTAssertGreaterThan(receipt.revision,detail.record.revision);XCTAssertEqual(receipt.title,"Fictional notes");XCTAssertEqual(receipt.note,"User wrote this.")
        do{_=try await history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"Stale",note:"Must not save");XCTFail("Stale CAS has no receipt")}catch{}
        XCTAssertEqual(history.snapshot.selected?.record.note,"User wrote this.")
    }
    func testDeleteNotifiesOwnedIDBeforePublicationAndRealWriteThenAllLockEscalates()async throws{
        let(history,port,_,detail)=try await rig(),epoch=history.snapshot.epoch
        var events:[HistoryRecordsUnavailable]=[]
        history.onRecordsUnavailable={event in
            // Delete is notified before its write starts. Lock must notify even
            // while a DIFFERENT thread is still inside an actual held save.
            if event.recordIDs != nil{XCTAssertFalse(port.inStorage)}
            events.append(event)
        }
        port.holdNextSave();let deletion=history.delete(detail.record.id,expectedRevision:detail.record.revision)
        XCTAssertEqual(events.count,1);XCTAssertEqual(events.first?.retiredEpoch,epoch)
        XCTAssertEqual(events.first?.recordIDs,[detail.record.id]);XCTAssertNil(history.snapshot.selected)
        try await until{port.isHeld};history.lock()
        XCTAssertEqual(events.count,2);XCTAssertNil(events.last?.recordIDs);XCTAssertTrue(port.inStorage)
        port.release();_=await deletion.result;await history.waitForQuiescence()
        XCTAssertEqual(history.snapshot.phase,.locked)
    }
    func testCommittedExpiryNotifiesEvenWhenFollowingLookupThrowsWithoutInferringPageAbsence()async throws{
        let(history,port,clock,detail)=try await rig(),epoch=history.snapshot.epoch
        var events:[HistoryRecordsUnavailable]=[]
        history.onRecordsUnavailable={event in XCTAssertFalse(port.inStorage);events.append(event)}
        try await history.openRecord(detail.record.id);XCTAssertTrue(events.isEmpty,"A read/reload is not a deletion")
        clock.expire()
        do{_=try await history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"Late",note:"Expired");XCTFail("Expired record cannot save")}catch{}
        XCTAssertEqual(events.count,1);XCTAssertEqual(events.first?.retiredEpoch,epoch);XCTAssertEqual(events.first?.recordIDs,[detail.record.id])
        XCTAssertNil(history.snapshot.selected);XCTAssertFalse(history.snapshot.records.contains{$0.id==detail.record.id})
    }
    func testOldExpiryReceiptAfterActualLockCannotNotifyOrRestoreReplacementScope()async throws{
        let(history,port,clock,detail)=try await rig()
        var events:[HistoryRecordsUnavailable]=[];history.onRecordsUnavailable={events.append($0)}
        clock.expire();port.holdNextSave()
        let read=Task{try await history.openRecord(detail.record.id)};try await until{port.isHeld}
        history.lock();XCTAssertEqual(events.count,1);XCTAssertNil(events[0].recordIDs)
        port.release();_=await read.result;await history.waitForQuiescence()
        XCTAssertEqual(events.count,1,"The old storage receipt is fenced by its original epoch/owner")
        try await history.openExisting();XCTAssertTrue(history.snapshot.records.isEmpty);XCTAssertEqual(events.count,1)
    }
    func testReadySubscriberLockCannotAdmitAnOldManualSaveReceiptAfterActualCommit()async throws{
        let(history,_,_,detail)=try await rig();var locked=false
        let observation=history.$snapshot.sink{incoming in
            if !locked,incoming.selected?.record.title=="Committed title"{locked=true;history.lock()}
        }
        do{_=try await history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"Committed title",note:"Actual saved prefix");XCTFail("A retired publication cannot return a current receipt")}catch{}
        XCTAssertTrue(locked);await history.waitForQuiescence();observation.cancel()
        XCTAssertEqual(history.snapshot.phase,.locked);XCTAssertNil(history.snapshot.selected)
        try await history.openExisting();try await history.openRecord(detail.record.id)
        XCTAssertEqual(history.snapshot.selected?.record.note,"Actual saved prefix","No timeout or UI flag undoes an actual committed save")
    }
    func testSourceDeletePreservesIndependentManualNotesAndDoesNotSendRecordUnavailable()async throws{
        let(history,_,_,detail)=try await rig();var events:[HistoryRecordsUnavailable]=[]
        history.onRecordsUnavailable={events.append($0)}
        try await history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"User title",note:"Independent manual notes.")
        let selected=try XCTUnwrap(history.snapshot.selected)
        try await history.deleteSource(detail.record.id,expectedRevision:selected.record.revision,captureID:detail.captures[0].id,source:.selectedAppAudio).value
        XCTAssertTrue(events.isEmpty);XCTAssertEqual(history.snapshot.selected?.record.note,"Independent manual notes.")
        do{_=try await history.saveNotes(detail.record.id,expectedRevision:selected.record.revision,title:"Old",note:"Stale");XCTFail("Source deletion stales CAS")}catch{}
        XCTAssertTrue(events.isEmpty)
    }
}
