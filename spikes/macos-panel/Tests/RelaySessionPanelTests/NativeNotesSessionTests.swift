import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

@MainActor private final class NotesSessionPreferences:HistorySavingPreferences {var savingEnabled=false}
private struct NotesSessionKey:ProfileKeyProvider {func key(createIfMissing:Bool)throws->Data{Data(repeating:67,count:32)}}

@MainActor final class NativeNotesSessionTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func fixture()async throws->(SessionHistoryCoordinator,HistoryNotesSource,HelperTransport){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-session-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let storage=HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:NotesSessionKey())
        let clock:@Sendable ()->Date={Date(timeIntervalSince1970:1_800_000_000)}
        let store=HistoryStore(storage:storage,clock:clock);try store.open(create:true);let record=try store.createRecord()
        let transcript=SessionTranscriptStore();var originals:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={originals.append($0)};var events=HistoryTestEvents();events.start(transcript)
        events.final(1,text:"Fictional original source question.",into:transcript)
        events.final(2,text:"Fictional original microphone response.",source:1,into:transcript);events.stop(into:transcript)
        for original in originals{try store.append(original,to:record.id)}
        try store.finish(record.id,outcome:.completed);try store.close()
        let history=SessionHistoryCoordinator(storageFactory:{storage},preferences:NotesSessionPreferences(),canEnable:{true},clock:clock)
        try await history.openExisting();try await history.openRecord(record.id)
        let revision=try XCTUnwrap(history.snapshot.selected?.record.revision)
        let source=try await history.prepareNotesSource(recordID:record.id,expectedRevision:revision,selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:{_ in})
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])),mode:.fixture,
            onFrame:{_ in throw PanelBridgeError.malformed},onFailure:{})
        try helper.start()
        addTeardownBlock{await helper.shutdownAndWait();await history.lock();await history.waitForQuiescence();try? FileManager.default.removeItem(at:directory)}
        return(history,source,helper)
    }
    func testActualSourceAndHelperIssueOneCompletedOperationAndJoinScope()async throws{
        let(history,source,helper)=try await fixture()
        let controller=NativeNotesSessionController(history:history,source:source,helper:helper,isCurrent:{true})
        let operation=try await controller.generate()
        XCTAssertTrue(operation.source === source);XCTAssertEqual(operation.output.summary.count,1)
        XCTAssertEqual(operation.modelID,"relay-synthetic-fixture");XCTAssertTrue(controller.isQuiesced)
        XCTAssertTrue(history.ownsNotesSource(source));XCTAssertFalse(helper.hasExited)
        let replay=try await controller.generate();XCTAssertTrue(replay === operation)
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
    }
    func testRetiredActualSourceCannotOpenOrProduceACompletion()async throws{
        let(history,source,helper)=try await fixture();history.retireNotesSource(source)
        let controller=NativeNotesSessionController(history:history,source:source,helper:helper,isCurrent:{true})
        do{_=try await controller.generate();XCTFail("Retired source produced completion") }catch{}
        XCTAssertTrue(controller.isQuiesced);XCTAssertFalse(helper.hasExited)
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
    }
    func testSynchronousSourceDenialDuringGeneratingCannotIssueCompletedOperation()async throws{
        let(history,source,helper)=try await fixture();var retired=false
        let controller=NativeNotesSessionController(history:history,source:source,helper:helper,isCurrent:{true},onProgress:{phase in
            if phase == .generating{retired=true;history.retireNotesSource(source)}
        })
        do{_=try await controller.generate();XCTFail("Denied original source produced completion") }catch{}
        XCTAssertTrue(retired);XCTAssertFalse(history.ownsNotesSource(source));XCTAssertTrue(controller.isQuiesced)
        XCTAssertFalse(helper.hasExited);_=try await helper.requestVisualInput(.status,onUpdate:{_ in})
    }
    func testAlreadyCancelledCallerDoesNotOpenAReplacementScope()async throws{
        let(history,source,helper)=try await fixture()
        let controller=NativeNotesSessionController(history:history,source:source,helper:helper,isCurrent:{true})
        let task=Task{try await controller.generate()};task.cancel()
        do{_=try await task.value;XCTFail("Cancelled caller produced completion")}catch{}
        XCTAssertTrue(controller.isQuiesced);XCTAssertFalse(helper.hasExited)
        _=try await helper.requestVisualInput(.status,onUpdate:{_ in})
    }
    func testFailedFinalCurrentnessCannotReplayItsCachedPrivateCompletion()async throws{
        let(history,source,helper)=try await fixture()
        var controller:NativeNotesSessionController?,wasActive=false,finalChecks=0
        let actual=NativeNotesSessionController(history:history,source:source,helper:helper,isCurrent:{
            guard let controller else{return true}
            if !controller.isQuiesced{wasActive=true}
            if wasActive,controller.isQuiesced{finalChecks+=1;return finalChecks != 2}
            return true
        })
        controller=actual
        do{_=try await actual.generate();XCTFail("The final caller-currentness failure must withhold completion")}catch{}
        XCTAssertEqual(finalChecks,2);XCTAssertTrue(actual.isQuiesced)
        do{_=try await actual.generate();XCTFail("A failed original intent replayed a cached completion")}catch{}
        XCTAssertFalse(helper.hasExited)
    }
}
