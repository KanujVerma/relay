import AppKit
import Foundation
import SwiftUI
import XCTest
import RelayProfile
import RelayNativeSession
import RelayContextComposition
@testable import RelayPanelSession

@MainActor private final class AppContextPreferences:SessionContextUsePreferences {
    var useInSessions:Bool
    init(_ enabled:Bool=false){useInSessions=enabled}
}
private final class AppContextKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock()
    private var created=0,read=0
    func key(createIfMissing:Bool)throws->Data {
        lock.withLock{if createIfMissing{created+=1}else{read+=1}}
        return Data(repeating:81,count:32)
    }
    var calls:(creates:Int,reads:Int){lock.withLock{(created,read)}}
}
@MainActor private final class AppContextReceipts {
    weak var model:SessionApplicationModel?
    let holdCommand:String?
    private(set) var commands:[String]=[]
    private(set) var nativeStarts=0
    private(set) var factsAtStart:[[String]]=[]
    private var pending:CheckedContinuation<Void,Never>?
    private var released=false
    var waiting:Bool{pending != nil}
    init(holdCommand:String?=nil){self.holdCommand=holdCommand}
    func observe(_ data:Data)async {
        guard let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let command=object["command"] as? String else{return}
        commands.append(command)
        if command==holdCommand && !released{await withCheckedContinuation{pending=$0}}
    }
    func release(){released=true;pending?.resume();pending=nil}
    func ingress(_ value:SessionIngress){
        if case .audio(let event)=value,event.kind == .sessionStarted{
            nativeStarts+=1;factsAtStart.append(model?.profile.memories.map(\.claimText) ?? [])
        }
    }
}
@MainActor private struct AppContextRig {
    let model:SessionApplicationModel
    let directory:URL
    let preferences:AppContextPreferences
    let key:AppContextKey
    let receipts:AppContextReceipts
}
@MainActor final class SavedContextApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func rig(directory:URL?=nil,preferences:AppContextPreferences?=nil,holdCommand:String?=nil,fixture:Bool=true,fixtureSuite:String="coding",runtimeBundle:URL?=nil)throws->AppContextRig {
        let ownsDirectory=directory==nil
        let directory=directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("relay-app-context-"+UUID().uuidString,isDirectory:true)
        let preferences=preferences ?? AppContextPreferences(),key=AppContextKey(),receipts=AppContextReceipts(holdCommand:holdCommand)
        let python=ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"] ?? "/usr/bin/python3"
        var arguments=runtimeBundle == nil ? ["relay","--repository",root.path,"--python",python]:["Relay"]
        if fixture{arguments += ["--fixture-suite",fixtureSuite]}
        let model=SessionApplicationModel(arguments:arguments,
            ingressEnqueued:receipts.ingress,contextPreferences:preferences,
            profileVaultFactory:{ProfileVault(directory:directory,keys:key)},profileResponseObserved:receipts.observe,
            bundleURL:runtimeBundle ?? Bundle.main.bundleURL,workingDirectory:URL(fileURLWithPath:"/"))
        receipts.model=model
        addTeardownBlock{await receipts.release();await model.stop();if ownsDirectory{try? FileManager.default.removeItem(at:directory)}}
        return AppContextRig(model:model,directory:directory,preferences:preferences,key:key,receipts:receipts)
    }
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<2000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"actual saved-context app boundary was not reached",code:1)
    }
    private func approveFictionalFact(_ model:SessionApplicationModel)async throws {
        let profile=model.profile
        await profile.stageEnteredText("I implemented validation tests for Fictional Northstar.",purpose:"project",label:"Fictional project notes",role:model.role,project:"Fictional Northstar")
        let card=try XCTUnwrap(profile.card)
        await profile.review(card,actor:"self",claimKey:"fictional.northstar.tests",replaces:nil)
        XCTAssertEqual(profile.memoryCount,1);XCTAssertNil(profile.errorStatus)
    }
    private func seed()async throws->AppContextRig {
        let rig=try rig();rig.model.openMyContext();await rig.model.contextUse.waitForQuiescence()
        try await approveFictionalFact(rig.model);await rig.model.stop()
        return rig
    }
    func testWorkspaceAndOptedOutFixtureStartDoNotReadAProfileOrCreateAVault()async throws {
        let rig=try rig(),model=rig.model
        let view=NSHostingView(rootView:RelayMemoryWorkspace(model:model))
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(rig.preferences.useInSessions);XCTAssertTrue(rig.receipts.commands.isEmpty)
        XCTAssertEqual(rig.key.calls.creates,0);XCTAssertEqual(rig.key.calls.reads,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
        await model.start();try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(model.running);XCTAssertEqual(rig.receipts.nativeStarts,1)
        await model.stop()
        XCTAssertTrue(rig.receipts.commands.isEmpty,"closed idle workspace must not launch profile work merely to stop")
        XCTAssertEqual(rig.key.calls.creates,0);XCTAssertEqual(rig.key.calls.reads,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
    }
    func testExplicitOpenAndEndRestoreApprovedFactsIntoAFreshActualHelperBeforeNativeStart()async throws {
        let rig=try rig(),model=rig.model
        model.openMyContext();XCTAssertTrue(rig.preferences.useInSessions)
        await model.contextUse.waitForQuiescence();XCTAssertTrue(model.profile.opened)
        try await approveFictionalFact(model)
        let oldProfile=model.profile,oldHelper=try model.ensureHelper()
        let file=rig.directory.appendingPathComponent("profile.relayvault"),saved=try Data(contentsOf:file),created=rig.key.calls.creates
        await model.stop();XCTAssertTrue(rig.preferences.useInSessions);XCTAssertFalse(oldProfile.opened)
        await model.start();try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(model.running);XCTAssertFalse(model.profile === oldProfile)
        XCTAssertFalse(try model.ensureHelper() === oldHelper)
        XCTAssertEqual(model.profile.memories.first?.actor,"self")
        XCTAssertEqual(model.profile.memories.first?.sourceLabel,"Fictional project notes")
        XCTAssertEqual(rig.receipts.factsAtStart.last,["I implemented validation tests for Fictional Northstar."])
        XCTAssertEqual(try Data(contentsOf:file),saved);XCTAssertEqual(rig.key.calls.creates,created)
        XCTAssertTrue(rig.receipts.commands.contains("load_commit"))
        model.lockMyContext();XCTAssertFalse(rig.preferences.useInSessions);XCTAssertFalse(model.profile.opened)
        await model.contextUse.waitForQuiescence();await model.stop()
        let loads=rig.receipts.commands.filter{$0=="load_commit"}.count
        await model.start();XCTAssertTrue(model.running)
        XCTAssertEqual(rig.receipts.commands.filter{$0=="load_commit"}.count,loads)
    }
    func testMissingRememberedVaultAbortsBeforeNativeStartAndLockRecoversWithoutCreatingIt()async throws {
        let rig=try rig(preferences:AppContextPreferences(true)),model=rig.model
        await model.start()
        XCTAssertFalse(model.running);XCTAssertEqual(rig.receipts.nativeStarts,0)
        XCTAssertEqual(model.contextUse.snapshot.status,.missing);XCTAssertNotNil(model.error)
        XCTAssertTrue(rig.receipts.commands.isEmpty);XCTAssertEqual(rig.key.calls.creates,0);XCTAssertEqual(rig.key.calls.reads,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
        model.lockMyContext();XCTAssertFalse(rig.preferences.useInSessions)
        await model.contextUse.waitForQuiescence();await model.start()
        XCTAssertTrue(model.running);XCTAssertEqual(rig.receipts.nativeStarts,1)
        XCTAssertTrue(rig.receipts.commands.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.path))
    }
    func testExplicitLockDuringAnAcceptedLoadNeverAdmitsLateNativeStart()async throws {
        let seed=try await seed(),rig=try rig(directory:seed.directory,preferences:seed.preferences,holdCommand:"load_commit"),model=rig.model
        let starting=Task{await model.start()}
        try await waitUntil{rig.receipts.waiting}
        model.lockMyContext()
        XCTAssertFalse(rig.preferences.useInSessions);XCTAssertFalse(model.running)
        XCTAssertFalse(model.canStartSession);XCTAssertTrue(model.contextUse.isBusy)
        await model.start();XCTAssertEqual(rig.receipts.nativeStarts,0)
        rig.receipts.release();await starting.value;await model.contextUse.waitForQuiescence()
        XCTAssertFalse(model.running);XCTAssertNil(model.currentSessionID);XCTAssertEqual(rig.receipts.nativeStarts,0)
        XCTAssertFalse(rig.preferences.useInSessions)
        await model.start();XCTAssertTrue(model.running);XCTAssertEqual(rig.receipts.nativeStarts,1)
    }
    func testEndJoinsAHeldActualRestoreBeforeAFreshHelperCanStart()async throws {
        let seed=try await seed(),rig=try rig(directory:seed.directory,preferences:seed.preferences,holdCommand:"load_commit"),model=rig.model
        let starting=Task{await model.start()}
        try await waitUntil{rig.receipts.waiting}
        let oldProfile=model.profile,oldHelper=try model.ensureHelper()
        var ended=false
        let ending=Task{await model.stop();ended=true}
        try await waitUntil{model.stopping}
        for _ in 0..<10{await Task.yield()}
        XCTAssertFalse(ended);XCTAssertFalse(model.canStartSession)
        await model.start();XCTAssertEqual(rig.receipts.nativeStarts,0)
        XCTAssertTrue(rig.preferences.useInSessions)
        rig.receipts.release();await starting.value;await ending.value
        XCTAssertTrue(ended);XCTAssertFalse(oldProfile.opened);XCTAssertFalse(model.running)
        XCTAssertEqual(rig.receipts.nativeStarts,0)
        await model.start();XCTAssertTrue(model.running)
        XCTAssertFalse(try model.ensureHelper() === oldHelper)
        XCTAssertFalse(model.profile === oldProfile)
        XCTAssertEqual(model.profile.memoryCount,1);XCTAssertEqual(rig.receipts.nativeStarts,1)
    }
    func testPauseRetiresActualContextAndResumeReloadsThroughTheSameSharedHelper()async throws {
        let rig=try rig(),model=rig.model
        model.openMyContext();await model.contextUse.waitForQuiescence();try await approveFictionalFact(model)
        await model.start();try await waitUntil{model.snapshot.card != nil}
        let profile=model.profile,helper=try model.ensureHelper(),session=try XCTUnwrap(model.currentSessionID)
        try model.perform(.pause)
        XCTAssertFalse(model.running);XCTAssertFalse(profile.opened);XCTAssertTrue(rig.preferences.useInSessions)
        XCTAssertFalse(model.canResume)
        try await waitUntil{model.canResume}
        XCTAssertEqual(profile.closeOutcome,.locked)
        await model.start();XCTAssertTrue(model.running)
        XCTAssertTrue(try model.ensureHelper() === helper);XCTAssertTrue(model.profile === profile)
        XCTAssertNotEqual(model.currentSessionID,session);XCTAssertEqual(profile.memoryCount,1)
        XCTAssertEqual(rig.receipts.commands.filter{$0=="load_commit"}.count,1)
    }
    func testLocalAIModeRetirementPreservesPreferenceWithoutAnyAccountOrModelRequest()async throws {
        let rig=try rig(fixture:false),model=rig.model
        model.openMyContext();await model.contextUse.waitForQuiescence();try await approveFictionalFact(model)
        let oldProfile=model.profile,oldHelper=try model.ensureHelper(),created=rig.key.calls.creates
        // Only the existing local mode setting changes. No OAuth-mode helper
        // is launched: return to no-inference mode before explicitly reopening.
        await model.setAIEnabled(true)
        XCTAssertTrue(model.oauth);XCTAssertTrue(rig.preferences.useInSessions)
        XCTAssertFalse(oldProfile.opened);XCTAssertEqual(oldProfile.closeOutcome,.locked)
        XCTAssertFalse(model.running);XCTAssertEqual(rig.receipts.nativeStarts,0)
        await model.setAIEnabled(false);XCTAssertFalse(model.oauth)
        model.openMyContext();await model.contextUse.waitForQuiescence()
        XCTAssertTrue(model.profile.opened);XCTAssertEqual(model.profile.memoryCount,1)
        XCTAssertFalse(try model.ensureHelper() === oldHelper)
        XCTAssertEqual(rig.key.calls.creates,created);XCTAssertTrue(rig.preferences.useInSessions)
        XCTAssertEqual(rig.receipts.nativeStarts,0)
    }
    func testRestoredFactReachesTheActualPersonalAnswerAndLockRemovesItsSupport()async throws {
        let seed=try await seed(),rig=try rig(directory:seed.directory,preferences:seed.preferences,fixtureSuite:"personal-memory"),model=rig.model
        await model.start();try await waitUntil{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.question,"What did you personally do on your Fictional Northstar project?")
        XCTAssertEqual(model.snapshot.card?.points,["Your contribution: I implemented validation tests for Fictional Northstar."])
        model.lockMyContext();XCTAssertNil(model.snapshot.card)
        await model.contextUse.waitForQuiescence();await model.stop()
        await model.start()
        try await waitUntil{model.snapshot.question != nil && model.snapshot.status != "Thinking"}
        XCTAssertNil(model.snapshot.card,"a new question after explicit Lock must not reuse the former personal facts")
        XCTAssertFalse(rig.preferences.useInSessions)
    }
    func testOptInPackagedHelperRestoresApprovedContextAndAnswersWithoutDeveloperOverrides()async throws {
        guard let path=ProcessInfo.processInfo.environment["RELAY_CONTEXT_BUNDLED_RUNTIME_APP"] else{
            throw XCTSkip("Explicit packaged personal-context gate; synthetic vault/key only, no system Keychain or real profile.")
        }
        let bundle=URL(fileURLWithPath:path,isDirectory:true)
        let rig=try rig(fixtureSuite:"personal-memory",runtimeBundle:bundle),model=rig.model
        XCTAssertTrue(model.root.path.hasPrefix(bundle.path+"/"));XCTAssertNil(model.error)
        model.openMyContext();await model.contextUse.waitForQuiescence()
        try await approveFictionalFact(model)
        let created=rig.key.calls.creates,oldHelper=try model.ensureHelper()
        await model.stop();await model.start()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertFalse(try model.ensureHelper() === oldHelper)
        XCTAssertEqual(model.snapshot.card?.points,["Your contribution: I implemented validation tests for Fictional Northstar."])
        XCTAssertEqual(rig.key.calls.creates,created)
        model.lockMyContext();XCTAssertNil(model.snapshot.card)
        await model.contextUse.waitForQuiescence();await model.stop()
        await model.start();try await waitUntil{model.snapshot.question != nil && model.snapshot.status != "Thinking"}
        XCTAssertNil(model.snapshot.card);XCTAssertFalse(rig.preferences.useInSessions)
    }
}
