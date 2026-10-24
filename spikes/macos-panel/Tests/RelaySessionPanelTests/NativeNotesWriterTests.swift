import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

@MainActor private final class NotesSessionPreferences:HistorySavingPreferences {var savingEnabled=false}
@MainActor private final class NotesSessionBox {weak var controller:NativeNotesSessionController?}
private struct NotesSessionKey:ProfileKeyProvider {func key(createIfMissing:Bool)throws->Data{Data(repeating:67,count:32)}}

@MainActor final class NativeNotesWriterTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func fixture(rows:Int=2,controls:Bool=false,pythonArguments:[String]=[])async throws->(SessionHistoryCoordinator,HistoryNotesSource,HelperTransport,NotesSessionBox){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-session-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let storage=HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:NotesSessionKey())
        let clock:@Sendable ()->Date={Date(timeIntervalSince1970:1_800_000_000)}
        let store=HistoryStore(storage:storage,clock:clock);try store.open(create:true);let record=try store.createRecord()
        let transcript=SessionTranscriptStore();var originals:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={originals.append($0)};var events=HistoryTestEvents();events.start(transcript)
        for index in 1...rows{events.final(UInt64(index),text:controls ? String(repeating:"\u{1}",count:256):"Fictional original row \(index).",source:index.isMultiple(of:2) ? 1:2,into:transcript)}
        events.stop(into:transcript)
        for original in originals{try store.append(original,to:record.id)}
        try store.finish(record.id,outcome:.completed);try store.close()
        let history=SessionHistoryCoordinator(storageFactory:{storage},preferences:NotesSessionPreferences(),canEnable:{true},clock:clock)
        try await history.openExisting();try await history.openRecord(record.id)
        let revision=try XCTUnwrap(history.snapshot.selected?.record.revision)
        let box=NotesSessionBox()
        let source=try await history.prepareNotesSource(recordID:record.id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{box.controller?.sourceRetired($0)})
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])),pythonArguments:pythonArguments,mode:.fixture,
            onFrame:{_ in throw PanelBridgeError.malformed},onFailure:{})
        try helper.start()
        addTeardownBlock{await helper.shutdownAndWait();await history.lock();await history.waitForQuiescence();try? FileManager.default.removeItem(at:directory)}
        return(history,source,helper,box)
    }
    private func heldTransfer(_ mode:String)async throws{
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-native-held-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let log=folder.appendingPathComponent("counts.jsonl"),release=folder.appendingPathComponent("release")
        defer{try? Data().write(to:release)}
        addTeardownBlock{try? FileManager.default.removeItem(at:folder)}
        let arguments=[root.appendingPathComponent("tests/support/notes_backend_helper.py").path,"--synthetic-notes-test","--log",log.path,"--release",release.path]
        let(history,source,helper,box)=try await fixture(rows:128,controls:true,pythonArguments:arguments)
        XCTAssertGreaterThan(source.data.rawBytes.count,200000)
        var phases:[GeneratedMeetingNotesPhase]=[]
        let controller=NativeNotesSessionController(history:history,source:source,helper:helper,isCurrent:{true},onProgress:{phases.append($0)})
        box.controller=controller
        let task=Task{try await controller.generate()}
        let until=ContinuousClock.now+Duration.seconds(5)
        while (try? String(contentsOf:log,encoding:.utf8).contains("staging_held")) != true {
            guard ContinuousClock.now<until else{throw HistoryError.unavailable}
            try await Task.sleep(for:.milliseconds(3))
        }
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertFalse(phases.contains(.generating));XCTAssertFalse(controller.isQuiesced)
        if mode=="source"{history.retireNotesSource(source)}else{task.cancel()}
        try await Task.sleep(for:.milliseconds(20))
        XCTAssertFalse(controller.isQuiesced)
        XCTAssertFalse(try String(contentsOf:log,encoding:.utf8).contains("model_post"))
        try Data().write(to:release)
        do{_=try await task.value;XCTFail("Retired held source yielded completion")}catch{}
        await controller.waitForQuiescence();XCTAssertTrue(controller.isQuiesced);XCTAssertFalse(helper.hasExited)
        let events=try String(contentsOf:log,encoding:.utf8).split(separator:"\n").map{try JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:String]}
        XCTAssertFalse(events.contains{$0["event"]=="model_post" || $0["kind"]=="notes_generate"})
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
    }
    func testActualSourceRetirementDuringHeldPartialWritePreventsGenerateAndKeepsFraming()async throws{try await heldTransfer("source")}
    func testActualCallerCancellationDuringHeldPartialWriteJoinsOriginalBeforeFinishing()async throws{try await heldTransfer("caller")}
}
