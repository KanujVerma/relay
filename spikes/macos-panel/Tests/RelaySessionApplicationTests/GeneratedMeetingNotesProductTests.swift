import AppKit
import Foundation
import SwiftUI
import XCTest
import RelayProfile
import RelayAccount
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor private final class NotesProductPreferences:HistorySavingPreferences{var savingEnabled=false}
private struct NotesProductKey:ProfileKeyProvider{func key(createIfMissing:Bool)throws->Data{Data(repeating:71,count:32)}}
private final class NotesProductExport:HistoryExportDestination,@unchecked Sendable{
    private let lock=NSLock();private var bytes:Data?
    var data:Data?{lock.withLock{bytes}}
    func write(_ data:Data)throws{lock.withLock{bytes=data}}
}
@MainActor final class GeneratedMeetingNotesProductTests:XCTestCase{
    private var repository:URL{URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()}
    private func until(_ predicate:()->Bool)async throws{
        let end=ContinuousClock.now+Duration.seconds(10)
        while !predicate(){guard ContinuousClock.now<end else{throw HistoryError.unavailable};try await Task.sleep(for:.milliseconds(3))}
    }
    private func folder()throws->URL{
        let value=FileManager.default.temporaryDirectory.appendingPathComponent("relay-notes-product-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        addTeardownBlock{try? FileManager.default.removeItem(at:value)};return value
    }
    private func seeded(_ directory:URL,app:URL?=nil)async throws->SessionApplicationModel{
        let preferences=NotesProductPreferences(),storage=HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:NotesProductKey())
        let args:[String]
        if app != nil{args=["Relay","--fixture-suite","analytics"]}
        else{args=["Relay","--fixture-suite","analytics","--repository",repository.path,"--python",try XCTUnwrap(ProcessInfo.processInfo.environment["RELAY_TEST_PYTHON"])]}
        let model=SessionApplicationModel(arguments:args,historyPreferences:preferences,historyStorageFactory:{storage},bundleURL:app ?? Bundle.main.bundleURL,workingDirectory:URL(fileURLWithPath:"/"))
        addTeardownBlock{await model.shutdown()}
        try await model.history.enableSaving();await model.start();try await until{!model.assistant.transcript.snapshot.rows.isEmpty};await model.stop();await model.history.waitForQuiescence()
        let record=try XCTUnwrap(model.history.snapshot.records.first);try await model.openHistoryRecord(record.id)
        return model
    }
    func testOptInActualHistoryNotesWindowRendersSavedCitedSourceWithoutOrderingAWindow()async throws{
        guard let output=ProcessInfo.processInfo.environment["RELAY_NOTES_HISTORY_RENDER_DIRECTORY"] else{throw XCTSkip("Explicit fictional actual-History Notes offscreen render only.")}
        let directory=try folder(),model=try await seeded(directory)
        model.generatedMeetingNotes.generate(model.generatedMeetingNotes.snapshot,selection:.fullSavedTranscript)
        await model.generatedMeetingNotes.waitForQuiescence();XCTAssertNotNil(model.generatedMeetingNotes.snapshot.document)
        try renderHistory(model,output:output)
    }
    private func renderHistory(_ model:SessionApplicationModel,output:String)throws{
        let size=CGSize(width:1080,height:960),view=NSHostingView(rootView:RelayHistoryWorkspace(model:model))
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        defer{window.contentView=nil;window.close()}
        window.isReleasedWhenClosed=false;window.contentView=view;view.frame=NSRect(origin:.zero,size:size)
        window.layoutIfNeeded();view.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.15));view.layoutSubtreeIfNeeded()
        XCTAssertFalse(window.isVisible)
        let destination=URL(fileURLWithPath:output,isDirectory:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let image=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:image)
        try XCTUnwrap(image.representation(using:.png,properties:[:])).write(to:destination.appendingPathComponent("actual-history-cited-notes.png"))
    }
    func testOptInStockBundleNotesUsesNormalResolverAndActualCitedHistoryMutation()async throws{
        guard let path=ProcessInfo.processInfo.environment["RELAY_BUNDLED_RUNTIME_APP"] else{throw XCTSkip("Explicit freshly built Notes app artifact required.")}
        let app=URL(fileURLWithPath:path,isDirectory:true),directory=try folder(),model=try await seeded(directory,app:app)
        XCTAssertNil(model.error);XCTAssertTrue(model.root.path.hasPrefix(app.path+"/"))
        let original=try XCTUnwrap(model.history.snapshot.selected),notes=model.generatedMeetingNotes
        notes.generate(notes.snapshot,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        let first=try XCTUnwrap(notes.snapshot.document);XCTAssertEqual(first.modelID,"relay-synthetic-fixture")
        XCTAssertEqual(first.sourceRows.map(\.rowID),original.rows.map(\.id))
        let citation=try XCTUnwrap(first.notes.summary.first?.citations.first)
        try await model.revealGeneratedMeetingNotesCitation(notes.snapshot,citation);XCTAssertEqual(model.historyCitationRowID,citation.rowID)
        try await notes.saveEdits(notes.snapshot,HistoryNotesEditedTexts(summary:["Explicit locally edited bundled notes."],decisions:[],nextSteps:[]))
        let edited=try XCTUnwrap(notes.snapshot.document);XCTAssertEqual(edited.origin,"generated_user_edited")
        XCTAssertEqual(edited.notes.summary[0].citations,first.notes.summary[0].citations)
        let destination=NotesProductExport(),current=try XCTUnwrap(model.history.snapshot.selected)
        try await model.history.export(current.record.id,expectedRevision:current.record.revision,format:.json,to:destination).value
        let exported=try XCTUnwrap(JSONSerialization.jsonObject(with:XCTUnwrap(destination.data)) as? [String:Any])
        XCTAssertEqual(exported["schemaVersion"] as? Int,2);XCTAssertNotNil(exported["generatedMeetingNotes"])
        notes.generate(notes.snapshot,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        let regenerated=try XCTUnwrap(notes.snapshot.document);XCTAssertGreaterThan(regenerated.noteRevision,edited.noteRevision)
        let helper=try model.ensureHelper();await model.stop();XCTAssertTrue(helper.hasExited)
        try await model.openHistoryRecord(current.record.id);XCTAssertNotNil(model.generatedMeetingNotes.snapshot.document)
        try await model.generatedMeetingNotes.deleteGenerated(model.generatedMeetingNotes.snapshot)
        XCTAssertNil(model.generatedMeetingNotes.snapshot.document);XCTAssertEqual(model.history.snapshot.selected?.rows,original.rows)
        XCTAssertEqual(model.speechSetup.snapshot.stage,.notPrepared)
    }
    func testOptInStockBundleAIOffKeepsLocalNoteEditsAndReferenceAssistanceAvailable()async throws{
        guard let path=ProcessInfo.processInfo.environment["RELAY_BUNDLED_RUNTIME_APP"] else{throw XCTSkip("Explicit freshly built Notes app artifact required.")}
        let app=URL(fileURLWithPath:path,isDirectory:true),directory=try folder(),seed=try await seeded(directory,app:app)
        seed.generatedMeetingNotes.generate(seed.generatedMeetingNotes.snapshot,selection:.fullSavedTranscript)
        await seed.generatedMeetingNotes.waitForQuiescence()
        let document=try XCTUnwrap(seed.generatedMeetingNotes.snapshot.document);await seed.shutdown()
        let storage=HistoryVaultStorage(directory:directory.appendingPathComponent("Relay/History"),keys:NotesProductKey())
        let ports=AccountApplicationPorts(storage:AccountStorage(sharedDirectory:directory.appendingPathComponent("Relay"),keys:NotesProductKey()),preferences:FixtureChatGPTPlanPreferences(),
            control:{_,_ in XCTFail("AI-off local edits cannot open account control");throw AccountError.unavailable},
            openBrowser:{_ in XCTFail("No browser in AI-off bundled control");return false},sessionArguments:{runtime,_ in runtime.arguments})
        let model=SessionApplicationModel(arguments:["Relay","--role","analytics"],historyPreferences:NotesProductPreferences(),historyStorageFactory:{storage},accountPorts:ports,bundleURL:app,workingDirectory:URL(fileURLWithPath:"/"))
        addTeardownBlock{await model.shutdown()}
        XCTAssertFalse(model.oauth);try await model.history.openExisting();try await model.openHistoryRecord(document.recordID)
        let notes=model.generatedMeetingNotes;XCTAssertNotNil(notes.snapshot.document);XCTAssertFalse(notes.snapshot.canGenerate)
        notes.generate(notes.snapshot,selection:.fullSavedTranscript);await notes.waitForQuiescence()
        XCTAssertEqual(notes.snapshot.document,document)
        try await notes.saveEdits(notes.snapshot,HistoryNotesEditedTexts(summary:["Locally edited while AI is off."],decisions:[],nextSteps:[]))
        XCTAssertEqual(notes.snapshot.document?.origin,"generated_user_edited")
        model.microphoneEnabled=false;model.assistant.draft="What is the difference between WHERE and HAVING?";model.assistant.submitDraft()
        try await until{model.snapshot.card != nil};XCTAssertFalse(model.running);XCTAssertTrue(model.assistantActive)
        XCTAssertEqual(model.speechSetup.snapshot.stage,.notPrepared);XCTAssertTrue(model.root.path.hasPrefix(app.path+"/"))
        await model.stop()
    }
}
