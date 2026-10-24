import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

@MainActor final class HistoryFixturePreferences:HistorySavingPreferences{
    var savingEnabled=false
}
private struct CoordinatorFixtureKey:ProfileKeyProvider {
    func key(createIfMissing:Bool)throws->Data{Data(repeating:71,count:32)}
}
/// Holds a real encrypted save after its storage call has begun. Releasing
/// performs the actual file write, so retirement cannot pass on a timer.
private final class HeldHistoryStorage:ProtectedSnapshotStorage,@unchecked Sendable {
    private let lock=NSLock(),releaseGate=DispatchSemaphore(value:0)
    private let real:any ProtectedSnapshotStorage
    private var arm=false,held=false,calls=0
    init(_ real:any ProtectedSnapshotStorage){self.real=real}
    func holdNextSave(){lock.withLock{arm=true}}
    var isHeld:Bool{lock.withLock{held}}
    var callCount:Int{lock.withLock{calls}}
    func release(){releaseGate.signal()}
    func exists()throws->Bool{lock.withLock{calls+=1};return try real.exists()}
    func load()throws->Data{lock.withLock{calls+=1};return try real.load()}
    func save(_ payload:Data,createKey:Bool)throws{
        let shouldHold=lock.withLock{calls+=1;if arm{arm=false;held=true;return true};return false}
        if shouldHold{
            guard releaseGate.wait(timeout:.now()+8) == .success else{throw ProfileError.unavailable}
            lock.withLock{held=false}
        }
        try real.save(payload,createKey:createKey)
    }
}
private final class HeldHistoryExport:HistoryExportDestination,@unchecked Sendable {
    private let lock=NSLock(),releaseGate=DispatchSemaphore(value:0)
    private var value:Data?,started=false
    var isStarted:Bool{lock.withLock{started}}
    var data:Data?{lock.withLock{value}}
    func release(){releaseGate.signal()}
    func write(_ data:Data)throws{
        lock.withLock{started=true}
        guard releaseGate.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable}
        lock.withLock{value=data}
    }
}

@MainActor final class HistoryCoordinatorTests:XCTestCase {
    private func fixture()throws->(URL,HeldHistoryStorage,HistoryFixturePreferences){
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("relay-history-coordinator-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return(root,HeldHistoryStorage(ProtectedSnapshotVault(directory:root.appendingPathComponent("Relay/History"),purpose:.history,keys:CoordinatorFixtureKey())),HistoryFixturePreferences())
    }
    private func until(_ condition:@MainActor ()->Bool)async throws{
        let deadline=ContinuousClock.now+Duration.seconds(5)
        while !condition(){guard ContinuousClock.now<deadline else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(5))}
    }
    private func coordinator(_ port:any ProtectedSnapshotStorage,_ preferences:HistoryFixturePreferences)->SessionHistoryCoordinator{
        SessionHistoryCoordinator(storageFactory:{port},preferences:preferences,canEnable:{true})
    }
    private func start(_ history:SessionHistoryCoordinator)async throws->(HistorySessionPermit,SessionTranscriptStore,HistoryTestEvents){
        try await history.enableSaving()
        let permit=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})!
        let transcript=SessionTranscriptStore();transcript.onHistoryObservation=history.observe
        var events=HistoryTestEvents();events.start(transcript);await history.waitForQuiescence()
        return(permit,transcript,events)
    }
    func testDefaultConstructorAndOffStartDoNoStorageWorkAndMissingRestoreCannotCreate()async throws{
        let(root,port,prefs)=try fixture(),history=coordinator(port,prefs)
        XCTAssertEqual(port.callCount,0);XCTAssertFalse(history.snapshot.savingEnabled)
        let off=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true});XCTAssertNil(off)
        XCTAssertEqual(port.callCount,0)
        prefs.savingEnabled=true
        do{_=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true});XCTFail("Missing remembered vault must abort")}
        catch{}
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("Relay").path))
        XCTAssertTrue(prefs.savingEnabled);XCTAssertEqual(history.snapshot.phase,.unavailable)
        history.lock();await history.waitForQuiescence();XCTAssertFalse(prefs.savingEnabled)
    }
    func testLockFencesPendingStartAndJoinsRealWriteBeforeReplacementOrReady()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        try await history.enableSaving();port.holdNextSave()
        let pending=Task(priority:.background){try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})}
        try await until{port.isHeld}
        history.lock()
        XCTAssertFalse(prefs.savingEnabled);XCTAssertTrue(history.isBusy);XCTAssertTrue(history.snapshot.records.isEmpty)
        do{try await history.enableSaving();XCTFail("Held old ownership must block replacement")}catch{}
        port.release();switch await pending.result{case .success:XCTFail("Late start cannot become ready");case .failure:break}
        await history.waitForQuiescence()
        XCTAssertFalse(history.isBusy);XCTAssertEqual(history.snapshot.phase,.locked)
        let fresh=HistoryStore(storage:port);try fresh.open(create:false)
        XCTAssertTrue(try fresh.list().records.isEmpty);try fresh.close()
    }
    func testStopSavingDropsUnstartedRowsButJoinsStartedPrefixAndKeepsReadAccess()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        port.holdNextSave();events.final(1,text:"Actually started prefix",into:transcript)
        try await until{port.isHeld}
        events.final(2,text:"Queued private text to discard",into:transcript)
        events.final(3,text:"Another queued private text",into:transcript)
        history.stopSaving();XCTAssertFalse(prefs.savingEnabled);XCTAssertTrue(history.isBusy)
        port.release();await history.waitForQuiescence()
        XCTAssertEqual(history.snapshot.records.first?.state,.partial)
        try await history.openRecord(permit.recordID)
        XCTAssertEqual(history.snapshot.selected?.rows.map(\.text),["Actually started prefix"])
        XCTAssertEqual(history.snapshot.selected?.record.state,.partial)
        XCTAssertTrue(history.snapshot.selected?.record.gaps.contains(.savingStopped)==true)
        events.final(4,text:"Late text after saving off",into:transcript);await history.waitForQuiescence()
        try await history.openRecord(permit.recordID)
        XCTAssertEqual(history.snapshot.selected?.rows.count,1)
        history.lock();await history.waitForQuiescence()
    }
    func testDeleteTombstonePrecedesHeldSaveAndLateCompletionCannotRecreateRecord()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        let revision=history.snapshot.records.first!.revision
        port.holdNextSave();events.final(1,text:"Started before deletion",into:transcript)
        try await until{port.isHeld}
        let deletion=history.delete(permit.recordID,expectedRevision:revision)
        XCTAssertTrue(history.snapshot.records.allSatisfy{$0.id != permit.recordID})
        events.final(2,text:"Must not recreate deleted history",into:transcript)
        XCTAssertTrue(history.isBusy)
        port.release();try await deletion.value;await history.waitForQuiescence()
        XCTAssertTrue(history.snapshot.records.isEmpty)
        history.lock();await history.waitForQuiescence()
        let fresh=HistoryStore(storage:port);try fresh.open(create:false)
        XCTAssertTrue(try fresh.list().records.isEmpty);try fresh.close()
    }
    func testPausedReadViewRequiresCurrentActualPermitAndNeverSurvivesEndOrLock()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        events.final(1,text:"Fictional paused passage",into:transcript)
        XCTAssertFalse(history.hasPausedSession)
        history.retireCurrentSession();events.stop(into:transcript)
        try await history.finishSession(permit,paused:true);XCTAssertTrue(history.hasPausedSession)
        history.retireCurrentSession();XCTAssertFalse(history.hasPausedSession,"An End prefix denies the paused read view immediately")
        try await history.finishSession(permit,paused:false);XCTAssertFalse(history.hasPausedSession)
        let(next,second,initial2)=try await start(history);var events2=initial2
        events2.final(1,text:"Another fictional passage",into:second)
        history.retireCurrentSession();events2.stop(into:second);try await history.finishSession(next,paused:true)
        XCTAssertTrue(history.hasPausedSession);history.lock();XCTAssertFalse(history.hasPausedSession)
        await history.waitForQuiescence()
    }
    func testPauseFlushesAdmittedRowsAndResumeUsesFreshOriginalCaptureSegment()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(first,transcript,initial)=try await start(history);var events=initial
        events.final(1,text:"Before actual pause",into:transcript)
        history.retireCurrentSession();events.stop(into:transcript)
        try await history.finishSession(first,paused:true)
        XCTAssertTrue(prefs.savingEnabled)
        let next=try await history.beginSession(intentID:UUID(),resuming:true,isCurrent:{true})!
        XCTAssertEqual(next.recordID,first.recordID)
        var resumed=HistoryTestEvents();resumed.start(transcript)
        resumed.final(1,text:"Fresh capture after resume",into:transcript)
        history.retireCurrentSession();resumed.stop(into:transcript);try await history.finishSession(next,paused:false)
        try await history.openRecord(first.recordID)
        XCTAssertEqual(history.snapshot.selected?.captures.count,2)
        XCTAssertEqual(history.snapshot.selected?.rows.map(\.text),["Before actual pause","Fresh capture after resume"])
        XCTAssertEqual(history.snapshot.selected?.record.state,.completed)
        XCTAssertTrue(prefs.savingEnabled)
        await history.closeForOwnerRetirement();XCTAssertTrue(prefs.savingEnabled)
    }
    func testPendingBudgetStopsOnlyHistoryAndFinalizesAnHonestPartialPrefix()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        port.holdNextSave();events.final(1,text:"Prefix",into:transcript);try await until{port.isHeld}
        for n in 2...200{events.final(UInt64(n),text:"Bounded row \(n)",into:transcript)}
        XCTAssertLessThanOrEqual(history.snapshot.pendingCount,HistoryBounds.pending)
        XCTAssertEqual(transcript.snapshot.rows.count,64)
        port.release();await history.waitForQuiescence()
        try await history.openRecord(permit.recordID)
        XCTAssertEqual(history.snapshot.selected?.record.state,.partial)
        XCTAssertTrue(history.snapshot.selected?.record.gaps.contains(.capacity)==true)
        XCTAssertLessThanOrEqual(history.snapshot.selected?.totalRows ?? Int.max,HistoryBounds.pending+1)
        history.lock();await history.waitForQuiescence()
    }
    func testCancelledBeforeRegistrationCannotEnableOrPublishAnExistingRead()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let enable=Task{try await history.enableSaving()};enable.cancel()
        switch await enable.result{case .success:XCTFail("Precancelled Enable cannot commit consent");case .failure:break}
        XCTAssertEqual(port.callCount,0);XCTAssertFalse(prefs.savingEnabled)
        let(permit,_,_)=try await start(history)
        let read=Task{try await history.openRecord(permit.recordID)};read.cancel()
        switch await read.result{case .success:XCTFail("Precancelled read cannot publish");case .failure:break}
        XCTAssertNil(history.snapshot.selected)
        history.lock();await history.waitForQuiescence()
    }
    func testReadyObserverCancellationCannotLeaveAnEmptyUncapturedRecordVisible()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        try await history.enableSaving()
        var pending:Task<HistorySessionPermit?,Error>?
        let observation=history.$snapshot.sink{value in if value.recordingID != nil{pending?.cancel()}}
        pending=Task{try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true})}
        switch await pending!.result{case .success:XCTFail("Cancelled issuance cannot be ready");case .failure:break}
        await history.waitForQuiescence()
        XCTAssertTrue(history.snapshot.records.isEmpty)
        observation.cancel();history.lock();await history.waitForQuiescence()
    }
    func testLockEscalatesAnAlreadyRunningStopSavingJoinWithoutDowngradingToReady()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        port.holdNextSave();events.final(1,text:"Owned prefix before close",into:transcript)
        try await until{port.isHeld}
        history.stopSaving();history.lock();history.lock()
        XCTAssertTrue(history.snapshot.records.isEmpty);XCTAssertTrue(history.isBusy)
        port.release();await history.waitForQuiescence()
        XCTAssertEqual(history.snapshot.phase,.locked);XCTAssertFalse(history.isBusy);XCTAssertFalse(prefs.savingEnabled)
        do{try await history.openRecord(permit.recordID);XCTFail("Lock must require a new explicit open")}catch{}
        XCTAssertNil(history.snapshot.selected)
    }
    func testManualNotesCASAndPagedTranscriptExportAreCompleteAfterRestart()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        for n in 1...70{events.final(UInt64(n),text:"Fictional row \(n)",into:transcript);await history.waitForQuiescence()}
        history.retireCurrentSession();events.stop(into:transcript);try await history.finishSession(permit,paused:false)
        try await history.openRecord(permit.recordID)
        XCTAssertEqual(history.snapshot.selected?.rows.count,64)
        let first=history.snapshot.selected!
        try await history.loadMoreTranscript()
        XCTAssertEqual(history.snapshot.selected?.rows.count,70)
        try await history.saveNotes(permit.recordID,expectedRevision:first.record.revision,title:"Practice notes",note:"User wrote this, not a confirmed fact.")
        do{try await history.saveNotes(permit.recordID,expectedRevision:first.record.revision,title:"Stale",note:"Must not replace");XCTFail("CAS must reject old editor")}catch{}
        XCTAssertEqual(history.snapshot.selected?.record.title,"Practice notes")
        let destination=HeldHistoryExport(),revision=history.snapshot.selected!.record.revision
        let export=history.export(permit.recordID,expectedRevision:revision,format:.json,to:destination)
        try await until{destination.isStarted};destination.release();try await export.value
        let json=try XCTUnwrap(try JSONSerialization.jsonObject(with:XCTUnwrap(destination.data)) as? [String:Any])
        XCTAssertEqual((json["transcript"] as? [Any])?.count,70)
        XCTAssertEqual(json["title"] as? String,"Practice notes")
        let output=FileManager.default.temporaryDirectory.appendingPathComponent("relay-explicit-history-export-"+UUID().uuidString+".md")
        defer{try? FileManager.default.removeItem(at:output)}
        try await history.export(permit.recordID,expectedRevision:revision,format:.markdown,to:HistoryFileExportDestination(url:output)).value
        XCTAssertTrue(try String(contentsOf:output,encoding:.utf8).contains("Fictional row 70"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:output.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
        history.lock();await history.waitForQuiescence();try await history.openExisting();try await history.openRecord(permit.recordID)
        XCTAssertEqual(history.snapshot.selected?.record.note,"User wrote this, not a confirmed fact.")
        history.lock();await history.waitForQuiescence()
    }
    func testSourceDeletionFencesQueuedSourceAndRetainsOtherSourceAndNotes()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        events.final(1,text:"Keep microphone",source:1,into:transcript);await history.waitForQuiescence()
        try await history.openRecord(permit.recordID)
        let detail=history.snapshot.selected!
        port.holdNextSave();events.final(2,text:"Started source to delete",into:transcript);try await until{port.isHeld}
        events.final(3,text:"Queued source to delete",into:transcript)
        let deletion=history.deleteSource(permit.recordID,expectedRevision:detail.record.revision,captureID:detail.captures[0].id,source:.selectedAppAudio)
        XCTAssertNil(history.snapshot.selected)
        events.final(4,text:"Late source must stay deleted",into:transcript)
        port.release();try await deletion.value;await history.waitForQuiescence()
        events.final(5,text:"Keep later microphone",source:1,into:transcript);await history.waitForQuiescence()
        try await history.openRecord(permit.recordID)
        XCTAssertEqual(history.snapshot.selected?.rows.map(\.text),["Keep microphone","Keep later microphone"])
        XCTAssertTrue(history.snapshot.selected?.record.blockedSources.contains(.selectedAppAudio)==true)
        history.retireCurrentSession();events.stop(into:transcript);try await history.finishSession(permit,paused:false)
        XCTAssertEqual(history.snapshot.records.first?.state,.partial)
        history.lock();await history.waitForQuiescence()
    }
    func testLockJoinsAnActuallyStartedExportButHidesImmediatelyAndPurgeCannotBeUndone()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(permit,transcript,initial)=try await start(history);var events=initial
        events.final(1,text:"Explicit exported copy",into:transcript);await history.waitForQuiescence()
        history.retireCurrentSession();events.stop(into:transcript);try await history.finishSession(permit,paused:false)
        try await history.openRecord(permit.recordID)
        let destination=HeldHistoryExport()
        let export=history.export(permit.recordID,expectedRevision:history.snapshot.selected!.record.revision,format:.markdown,to:destination)
        try await until{destination.isStarted};history.lock()
        XCTAssertNil(history.snapshot.selected);XCTAssertTrue(history.snapshot.records.isEmpty);XCTAssertTrue(history.isBusy)
        destination.release();_=await export.result;await history.waitForQuiescence()
        XCTAssertNotNil(destination.data);XCTAssertEqual(history.snapshot.phase,.locked)
        try await history.openExisting();let purge=history.deleteAll()
        XCTAssertTrue(history.snapshot.records.isEmpty);XCTAssertFalse(prefs.savingEnabled)
        try await purge.value;history.lock();await history.waitForQuiescence()
        try await history.openExisting();XCTAssertTrue(history.snapshot.records.isEmpty)
        history.lock();await history.waitForQuiescence()
    }
    func testReadyDetailSubscriberDeleteAndSourceDeleteStayHiddenBeforeActualReceipt()async throws{
        for sourceOnly in [false,true]{
            let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
            let(permit,transcript,initial)=try await start(history);var events=initial
            events.final(1,text:"Fictional selected app passage",into:transcript)
            events.final(2,text:"Fictional microphone passage",source:1,into:transcript)
            history.retireCurrentSession();events.stop(into:transcript);try await history.finishSession(permit,paused:false)
            var deletion:Task<Void,Error>?,triggered=false
            port.holdNextSave();defer{port.release()}
            let observation=history.$snapshot.sink{incoming in
                guard !triggered,let detail=incoming.selected,detail.record.id==permit.recordID else{return}
                triggered=true
                if sourceOnly{
                    deletion=history.deleteSource(permit.recordID,expectedRevision:detail.record.revision,captureID:detail.captures[0].id,source:.selectedAppAudio)
                }else{deletion=history.delete(permit.recordID,expectedRevision:detail.record.revision)}
            }
            try await history.openRecord(permit.recordID)
            XCTAssertTrue(triggered)
            // This assertion intentionally precedes any await/task scheduling:
            // the outer @Published will-set must not restore nested-cleared data.
            XCTAssertNil(history.snapshot.selected,"Reentrant deletion must stay hidden immediately")
            if !sourceOnly{XCTAssertFalse(history.snapshot.records.contains{$0.id==permit.recordID})}
            try await until{port.isHeld};XCTAssertTrue(history.isBusy);XCTAssertNil(history.snapshot.selected)
            port.release();try await XCTUnwrap(deletion).value;observation.cancel()
            if sourceOnly{
                try await history.openRecord(permit.recordID)
                XCTAssertEqual(history.snapshot.selected?.rows.map(\.text),["Fictional microphone passage"])
                XCTAssertNil(history.snapshot.selected?.captures[0].selectedBundleID)
            }else{
                do{try await history.openRecord(permit.recordID);XCTFail("The actual deleted session cannot reopen")}catch{}
                XCTAssertFalse(history.snapshot.records.contains{$0.id==permit.recordID})
            }
            history.lock();await history.waitForQuiescence()
        }
    }
    func testReentrantLockObserverCannotRecursivelyRepublishTheSameClosingOwner()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        try await history.enableSaving();var callbackCount=0
        let observation=history.$snapshot.sink{value in
            if value.recordingID != nil{
                callbackCount+=1
                // Bounded probe avoids overflowing the stack on the red path.
                if callbackCount<20{history.lock()}
            }
        }
        do{_=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true});XCTFail("Reentrant Lock cannot admit Start")}catch{}
        await history.waitForQuiescence();observation.cancel()
        XCTAssertLessThan(callbackCount,20,"One close owner must not recursively republish itself")
        XCTAssertEqual(history.snapshot.phase,.locked);XCTAssertFalse(prefs.savingEnabled)
    }
    func testRepeatedStopSavingFromObserverAlsoCoalescesItsOriginalJoin()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        try await history.enableSaving();var callbackCount=0
        let observation=history.$snapshot.sink{value in
            if value.recordingID != nil{callbackCount+=1;if callbackCount<20{history.stopSaving()}}
        }
        do{_=try await history.beginSession(intentID:UUID(),resuming:false,isCurrent:{true});XCTFail("Off cannot admit Start")}catch{}
        await history.waitForQuiescence();observation.cancel()
        XCTAssertLessThan(callbackCount,20);XCTAssertFalse(prefs.savingEnabled)
        XCTAssertTrue(history.snapshot.records.isEmpty);history.lock();await history.waitForQuiescence()
    }
    func testUnfinishedSpeechGapSurvivesPauseResumeWithoutInventingAFinalPassage()async throws{
        let(_,port,prefs)=try fixture(),history=coordinator(port,prefs)
        let(first,transcript,_)=try await start(history)
        history.retireCurrentSession(gap:.unfinishedSpeech);try await history.finishSession(first,paused:true)
        let second=try await history.beginSession(intentID:UUID(),resuming:true,isCurrent:{true})!
        var events=HistoryTestEvents();events.start(transcript)
        history.retireCurrentSession();try await history.finishSession(second,paused:false)
        try await history.openRecord(first.recordID)
        XCTAssertEqual(history.snapshot.selected?.record.state,.partial)
        XCTAssertTrue(history.snapshot.selected?.record.gaps.contains(.unfinishedSpeech)==true)
        XCTAssertTrue(history.snapshot.selected?.rows.isEmpty==true)
        history.lock();await history.waitForQuiescence()
    }
}
