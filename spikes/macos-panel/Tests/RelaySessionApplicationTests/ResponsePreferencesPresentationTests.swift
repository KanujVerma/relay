import Foundation
import XCTest
import RelayProfile
@testable import RelayPanelSession

@MainActor final class ResponsePreferencesPresentationTests:XCTestCase {
    func testSaveReceiptPreservesNewerEditorTextAndOnlyAdvancesItsOwnCommittedBase()async throws {
        var editor=ResponseGuideEditorState(catalogRevision:UUID())
        editor.name="Concise";editor.guidance="Prefer concise invariants."
        let submitted=editor,guide=try editor.validatedGuide(),committed=UUID()
        editor.guidance="Newer unsaved guidance must remain."
        XCTAssertTrue(editor.applySaveReceipt(submitted:submitted,revision:committed))
        XCTAssertEqual(editor.guidance,"Newer unsaved guidance must remain.")
        XCTAssertEqual(editor.id,guide.id);XCTAssertEqual(editor.catalogRevision,committed)
        XCTAssertFalse(editor.applySaveReceipt(submitted:submitted,revision:UUID()))
        XCTAssertEqual(editor.catalogRevision,committed)
    }
    func testReplacedEditorRejectsOldCompletionAndValidationUsesUTF8Bounds()async throws {
        var original=ResponseGuideEditorState();original.name="Original";original.guidance="Brief response."
        var replacement=ResponseGuideEditorState();replacement.name="New draft";replacement.guidance="Keep this text."
        let before=replacement
        XCTAssertFalse(replacement.applySaveReceipt(submitted:original,revision:UUID()))
        XCTAssertEqual(replacement,before)
        replacement.name=String(repeating:"é",count:33)
        XCTAssertThrowsError(try replacement.validatedGuide())
        replacement.name="Valid";replacement.guidance=String(repeating:"é",count:1025)
        XCTAssertThrowsError(try replacement.validatedGuide())
        replacement.guidance="Allowed newline\nand tab\there."
        XCTAssertEqual(try replacement.validatedGuide().guidance,replacement.guidance)
    }
    func testEditorOpeningSavedGuideKeepsItsExactIdAndDoesNotTurnItIntoFacts()async throws {
        let guide=try ResponseGuide(name:"Feature discussion",focus:.feature,guidance:"Prefer the current workflow stage.")
        let revision=UUID(),editor=ResponseGuideEditorState(guide:guide,catalogRevision:revision)
        XCTAssertEqual(try editor.validatedGuide(),guide)
        XCTAssertEqual(editor.catalogRevision,revision);XCTAssertEqual(editor.focus,.feature)
    }
    func testSelectionReceiptRefreshesOnlySameUntouchedBlankEditor()async throws {
        var blank=ResponseGuideEditorState(catalogRevision:UUID());let submitted=blank,revision=UUID()
        XCTAssertTrue(blank.applySelectionReceipt(submitted:submitted,revision:revision))
        XCTAssertEqual(blank.catalogRevision,revision);XCTAssertEqual(blank.id,submitted.id)
        XCTAssertTrue(blank.name.isEmpty);XCTAssertTrue(blank.guidance.isEmpty)
        var edited=submitted;edited.guidance="Newer text entered while Use was held."
        XCTAssertFalse(edited.applySelectionReceipt(submitted:submitted,revision:revision))
        XCTAssertEqual(edited.catalogRevision,submitted.catalogRevision)
        var replacement=ResponseGuideEditorState()
        XCTAssertFalse(replacement.applySelectionReceipt(submitted:submitted,revision:revision))
        var existing=submitted;existing.name="Existing unsaved draft";existing.guidance="Keep it."
        let oldDraft=existing
        XCTAssertFalse(existing.applySelectionReceipt(submitted:oldDraft,revision:revision));XCTAssertEqual(existing,oldDraft)
    }

}
