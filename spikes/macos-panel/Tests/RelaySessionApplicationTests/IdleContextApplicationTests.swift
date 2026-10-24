import Foundation
import XCTest
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class IdleContextPreference:SessionContextUsePreferences {var useInSessions=false}
private final class IdleContextKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock();private var reads=0,creates=0
    func key(createIfMissing:Bool)throws->Data {
        lock.withLock{if createIfMissing{creates+=1}else{reads+=1}}
        return Data(repeating:74,count:32)
    }
    var calls:(Int,Int){lock.withLock{(reads,creates)}}
}
@MainActor private final class IdleContextReceipt {
    let hold:Bool
    let command:String
    var entered=false
    private var pending:CheckedContinuation<Void,Never>?
    init(hold:Bool=false,command:String="load_commit"){self.hold=hold;self.command=command}
    func observe(_ data:Data)async {
        guard hold,let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],value["command"] as? String==command else{return}
        entered=true;await withCheckedContinuation{pending=$0}
    }
    func release(){pending?.resume();pending=nil}
}
@MainActor final class IdleContextApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func waitUntil(_ predicate:()->Bool)async throws{
        for _ in 0..<2000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"Idle context boundary not reached",code:1)
    }
    func testFailedOpenReapsItsChildAndJoinsHeldOriginalProfileBeforeAvailability()async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-idle-failed-profile-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let log=directory.appendingPathComponent("events.jsonl"),release=directory.appendingPathComponent("release"),launcher=directory.appendingPathComponent("helper")
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        func quote(_ value:String)->String{"'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"}
        try Data("#!/bin/sh\nexec \(quote(python)) \(quote(root.appendingPathComponent("tests/support/idle_backend_helper.py").path)) --synthetic-idle-test --hold open --log \(quote(log.path)) --release \(quote(release.path)) \"$@\"\n".utf8).write(to:launcher)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let preferences=IdleContextPreference(),key=IdleContextKey(),receipt=IdleContextReceipt(hold:true,command:"select_begin")
        let model=SessionApplicationModel(arguments:["relay","--repository",root.path,"--role","analytics","--python",launcher.path],
            contextPreferences:preferences,profileVaultFactory:{ProfileVault(directory:directory.appendingPathComponent("vault"),keys:key)},profileResponseObserved:receipt.observe)
        model.openMyContext();await model.contextUse.waitForQuiescence()
        XCTAssertTrue(model.profile.opened)
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        try await waitUntil{((try? String(contentsOf:log,encoding:.utf8)) ?? "").contains("open_ready")}
        let profile=model.profile
        let edit=Task{await profile.stageEnteredText("I wrote fictional validation tests.",purpose:"project",label:"Synthetic overlap",role:"analytics",project:"Fictional Northstar")}
        do {
            try await waitUntil{receipt.entered}
            let helper=try model.ensureHelper();await helper.shutdownAndWait()
            for _ in 0..<50{await Task.yield()}
            XCTAssertTrue(profile.busy)
            XCTAssertTrue(model.assistant.snapshot.isPreparing,"Reaped child alone does not join a held native profile receipt")
            XCTAssertFalse(model.canStartSession)
            receipt.release();await edit.value;await model.assistant.waitForPreparationQuiescence()
            XCTAssertFalse(profile.busy);XCTAssertFalse(model.assistantActive);XCTAssertNil(model.currentSessionID)
            XCTAssertEqual(model.assistant.draft,"What is the difference between WHERE and HAVING?")
            await model.stop();try? FileManager.default.removeItem(at:directory)
        }catch{receipt.release();await edit.value;await model.stop();try? FileManager.default.removeItem(at:directory);throw error}
    }
    private func model(directory:URL,preferences:IdleContextPreference,key:IdleContextKey,receipt:IdleContextReceipt=IdleContextReceipt())throws->SessionApplicationModel {
        SessionApplicationModel(arguments:["relay","--repository",root.path,"--role","analytics","--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])],
            contextPreferences:preferences,profileVaultFactory:{ProfileVault(directory:directory,keys:key)},profileResponseObserved:receipt.observe)
    }
    private func seed(directory:URL,preferences:IdleContextPreference,key:IdleContextKey)async throws {
        let seed=try model(directory:directory,preferences:preferences,key:key)
        seed.openMyContext();await seed.contextUse.waitForQuiescence()
        XCTAssertTrue(seed.profile.opened)
        await seed.profile.stageEnteredText("I implemented validation tests for Fictional Northstar.",purpose:"project",label:"Synthetic project",role:seed.role,project:"Fictional Northstar")
        let card=try XCTUnwrap(seed.profile.card)
        await seed.profile.review(card,actor:"self",claimKey:"fictional.northstar.tests",replaces:nil)
        XCTAssertEqual(seed.profile.memoryCount,1)
        await seed.stop()
    }
    func testIdleRestoreUsesActualReviewedPersonalEvidenceAndExplicitLockRetiresIt()async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-idle-context-"+UUID().uuidString)
        let preferences=IdleContextPreference(),key=IdleContextKey()
        defer{try? FileManager.default.removeItem(at:directory)}
        try await seed(directory:directory,preferences:preferences,key:key)
        let created=key.calls.1,saved=try Data(contentsOf:directory.appendingPathComponent("profile.relayvault"))
        let model=try model(directory:directory,preferences:preferences,key:key)
        model.assistant.draft="What did you personally do on your Fictional Northstar project?";model.assistant.submitDraft()
        do {
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running)
            XCTAssertTrue(model.profile.opened)
            XCTAssertEqual(model.snapshot.card?.points,["Your contribution: I implemented validation tests for Fictional Northstar."])
            XCTAssertEqual(key.calls.1,created);XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("profile.relayvault")),saved)
            XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
            model.lockMyContext();XCTAssertNil(model.snapshot.card)
            await model.contextUse.waitForQuiescence();XCTAssertFalse(model.profile.opened);XCTAssertFalse(preferences.useInSessions)
            model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.sendDraftAsNewQuestion()
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running)
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testMissingEnabledVaultPreservesIdleDraftWithoutKeyCreationOrNativeScope()async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-idle-missing-"+UUID().uuidString)
        let preferences=IdleContextPreference(),key=IdleContextKey();preferences.useInSessions=true
        let model=try model(directory:directory,preferences:preferences,key:key)
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        await model.assistant.waitForPreparationQuiescence()
        XCTAssertFalse(model.assistantActive);XCTAssertNil(model.currentSessionID);XCTAssertNil(model.snapshot.card)
        XCTAssertEqual(model.assistant.draft,"What is the difference between WHERE and HAVING?")
        XCTAssertEqual(model.contextUse.snapshot.status,.missing);XCTAssertEqual(key.calls.0,0);XCTAssertEqual(key.calls.1,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path));await model.stop()
    }
    func testExplicitLockAndEndJoinHeldActualIdleRestoreBeforeLateReadiness()async throws {
        for end in [false,true] {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-idle-held-context-"+UUID().uuidString)
            let preferences=IdleContextPreference(),key=IdleContextKey()
            try await seed(directory:directory,preferences:preferences,key:key)
            let receipt=IdleContextReceipt(hold:true),model=try model(directory:directory,preferences:preferences,key:key,receipt:receipt)
            model.assistant.draft="What did you personally do on your Fictional Northstar project?";model.assistant.submitDraft()
            do {
                try await waitUntil{receipt.entered}
                var ended=false
                let ending:Task<Void,Never>?
                if end{ending=Task{await model.stop();ended=true}}
                else{ending=nil;model.lockMyContext()}
                for _ in 0..<20{await Task.yield()}
                XCTAssertFalse(ended);XCTAssertTrue(model.assistant.snapshot.isPreparing)
                XCTAssertFalse(model.canStartSession);XCTAssertNil(model.currentSessionID);XCTAssertNil(model.snapshot.card)
                receipt.release();await ending?.value;await model.assistant.waitForPreparationQuiescence()
                await model.contextUse.waitForQuiescence()
                XCTAssertFalse(model.assistantActive);XCTAssertFalse(model.running);XCTAssertNil(model.currentSessionID)
                XCTAssertEqual(model.assistant.draft,"What did you personally do on your Fictional Northstar project?")
                await model.stop();try? FileManager.default.removeItem(at:directory)
            }catch{receipt.release();await model.stop();try? FileManager.default.removeItem(at:directory);throw error}
        }
    }
}
