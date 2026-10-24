import Dispatch
import Foundation
import XCTest
import RelayProfile
@testable import RelaySessionPanel

@MainActor private final class NotesCommitPreferences:HistorySavingPreferences {var savingEnabled=false}
private struct NotesCommitKey:ProfileKeyProvider {func key(createIfMissing:Bool)throws->Data{Data(repeating:73,count:32)}}
private final class NotesCommitStorage:HistoryOwnedSnapshotStorage,@unchecked Sendable {
    enum Fault:Equatable{case none,afterWrite,hold}
    let real:HistoryVaultStorage
    private let lock=NSLock(),release=DispatchSemaphore(value:0)
    private var fault:Fault = .none,waiting=false
    init(_ real:HistoryVaultStorage){self.real=real}
    var held:Bool{lock.withLock{waiting}}
    func arm(_ value:Fault){lock.withLock{fault=value}}
    func resume(){release.signal()}
    func beginAccess(create:Bool)throws{try real.beginAccess(create:create)}
    func endAccess()throws{try real.endAccess()}
    func exists()throws->Bool{try real.exists()}
    func load()throws->Data{try real.load()}
    func save(_ bytes:Data,createKey:Bool)throws{
        let original=lock.withLock{let value=fault;fault = .none;if value == .hold{waiting=true};return value}
        if original == .hold{guard release.wait(timeout:.now()+8) == .success else{throw HistoryError.unavailable};lock.withLock{waiting=false}}
        try real.save(bytes,createKey:createKey)
        if original == .afterWrite{throw HistoryError.unavailable}
    }
}

@MainActor final class HistoryNotesCommitCoordinatorTests:XCTestCase {
    private var root:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func fixture(onRetired:@escaping @MainActor (HistoryNotesSource)->Void={_ in})async throws->(SessionHistoryCoordinator,HistoryNotesSource,HelperTransport,NotesCommitStorage){
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-commit-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let storage=NotesCommitStorage(HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:NotesCommitKey()))
        let clock:@Sendable ()->Date={Date(timeIntervalSince1970:1_800_000_000)}
        let store=HistoryStore(storage:storage,clock:clock);try store.open(create:true);let record=try store.createRecord()
        _=try store.edit(record.id,expectedRevision:record.revision,title:"Fictional meeting",note:"Keep these manual notes.")
        let transcript=SessionTranscriptStore();var originals:[ValidatedTranscriptObservation]=[]
        transcript.onHistoryObservation={originals.append($0)};var events=HistoryTestEvents();events.start(transcript)
        events.final(1,text:"Fictional original meeting question.",into:transcript);events.final(2,text:"Fictional original microphone reply.",source:1,into:transcript);events.stop(into:transcript)
        for original in originals{try store.append(original,to:record.id)}
        try store.finish(record.id,outcome:.completed);try store.close()
        let history=SessionHistoryCoordinator(storageFactory:{storage},preferences:NotesCommitPreferences(),canEnable:{true},clock:clock)
        try await history.openExisting();try await history.openRecord(record.id)
        let source=try await history.prepareNotesSource(recordID:record.id,expectedRevision:XCTUnwrap(history.snapshot.selected?.record.revision),selection:.fullSavedTranscript,intentID:UUID(),isCurrent:{true},onRetired:onRetired)
        let helper=HelperTransport(root:root,python:URL(fileURLWithPath:try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])),mode:.fixture,onFrame:{_ in throw PanelBridgeError.malformed},onFailure:{})
        try helper.start()
        addTeardownBlock{storage.resume();await helper.shutdownAndWait();await history.lock();await history.waitForQuiescence();try? FileManager.default.removeItem(at:directory)}
        return(history,source,helper,storage)
    }
    private func operation(_ history:SessionHistoryCoordinator,_ source:HistoryNotesSource,_ helper:HelperTransport,deadline:UInt64=DispatchTime.now().uptimeNanoseconds+30_000_000_000)async throws->NotesCompletedOperation{
        try await NativeNotesSessionController(history:history,source:source,helper:helper,deadline:deadline,isCurrent:{true}).generate()
    }
    func testActualHelperCompletionCommitsThroughOwnedHistoryAndLatchesBeforeRetirement()async throws{
        var actual:NotesCompletedOperation?,retired=0
        let(history,source,helper,_)=try await fixture(onRetired:{_ in retired+=1;XCTAssertNotNil(actual?.actualCommittedOutcome)})
        let completed=try await operation(history,source,helper);actual=completed
        let outcome=try await history.commitGeneratedNotes(completed)
        XCTAssertTrue(outcome.receipt === completed.actualCommittedOutcome?.receipt);XCTAssertTrue(outcome.cleanupComplete)
        XCTAssertEqual(retired,1);XCTAssertFalse(history.ownsNotesSource(source))
        XCTAssertEqual(history.snapshot.selected?.record.revision,outcome.receipt.savedAtRecordRevision)
        XCTAssertEqual(history.snapshot.selected?.record.note,"Keep these manual notes.")
        let restored=try await history.generatedNotes(source.data.recordID,expectedRevision:outcome.receipt.savedAtRecordRevision,epoch:history.snapshot.epoch)
        XCTAssertEqual(restored,outcome.document);XCTAssertEqual(restored?.sourceRows.count,2)
        do{_=try await history.commitGeneratedNotes(completed);XCTFail("One original operation committed twice")}catch{}
    }
    func testForeignWorkspaceCannotConsumeAnOriginalCompletionOrWriteItsOwnStore()async throws{
        let(first,source,helper,_)=try await fixture(),(other,_,_,storage)=try await fixture()
        let completed=try await operation(first,source,helper),before=try storage.load()
        do{_=try await other.commitGeneratedNotes(completed);XCTFail("Foreign workspace accepted completion")}catch{}
        XCTAssertEqual(try storage.load(),before);XCTAssertNil(completed.actualCommittedOutcome)
        let saved=try await first.commitGeneratedNotes(completed);XCTAssertEqual(saved.receipt.recordID,source.data.recordID)
    }
    func testUnconfirmedSaveDeniesCachedAccessUntilActualOwnedReopen()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        storage.arm(.afterWrite)
        do{_=try await history.commitGeneratedNotes(completed);XCTFail("A throwing save cannot issue a receipt")}
        catch HistoryNotesCommitError.indeterminate{}catch{XCTFail("Expected the typed indeterminate outcome")}
        XCTAssertNil(completed.actualCommittedOutcome);XCTAssertEqual(history.snapshot.phase,.unavailable)
        await history.lock();await history.waitForQuiescence();try await history.openExisting();try await history.openRecord(source.data.recordID)
        let revision=try XCTUnwrap(history.snapshot.selected?.record.revision)
        let restored=try await history.generatedNotes(source.data.recordID,expectedRevision:revision,epoch:history.snapshot.epoch)
        XCTAssertNotNil(restored)
    }
    func testLockDuringActualSaveJoinsAndKeepsPositiveDurableOutcomeSeparateFromPaint()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        storage.arm(.hold);let saving=Task{try await history.commitGeneratedNotes(completed)}
        let deadline=ContinuousClock.now+Duration.seconds(5)
        while !storage.held{guard ContinuousClock.now<deadline else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
        saving.cancel();history.lock();XCTAssertTrue(history.isBusy);XCTAssertNil(history.snapshot.selected)
        storage.resume();let outcome=try await saving.value;await history.waitForQuiescence()
        XCTAssertTrue(outcome.receipt === completed.actualCommittedOutcome?.receipt);XCTAssertEqual(history.snapshot.phase,.locked)
        XCTAssertNil(history.snapshot.selected)
        try await history.openExisting();try await history.openRecord(source.data.recordID)
        let restored=try await history.generatedNotes(source.data.recordID,expectedRevision:outcome.receipt.savedAtRecordRevision,epoch:history.snapshot.epoch)
        XCTAssertEqual(restored,outcome.document)
    }
    func testExpiredOriginalIntentCannotCommitAStoredSourceEvenWhenTheRecordSurvives()async throws{
        let(history,source,helper,storage)=try await fixture(),deadline=DispatchTime.now().uptimeNanoseconds+1_000_000_000
        let completed=try await operation(history,source,helper,deadline:deadline),before=try storage.load()
        while DispatchTime.now().uptimeNanoseconds<=deadline{try await Task.sleep(for:.milliseconds(5))}
        do{_=try await history.commitGeneratedNotes(completed);XCTFail("Expired intent persisted completion")}catch{}
        XCTAssertEqual(try storage.load(),before);XCTAssertNil(completed.actualCommittedOutcome)
    }
    func testReadOfMissingGeneratedNotesNeverMigratesOrWritesTheExistingLedger()async throws{
        let(history,source,_,storage)=try await fixture(),before=try storage.load()
        let document=try await history.generatedNotes(source.data.recordID,expectedRevision:source.data.recordRevision,epoch:history.snapshot.epoch)
        XCTAssertNil(document);XCTAssertEqual(try storage.load(),before)
    }
    func testStoppedActualHelperCannotSupplyAStillUsableSaveOperation()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        await helper.shutdownAndWait();let before=try storage.load()
        do{_=try await history.commitGeneratedNotes(completed);XCTFail("Retired helper supplied save authority")}catch{}
        XCTAssertEqual(try storage.load(),before);XCTAssertNil(completed.actualCommittedOutcome)
    }
    func testActualManualRevisionChangeCannotRebaseAnEarlierModelCompletion()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        _=try await history.saveNotes(source.data.recordID,expectedRevision:source.data.recordRevision,title:"Later user title",note:"Later manual note.")
        let before=try storage.load()
        do{_=try await history.commitGeneratedNotes(completed);XCTFail("Completion rebased onto later user revision")}catch{}
        XCTAssertEqual(try storage.load(),before);XCTAssertEqual(history.snapshot.selected?.record.note,"Later manual note.")
    }

    func testUserWordingEditNeedsNoLiveHelperAndPreservesOriginalCitationsAndGeneration()async throws{
        let(history,source,helper,_)=try await fixture(),completed=try await operation(history,source,helper)
        let first=try await history.commitGeneratedNotes(completed);await helper.shutdownAndWait()
        let edited=try await history.editGeneratedNotes(source.data.recordID,expectedRecordRevision:first.receipt.savedAtRecordRevision,
            noteID:first.document.noteID,expectedNoteRevision:first.document.noteRevision,
            texts:HistoryNotesEditedTexts(summary:["My edited meeting wording."],decisions:[],nextSteps:[]),epoch:history.snapshot.epoch,operationID:UUID())
        XCTAssertEqual(edited.document.origin,"generated_user_edited");XCTAssertEqual(edited.document.notes.summary[0].text,"My edited meeting wording.")
        XCTAssertEqual(edited.document.notes.summary[0].citations,first.document.notes.summary[0].citations)
        XCTAssertEqual(edited.document.sourceRows,first.document.sourceRows);XCTAssertEqual(edited.document.generation,first.document.generation)
        XCTAssertEqual(history.snapshot.selected?.record.revision,edited.receipt.savedAtRecordRevision)
    }
    func testAnchoredUserDeleteReturnsActualReceiptAndPreservesManualAndTranscript()async throws{
        let(history,source,helper,_)=try await fixture(),completed=try await operation(history,source,helper)
        let first=try await history.commitGeneratedNotes(completed),before=try XCTUnwrap(history.snapshot.selected)
        await helper.shutdownAndWait()
        let deleted=try await history.deleteGeneratedNotes(source.data.recordID,expectedRecordRevision:first.receipt.savedAtRecordRevision,
            noteID:first.document.noteID,expectedNoteRevision:first.document.noteRevision,epoch:history.snapshot.epoch,operationID:UUID())
        XCTAssertTrue(deleted.cleanupComplete);XCTAssertEqual(deleted.receipt.noteID,first.document.noteID)
        XCTAssertEqual(history.snapshot.selected?.rows,before.rows);XCTAssertEqual(history.snapshot.selected?.record.note,"Keep these manual notes.")
        let read=try await history.generatedNotes(source.data.recordID,expectedRevision:deleted.receipt.savedAtRecordRevision,epoch:history.snapshot.epoch)
        XCTAssertNil(read)
    }
    func testUserMutationWithOldWorkspaceOrNoteVersionCannotRetargetAReopenedRecord()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        let first=try await history.commitGeneratedNotes(completed),oldEpoch=history.snapshot.epoch
        await history.lock();await history.waitForQuiescence();try await history.openExisting();try await history.openRecord(source.data.recordID)
        let before=try storage.load()
        do{_=try await history.editGeneratedNotes(source.data.recordID,expectedRecordRevision:first.receipt.savedAtRecordRevision,
            noteID:first.document.noteID,expectedNoteRevision:first.document.noteRevision,
            texts:HistoryNotesEditedTexts(summary:["Stale wording"],decisions:[],nextSteps:[]),epoch:oldEpoch,operationID:UUID());XCTFail("Old editor crossed workspace reopen")}catch{}
        do{_=try await history.deleteGeneratedNotes(source.data.recordID,expectedRecordRevision:first.receipt.savedAtRecordRevision,
            noteID:first.document.noteID,expectedNoteRevision:first.document.noteRevision+1,epoch:history.snapshot.epoch,operationID:UUID());XCTFail("Wrong note version deleted current notes")}catch{}
        XCTAssertEqual(try storage.load(),before)
    }
    func testUnknownUserWordingSaveKeepsIndeterminateStateUntilOwnedReopen()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        let first=try await history.commitGeneratedNotes(completed);storage.arm(.afterWrite)
        do{_=try await history.editGeneratedNotes(source.data.recordID,expectedRecordRevision:first.receipt.savedAtRecordRevision,
            noteID:first.document.noteID,expectedNoteRevision:first.document.noteRevision,
            texts:HistoryNotesEditedTexts(summary:["A durable but initially unconfirmed edit."],decisions:[],nextSteps:[]),epoch:history.snapshot.epoch,operationID:UUID());XCTFail("Unconfirmed edit issued an acknowledgement")}
        catch HistoryNotesCommitError.indeterminate{}catch{XCTFail("Expected typed unknown outcome")}
        XCTAssertEqual(history.snapshot.phase,.unavailable)
        await history.lock();await history.waitForQuiescence();try await history.openExisting();try await history.openRecord(source.data.recordID)
        let revision=try XCTUnwrap(history.snapshot.selected?.record.revision)
        let read=try await history.generatedNotes(source.data.recordID,expectedRevision:revision,epoch:history.snapshot.epoch)
        XCTAssertEqual(read?.notes.summary[0].text,"A durable but initially unconfirmed edit.")
    }
    func testUnknownUserDeleteCannotPromiseTheOldNoteWasPreserved()async throws{
        let(history,source,helper,storage)=try await fixture(),completed=try await operation(history,source,helper)
        let first=try await history.commitGeneratedNotes(completed);storage.arm(.afterWrite)
        do{_=try await history.deleteGeneratedNotes(source.data.recordID,expectedRecordRevision:first.receipt.savedAtRecordRevision,
            noteID:first.document.noteID,expectedNoteRevision:first.document.noteRevision,epoch:history.snapshot.epoch,operationID:UUID());XCTFail("Unconfirmed delete issued a receipt")}
        catch HistoryNotesCommitError.indeterminate{}catch{XCTFail("Expected typed unknown outcome")}
        XCTAssertEqual(history.snapshot.phase,.unavailable)
        await history.lock();await history.waitForQuiescence();try await history.openExisting();try await history.openRecord(source.data.recordID)
        let revision=try XCTUnwrap(history.snapshot.selected?.record.revision)
        let read=try await history.generatedNotes(source.data.recordID,expectedRevision:revision,epoch:history.snapshot.epoch)
        XCTAssertNil(read);XCTAssertEqual(history.snapshot.selected?.record.note,"Keep these manual notes.")
    }
}
