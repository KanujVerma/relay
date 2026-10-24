import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI
import XCTest
import RelaySessionPanel
@testable import RelayPanelSession

@MainActor final class GeneratedMeetingNotesPresentationTests:XCTestCase{
    func testUnsafeSourceFormattingIsVisibleWithoutChangingTheOriginalCitation()async throws{
        let original="quoted \u{202e}hidden\u{1}\nnext"
        XCTAssertEqual(GeneratedMeetingNotesSection.visibleQuote(original),"quoted \\u{202e}hidden\\u{1}\nnext")
        XCTAssertEqual(original,"quoted \u{202e}hidden\u{1}\nnext")
    }
    func testOptInFictionalNotesPresentationNeverOrdersAWindow()async throws{
        guard let folder=ProcessInfo.processInfo.environment["RELAY_NOTES_RENDER_DIRECTORY"] else{throw XCTSkip("Explicit fictional Notes presentation exports only.")}
        let directory=URL(fileURLWithPath:folder,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let document=try note(),epoch=UUID()
        for (name,snapshot) in [
            ("empty",GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,totalSavedRows:1,canGenerate:true)),
            ("ready",GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,phase:.ready,document:document,totalSavedRows:1,includedRows:1,canGenerate:true,canEdit:true,canDelete:true)),
            ("working",GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,operationID:UUID(),phase:.generating,document:document,totalSavedRows:1,canCancel:true)),
            ("unavailable",GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,phase:.unavailable,message:"The saved text changed. Choose the session again before generating notes."))
        ]{
            let view=GeneratedMeetingNotesSection(snapshot:snapshot,generate:{_,_ in XCTFail("Rendering cannot generate")},cancel:{_ in XCTFail("Rendering cannot cancel")},showCitation:{_,_ in XCTFail("Rendering cannot navigate")},saveEdits:{_,_ in XCTFail("Rendering cannot save")},deleteGenerated:{_ in XCTFail("Rendering cannot delete")},draft:GeneratedMeetingNotesDraft())
            let size=CGSize(width:640,height:760)
            let hosting=NSHostingView(rootView:VStack(alignment:.leading,spacing:16){Text("SYNTHETIC NOTES · fictional source · presentation only").font(.system(size:10));view;Spacer(minLength:0)}.padding(24).frame(width:size.width,height:size.height).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark))
            let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.contentView=hosting;hosting.frame=NSRect(origin:.zero,size:size)
            settleLayout(window,hosting)
            XCTAssertFalse(window.isVisible)
            let bitmap=try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds));hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("notes-"+name+".png"))
            window.contentView=nil;window.close()
        }
    }
    private func settleLayout(_ window:NSWindow,_ hosting:NSView){
        window.layoutIfNeeded();hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until:Date().addingTimeInterval(0.1));hosting.layoutSubtreeIfNeeded()
    }
    func testAppOwnedDraftRejectsRetargetAndKeepsExactWordingAfterFailedSave()async throws{
        let document=try note(),other=try note(),epoch=UUID(),draft=GeneratedMeetingNotesDraft()
        let original=GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,phase:.ready,document:document,canEdit:true)
        XCTAssertTrue(draft.stage(original));draft.edit("Keep this exact unsaved wording.",group:0,index:0)
        let replacement=GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:other.recordID,recordRevision:8,phase:.ready,document:other,canEdit:true)
        XCTAssertFalse(draft.stage(replacement));XCTAssertEqual(draft.snapshot.target?.recordID,document.recordID)
        do{try await draft.save{target,texts in
            XCTAssertEqual(target.recordID,document.recordID);XCTAssertEqual(target.recordRevision,8)
            XCTAssertEqual(texts.summary,["Keep this exact unsaved wording."]);throw HistoryError.stale
        };XCTFail("A failed actual edit callback cannot acknowledge the UI draft")}catch{}
        XCTAssertEqual(draft.snapshot.summary,["Keep this exact unsaved wording."]);XCTAssertTrue(draft.snapshot.isDirty)
        XCTAssertFalse(draft.snapshot.isSaving);XCTAssertEqual(draft.snapshot.target?.recordRevision,8)
    }
    func testMatchingSourceDenialClearsDraftBeforeHeldAcknowledgementAndCannotRestoreIt()async throws{
        let document=try note(),epoch=UUID(),draft=GeneratedMeetingNotesDraft()
        XCTAssertTrue(draft.stage(GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,phase:.ready,document:document)))
        draft.edit("Original held wording.",group:0,index:0)
        var entered=false;var release:CheckedContinuation<Void,Never>?
        let save=Task{try await draft.save{_,_ in entered=true;await withCheckedContinuation{release=$0}}}
        for _ in 0..<100{if entered{break};await Task.yield()};XCTAssertTrue(entered)
        draft.invalidate(.workspace(retiredEpoch:epoch,reason:.locked))
        XCTAssertNil(draft.snapshot.target);XCTAssertTrue(draft.snapshot.summary.isEmpty)
        release?.resume()
        do{try await save.value;XCTFail("A retired editor cannot acknowledge a save")}catch{}
        XCTAssertNil(draft.snapshot.target);XCTAssertTrue(draft.snapshot.summary.isEmpty)
    }
    func testHeldOldSaveCannotAcknowledgeOrCloseAReboundEditor()async throws{
        let first=try note(),second=try note(),epoch=UUID(),draft=GeneratedMeetingNotesDraft()
        XCTAssertTrue(draft.stage(GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:first.recordID,recordRevision:8,phase:.ready,document:first)))
        draft.edit("The first editor is waiting for its real save.",group:0,index:0)
        var entered=false;var release:CheckedContinuation<Void,Never>?
        let save=Task{try await draft.save{_,_ in entered=true;await withCheckedContinuation{release=$0}}}
        for _ in 0..<100{if entered{break};await Task.yield()};XCTAssertTrue(entered)
        draft.invalidate(.record(retiredEpoch:epoch,recordID:first.recordID,reason:.deleted))
        XCTAssertTrue(draft.stage(GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:second.recordID,recordRevision:8,phase:.ready,document:second)))
        draft.edit("Keep the second editor open and preserve these words.",group:0,index:0)
        release?.resume()
        do{try await save.value;XCTFail("An old save cannot acknowledge the replacement editor")}catch{}
        XCTAssertEqual(draft.snapshot.target?.recordID,second.recordID)
        XCTAssertEqual(draft.snapshot.summary,["Keep the second editor open and preserve these words."])
        XCTAssertTrue(draft.snapshot.isDirty);XCTAssertFalse(draft.snapshot.isSaving)
    }
    func testUnrelatedDenialDoesNotEraseDraftAndAcknowledgedSaveClearsOnlyMatchingEditor()async throws{
        let document=try note(),epoch=UUID(),draft=GeneratedMeetingNotesDraft()
        XCTAssertTrue(draft.stage(GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,phase:.ready,document:document)))
        draft.edit("A concise rewrite.",group:0,index:0)
        draft.invalidate(.record(retiredEpoch:epoch,recordID:UUID(),reason:.deleted))
        XCTAssertEqual(draft.snapshot.summary,["A concise rewrite."])
        try await draft.save{target,texts in XCTAssertEqual(target.document?.noteID,document.noteID);XCTAssertEqual(texts.summary,["A concise rewrite."])}
        XCTAssertNil(draft.snapshot.target);XCTAssertTrue(draft.snapshot.summary.isEmpty)
    }
    func testReopenOfChangedSameNoteKeepsOriginalVersionAndUnsavedWording()async throws{
        let document=try note(),epoch=UUID(),draft=GeneratedMeetingNotesDraft()
        let first=GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:8,phase:.ready,document:document)
        XCTAssertTrue(draft.prepareEditor(first));draft.edit("Keep the original unsaved rewrite.",group:0,index:0)
        let newer=GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:document.recordID,recordRevision:9,phase:.ready,document:document)
        XCTAssertTrue(draft.prepareEditor(newer))
        XCTAssertEqual(draft.snapshot.target?.recordRevision,8)
        XCTAssertEqual(draft.snapshot.summary,["Keep the original unsaved rewrite."])
        do{try await draft.save{original,_ in XCTAssertEqual(original.recordRevision,8);throw HistoryError.stale};XCTFail("No matching receipt")}catch{}
        XCTAssertTrue(draft.prepareEditor(newer));XCTAssertTrue(draft.snapshot.isDirty)
    }
    func testReentrantReplacementDuringSaveClearCannotAcknowledgeTheNewEditor()async throws{
        let first=try note(),second=try note(),epoch=UUID(),draft=GeneratedMeetingNotesDraft()
        XCTAssertTrue(draft.stage(GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:first.recordID,recordRevision:8,phase:.ready,document:first)))
        draft.edit("Save the first rewrite.",group:0,index:0)
        var armed=true
        let observer=draft.$snapshot.sink{snapshot in
            if armed,snapshot.target==nil{
                armed=false
                XCTAssertTrue(draft.stage(GeneratedMeetingNotesSnapshot(workspaceEpoch:epoch,recordID:second.recordID,recordRevision:8,phase:.ready,document:second)))
                draft.edit("Keep the replacement visible.",group:0,index:0)
            }
        }
        defer{observer.cancel()}
        do{try await draft.save{_,_ in};XCTFail("The old save cannot close a reentrant replacement")}catch{}
        XCTAssertFalse(armed);XCTAssertEqual(draft.snapshot.target?.recordID,second.recordID)
        XCTAssertEqual(draft.snapshot.summary,["Keep the replacement visible."])
    }
    private func note()throws->HistoryNotesDocumentData{
        let record=UUID().uuidString.lowercased(),capture=UUID().uuidString.lowercased(),row=capture+":1:2:1:1"
        let text="We agreed to keep the queue bounded and confirm overflow behavior."
        let selection:[String:Any]=["kind":"full_saved_transcript","totalSavedRows":1,"includedRows":1,"firstRowID":row,"lastRowID":row]
        let raw:[String:Any]=["schemaVersion":1,"recordID":record,"recordRevision":"7","selection":selection,"recordState":"completed","gaps":[],"rows":[["id":row,"revision":"1","source":"selected_app_audio","text":text]]]
        let source=try HistoryNotesData.source(JSONSerialization.data(withJSONObject:raw,options:[.sortedKeys,.withoutEscapingSlashes]))
        func item(_ text:String,_ quote:String)->[String:Any]{["text":text,"citations":[["rowID":row,"quote":quote]]]}
        let value:[String:Any]=["schemaVersion":1,"noteID":UUID().uuidString.lowercased(),"noteRevision":"1","recordID":record,
            "sourceRecordRevision":"7","savedAtRecordRevision":"8","selection":selection,"sourceState":"completed","sourceGaps":[],"sourceDigest":source.sourceDigest,
            "sourceRows":[["rowID":row,"revision":"1","textDigest":source.rows[0].textDigest]],"origin":"generated","modelID":"fictional-presentation-model","promptPolicy":"notes_source_v1",
            "generation":["scopeID":UUID().uuidString.lowercased(),"scopeEpoch":"1","operationID":UUID().uuidString.lowercased(),"requestID":UUID().uuidString.lowercased(),"requestSequence":"1","transferID":UUID().uuidString.lowercased(),"completedAt":"2026-10-24T12:00:00.000Z"],"editedAt":NSNull(),
            "notes":["schemaVersion":1,"summary":[item("The discussion covered bounded storage and overflow behavior.","keep the queue bounded")],"decisions":[item("Keep a fixed queue capacity.","keep the queue bounded")],"nextSteps":[item("Confirm how overflow should behave.","confirm overflow behavior")]]]
        return try HistoryNotesData.document(JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes]),source:source)
    }
}
