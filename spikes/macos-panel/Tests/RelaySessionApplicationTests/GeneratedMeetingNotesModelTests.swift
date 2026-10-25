import Foundation
import XCTest
import RelayAccount
import RelayProfile
import RelaySessionPanel
import RelayContextComposition
@testable import RelayPanelSession

@MainActor private final class NotesModelPreferences:HistorySavingPreferences{var savingEnabled=false}
private struct NotesModelKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:79,count:32)}}
@MainActor private final class NotesModelSwitch {
    var held=false,starts=0
    let root:URL,folder:URL,release:URL,log:URL
    init(_ root:URL,_ folder:URL){self.root=root;self.folder=folder;release=folder.appendingPathComponent("release");log=folder.appendingPathComponent("notes.jsonl")}
    func ingress(_ value:SessionIngress){if case .audio(let event)=value,event.kind == .sessionStarted{starts+=1}}
    func arguments(_ runtime:HelperRuntimeLocation,_ mode:HelperMode)->[String]{
        guard held else{return runtime.arguments}
        return [root.appendingPathComponent("tests/support/notes_backend_helper.py").path,"--synthetic-notes-test","--log",log.path,"--release",release.path,"--hold-response"]
    }
    func events()->[[String:String]]{((try? String(contentsOf:log,encoding:.utf8)) ?? "").split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:String]}}
}

@MainActor final class GeneratedMeetingNotesModelTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func until(_ predicate:()->Bool)async throws{
        let end=ContinuousClock.now+Duration.seconds(7)
        while !predicate(){guard ContinuousClock.now<end else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
    }
    private func fixture()async throws->(SessionApplicationModel,NotesModelSwitch){
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-model-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let switches=NotesModelSwitch(root,folder),key=NotesModelKey(),preferences=NotesModelPreferences()
        let storage=HistoryVaultStorage(directory:folder.appendingPathComponent("Relay/History"),keys:key)
        let ports=AccountApplicationPorts(storage:AccountStorage(sharedDirectory:folder.appendingPathComponent("Relay"),keys:key),preferences:FixtureChatGPTPlanPreferences(),
            control:{_,_ in XCTFail("Reference/fixture Notes must not open account control");throw AccountError.unavailable},openBrowser:{_ in XCTFail("No browser in synthetic Notes test");return false},sessionArguments:switches.arguments)
        let python=try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])
        let model=SessionApplicationModel(arguments:["Relay","--fixture-suite","analytics","--repository",root.path,"--python",python],ingressEnqueued:switches.ingress,historyPreferences:preferences,historyStorageFactory:{storage},accountPorts:ports)
        try await model.history.enableSaving();await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop();await model.history.waitForQuiescence()
        let saved=try XCTUnwrap(model.history.snapshot.records.first);try await model.openHistoryRecord(saved.id)
        addTeardownBlock{try? Data().write(to:switches.release);await model.shutdown();try? FileManager.default.removeItem(at:folder)}
        return(model,switches)
    }
    func testHeldNotesMustActuallyCloseBeforeNonOAuthReferenceStartAdmitsCapture()async throws{
        let(model,switches)=try await fixture();switches.held=true
        XCTAssertFalse(model.oauth);XCTAssertEqual(switches.starts,1)
        model.generatedMeetingNotes.generate(model.generatedMeetingNotes.snapshot,selection:.fullSavedTranscript)
        try await until{switches.events().contains{$0["event"]=="model_held"}}
        let start=Task{await model.start()}
        try await until{model.generatedMeetingNotes.snapshot.phase == .cancelling}
        XCTAssertEqual(switches.starts,1);XCTAssertFalse(model.running);XCTAssertTrue(model.generatedMeetingNotes.isBusy)
        try Data().write(to:switches.release);await start.value
        XCTAssertTrue(switches.events().contains{$0["event"]=="model_closed"})
        XCTAssertEqual(switches.starts,2);XCTAssertTrue(model.running)
        XCTAssertNil(model.generatedMeetingNotes.snapshot.document)
        try await until{model.snapshot.card != nil}
        XCTAssertEqual(switches.events().filter{$0["event"]=="model_post"}.count,1,"Only the retired Notes attempt; reviewed reference Start must not retry it")
        await model.stop()
    }

    func testActualModelOpensGeneratesRevealsCitationAndPrivacyFanoutClearsOwnedDraft()async throws{
        let(model,_)=try await fixture()
        let notes=model.generatedMeetingNotes
        XCTAssertNil(notes.snapshot.document)
        notes.generate(notes.snapshot,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        let document=try XCTUnwrap(notes.snapshot.document),citation=try XCTUnwrap(document.notes.summary.first?.citations.first)
        try await model.revealGeneratedMeetingNotesCitation(notes.snapshot,citation)
        XCTAssertEqual(model.historyCitationRowID,citation.rowID)
        XCTAssertTrue(model.generatedMeetingNotesDraft.stage(notes.snapshot))
        model.generatedMeetingNotesDraft.edit("Keep this explicit user wording until Lock.",group:0,index:0)
        XCTAssertTrue(model.generatedMeetingNotesDraft.snapshot.isDirty)
        model.history.lock();await model.history.waitForQuiescence();await notes.waitForQuiescence()
        XCTAssertNil(model.generatedMeetingNotesDraft.snapshot.target);XCTAssertNil(notes.snapshot.document)
        XCTAssertEqual(model.history.snapshot.phase,.locked)
    }
}
