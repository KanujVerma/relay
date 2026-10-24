import Foundation
import XCTest
import RelayProfile
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class NotesAppPreferences:HistorySavingPreferences{var savingEnabled=false}
private struct NotesAppKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:83,count:32)}}
@MainActor private final class NotesAppHelperPort {
    let root:URL,python:URL
    var helper:HelperTransport?,preparations=0,held=false,release:CheckedContinuation<Void,Never>?
    var onPrepare:(@MainActor (UUID)async->Void)?
    init(_ root:URL,_ python:URL){self.root=root;self.python=python}
    func prepare(_ intent:UUID,_ isCurrent:@escaping @MainActor ()->Bool)async throws->HelperTransport{
        preparations+=1
        if let onPrepare{await onPrepare(intent)}
        if held{await withCheckedContinuation{release=$0}}
        try Task.checkCancellation();guard isCurrent() else{throw CancellationError()}
        if let helper{return helper}
        let actual=HelperTransport(root:root,python:python,mode:.fixture,onFrame:{_ in throw PanelBridgeError.malformed},onFailure:{})
        try actual.start();helper=actual;return actual
    }
}

@MainActor final class GeneratedMeetingNotesControllerTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func until(_ current:()->Bool)async throws{
        let deadline=ContinuousClock.now+Duration.seconds(7)
        while !current(){guard ContinuousClock.now<deadline else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
    }
    private func fixture()async throws->(SessionApplicationModel,GeneratedMeetingNotesController,NotesAppHelperPort){
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-app-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let storage=HistoryVaultStorage(directory:folder.appendingPathComponent("Relay/History"),keys:NotesAppKey()),prefs=NotesAppPreferences()
        let python=URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"]))
        let model=SessionApplicationModel(arguments:["relay","--fixture-suite","coding","--repository",root.path,"--python",python.path],historyPreferences:prefs,historyStorageFactory:{storage})
        try await model.history.enableSaving();await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop();await model.history.waitForQuiescence()
        let record=try XCTUnwrap(model.history.snapshot.records.first);try await model.history.openRecord(record.id)
        let port=NotesAppHelperPort(root,python)
        let notes=GeneratedMeetingNotesController(history:model.history,prepareHelper:port.prepare,mayOfferGeneration:{true})
        model.history.onSourceDenial={[weak notes] in notes?.handleSourceDenial($0)}
        try await notes.loadSelectedRecord()
        addTeardownBlock{await MainActor.run{port.release?.resume();port.release=nil};await notes.retireAndWait();await port.helper?.shutdownAndWait();await model.shutdown();try? FileManager.default.removeItem(at:folder)}
        return(model,notes,port)
    }
    func testActualAppHistorySourceHelperSaveReadEditDeleteAndCitationFlow()async throws{
        let(model,notes,port)=try await fixture(),loaded=notes.snapshot
        notes.generate(loaded,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        let first=try XCTUnwrap(notes.snapshot.document);XCTAssertEqual(notes.snapshot.phase,.ready);XCTAssertEqual(port.preparations,1)
        let citation=try XCTUnwrap(first.notes.summary.first?.citations.first)
        let original=try await notes.revealCitation(notes.snapshot,citation)
        XCTAssertEqual(original.id,citation.rowID);XCTAssertTrue(original.text.contains(citation.quote))
        await port.helper?.shutdownAndWait()
        try await notes.saveEdits(notes.snapshot,HistoryNotesEditedTexts(summary:["Edited locally with original source references."],decisions:[],nextSteps:[]))
        let edited=try XCTUnwrap(notes.snapshot.document)
        XCTAssertEqual(edited.origin,"generated_user_edited");XCTAssertEqual(edited.notes.summary[0].citations,first.notes.summary[0].citations)
        XCTAssertEqual(port.preparations,1,"Local edits must not prepare another account/helper/model")
        let before=try XCTUnwrap(model.history.snapshot.selected)
        try await notes.deleteGenerated(notes.snapshot)
        XCTAssertNil(notes.snapshot.document);XCTAssertEqual(model.history.snapshot.selected?.rows,before.rows)
        XCTAssertEqual(port.preparations,1)
    }
    func testStaleDisplayedTargetCannotGenerateAfterActualManualRecordChange()async throws{
        let(model,notes,port)=try await fixture(),old=notes.snapshot,detail=try XCTUnwrap(model.history.snapshot.selected)
        _=try await model.history.saveNotes(detail.record.id,expectedRevision:detail.record.revision,title:"Later user title",note:"Later manual wording.")
        notes.generate(old,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        XCTAssertEqual(port.preparations,0);XCTAssertNil(notes.snapshot.document)
        XCTAssertEqual(model.history.snapshot.selected?.record.note,"Later manual wording.")
    }
    func testActualPreparationCancellationJoinsOriginalAndOldViewCannotCancelReplacement()async throws{
        let(_,notes,port)=try await fixture(),old=notes.snapshot;port.held=true
        notes.generate(old,selection:.fullSavedTranscript);try await until{port.release != nil}
        let pending=notes.snapshot;notes.cancel(old);XCTAssertTrue(notes.isBusy)
        notes.cancel(pending);for _ in 0..<5{await Task.yield()}
        XCTAssertTrue(notes.isBusy);XCTAssertNil(port.helper)
        port.release?.resume();port.release=nil;await notes.waitForQuiescence()
        XCTAssertFalse(notes.isBusy);XCTAssertNil(notes.snapshot.document);XCTAssertNil(port.helper)
    }
    func testDefaultControllerConstructionCannotOpenStorageOrPrepareAHelper()async throws{
        let history=SessionHistoryCoordinator(storageFactory:{XCTFail("Constructor cannot request storage");throw HistoryError.unavailable},preferences:NotesAppPreferences(),canEnable:{true})
        let notes=GeneratedMeetingNotesController(history:history,prepareHelper:{_,_ in XCTFail("Constructor cannot prepare helper");throw HistoryError.unavailable},mayOfferGeneration:{true})
        XCTAssertNil(notes.snapshot.recordID);XCTAssertNil(notes.snapshot.document);XCTAssertFalse(notes.isBusy)
        XCTAssertEqual(history.snapshot.phase,.locked)
    }

    func testExactCurrentHelperPreparerSurvivesAccountHelperRetirementWithoutSelfAwait()async throws{
        let(_,notes,port)=try await fixture()
        port.onPrepare={intent in await notes.retireHelperDependents(excludingPreparation:intent)}
        notes.generate(notes.snapshot,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        XCTAssertNotNil(notes.snapshot.document);XCTAssertEqual(port.preparations,1);XCTAssertFalse(notes.isBusy)
    }
    func testForeignPreparerExclusionCannotPreserveOrReleaseHeldOriginalWork()async throws{
        let(_,notes,port)=try await fixture();port.held=true
        notes.generate(notes.snapshot,selection:.fullSavedTranscript);try await until{port.release != nil}
        var joined=false
        let retirement=Task{await notes.retireHelperDependents(excludingPreparation:UUID());joined=true}
        for _ in 0..<10{await Task.yield()}
        XCTAssertFalse(joined);XCTAssertTrue(notes.isBusy);XCTAssertNil(port.helper)
        port.release?.resume();port.release=nil;await retirement.value
        XCTAssertTrue(joined);XCTAssertFalse(notes.isBusy);XCTAssertNil(notes.snapshot.document);XCTAssertNil(port.helper)
    }
}
