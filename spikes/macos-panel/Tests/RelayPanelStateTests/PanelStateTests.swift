import XCTest
@testable import RelayPanelState

final class PanelStateTests: XCTestCase {
    private func turn(_ id: String = "D02", _ generation: UInt64) -> TurnKey {
        TurnKey(identifier: id, revision: 1, generation: generation)!
    }

    private func card() -> PanelCard {
        PanelCard(
            lead: "WHERE filters rows; HAVING filters groups.",
            points: ["Row filters precede grouping.", "Group filters follow aggregation."]
        )!
    }

    func testOnlyCurrentCompletedCardCanPublish() {
        var state = PanelState()
        let first = turn("D02", 1)
        let second = turn("D02-corrected", 2)
        XCTAssertTrue(state.apply(.begin(turn: first, question: "WHERE versus HAVING?")))
        XCTAssertTrue(state.apply(.publish(turn: first, card: card())))
        XCTAssertEqual(state.status, .finalUnverified)
        XCTAssertNotNil(state.card)

        XCTAssertTrue(state.apply(.begin(turn: second, question: "What if the query uses GROUP BY?")))
        XCTAssertNil(state.card)
        XCTAssertEqual(state.status, .waiting)
        XCTAssertFalse(state.apply(.publish(turn: first, card: card())))
        XCTAssertNil(state.card)
        XCTAssertTrue(state.apply(.publish(turn: second, card: card())))
        XCTAssertEqual(state.status, .finalUnverified)
    }

    func testRejectedOlderOrReplayedGenerationsCannotReplaceQuestion() {
        var state = PanelState()
        let first = turn("first", 10)
        let earlier = turn("earlier", 9)
        let sameGeneration = turn("conflict", 10)
        XCTAssertTrue(state.apply(.begin(turn: first, question: "Question 10?")))
        XCTAssertFalse(state.apply(.begin(turn: earlier, question: "Older?")))
        XCTAssertFalse(state.apply(.begin(turn: sameGeneration, question: "Conflicting?")))
        XCTAssertEqual(state.currentTurn, first)
        XCTAssertEqual(state.question, "Question 10?")
    }

    func testStopAndResumeRequireFreshGeneration() {
        var state = PanelState()
        let first = turn("first", 7)
        XCTAssertTrue(state.apply(.begin(turn: first, question: "Original?")))
        XCTAssertTrue(state.apply(.publish(turn: first, card: card())))
        XCTAssertTrue(state.apply(.stop))
        XCTAssertTrue(state.isStopped)
        XCTAssertNil(state.card)
        XCTAssertNil(state.currentTurn)
        XCTAssertFalse(state.apply(.publish(turn: first, card: card())))
        XCTAssertFalse(state.apply(.begin(turn: turn("stopped", 8), question: "While stopped?")))
        XCTAssertTrue(state.apply(.resume))
        XCTAssertEqual(state.status, .idle)
        XCTAssertFalse(state.apply(.begin(turn: first, question: "Replayed after resume?")))
        XCTAssertTrue(state.apply(.begin(turn: turn("new", 8), question: "New authorized turn?")))
        XCTAssertEqual(state.status, .waiting)
        XCTAssertNil(state.card)
    }

    func testWithholdingRetractsAlreadyDisplayedAnswer() {
        var state = PanelState()
        let key = turn("a", 1)
        XCTAssertTrue(state.apply(.begin(turn: key, question: "A?")))
        XCTAssertTrue(state.apply(.publish(turn: key, card: card())))
        XCTAssertTrue(state.apply(.withhold(turn: key, reason: .uncertainSource)))
        XCTAssertEqual(state.status, .needsReview)
        XCTAssertNil(state.card)
        XCTAssertEqual(state.reason?.label, "Source uncertain — no answer displayed")
        XCTAssertFalse(state.apply(.publish(turn: key, card: card())))
        XCTAssertNil(state.card)
    }

    func testTurnVersionMismatchCannotPublish() {
        var state = PanelState()
        let current = TurnKey(identifier: "D02", revision: 3, generation: 4)!
        let stale = TurnKey(identifier: "D02", revision: 2, generation: 4)!
        XCTAssertTrue(state.apply(.begin(turn: current, question: "Current?")))
        XCTAssertFalse(state.apply(.publish(turn: stale, card: card())))
        XCTAssertTrue(state.apply(.publish(turn: current, card: card())))
    }

    func testBoundedContentRejectsControlsAndEmptyItems() {
        XCTAssertNil(TurnKey(identifier: "x y", revision: 1, generation: 1))
        XCTAssertNil(TurnKey(identifier: "x", revision: 0, generation: 1))
        XCTAssertNil(TurnKey(identifier: "x", revision: 1, generation: 0))
        XCTAssertNil(PanelCard(lead: String(repeating: "a", count: 281), points: ["valid"]))
        XCTAssertNil(PanelCard(lead: "hello\u{0001}", points: ["valid"]))
        XCTAssertNil(PanelCard(lead: "hello", points: []))
        XCTAssertNil(PanelCard(lead: "hello", points: ["", "valid"]))
        XCTAssertNil(PanelCard(lead: "hello", points: ["a", "b", "c"]))
        XCTAssertNil(PanelCard(lead: "hello", points: ["valid"], detail: String(repeating: "a", count: 901)))

        var state = PanelState()
        XCTAssertFalse(state.apply(.begin(turn: turn("a", 1), question: String(repeating: "q", count: 501))))
        XCTAssertNil(state.currentTurn)
        XCTAssertTrue(state.apply(.begin(turn: turn("a", 1), question: "Valid?")))
    }

    func testWithheldTextNeverEntersPresentationState() {
        var state = PanelState()
        let key = turn("unknown", 1)
        XCTAssertTrue(state.apply(.begin(turn: key, question: "Synthetic question?")))
        XCTAssertTrue(state.apply(.withhold(turn: key, reason: .validationRequired)))
        XCTAssertNil(state.card)
        XCTAssertEqual(state.status, .needsReview)
        XCTAssertFalse(state.apply(.publish(turn: key, card: card())))
        XCTAssertNil(state.card)
    }
}
