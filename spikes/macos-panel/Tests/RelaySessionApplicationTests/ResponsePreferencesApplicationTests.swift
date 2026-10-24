import Foundation
import XCTest
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

private final class ApplicationPreferenceStorage:ProtectedSnapshotStorage,@unchecked Sendable {
    private let condition=NSCondition();private var bytes:Data?,calls=[0,0,0],held=false,waiting=false
    init(_ bytes:Data?=nil){self.bytes=bytes}
    var counts:[Int]{condition.lock();defer{condition.unlock()};return calls}
    var entered:Bool{condition.lock();defer{condition.unlock()};return waiting}
    func holdLoad(){condition.lock();held=true;waiting=false;condition.unlock()}
    func release(){condition.lock();held=false;condition.broadcast();condition.unlock()}
    func exists()throws->Bool{condition.lock();defer{condition.unlock()};calls[0]+=1;return bytes != nil}
    func load()throws->Data{
        condition.lock();defer{condition.unlock()};calls[1]+=1
        if held{waiting=true;while held{condition.wait()};waiting=false}
        guard let bytes else{throw ProfileError.unavailable};return bytes
    }
    func save(_ payload:Data,createKey:Bool)throws{condition.lock();defer{condition.unlock()};calls[2]+=1;bytes=payload}
}
@MainActor private final class ApplicationPreferenceReceipts:ResponsePreferencesReceiptStore {
    var value:ResponsePreferencesReceipt;var reads=0
    init(_ value:ResponsePreferencesReceipt = .init(enabled:false,revision:nil)){self.value=value}
    func read()->ResponsePreferencesReceipt{reads+=1;return value}
    func commit(_ revision:UUID){value = .init(enabled:true,revision:revision)}
    func disable(){value = .init(enabled:false,revision:nil)}
}
@MainActor private final class ApplicationContextPreferences:SessionContextUsePreferences{var useInSessions=false}
@MainActor final class ResponsePreferencesApplicationTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func args(_ role:String="developer")throws->[String]{["Relay","--repository",root.path,"--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]),"--role",role]}
    private func waitUntil(_ predicate:()->Bool)async throws{
        for _ in 0..<2500{if predicate(){return};try await Task.sleep(for:.milliseconds(2))}
        throw NSError(domain:"actual preference app boundary not reached",code:1)
    }
    private func quoted(_ value:String)->String{"'"+value.replacingOccurrences(of:"'",with:"'\\''")+"'"}
    private func generatedRig()throws->(SessionApplicationModel,URL){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-response-app-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let launcher=directory.appendingPathComponent("helper"),log=directory.appendingPathComponent("requests.jsonl"),release=directory.appendingPathComponent("release")
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let script="#!/bin/sh\nexec \(quoted(python)) \(quoted(root.appendingPathComponent("tests/support/idle_backend_helper.py").path)) --synthetic-idle-test --hold none --log \(quoted(log.path)) --release \(quoted(release.path)) \"$@\"\n"
        try Data(script.utf8).write(to:launcher);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
        let model=SessionApplicationModel(arguments:["Relay","--repository",root.path,"--python",launcher.path,"--role","developer","--oauth"],contextPreferences:ApplicationContextPreferences(),responsePreferencesStorage:ApplicationPreferenceStorage(),responsePreferencesReceipts:ApplicationPreferenceReceipts())
        addTeardownBlock{try? Data().write(to:release);await model.stop();try? FileManager.default.removeItem(at:directory)}
        return(model,log)
    }
    private func posts(_ log:URL)->Int{
        ((try? String(contentsOf:log,encoding:.utf8)) ?? "").split(separator:"\n").filter{line in
            (try? JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:String])?["kind"]=="text_post"
        }.count
    }
    func testActualGeneratedGuideChangeWithholdsOldCardAndHelpUsesFreshGuideWithoutLosingDraft()async throws {
        let (model,log)=try generatedRig()
        try await model.responsePreferences.useBuiltin(.coding)
        let old=try XCTUnwrap(model.responsePreferences.capture())
        model.assistant.draft="Explain event loops.";model.assistant.submitDraft()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.responsePreferencesRevision,old.revision)
        XCTAssertFalse(model.running);XCTAssertTrue(model.assistantActive);XCTAssertFalse(model.authorizedConversation)
        let scope=model.currentSessionID,helper=try model.ensureHelper()
        model.assistant.draft="Newer unsent draft remains here."
        try await model.responsePreferences.useBuiltin(.feature)
        XCTAssertNil(model.snapshot.card);XCTAssertEqual(model.snapshot.status,"Response guide changed. Ask again.")
        XCTAssertEqual(model.snapshot.question,"Explain event loops.");XCTAssertEqual(model.currentSessionID,scope)
        XCTAssertTrue(model.assistant.snapshot.canHelpCurrent);XCTAssertEqual(posts(log),1)
        model.assistant.requestCurrentQuestionHelp()
        try await waitUntil{model.snapshot.card != nil}
        XCTAssertEqual(model.snapshot.responsePreferencesRevision,try XCTUnwrap(model.responsePreferences.capture()).revision)
        XCTAssertNotEqual(model.snapshot.responsePreferencesRevision,old.revision)
        XCTAssertEqual(model.assistant.draft,"Newer unsent draft remains here.")
        XCTAssertTrue(try model.ensureHelper() === helper);XCTAssertEqual(posts(log),2)
        XCTAssertTrue(model.assistant.transcript.snapshot.rows.isEmpty)
        await model.stop()
    }
    func testDefaultModelTypingAndPresentationNeverReadOrCreatePreferenceStorage()async throws {
        let store=ApplicationPreferenceStorage(),receipts=ApplicationPreferenceReceipts()
        let model=SessionApplicationModel(arguments:try args(),contextPreferences:ApplicationContextPreferences(),responsePreferencesStorage:store,responsePreferencesReceipts:receipts)
        model.assistant.draft="Unsent public question."
        _=model.relayPresentation;_=model.responsePreferences.snapshot
        XCTAssertEqual(store.counts,[0,0,0]);XCTAssertEqual(receipts.reads,0)
        XCTAssertFalse(model.running);XCTAssertFalse(model.assistantActive);XCTAssertNil(model.currentSessionID)
        await model.stop();XCTAssertEqual(store.counts,[0,0,0]);XCTAssertEqual(model.assistant.draft,"Unsent public question.")
    }
    func testActualIdleReferenceSurvivesGuideChangeWithSameHelperAndNoRecording()async throws {
        let store=ApplicationPreferenceStorage(),receipts=ApplicationPreferenceReceipts()
        var audio=0
        let model=SessionApplicationModel(arguments:try args("analytics"),ingressEnqueued:{_ in audio+=1},contextPreferences:ApplicationContextPreferences(),responsePreferencesStorage:store,responsePreferencesReceipts:receipts)
        try await model.responsePreferences.useBuiltin(.coding)
        model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        do{
            try await waitUntil{model.snapshot.card != nil}
            let card=model.snapshot.card,session=model.currentSessionID,helper=try model.ensureHelper()
            XCTAssertNil(model.snapshot.responsePreferencesRevision);XCTAssertTrue(model.assistantActive)
            XCTAssertFalse(model.running);XCTAssertFalse(model.authorizedConversation);XCTAssertEqual(audio,0)
            model.assistant.draft="Newer unsent public question."
            try await model.responsePreferences.useBuiltin(.feature)
            XCTAssertEqual(model.snapshot.card,card);XCTAssertEqual(model.currentSessionID,session)
            XCTAssertTrue(try model.ensureHelper() === helper);XCTAssertTrue(model.assistant.snapshot.canHelpCurrent)
            XCTAssertEqual(model.assistant.draft,"Newer unsent public question.")
            await model.stop()
        }catch{await model.stop();throw error}
    }
    func testHeldRememberedGuidePreparationJoinsBeforeStopAndKeepsNewDraftWithoutScope()async throws {
        let catalog=try ResponsePreferencesCatalog(selected:"coding"),store=ApplicationPreferenceStorage(try catalog.encoded())
        let receipts=ApplicationPreferenceReceipts(.init(enabled:true,revision:catalog.revision))
        let model=SessionApplicationModel(arguments:try args(),contextPreferences:ApplicationContextPreferences(),responsePreferencesStorage:store,responsePreferencesReceipts:receipts)
        store.holdLoad();defer{store.release()}
        model.assistant.draft="Original public question.";model.assistant.sendDraftAsNewQuestion()
        try await waitUntil{store.entered}
        XCTAssertNil(model.currentSessionID);XCTAssertFalse(model.assistantActive);XCTAssertFalse(model.running)
        model.assistant.draft="Newer draft while the real preference call is held."
        var stopped=false
        let stopping=Task{await model.stop();stopped=true}
        try await waitUntil{model.stopping}
        XCTAssertFalse(stopped);XCTAssertTrue(model.responsePreferences.snapshot.isBusy);XCTAssertFalse(model.canStartSession)
        store.release();await stopping.value
        XCTAssertTrue(stopped);XCTAssertFalse(model.responsePreferences.snapshot.isBusy)
        XCTAssertFalse(model.assistantActive);XCTAssertNil(model.currentSessionID)
        XCTAssertEqual(model.assistant.draft,"Newer draft while the real preference call is held.")
    }
}
