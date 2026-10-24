import Foundation
import XCTest
import RelayAccount
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

private final class BundledGuideKey:ProfileKeyProvider,@unchecked Sendable {
    private let lock=NSLock();private var count=0
    var calls:Int{lock.withLock{count}}
    func key(createIfMissing:Bool)throws->Data{lock.withLock{count+=1};return Data(repeating:97,count:32)}
}
@MainActor private final class BundledGuideReceipts:ResponsePreferencesReceiptStore {
    private var value:ResponsePreferencesReceipt
    init(rememberedMissing:Bool){value = .init(enabled:rememberedMissing,revision:rememberedMissing ? UUID():nil)}
    func read()->ResponsePreferencesReceipt{value}
    func commit(_ revision:UUID){value = .init(enabled:true,revision:revision)}
    func disable(){value = .init(enabled:false,revision:nil)}
}
@MainActor private final class BundledGuideContextPreferences:SessionContextUsePreferences{var useInSessions=false}
@MainActor private final class BundledGuideEffects {
    var launches=0,accountRequests=0,browserRequests=0,audioEvents=0
}

/// Requires an actual complete app. The Model receives neither a repository nor
/// a Python override, and its helper arguments are never replaced by a launcher.
@MainActor final class BundledResponsePreferencesTests:XCTestCase {
    private struct Rig {
        let model:SessionApplicationModel,directory:URL,guideKey:BundledGuideKey,otherKey:BundledGuideKey
        let effects:BundledGuideEffects
    }
    private func app()throws->URL {
        guard let path=ProcessInfo.processInfo.environment["RELAY_RESPONSE_PREFERENCES_BUNDLED_APP"] else{
            throw XCTSkip("Explicit actual bundled response-guide gate; fake keys and fixture inference only.")
        }
        let app=URL(fileURLWithPath:path,isDirectory:true)
        let location=try HelperRuntimeResolver.resolve(bundleURL:app,arguments:["Relay"],workingDirectory:URL(fileURLWithPath:"/"))
        XCTAssertTrue(location.executable.path.hasPrefix(app.path+"/Contents/Helpers/"))
        XCTAssertTrue(location.arguments.isEmpty)
        return app
    }
    private func rig(app:URL,fixture:Bool=false,rememberedMissing:Bool=false)throws->Rig {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-bundled-guide-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:directory)}
        let guideKey=BundledGuideKey(),otherKey=BundledGuideKey(),effects=BundledGuideEffects()
        let ports=AccountApplicationPorts(storage:AccountStorage(sharedDirectory:directory.appendingPathComponent("Relay"),keys:otherKey),preferences:FixtureChatGPTPlanPreferences(),
            control:{_,_ in effects.accountRequests+=1;throw AccountError.unavailable},
            openBrowser:{_ in effects.browserRequests+=1;return false},sessionArguments:{location,_ in
                effects.launches+=1
                XCTAssertTrue(location.executable.path.hasPrefix(app.path+"/Contents/Helpers/"))
                XCTAssertTrue(location.resourceRoot.path.hasPrefix(app.path+"/"));XCTAssertTrue(location.arguments.isEmpty)
                return location.arguments
            })
        var arguments=["Relay","--role","analytics"]
        if fixture{arguments += ["--fixture-suite","coding"]}
        let model=SessionApplicationModel(arguments:arguments,ingressEnqueued:{ingress in
            if case .audio=ingress{effects.audioEvents+=1}
        },contextPreferences:BundledGuideContextPreferences(),
            profileVaultFactory:{ProfileVault(directory:directory.appendingPathComponent("Relay"),keys:otherKey)},
            responsePreferencesStorage:ProtectedSnapshotVault(directory:directory.appendingPathComponent("Relay/ResponsePreferences"),purpose:.responsePreferences,keys:guideKey),
            responsePreferencesReceipts:BundledGuideReceipts(rememberedMissing:rememberedMissing),accountPorts:ports,
            bundleURL:app,workingDirectory:URL(fileURLWithPath:"/"))
        addTeardownBlock{await model.shutdown()}
        XCTAssertNil(model.error);XCTAssertTrue(model.root.path.hasPrefix(app.path+"/"))
        XCTAssertFalse(model.oauth);XCTAssertEqual(guideKey.calls,0);XCTAssertEqual(otherKey.calls,0)
        return Rig(model:model,directory:directory,guideKey:guideKey,otherKey:otherKey,effects:effects)
    }
    private func until(_ predicate:()->Bool)async throws {
        for _ in 0..<5000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"Actual bundled guide boundary was not reached",code:1)
    }
    private func assertNoAccountEffects(_ rig:Rig){
        XCTAssertEqual(rig.otherKey.calls,0);XCTAssertEqual(rig.effects.accountRequests,0);XCTAssertEqual(rig.effects.browserRequests,0)
    }
    func testOptInBundledGuideUsesActualMetadataThenGeneralAndFreshHelpKeepOriginalScopeUntilEnd()async throws {
        let app=try app(),rig=try rig(app:app,fixture:true),model=rig.model
        try await model.responsePreferences.useBuiltin(.coding)
        let original=try XCTUnwrap(model.responsePreferences.capture())
        XCTAssertGreaterThan(rig.guideKey.calls,0)
        let encrypted=try Data(contentsOf:rig.directory.appendingPathComponent("Relay/ResponsePreferences/preferences.relayvault"))
        XCTAssertNil(encrypted.range(of:Data(original.guidance.utf8)))
        await model.start();try await until{model.snapshot.card != nil || !model.running}
        XCTAssertTrue(model.running);XCTAssertNotNil(model.snapshot.card)
        guard model.running,model.snapshot.card != nil else{return}
        XCTAssertEqual(model.snapshot.responsePreferencesRevision,original.revision)
        XCTAssertEqual(model.usedResponseGuideName,"Coding discussion")
        let helper=try model.ensureHelper(),scope=try XCTUnwrap(model.currentSessionID)
        XCTAssertEqual(rig.effects.launches,1);XCTAssertGreaterThan(rig.effects.audioEvents,0)
        let question="Write a Python function to get the first item or None when a list is empty."
        model.assistant.draft=question;model.assistant.submitDraft()
        try await until{model.snapshot.question==question && model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.responsePreferencesRevision,original.revision)
        XCTAssertEqual(model.usedResponseGuideName,"Coding discussion")
        XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1)
        model.responsePreferences.useGeneral()
        XCTAssertNil(model.snapshot.card);XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertNil(model.usedResponseGuideName);XCTAssertEqual(model.responseGuideName,"General")
        let replacement=model.snapshot.replacement
        model.assistant.requestCurrentQuestionHelp()
        try await until{model.snapshot.replacement>replacement && model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.question,question);XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertNil(model.usedResponseGuideName);XCTAssertEqual(model.currentSessionID,scope)
        XCTAssertTrue(try model.ensureHelper() === helper);XCTAssertEqual(rig.effects.launches,1)
        XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1)
        await model.stop()
        XCTAssertTrue(helper.hasExited);XCTAssertNil(model.currentSessionID);XCTAssertNil(model.snapshot.card)
        XCTAssertFalse(model.running);XCTAssertFalse(model.stopping);assertNoAccountEffects(rig)
    }
    func testOptInNormalBundledGeneralReferenceNeedsNoGuideKeyRecordingOrDeveloperRuntime()async throws {
        let app=try app(),rig=try rig(app:app),model=rig.model
        let question="What is the difference between WHERE and HAVING?"
        model.assistant.draft=question;model.assistant.submitDraft()
        try await until{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.question,question);XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertNil(model.usedResponseGuideName);XCTAssertEqual(model.responseGuideName,"General")
        XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running);XCTAssertFalse(model.authorizedConversation)
        XCTAssertEqual(rig.effects.audioEvents,0);XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
        XCTAssertEqual(model.speechSetup.snapshot.stage,.notPrepared)
        XCTAssertEqual(rig.guideKey.calls,0);XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.appendingPathComponent("Relay").path))
        let helper=try model.ensureHelper();await model.stop();XCTAssertTrue(helper.hasExited)
        assertNoAccountEffects(rig)
    }
    func testOptInMissingRememberedGuideWithholdsBeforeBundledHelperAndGeneralRecoversPreservedDraft()async throws {
        let app=try app(),rig=try rig(app:app,rememberedMissing:true),model=rig.model
        let question="What is the difference between WHERE and HAVING?"
        model.assistant.draft=question;model.assistant.submitDraft();await model.assistant.waitForPreparationQuiescence()
        XCTAssertNil(model.currentSessionID);XCTAssertFalse(model.assistantActive)
        XCTAssertEqual(model.assistant.draft,question);XCTAssertNil(model.snapshot.card)
        XCTAssertEqual(model.responsePreferences.snapshot.stage,.unavailable)
        XCTAssertEqual(rig.effects.launches,0);XCTAssertEqual(rig.guideKey.calls,0)
        XCTAssertFalse(FileManager.default.fileExists(atPath:rig.directory.appendingPathComponent("Relay").path))
        model.responsePreferences.useGeneral();model.assistant.submitDraft()
        try await until{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.question,question);XCTAssertNil(model.snapshot.responsePreferencesRevision)
        XCTAssertNil(model.usedResponseGuideName);XCTAssertEqual(rig.effects.launches,1)
        XCTAssertEqual(rig.effects.audioEvents,0);XCTAssertEqual(rig.guideKey.calls,0)
        let helper=try model.ensureHelper();await model.stop();XCTAssertTrue(helper.hasExited)
        assertNoAccountEffects(rig)
    }
}
