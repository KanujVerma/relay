import Foundation
import XCTest
import RelayProfile
import RelaySessionPanel
import RelayControls
import RelayContextComposition
import RelayNativeSession
@testable import RelaySessionCapture
@testable import RelayPanelSession

@MainActor private final class IdlePreferences:SessionContextUsePreferences{var useInSessions=false}
private actor IdleSpeechCalls{
    private(set) var count=0
    func prepare()throws->PreparedSpeechAssets{count+=1;throw SpeechSetupError.offline}
}
@MainActor private final class IdleAccountGate {
    var entered=false,finished=false
    private var waiter:CheckedContinuation<Void,Never>?
    func prepare()async{entered=true;await withCheckedContinuation{waiter=$0};finished=true}
    func release(){waiter?.resume();waiter=nil}
}

@MainActor final class IdleAssistantApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func arguments(fixture:Bool=false)throws->[String]{
        var value=["Relay","--repository",root.path,"--role","analytics","--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])]
        if fixture{value += ["--fixture-suite","coding"]};return value
    }
    private func waitUntil(_ predicate:()->Bool)async throws {
        for _ in 0..<2000{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"idle assistant boundary was not reached",code:1)
    }
    private func kinds(_ log:URL)->[String]{
        ((try? String(contentsOf:log,encoding:.utf8)) ?? "").split(separator:"\n").compactMap{
            (try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:String])?["kind"]
        }
    }
    private func shellQuote(_ value:String)->String{"'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"}
    private func heldRig(_ hold:String)throws->(SessionApplicationModel,URL,URL,URL){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-idle-app-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let launcher=directory.appendingPathComponent("helper"),log=directory.appendingPathComponent("events.jsonl"),release=directory.appendingPathComponent("release")
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let script="#!/bin/sh\nexec \(shellQuote(python)) \(shellQuote(root.appendingPathComponent("tests/support/idle_backend_helper.py").path)) --synthetic-idle-test --hold \(hold) --log \(shellQuote(log.path)) --release \(shellQuote(release.path)) \"$@\"\n"
        try Data(script.utf8).write(to:launcher);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let model=SessionApplicationModel(arguments:["Relay","--repository",root.path,"--python",launcher.path,"--role","analytics"],contextPreferences:IdlePreferences())
        addTeardownBlock{try? Data().write(to:release);await model.stop();try? FileManager.default.removeItem(at:directory)}
        return(model,directory,log,release)
    }
    func testActualWorkerCloseBlocksAudioAndNewScopeUntilItsRealCleanupReturns()async throws {
        let (model,_,log,release)=try heldRig("worker")
        model.assistant.draft="Explain event loops.";model.assistant.submitDraft()
        try await waitUntil{kinds(log).contains("worker_entered")}
        let oldHelper=try model.ensureHelper()
        try model.perform(.pause)
        XCTAssertFalse(model.assistantActive);XCTAssertTrue(model.stopping);XCTAssertFalse(model.canStartSession)
        model.assistant.draft="Newer unsent question.";model.assistant.sendDraftAsNewQuestion()
        for _ in 0..<10{await Task.yield()}
        XCTAssertTrue(model.stopping);XCTAssertNil(model.snapshot.card)
        XCTAssertFalse(kinds(log).contains("worker_finished"));XCTAssertEqual(model.assistant.draft,"Newer unsent question.")
        try Data().write(to:release);try await waitUntil{!model.stopping}
        XCTAssertTrue(kinds(log).contains("worker_finished"));XCTAssertNil(model.snapshot.card)
        XCTAssertTrue(try model.ensureHelper() === oldHelper)
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.sendDraftAsNewQuestion()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running)
        XCTAssertEqual(kinds(log).filter{$0=="text_post"}.count,1)
    }
    func testLateOpenReceiptAfterEndCannotIssueOrCloseTheNextOwner()async throws {
        let (model,_,log,release)=try heldRig("open")
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        try await waitUntil{kinds(log).contains("open_ready")}
        var ended=false
        let ending=Task{await model.stop();ended=true}
        try await waitUntil{model.stopping}
        for _ in 0..<20{await Task.yield()}
        XCTAssertFalse(ended);XCTAssertTrue(model.assistant.snapshot.isPreparing)
        XCTAssertNil(model.snapshot.card);XCTAssertFalse(model.canStartSession)
        try Data().write(to:release);await ending.value
        XCTAssertTrue(ended);XCTAssertFalse(model.assistantActive);XCTAssertTrue(kinds(log).filter{$0=="text_post"}.isEmpty)
        XCTAssertNil(model.error,"A joined already-closed original must not be closed or reaped twice")
        XCTAssertEqual(model.assistant.draft,"What is the difference between WHERE and HAVING?")
        try FileManager.default.removeItem(at:log);try FileManager.default.removeItem(at:release)
        model.assistant.submitDraft();try await waitUntil{kinds(log).contains("open_ready")}
        try Data().write(to:release);try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(model.assistantActive);XCTAssertNil(model.error)
    }
    func testUnconnectedAIEnableCannotMutateOrRetireTheHeldIdleRequest()async throws {
        let (model,_,log,release)=try heldRig("token")
        model.assistant.draft="Explain event loops.";model.assistant.submitDraft()
        try await waitUntil{kinds(log).contains("token_entered")}
        let original=try model.ensureHelper(),session=try XCTUnwrap(model.currentSessionID)
        await model.setAIEnabled(true)
        XCTAssertFalse(model.oauth);XCTAssertNil(model.account.inferenceSelection)
        XCTAssertFalse(model.stopping);XCTAssertTrue(model.assistantActive)
        XCTAssertFalse(kinds(log).contains("token_finished"));XCTAssertFalse(original.hasExited)
        XCTAssertEqual(model.currentSessionID,session)
        try Data().write(to:release);try await waitUntil{model.snapshot.card != nil}
        XCTAssertEqual(kinds(log).filter{$0=="text_post"}.count,1)
        XCTAssertTrue(try model.ensureHelper() === original);XCTAssertFalse(model.oauth)
    }
    func testActualReusedHelperEOFClearsTheCurrentAppCardAndAllowsFreshIdleOwner()async throws {
        let (model,_,log,release)=try heldRig("eof")
        let question="What is the difference between WHERE and HAVING?"
        model.assistant.draft=question;model.assistant.submitDraft()
        try await waitUntil{model.snapshot.card != nil}
        let oldHelper=try model.ensureHelper()
        try model.perform(.pause);try await waitUntil{!model.stopping}
        model.assistant.draft=question;model.assistant.sendDraftAsNewQuestion()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertTrue(try model.ensureHelper() === oldHelper)
        try Data().write(to:release)
        try await waitUntil{!model.assistantActive && !model.stopping}
        XCTAssertTrue(kinds(log).contains("child_exit"));XCTAssertNil(model.snapshot.card)
        XCTAssertNil(model.currentSessionID);XCTAssertNotNil(model.error)
        try FileManager.default.removeItem(at:log);try FileManager.default.removeItem(at:release)
        model.assistant.draft=question;model.assistant.sendDraftAsNewQuestion()
        try await waitUntil{model.assistantActive && model.snapshot.card != nil}
        XCTAssertTrue(model.assistantActive);XCTAssertFalse(try model.ensureHelper() === oldHelper)
        XCTAssertNil(model.error)
    }
    func testCapturePauseToIdleAskAndBackUsesOneChildAndDropsActualOldSourceCallback()async throws {
        var originalStopped:NativeSessionEvent?
        let model=SessionApplicationModel(arguments:try arguments(fixture:true),ingressEnqueued:{ingress in
            if case .audio(let event)=ingress,event.kind == .stopped{originalStopped=event}
        },contextPreferences:IdlePreferences())
        await model.start()
        do {
            try await waitUntil{model.snapshot.card != nil}
            let helper=try model.ensureHelper(),audioSession=try XCTUnwrap(model.currentSessionID)
            try model.perform(.pause);try await waitUntil{!model.stopping}
            model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running);XCTAssertNotEqual(model.currentSessionID,audioSession)
            XCTAssertTrue(try model.ensureHelper() === helper);XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
            let replacement=model.snapshot.replacement
            model.receive(.audio(try XCTUnwrap(originalStopped)))
            XCTAssertTrue(model.assistantActive);XCTAssertEqual(model.snapshot.replacement,replacement)
            await model.start();try await waitUntil{model.running && model.snapshot.card != nil}
            XCTAssertFalse(model.assistantActive);XCTAssertTrue(try model.ensureHelper() === helper)
            XCTAssertEqual(model.assistant.transcript.snapshot.rows.count,1)
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testActualSourceFailureJoinsAudioBeforeIdleTypedAdmission()async throws {
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","source-failure","--repository",root.path,
            "--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])],contextPreferences:IdlePreferences())
        await model.start();try await waitUntil{!model.running && !model.stopping}
        XCTAssertNil(model.currentSessionID)
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        do {
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running);XCTAssertNil(model.error)
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testActualLastMicrophoneFailureJoinsAudioBeforeIdleTypedAdmission()async throws {
        var unavailable:NativeSessionEvent?
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","microphone-source-failure","--repository",root.path,
            "--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])],ingressEnqueued:{ingress in
                if case .audio(let event)=ingress,event.kind == .sourceUnavailable{unavailable=event}
            },contextPreferences:IdlePreferences())
        await model.start()
        do {
            try await waitUntil{unavailable != nil}
            XCTAssertEqual(unavailable?.sourceCode,1)
            try await waitUntil{!model.running && !model.stopping}
            model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running)
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testIdleReferenceAndHelpNeedNoSpeechAudioSourceOrRecordingConsent()async throws {
        let speech=IdleSpeechCalls(),setup=SpeechSetupCoordinator(prepare:{_ in try await speech.prepare()})
        var audioEvents=0
        let model=SessionApplicationModel(arguments:try arguments(),ingressEnqueued:{_ in audioEvents+=1},
            speechSetup:setup,contextPreferences:IdlePreferences())
        XCTAssertFalse(model.authorizedConversation);XCTAssertFalse(model.running);XCTAssertFalse(model.assistantActive)
        model.microphoneEnabled=false;model.selectedBundleID=""
        model.assistant.draft="What is the difference between WHERE and HAVING?"
        XCTAssertTrue(model.assistant.snapshot.canSend)
        model.assistant.submitDraft();model.assistant.submitDraft()
        do {
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.running)
            XCTAssertEqual(model.snapshot.question,"What is the difference between WHERE and HAVING?")
            XCTAssertFalse(model.authorizedConversation);XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
            XCTAssertEqual(audioEvents,0);let count=await speech.count;XCTAssertEqual(count,0)
            let replacement=model.snapshot.replacement
            try model.perform(.requestHelp)
            try await waitUntil{model.snapshot.replacement>replacement && model.snapshot.card != nil}
            XCTAssertNil(model.error);XCTAssertFalse(model.running)
            await model.stop()
            XCTAssertFalse(model.assistantActive);XCTAssertNil(model.currentSessionID)
        }catch{await model.stop();throw error}
    }
    func testIdleFixtureModelAndPersonalMissingUseActualHelperWithoutAudio()async throws {
        let model=SessionApplicationModel(arguments:try arguments(fixture:true),contextPreferences:IdlePreferences())
        model.assistant.draft="What did you personally do on your Atlas project?";model.assistant.submitDraft()
        do {
            try await waitUntil{model.snapshot.question=="What did you personally do on your Atlas project?" && model.snapshot.status != "Thinking" && model.assistantActive && !model.assistant.snapshot.isPreparing}
            XCTAssertNil(model.snapshot.card);XCTAssertFalse(model.running)
            model.assistant.draft="Write a Python function that returns the first item or None for an empty list."
            model.assistant.sendDraftAsNewQuestion()
            try await waitUntil{model.snapshot.card != nil}
            XCTAssertNotNil(model.snapshot.card?.detail);XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testAudioStartJoinsIdleScopeThenChecksConsentBeforeAnySpeechPreparation()async throws {
        let speech=IdleSpeechCalls(),setup=SpeechSetupCoordinator(prepare:{_ in try await speech.prepare()})
        let model=SessionApplicationModel(arguments:try arguments(),speechSetup:setup,contextPreferences:IdlePreferences())
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        do {
            try await waitUntil{model.snapshot.card != nil}
            let helper=try model.ensureHelper()
            XCTAssertTrue(model.canStartSession)
            await model.start()
            XCTAssertFalse(model.assistantActive);XCTAssertFalse(model.running)
            XCTAssertNil(model.currentSessionID);XCTAssertNotNil(model.error)
            let count=await speech.count;XCTAssertEqual(count,0)
            XCTAssertTrue(try model.ensureHelper() === helper)
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testEndJoinsHeldExplicitAccountPreparationAndPreservesNewerDraft()async throws {
        let gate=IdleAccountGate()
        let model=SessionApplicationModel(arguments:try arguments(),contextPreferences:IdlePreferences(),
            explicitAccountPreparation:{_,_ in await gate.prepare()})
        model.assistant.draft="Original question.";model.assistant.submitDraft()
        try await waitUntil{gate.entered}
        model.assistant.draft="Newer question."
        var ended=false
        let ending=Task{await model.stop();ended=true}
        try await waitUntil{model.stopping}
        XCTAssertFalse(ended);XCTAssertFalse(model.canStartSession)
        XCTAssertTrue(model.assistant.snapshot.isPreparing);XCTAssertFalse(gate.finished)
        gate.release();await ending.value
        XCTAssertTrue(ended);XCTAssertTrue(gate.finished);XCTAssertEqual(model.assistant.draft,"Newer question.")
        XCTAssertFalse(model.assistantActive);XCTAssertFalse(model.running);XCTAssertNil(model.currentSessionID)
        XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
    }
}
