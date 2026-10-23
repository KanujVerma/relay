import Foundation
import Combine
import XCTest
@testable import RelayProfile

@MainActor private final class UsePreferences:SessionContextUsePreferences {
    var useInSessions:Bool
    init(_ value:Bool=false){useInSessions=value}
}
private final class UseKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock()
    private var created=0,read=0
    func key(createIfMissing:Bool)throws->Data {
        lock.withLock{if createIfMissing{created+=1}else{read+=1}}
        return Data(repeating:87,count:32)
    }
    var calls:(creates:Int,reads:Int){lock.withLock{(created,read)}}
}
@MainActor private final class UseRig {
    let directory:URL
    let key=UseKey()
    let helper:PipeProfilePort
    let client:ProfileClient
    let controller:ProfileController
    let bindingID=UUID()
    var current=true
    init(root:URL,directory:URL)throws {
        self.directory=directory
        helper=PipeProfilePort(python:try ProfileTestEnvironment.python(),repository:root)
        client=ProfileClient(port:helper)
        controller=ProfileController(client:client,vault:ProfileVault(directory:directory,keys:key))
    }
    var target:ProfileUseTarget{ProfileUseTarget(controller:controller,bindingID:bindingID,isCurrent:{[weak self] in self?.current==true})}
}

@MainActor final class SessionContextUseTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func rig(directory:URL?=nil)throws->UseRig {
        let owned=directory==nil
        let directory=directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("relay-context-use-"+UUID().uuidString)
        let rig=try UseRig(root:root,directory:directory),helper=rig.helper
        addTeardownBlock{await helper.emergencyShutdown();if owned{try? FileManager.default.removeItem(at:directory)}}
        return rig
    }
    private func approveFictionalFact(_ controller:ProfileController)async throws {
        await controller.stageEnteredText("I implemented validation tests for Fictional Northstar.",purpose:"project",label:"Fictional project notes",role:"developer",project:"Fictional Northstar")
        let card=try XCTUnwrap(controller.card)
        await controller.review(card,actor:"self",claimKey:"fictional.northstar.tests",replaces:nil)
        XCTAssertEqual(controller.memoryCount,1);XCTAssertNil(controller.errorStatus)
    }
    func testDisabledConstructionAndRestoreDoNoProfileKeyOrHelperWork()async throws {
        let rig=try rig(),preferences=UsePreferences()
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        XCTAssertFalse(use.useInSessions);XCTAssertEqual(use.snapshot.status,.off)
        let result=await use.restoreBeforeSession(target:rig.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(result,.disabled);XCTAssertFalse(use.snapshot.isBusy)
        XCTAssertEqual(rig.key.calls.creates,0);XCTAssertEqual(rig.key.calls.reads,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
        let running=await rig.helper.isRunning;XCTAssertFalse(running)
    }
    func testRememberedUseCannotCreateMissingContextAndLockRemainsAnOptOut()async throws {
        let rig=try rig(),preferences=UsePreferences(true)
        var invalidations=0
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{invalidations+=1})
        let result=await use.restoreBeforeSession(target:rig.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(result,.missing);XCTAssertEqual(use.snapshot.status,.missing);XCTAssertTrue(use.useInSessions)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
        XCTAssertEqual(rig.key.calls.creates,0);XCTAssertEqual(rig.key.calls.reads,0)
        use.lockFromUserAction(target:rig.target)
        XCTAssertFalse(preferences.useInSessions);XCTAssertFalse(use.useInSessions);XCTAssertEqual(invalidations,1)
        await use.waitForQuiescence()
        let running=await rig.helper.isRunning;XCTAssertFalse(running)
    }
    func testInternalRetirementKeepsChoiceAndLoadsApprovedFactsIntoAFreshHelper()async throws {
        let first=try rig(),preferences=UsePreferences()
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        use.openFromUserAction(target:first.target)
        XCTAssertTrue(preferences.useInSessions);XCTAssertTrue(use.snapshot.isBusy)
        await use.waitForQuiescence();XCTAssertEqual(use.snapshot.status,.ready)
        try await approveFictionalFact(first.controller)
        let file=first.directory.appendingPathComponent("profile.relayvault"),before=try Data(contentsOf:file)
        use.retireForHelperChange()
        XCTAssertTrue(preferences.useInSessions);XCTAssertFalse(first.controller.opened)
        await use.waitForQuiescence()
        let oldRunning=await first.helper.isRunning;XCTAssertFalse(oldRunning)
        let fresh=try rig(directory:first.directory)
        let result=await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(result,.ready);XCTAssertTrue(fresh.controller.opened);XCTAssertEqual(fresh.controller.memoryCount,1)
        XCTAssertEqual(fresh.controller.memories.first?.sourceLabel,"Fictional project notes")
        XCTAssertEqual(fresh.key.calls.creates,0);XCTAssertEqual(fresh.key.calls.reads,1)
        XCTAssertEqual(try Data(contentsOf:file),before,"automatic restore must not replace the saved vault")
        let response=try await fresh.client.command(["command":"current_claim","claim_key":"fictional.northstar.tests"])
        XCTAssertEqual((response["fact"] as? [String:Any])?["actor"] as? String,"self")
        use.retireForHelperChange();await use.waitForQuiescence()
    }
    func testExplicitLockDisablesChoiceBeforeCloseAndOnlyExplicitOpenEnablesAgain()async throws {
        let first=try rig(),preferences=UsePreferences()
        var invalidations=0
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{invalidations+=1})
        use.openFromUserAction(target:first.target);await use.waitForQuiescence()
        try await approveFictionalFact(first.controller)
        use.lockFromUserAction(target:first.target)
        XCTAssertFalse(preferences.useInSessions);XCTAssertFalse(use.useInSessions)
        XCTAssertFalse(first.controller.opened);XCTAssertTrue(use.snapshot.isBusy);XCTAssertEqual(invalidations,1)
        await use.waitForQuiescence()
        let next=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        let fresh=try rig(directory:first.directory)
        let result=await next.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(result,.disabled);XCTAssertEqual(fresh.key.calls.reads,0)
        let running=await fresh.helper.isRunning;XCTAssertFalse(running)
        next.openFromUserAction(target:fresh.target)
        XCTAssertTrue(preferences.useInSessions)
        await next.waitForQuiescence()
        XCTAssertEqual(next.snapshot.status,.ready);XCTAssertEqual(fresh.controller.memoryCount,1)
        XCTAssertEqual(fresh.key.calls.creates,0)
        next.lockFromUserAction(target:fresh.target);await next.waitForQuiescence()
    }
    func testLockBeforeOpenTaskStartsDoesNotCreateAProfileOrHelper()async throws {
        let rig=try rig(),preferences=UsePreferences()
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        use.openFromUserAction(target:rig.target)
        use.lockFromUserAction(target:rig.target)
        XCTAssertFalse(preferences.useInSessions)
        await use.waitForQuiescence()
        XCTAssertEqual(use.snapshot.status,.off)
        XCTAssertEqual(rig.key.calls.creates,0);XCTAssertEqual(rig.key.calls.reads,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
        let running=await rig.helper.isRunning;XCTAssertFalse(running)
    }
    func testReadyObserverLockCannotReturnAReadyRestore()async throws {
        let seed=try rig();await seed.controller.openProfile();await seed.controller.close()
        let fresh=try rig(directory:seed.directory),preferences=UsePreferences(true)
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        var locked=false
        let observer=use.$snapshot.sink{snapshot in
            if snapshot.status == .ready && !locked{locked=true;use.lockFromUserAction(target:fresh.target)}
        }
        let result=await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertNotEqual(result,.ready,"Lock during ready delivery must invalidate the returned admission result")
        XCTAssertFalse(use.useInSessions)
        await use.waitForQuiescence();XCTAssertEqual(use.snapshot.status,.off)
        observer.cancel()
    }
    func testOpeningAnotherBindingWaitsForOldProviderRetirement()async throws {
        let first=try rig(),preferences=UsePreferences()
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        use.openFromUserAction(target:first.target);await use.waitForQuiescence()
        first.current=false
        let fresh=try rig(directory:first.directory)
        use.openFromUserAction(target:fresh.target)
        XCTAssertFalse(first.controller.opened,"a different helper cannot inherit the old loaded authority")
        await use.waitForQuiescence()
        let oldRunning=await first.helper.isRunning,newRunning=await fresh.helper.isRunning
        XCTAssertFalse(oldRunning);XCTAssertFalse(newRunning,"replacement must wait for old ownership to finish")
        use.openFromUserAction(target:fresh.target);await use.waitForQuiescence()
        XCTAssertEqual(use.snapshot.status,.ready);XCTAssertTrue(fresh.controller.opened)
        use.retireForHelperChange();await use.waitForQuiescence()
    }
}
