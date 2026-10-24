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
private actor HeldUsePort:ProfilePort {
    let helper:PipeProfilePort
    let command:String
    private var response:Data?
    private var pending:CheckedContinuation<Data,any Error>?
    private var released=false
    private(set) var retired=false
    var waiting:Bool{pending != nil}
    init(helper:PipeProfilePort,command:String){self.helper=helper;self.command=command}
    func request(_ data:Data)async throws->Data {
        guard !retired else{throw ProfileError.unavailable}
        let message=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let result=try await helper.request(data)
        if message?["command"] as? String == command && !released {
            response=result
            return try await withCheckedThrowingContinuation{pending=$0}
        }
        return result
    }
    func release(){released=true;if let pending,let response{self.pending=nil;self.response=nil;pending.resume(returning:response)}}
    func close()async{await helper.close()}
    func emergencyShutdown()async{retired=true;await helper.emergencyShutdown()}
}
@MainActor private final class UseRig {
    let directory:URL
    let key=UseKey()
    let helper:PipeProfilePort
    let client:ProfileClient
    let controller:ProfileController
    let held:HeldUsePort?
    let bindingID=UUID()
    var current=true
    init(root:URL,directory:URL,holdCommand:String?=nil)throws {
        self.directory=directory
        let child=PipeProfilePort(python:try ProfileTestEnvironment.python(),repository:root)
        helper=child
        held=holdCommand.map{HeldUsePort(helper:child,command:$0)}
        if let held{client=ProfileClient(port:held)}else{client=ProfileClient(port:child)}
        controller=ProfileController(client:client,vault:ProfileVault(directory:directory,keys:key))
    }
    var target:ProfileUseTarget{ProfileUseTarget(controller:controller,bindingID:bindingID,isCurrent:{[weak self] in self?.current==true})}
}

@MainActor final class SessionContextUseTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func rig(directory:URL?=nil,holdCommand:String?=nil)throws->UseRig {
        let owned=directory==nil
        let directory=directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("relay-context-use-"+UUID().uuidString)
        let rig=try UseRig(root:root,directory:directory,holdCommand:holdCommand),helper=rig.helper,held=rig.held
        addTeardownBlock{await held?.release();await helper.emergencyShutdown();if owned{try? FileManager.default.removeItem(at:directory)}}
        return rig
    }
    private func waitUntil(_ condition:()async->Bool)async throws {
        for _ in 0..<2000{if await condition(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"actual synthetic context operation did not reach boundary",code:1)
    }
    private func savedContext()async throws->UseRig {
        let seed=try rig();await seed.controller.openProfile()
        try await approveFictionalFact(seed.controller);await seed.controller.close()
        return seed
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
    func testCancelledRestoreStaysBusyUntilTheActualLateDeliveryJoins()async throws {
        let seed=try await savedContext(),fresh=try rig(directory:seed.directory,holdCommand:"load_commit")
        let held=try XCTUnwrap(fresh.held),preferences=UsePreferences(true)
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        var finished=false
        let restoring=Task{let result=await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true});finished=true;return result}
        try await waitUntil{await held.waiting}
        restoring.cancel()
        try await waitUntil{let retired=await held.retired,running=await fresh.helper.isRunning;return retired && !running}
        XCTAssertTrue(use.isBusy);XCTAssertFalse(finished);XCTAssertFalse(fresh.controller.opened)
        let replacement=try rig(directory:seed.directory)
        let blocked=await use.restoreBeforeSession(target:replacement.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(blocked,.busy);XCTAssertEqual(replacement.key.calls.reads,0)
        await held.release();let old=await restoring.value
        XCTAssertEqual(old,.stale);await use.waitForQuiescence();XCTAssertTrue(preferences.useInSessions)
        let current=await use.restoreBeforeSession(target:replacement.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(current,.ready);XCTAssertEqual(replacement.controller.memoryCount,1)
        use.retireForHelperChange();await use.waitForQuiescence()
    }
    func testChangedNativeStartOrBindingRejectsAndClosesLateLoadedContext()async throws {
        let seed=try await savedContext()
        for changeBinding in [false,true] {
            let fresh=try rig(directory:seed.directory,holdCommand:"load_commit"),held=try XCTUnwrap(fresh.held)
            let preferences=UsePreferences(true),use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
            var startCurrent=true
            let restoring=Task{await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{startCurrent})}
            try await waitUntil{await held.waiting}
            if changeBinding{fresh.current=false}else{startCurrent=false}
            await held.release();let result=await restoring.value;await use.waitForQuiescence()
            XCTAssertEqual(result,.stale);XCTAssertFalse(fresh.controller.opened);XCTAssertTrue(preferences.useInSessions)
            let running=await fresh.helper.isRunning;XCTAssertFalse(running)
        }
    }
    func testExplicitLockDuringLoadStaysOffAndJoinsTheOriginalHelper()async throws {
        let seed=try await savedContext(),fresh=try rig(directory:seed.directory,holdCommand:"load_commit")
        let held=try XCTUnwrap(fresh.held),preferences=UsePreferences(true)
        var invalidations=0
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{invalidations+=1})
        let restoring=Task{await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true})}
        try await waitUntil{await held.waiting}
        let actions=ProfilePreparationActions(controller:fresh.controller,onLock:{use.lockFromUserAction(target:fresh.target)})
        XCTAssertTrue(actions.canLock(sessionUse:use.snapshot))
        actions.lock();actions.lock()
        XCTAssertFalse(preferences.useInSessions);XCTAssertFalse(fresh.controller.opened)
        XCTAssertTrue(use.isBusy);XCTAssertEqual(invalidations,1)
        try await waitUntil{let retired=await held.retired,running=await fresh.helper.isRunning;return retired && !running}
        XCTAssertTrue(use.isBusy,"actual late delivery must still join after the original child has retired")
        await held.release();let result=await restoring.value;await use.waitForQuiescence()
        XCTAssertEqual(result,.stale);XCTAssertEqual(use.snapshot.status,.off)
        let replacement=try rig(directory:seed.directory)
        let next=await use.restoreBeforeSession(target:replacement.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(next,.disabled);XCTAssertEqual(replacement.key.calls.reads,0)
        let running=await replacement.helper.isRunning;XCTAssertFalse(running)
    }
    func testCorruptExistingVaultRemainsUnchangedAndReportsFixedUnavailable()async throws {
        let seed=try await savedContext(),file=seed.directory.appendingPathComponent("profile.relayvault")
        let corrupt=Data("fictional-corrupt-payload-must-not-appear-in-status".utf8)
        try corrupt.write(to:file)
        let fresh=try rig(directory:seed.directory),preferences=UsePreferences(true)
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        let result=await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true})
        XCTAssertEqual(result,.unavailable);XCTAssertEqual(use.snapshot.status,.unavailable)
        XCTAssertEqual(try Data(contentsOf:file),corrupt);XCTAssertEqual(fresh.key.calls.creates,0)
        XCTAssertFalse(use.snapshot.message.contains("fictional-corrupt"));XCTAssertTrue(preferences.useInSessions)
        use.lockFromUserAction(target:fresh.target);await use.waitForQuiescence();XCTAssertFalse(use.useInSessions)
    }
    func testEachCoalescedCallerStillRequiresItsOwnNativeStartGuard()async throws {
        let seed=try await savedContext()
        for revokeAfterJoining in [false,true] {
            let fresh=try rig(directory:seed.directory,holdCommand:"load_commit"),held=try XCTUnwrap(fresh.held)
            let use=SessionContextUseCoordinator(preferences:UsePreferences(true),onInvalidate:{}),id=UUID()
            let first=Task{await use.restoreBeforeSession(target:fresh.target,startIntentID:id,isStartCurrent:{true})}
            try await waitUntil{await held.waiting}
            var callerCurrent=revokeAfterJoining
            let stale=Task{await use.restoreBeforeSession(target:fresh.target,startIntentID:id,isStartCurrent:{callerCurrent})}
            for _ in 0..<10{await Task.yield()}
            callerCurrent=false
            await held.release();let current=await first.value,invalid=await stale.value
            XCTAssertEqual(current,.ready);XCTAssertEqual(invalid,.stale)
            XCTAssertTrue(fresh.controller.opened);XCTAssertEqual(fresh.key.calls.reads,1)
            use.retireForHelperChange();await use.waitForQuiescence()
        }
    }
    func testObsoleteCoalescedCancellationCannotRetireAReplacementReadyUse()async throws {
        let seed=try await savedContext(),fresh=try rig(directory:seed.directory,holdCommand:"load_commit")
        let held=try XCTUnwrap(fresh.held),use=SessionContextUseCoordinator(preferences:UsePreferences(true),onInvalidate:{}),id=UUID()
        var oldWaiter:Task<SessionContextRestoreResult,Never>?
        var replacement:Task<SessionContextRestoreResult,Never>?
        var launched=false
        let observer=use.$snapshot.sink{snapshot in
            if snapshot.status == .ready && !launched {
                launched=true
                replacement=Task(priority:.high){await use.restoreBeforeSession(target:fresh.target,startIntentID:UUID(),isStartCurrent:{true})}
                oldWaiter?.cancel()
            }
        }
        let first=Task(priority:.high){await use.restoreBeforeSession(target:fresh.target,startIntentID:id,isStartCurrent:{true})}
        oldWaiter=Task(priority:.background){await use.restoreBeforeSession(target:fresh.target,startIntentID:id,isStartCurrent:{true})}
        try await waitUntil{await held.waiting};for _ in 0..<10{await Task.yield()}
        await held.release();_=await first.value;_=await oldWaiter?.value
        let current=await replacement?.value
        for _ in 0..<20{await Task.yield()}
        XCTAssertEqual(current,.ready);XCTAssertTrue(fresh.controller.opened);XCTAssertEqual(use.snapshot.status,.ready)
        observer.cancel()
        use.retireForHelperChange();await use.waitForQuiescence()
    }
    func testPreparationActionsUseTheRememberedOpenAndSynchronousLockPorts()async throws {
        let rig=try rig(),preferences=UsePreferences()
        let use=SessionContextUseCoordinator(preferences:preferences,onInvalidate:{})
        let actions=ProfilePreparationActions(controller:rig.controller,onOpen:{use.openFromUserAction(target:rig.target)},onLock:{use.lockFromUserAction(target:rig.target)})
        actions.open();XCTAssertTrue(preferences.useInSessions)
        await use.waitForQuiescence();XCTAssertTrue(rig.controller.opened)
        actions.lock()
        XCTAssertFalse(preferences.useInSessions);XCTAssertFalse(rig.controller.opened);XCTAssertTrue(use.isBusy)
        await use.waitForQuiescence()
        let running=await rig.helper.isRunning;XCTAssertFalse(running)
    }
    func testDefaultPreparationLockRetiresImmediatelyAndUnavailableUseCanBeLocked()async throws {
        let rig=try rig();await rig.controller.openProfile()
        let defaults=ProfilePreparationActions(controller:rig.controller)
        defaults.lock();XCTAssertFalse(rig.controller.opened);XCTAssertTrue(rig.controller.busy)
        await rig.controller.close()
        let missing=try self.rig(),use=SessionContextUseCoordinator(preferences:UsePreferences(true),onInvalidate:{})
        _=await use.restoreBeforeSession(target:missing.target,startIntentID:UUID(),isStartCurrent:{true})
        let actions=ProfilePreparationActions(controller:missing.controller,onLock:{use.lockFromUserAction(target:missing.target)})
        XCTAssertTrue(actions.canLock(sessionUse:use.snapshot),"enabled unavailable context must retain its opt-out")
        actions.lock();XCTAssertFalse(use.useInSessions)
        await use.waitForQuiescence()
    }
}
