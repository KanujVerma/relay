import AppKit
import Foundation
import SwiftUI
import XCTest
import RelayProfile
import RelaySessionPanel
import RelayControls
import RelayContextComposition
@testable import RelayPanelSession

@MainActor private final class AppHistoryPreferences:HistorySavingPreferences{var savingEnabled=false}
private final class AppHistoryKey:ProfileKeyProvider,@unchecked Sendable{
    private let lock=NSLock();private var count=0
    var calls:Int{lock.withLock{count}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{count+=1};return Data(repeating:91,count:32)}
}
private final class AppHistoryStorage:HistoryOwnedSnapshotStorage,@unchecked Sendable{
    private let real:any HistoryOwnedSnapshotStorage
    private let lock=NSLock(),releaseGate=DispatchSemaphore(value:0)
    private var armed=false,held=false,skip=0
    init(_ real:any HistoryOwnedSnapshotStorage){self.real=real}
    func beginAccess(create:Bool)throws{try real.beginAccess(create:create)}
    func endAccess()throws{try real.endAccess()}
    func holdNextSave(skipping:Int=0){lock.withLock{armed=true;skip=skipping}}
    var isHeld:Bool{lock.withLock{held}}
    func release(){releaseGate.signal()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ data:Data,createKey:Bool)throws{
        let wait=lock.withLock{if armed{if skip>0{skip-=1;return false};armed=false;held=true;return true};return false}
        if wait{guard releaseGate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable};lock.withLock{held=false}}
        try real.save(data,createKey:createKey)
    }
}
@MainActor private final class AppHistoryStarts{
    var count=0
    func observe(_ ingress:SessionIngress){if case .audio(let event)=ingress,event.kind == .sessionStarted{count+=1}}
}
@MainActor final class HistoryApplicationTests:XCTestCase{
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func rig(directory:URL?=nil,preferences:AppHistoryPreferences?=nil,suite:String="coding")throws->(SessionApplicationModel,URL,AppHistoryPreferences,AppHistoryKey,AppHistoryStorage,AppHistoryStarts){
        let owns=directory==nil,directory=directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("relay-app-history-"+UUID().uuidString)
        if owns{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
        let prefs=preferences ?? AppHistoryPreferences(),key=AppHistoryKey(),starts=AppHistoryStarts()
        let port=AppHistoryStorage(HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:key))
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite",suite,"--repository",root.path,"--python",python],ingressEnqueued:starts.observe,
            historyPreferences:prefs,historyStorageFactory:{port})
        addTeardownBlock{port.release();await model.shutdown();if owns{try? FileManager.default.removeItem(at:directory)}}
        return(model,directory,prefs,key,port,starts)
    }
    private func until(_ condition:()->Bool)async throws{
        let deadline=ContinuousClock.now+Duration.seconds(6)
        while !condition(){guard ContinuousClock.now<deadline else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
    }
    func testDefaultFixtureCannotEnableOrOpenProductionHistoryStorage()async throws{
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path,"--python",python])
        XCTAssertFalse(model.canEnableHistory,"A demo without explicit synthetic storage must not reach AppSupport or Keychain")
        // On a predecessor failure, never call a potentially real storage path.
        guard !model.canEnableHistory else{return}
        do{try await model.history.enableSaving();XCTFail("Fixture production storage must stay unavailable")}catch{}
        do{try await model.history.openExisting();XCTFail("Fixture must not read a real vault")}catch{}
        XCTAssertFalse(model.history.savingEnabled);XCTAssertEqual(model.history.snapshot.phase,.unavailable)
        await model.shutdown()
    }
    func testEndEscalatingAHeldPauseCannotLeaveAPausedHistoryRecord()async throws{
        let(model,_,_,_,port,_)=try rig();try await model.history.enableSaving()
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.history.waitForQuiescence()
        let record=try XCTUnwrap(model.history.snapshot.recordingID)
        port.holdNextSave(skipping:1);try model.perform(.pause);try await until{port.isHeld}
        let end=Task{await model.stop()};for _ in 0..<10{await Task.yield()}
        XCTAssertTrue(model.stopping);XCTAssertFalse(model.canResume)
        port.release();await end.value
        XCTAssertFalse(model.paused);XCTAssertFalse(model.history.hasPausedSession)
        try await model.history.openRecord(record)
        XCTAssertNotEqual(model.history.snapshot.selected?.record.state,.paused)
        XCTAssertFalse(model.history.snapshot.selected?.captures.isEmpty ?? true)
    }
    func testHistoryAppearanceAndDefaultFixtureAreInertThenActualFinalAndNotesReopen()async throws{
        let(model,directory,prefs,key,_,starts)=try rig()
        let view=NSHostingView(rootView:RelayHistoryWorkspace(model:model));view.layoutSubtreeIfNeeded()
        XCTAssertEqual(key.calls,0);XCTAssertFalse(prefs.savingEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("Relay").path))
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop()
        XCTAssertEqual(key.calls,0);XCTAssertEqual(starts.count,1)
        try await model.history.enableSaving();await model.start()
        try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop();await model.history.waitForQuiescence()
        let record=try XCTUnwrap(model.history.snapshot.records.first)
        try await model.history.openRecord(record.id)
        let detail=try XCTUnwrap(model.history.snapshot.selected)
        XCTAssertEqual(detail.rows.map(\.text),["Write a Python function that returns the first item or None for an empty list."])
        XCTAssertEqual(detail.rows.map(\.source),[.selectedAppAudio]);XCTAssertEqual(detail.record.state,.completed)
        XCTAssertEqual(detail.rows[0].captureSessionID,detail.captures[0].captureSessionID)
        XCTAssertTrue(detail.captures[0].stop?.quiesced==true);XCTAssertNotNil(detail.captures[0].observedEndUptimeNanoseconds)
        try await model.history.saveNotes(record.id,expectedRevision:detail.record.revision,title:"Fictional practice",note:"Review an empty-list case.")
        await model.shutdown();XCTAssertTrue(prefs.savingEnabled)
        let(fresh,_,_,_,_,_)=try rig(directory:directory,preferences:prefs)
        try await fresh.history.openExisting();try await fresh.history.openRecord(record.id)
        XCTAssertEqual(fresh.history.snapshot.selected?.record.note,"Review an empty-list case.")
        XCTAssertEqual(fresh.history.snapshot.selected?.rows,detail.rows)
    }
    func testRememberedMissingHistoryAbortsActualStartWithoutAutoCreationAndLockRecovers()async throws{
        let(model,directory,prefs,key,_,starts)=try rig();prefs.savingEnabled=true
        await model.start()
        XCTAssertFalse(model.running);XCTAssertEqual(starts.count,0);XCTAssertEqual(key.calls,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("Relay").path));XCTAssertNotNil(model.error)
        model.history.lock();await model.history.waitForQuiescence();await model.start()
        XCTAssertTrue(model.running);XCTAssertEqual(starts.count,1);XCTAssertFalse(prefs.savingEnabled)
    }
    func testLockAndEndJoinActualPendingHistoryBeforeAnyNativeStart()async throws{
        let(model,_,prefs,_,port,starts)=try rig()
        try await model.history.enableSaving();port.holdNextSave()
        let start=Task{await model.start()};try await until{port.isHeld}
        model.history.lock();let end=Task{await model.stop()}
        try await until{model.stopping};XCTAssertFalse(model.canStartSession)
        XCTAssertEqual(starts.count,0);XCTAssertTrue(model.history.isBusy)
        port.release();await start.value;await end.value;await model.history.waitForQuiescence()
        XCTAssertFalse(model.running);XCTAssertEqual(starts.count,0);XCTAssertFalse(prefs.savingEnabled)
        await model.start();XCTAssertTrue(model.running);XCTAssertEqual(starts.count,1)
    }
    func testActualFinalHistorySubscriberEndCannotRepublishRetiredEphemeralTranscript()async throws{
        let(model,_,_,_,_,_)=try rig();try await model.history.enableSaving()
        var startedPending=false,startDrained=false,ended=false,republished=false,clearedInsideEnd=false
        let transient=model.assistant.transcript.$snapshot.sink{incoming in
            if ended && !incoming.rows.isEmpty{republished=true}
        }
        let retention=model.history.$snapshot.sink{incoming in
            // This fixture has one native start observation, then one original
            // actual final. Handle both valid writer schedules: start still
            // queued, or start already drained before that final arrives.
            if incoming.pendingCount>0 && !startedPending{startedPending=true;return}
            if startedPending && incoming.pendingCount==0{startDrained=true}
            guard !ended,model.running,incoming.pendingCount>0,
                  startDrained || incoming.pendingCount>1 else{return}
            ended=true;model.beginRetirement(end:true)
            clearedInsideEnd=model.assistant.transcript.snapshot.rows.isEmpty
        }
        await model.start();try await until{ended && !model.stopping}
        retention.cancel();transient.cancel()
        XCTAssertTrue(clearedInsideEnd)
        XCTAssertFalse(republished,"The original consume must not append its final after the History callback synchronously Ends")
        XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty);XCTAssertFalse(model.running)
        await model.history.waitForQuiescence()
        let record=try XCTUnwrap(model.history.snapshot.records.first)
        try await model.history.openRecord(record.id)
        XCTAssertEqual(model.history.snapshot.selected?.rows.map(\.text),["Write a Python function that returns the first item or None for an empty list."])
    }
    func testActualPauseResumeUsesFreshCaptureAndOneLogicalHistoryRecord()async throws{
        let(model,_,prefs,_,_,starts)=try rig();try await model.history.enableSaving()
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty}
        let record=try XCTUnwrap(model.history.snapshot.recordingID),first=try XCTUnwrap(model.currentSessionID)
        try model.perform(.pause);try await until{model.canResume}
        XCTAssertTrue(prefs.savingEnabled);XCTAssertEqual(model.history.snapshot.records.first?.state,.paused)
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty}
        XCTAssertNotEqual(model.currentSessionID,first);XCTAssertEqual(model.history.snapshot.recordingID,record)
        await model.stop();try await model.history.openRecord(record)
        XCTAssertEqual(starts.count,2);XCTAssertEqual(model.history.snapshot.selected?.captures.count,2)
        XCTAssertEqual(model.history.snapshot.selected?.rows.count,2);XCTAssertEqual(model.history.snapshot.selected?.record.state,.completed)
    }
    func testActualEndRemainsBusyUntilStartedHistoryFinishAndLockJoinReturn()async throws{
        let(model,_,prefs,_,port,_)=try rig();try await model.history.enableSaving()
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.history.waitForQuiescence()
        port.holdNextSave();var ended=false
        let end=Task{await model.stop();ended=true};try await until{port.isHeld}
        XCTAssertFalse(ended);XCTAssertTrue(model.stopping);XCTAssertFalse(model.canStartSession)
        model.history.lock();XCTAssertFalse(prefs.savingEnabled);XCTAssertTrue(model.history.snapshot.records.isEmpty)
        port.release();await end.value;await model.history.waitForQuiescence()
        XCTAssertTrue(ended);XCTAssertFalse(model.stopping);XCTAssertEqual(model.history.snapshot.phase,.locked)
    }
    func testReadyObserverLockPreventsActualCaptureAndDoesNotReviveHistory()async throws{
        let(model,_,prefs,_,_,starts)=try rig();try await model.history.enableSaving()
        let observation=model.history.$snapshot.sink{value in if value.recordingID != nil{model.history.lock()}}
        await model.start();await model.history.waitForQuiescence();observation.cancel()
        XCTAssertEqual(starts.count,0);XCTAssertFalse(model.running);XCTAssertFalse(prefs.savingEnabled)
        XCTAssertEqual(model.history.snapshot.phase,.locked);XCTAssertTrue(model.history.snapshot.records.isEmpty)
    }
    func testActualSourceFailureKeepsAnHonestPartialPrefixWithoutInventingText()async throws{
        let(model,_,_,_,_,starts)=try rig(suite:"source-failure");try await model.history.enableSaving()
        await model.start();try await until{starts.count==1 && !model.running && !model.stopping}
        await model.history.waitForQuiescence()
        let record=try XCTUnwrap(model.history.snapshot.records.first)
        XCTAssertEqual(record.state,.partial);XCTAssertTrue(record.gaps.contains(.sourceUnavailable))
        try await model.history.openRecord(record.id)
        XCTAssertEqual(model.history.snapshot.selected?.rows.count,0)
    }
    func testIdleAssistantDoesNotCreateAudioHistoryOrTreatNotesAsPersonalFacts()async throws{
        let(model,_,_,_,_,starts)=try rig();try await model.history.enableSaving()
        await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop()
        let record=try XCTUnwrap(model.history.snapshot.records.first);try await model.history.openRecord(record.id)
        try await model.history.saveNotes(record.id,expectedRevision:model.history.snapshot.selected!.record.revision,title:"Fictional notes",note:"I implemented the Fictional Northstar system.")
        let count=model.history.snapshot.records.count
        model.assistant.draft="What did you personally do on your Fictional Northstar project?";model.assistant.submitDraft()
        try await until{model.assistantActive && model.snapshot.question != nil && model.snapshot.status != "Thinking"}
        XCTAssertNil(model.snapshot.card);XCTAssertEqual(starts.count,1)
        XCTAssertNil(model.history.snapshot.recordingID);XCTAssertEqual(model.history.snapshot.records.count,count)
    }
    func testWarmMissingOrCorruptVaultCannotBeRecreatedByAnotherRememberedStart()async throws{
        for corrupt in [false,true]{
            let(model,directory,_,_,_,starts)=try rig();try await model.history.enableSaving()
            await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop()
            let path=directory.appendingPathComponent("Relay/History/history.relayvault")
            if corrupt{try Data("synthetic-invalid-history-ciphertext".utf8).write(to:path)}else{try FileManager.default.removeItem(at:path)}
            await model.start()
            XCTAssertFalse(model.running,"An open memory queue cannot replace actual existing-vault validation")
            XCTAssertEqual(starts.count,1)
            if corrupt{XCTAssertEqual(try Data(contentsOf:path),Data("synthetic-invalid-history-ciphertext".utf8))}
            else{XCTAssertFalse(FileManager.default.fileExists(atPath:path.path))}
            await model.shutdown()
        }
    }
    func testSecondActualModelCannotReadHistoryOrStartCaptureUntilFirstOwnerCloses()async throws{
        let(first,directory,_,_,_,_)=try rig();try await first.history.enableSaving()
        await first.start();try await until{!first.assistant.transcript.snapshot.rows.isEmpty};await first.stop()
        let preference=AppHistoryPreferences();preference.savingEnabled=true
        let(second,_,_,key,_,starts)=try rig(directory:directory,preferences:preference)
        await second.start();XCTAssertFalse(second.running);XCTAssertEqual(starts.count,0);XCTAssertEqual(key.calls,0)
        XCTAssertTrue(second.error?.contains("in use")==true,"The actual contention result needs a useful fixed recovery message")
        await first.shutdown();await second.start();try await until{!second.assistant.transcript.snapshot.rows.isEmpty}
        XCTAssertTrue(second.running);XCTAssertEqual(starts.count,1)
        await second.stop();XCTAssertEqual(second.history.snapshot.records.count,2)
    }
    func testHistoryLockLeavesCaptureActiveAndActualHelperDoesNotInheritLease()async throws{
        let(first,directory,prefs,_,_,_)=try rig();try await first.history.enableSaving()
        await first.start();try await until{!first.assistant.transcript.snapshot.rows.isEmpty};await first.history.waitForQuiescence()
        let helper=try first.ensureHelper(),record=try XCTUnwrap(first.history.snapshot.recordingID)
        first.history.lock();await first.history.waitForQuiescence()
        XCTAssertFalse(prefs.savingEnabled);XCTAssertTrue(first.running)
        XCTAssertTrue(try first.ensureHelper() === helper);XCTAssertEqual(first.assistant.transcript.snapshot.rows.count,1)
        let(second,_,_,_,_,_)=try rig(directory:directory)
        try await second.history.openExisting();try await second.history.openRecord(record)
        XCTAssertEqual(second.history.snapshot.selected?.record.state,.partial)
        XCTAssertTrue(second.history.snapshot.selected?.record.gaps.contains(.savingStopped)==true)
        second.history.lock();await second.history.waitForQuiescence()
    }
    func testOptInSyntheticHistoryRendersNeverOrderAWindowOnScreen()async throws{
        guard let path=ProcessInfo.processInfo.environment["RELAY_HISTORY_RENDER_DIRECTORY"] else{throw XCTSkip("Explicit synthetic offscreen History exports only.")}
        let directory=URL(fileURLWithPath:path,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let(model,_,_,_,_,_)=try rig()
        try renderHistory(model,name:"history-locked",directory:directory)
        try await model.history.enableSaving();await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop()
        let record=try XCTUnwrap(model.history.snapshot.records.first);try await model.history.openRecord(record.id)
        try await model.history.saveNotes(record.id,expectedRevision:model.history.snapshot.selected!.record.revision,title:"Fictional queue practice",note:"Review the empty-input case. Explain tradeoffs clearly.\nThese are user notes, not approved facts.")
        try renderHistory(model,name:"history-saved",directory:directory)
        model.history.lock();await model.history.waitForQuiescence()
    }
    private func renderHistory(_ model:SessionApplicationModel,name:String,directory:URL)throws{
        let size=CGSize(width:920,height:720)
        let hosting=NSHostingView(rootView:VStack(spacing:0){Text("SYNTHETIC HISTORY · fictional audio packets · temporary encrypted store · fake key").font(.system(size:10)).foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(12);RelayHistoryWorkspace(model:model)}.frame(width:size.width,height:size.height).preferredColorScheme(.dark))
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentView=hosting;hosting.frame=NSRect(origin:.zero,size:size)
        window.layoutIfNeeded();hosting.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.1));hosting.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds));hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent(name+".png"))
        window.contentView=nil;window.close()
    }
}
