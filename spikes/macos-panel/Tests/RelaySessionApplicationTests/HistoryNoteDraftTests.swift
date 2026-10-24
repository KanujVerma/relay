import AppKit
import Combine
import Foundation
import SwiftUI
import XCTest
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class DraftHistoryPreferences:HistorySavingPreferences{var savingEnabled=false}
private final class DraftHistoryKey:ProfileKeyProvider,@unchecked Sendable{
    private let lock=NSLock();private var count=0
    var calls:Int{lock.withLock{count}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{count+=1};return Data(repeating:123,count:32)}
}
private final class DraftHistoryStorage:ProtectedSnapshotStorage,@unchecked Sendable{
    let real:ProtectedSnapshotVault
    private let lock=NSLock(),gate=DispatchSemaphore(value:0)
    private var armed=false,held=false
    init(_ real:ProtectedSnapshotVault){self.real=real}
    var isHeld:Bool{lock.withLock{held}}
    func holdNextSave(){lock.withLock{armed=true}}
    func release(){gate.signal()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ data:Data,createKey:Bool)throws{
        let wait=lock.withLock{if armed{armed=false;held=true;return true};return false}
        if wait{guard gate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable}}
        defer{lock.withLock{held=false}}
        try real.save(data,createKey:createKey)
    }
}
@MainActor final class HistoryNoteDraftTests:XCTestCase{
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func rig()throws->(SessionApplicationModel,URL,DraftHistoryStorage,DraftHistoryKey){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-draft-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let key=DraftHistoryKey(),port=DraftHistoryStorage(ProtectedSnapshotVault(directory:directory.appendingPathComponent("Relay/History"),purpose:.history,keys:key))
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path,"--python",python],historyPreferences:DraftHistoryPreferences(),historyStorageFactory:{port})
        addTeardownBlock{port.release();await model.shutdown();try? FileManager.default.removeItem(at:directory)}
        return(model,directory,port,key)
    }
    private func until(_ condition:()->Bool)async throws{
        for _ in 0..<1600{if condition(){return};try await Task.sleep(for:.milliseconds(3))};throw HistoryError.unavailable
    }
    private func record(_ model:SessionApplicationModel)async throws->HistoryDetail{
        if !model.history.savingEnabled{try await model.history.enableSaving()}
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop()
        let id=try XCTUnwrap(model.history.snapshot.records.first?.id)
        try await model.history.openRecord(id);return try XCTUnwrap(model.history.snapshot.selected)
    }
    func testConstructRenderAndRestageDoNoIOAndDirtyDraftSurvivesWorkspaceRecreation()async throws{
        let(model,directory,_,key)=try rig()
        let first=NSHostingView(rootView:RelayHistoryWorkspace(model:model));first.layoutSubtreeIfNeeded()
        XCTAssertEqual(key.calls,0);XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("Relay").path))
        let detail=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        let before=key.calls
        model.historyNoteDraft.editTitle("My unsaved title");model.historyNoteDraft.editNote("Original unsaved wording.")
        let second=NSHostingView(rootView:RelayHistoryWorkspace(model:model));second.layoutSubtreeIfNeeded()
        XCTAssertTrue(model.stageHistoryNoteDraft());XCTAssertEqual(key.calls,before)
        XCTAssertEqual(model.historyNoteDraft.snapshot.recordID,detail.record.id)
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"Original unsaved wording.");XCTAssertTrue(model.historyNoteDraft.snapshot.isDirty)
        try await model.history.openRecord(detail.record.id)
        XCTAssertEqual(model.history.snapshot.selected?.record.note,"")
    }
    func testActualSaveAcknowledgesCapturedTextWhileNewerEditsStayDirtyAndUseNewRevision()async throws{
        let(model,_,port,_)=try rig();let detail=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        model.historyNoteDraft.editNote("Captured save text.");port.holdNextSave()
        let save=Task{try await model.historyNoteDraft.save(using:model.history)};try await until{port.isHeld}
        model.historyNoteDraft.editNote("Newer edit made during save.")
        port.release();try await save.value
        XCTAssertEqual(model.history.snapshot.selected?.record.note,"Captured save text.")
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"Newer edit made during save.")
        XCTAssertTrue(model.historyNoteDraft.snapshot.isDirty)
        XCTAssertGreaterThan(try XCTUnwrap(model.historyNoteDraft.snapshot.expectedRevision),detail.record.revision)
        try await model.historyNoteDraft.save(using:model.history)
        XCTAssertEqual(model.history.snapshot.selected?.record.note,"Newer edit made during save.")
        XCTAssertFalse(model.historyNoteDraft.snapshot.isDirty)
    }
    func testFailedActualCASPreservesExactDraftAndOriginalExpectedRevision()async throws{
        let(model,_,_,_)=try rig();let detail=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        model.historyNoteDraft.editNote("Keep this exact unsaved text.")
        try await model.history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"Foreign edit",note:"Stored elsewhere.")
        XCTAssertFalse(model.stageHistoryNoteDraft(),"A passive refresh must not rebase a dirty draft")
        do{try await model.historyNoteDraft.save(using:model.history);XCTFail("Original CAS must remain stale")}catch{}
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"Keep this exact unsaved text.")
        XCTAssertEqual(model.historyNoteDraft.snapshot.expectedRevision,detail.record.revision)
        XCTAssertTrue(model.historyNoteDraft.snapshot.isDirty);XCTAssertFalse(model.historyNoteDraft.snapshot.isSaving)
        XCTAssertEqual(model.history.snapshot.selected?.record.note,"Stored elsewhere.")
    }
    func testActualLockDuringSaveClearsDraftBeforeJoinAndOldReceiptCannotRestoreIt()async throws{
        let(model,_,port,_)=try rig();_=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        model.historyNoteDraft.editNote("Private held draft.");port.holdNextSave()
        let save=Task{try await model.historyNoteDraft.save(using:model.history)};try await until{port.isHeld}
        model.history.lock()
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"");XCTAssertNil(model.historyNoteDraft.snapshot.recordID)
        XCTAssertFalse(model.stageHistoryNoteDraft(),"Closing/old publication cannot restage text")
        port.release();_=await save.result;await model.history.waitForQuiescence()
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"");XCTAssertNil(model.historyNoteDraft.snapshot.recordID)
    }
    func testReentrantDraftSubscriberLockCannotRestoreOuterText()async throws{
        let(model,_,_,_)=try rig();_=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        var locked=false
        let observation=model.historyNoteDraft.$snapshot.sink{incoming in
            if !locked,incoming.note=="Must clear synchronously"{locked=true;model.history.lock()}
        }
        model.historyNoteDraft.editNote("Must clear synchronously")
        XCTAssertTrue(locked);XCTAssertEqual(model.historyNoteDraft.snapshot.note,"")
        XCTAssertNil(model.historyNoteDraft.snapshot.recordID);observation.cancel();await model.history.waitForQuiescence()
    }
    func testAudioEndAndAccountHelperRetirementLeaveUnlockedDraftAlone()async throws{
        let(model,_,_,_)=try rig();let original=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        model.historyNoteDraft.editNote("Keep across ordinary session teardown.")
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop()
        try await model.retireSessionHelperForAccountChange()
        XCTAssertEqual(model.historyNoteDraft.snapshot.recordID,original.record.id)
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"Keep across ordinary session teardown.")
        XCTAssertTrue(model.historyNoteDraft.snapshot.isDirty)
    }
    func testUnrelatedDeleteKeepsDraftButMatchingDeleteClearsBeforeActualWriteJoin()async throws{
        let(model,_,_,_)=try rig();let original=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft())
        model.historyNoteDraft.editNote("Retain for the original session.")
        let other=try await record(model)
        XCTAssertNotEqual(other.record.id,original.record.id)
        XCTAssertFalse(model.stageHistoryNoteDraft(),"A different selected record cannot overwrite a dirty draft")
        try await model.history.delete(other.record.id,expectedRevision:other.record.revision).value
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,"Retain for the original session.")
        let deletion=model.history.delete(original.record.id,expectedRevision:original.record.revision)
        XCTAssertNil(model.historyNoteDraft.snapshot.recordID);XCTAssertEqual(model.historyNoteDraft.snapshot.note,"")
        try await deletion.value
    }
    func testEditorBoundsUTF8WithoutPersistingAndExplicitDiscardRestoresBaseline()async throws{
        let(model,_,_,key)=try rig();let detail=try await record(model);XCTAssertTrue(model.stageHistoryNoteDraft());let count=key.calls
        model.historyNoteDraft.editTitle(String(repeating:"a",count:200));model.historyNoteDraft.editNote(String(repeating:"🙂",count:3000))
        XCTAssertEqual(model.historyNoteDraft.snapshot.title,String(repeating:"a",count:120))
        XCTAssertEqual(model.historyNoteDraft.snapshot.note,String(repeating:"🙂",count:2048));XCTAssertEqual(key.calls,count)
        model.historyNoteDraft.discard()
        XCTAssertEqual(model.historyNoteDraft.snapshot.title,detail.record.title);XCTAssertEqual(model.historyNoteDraft.snapshot.note,"")
        XCTAssertFalse(model.historyNoteDraft.snapshot.isDirty);XCTAssertEqual(key.calls,count)
    }
}
