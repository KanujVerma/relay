import XCTest
@testable import RelayPanelState

final class PanelStateTests: XCTestCase {
    private func turn(_ id: String = "D02", _ generation: UInt64, epoch: UInt64 = 1) -> TurnKey {
        TurnKey(identifier: id, revision: 1, generation: generation, sessionEpoch: epoch)!
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
        XCTAssertEqual(state.sessionEpoch, 2)
        XCTAssertEqual(state.status, .idle)
        XCTAssertFalse(state.apply(.begin(turn: first, question: "Replayed after resume?")))
        XCTAssertFalse(state.apply(.begin(turn: turn("old-pre-resume", 8), question: "Replayed after resume?")))
        XCTAssertTrue(state.apply(.begin(turn: turn("new", 9, epoch: 2), question: "New authorized turn?")))
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
        let current = TurnKey(identifier: "D02", revision: 3, generation: 4, sessionEpoch: 1)!
        let stale = TurnKey(identifier: "D02", revision: 2, generation: 4, sessionEpoch: 1)!
        XCTAssertTrue(state.apply(.begin(turn: current, question: "Current?")))
        XCTAssertFalse(state.apply(.publish(turn: stale, card: card())))
        XCTAssertTrue(state.apply(.publish(turn: current, card: card())))
    }

    func testBoundedContentRejectsControlsAndEmptyItems() {
        XCTAssertNil(TurnKey(identifier: "x y", revision: 1, generation: 1, sessionEpoch: 1))
        XCTAssertNil(TurnKey(identifier: "x", revision: 0, generation: 1, sessionEpoch: 1))
        XCTAssertNil(TurnKey(identifier: "x", revision: 1, generation: 0, sessionEpoch: 1))
        XCTAssertNil(TurnKey(identifier: "x", revision: 1, generation: 1, sessionEpoch: 0))
        XCTAssertNil(PanelCard(lead: String(repeating: "a", count: 281), points: ["valid"]))
        XCTAssertNil(PanelCard(lead: "hello\u{0001}", points: ["valid"]))
        XCTAssertNil(PanelCard(lead: "hello", points: []))
        XCTAssertNil(PanelCard(lead: "hello", points: ["", "valid"]))
        XCTAssertNil(PanelCard(lead: "hello", points: ["a", "b", "c"]))
        XCTAssertNil(PanelCard(lead: "hello", points: ["valid"], detail: String(repeating: "a", count: 901)))

        var state = PanelState()
        XCTAssertFalse(state.apply(.begin(turn: turn("a", 1), question: String(repeating: "q", count: 501))))
        XCTAssertNil(state.currentTurn)
        XCTAssertEqual(state.status, .needsReview)
        // Invalid new turns consume their generation, so a revised payload
        // cannot resurrect a previously unsafe interval under the same key.
        XCTAssertFalse(state.apply(.begin(turn: turn("a", 1), question: "Valid?")))
        XCTAssertTrue(state.apply(.begin(turn: turn("b", 2), question: "Valid?")))
    }


    func testInvalidNewQuestionClearsPreviouslyVisibleCard() {
        var state = PanelState()
        let old = turn("old", 1)
        let invalid = turn("invalid", 2)
        let fresh = turn("fresh", 3)
        XCTAssertTrue(state.apply(.begin(turn: old, question: "Original?")))
        XCTAssertTrue(state.apply(.publish(turn: old, card: card())))
        XCTAssertNotNil(state.card)
        XCTAssertFalse(state.apply(.begin(
            turn: invalid, question: String(repeating: "oversized", count: 70)
        )))
        XCTAssertNil(state.card)
        XCTAssertNil(state.question)
        XCTAssertNil(state.currentTurn)
        XCTAssertEqual(state.reason, .validationRequired)
        XCTAssertEqual(state.status, .needsReview)
        XCTAssertFalse(state.apply(.publish(turn: old, card: card())))
        XCTAssertFalse(state.apply(.begin(turn: invalid, question: "Same generation retry?")))
        XCTAssertTrue(state.apply(.begin(turn: fresh, question: "Fresh question?")))
        XCTAssertNil(state.card)
        XCTAssertTrue(state.apply(.publish(turn: fresh, card: card())))
    }

    func testControlCharacterReplacementAlsoClearsVisibleCard() {
        var state = PanelState()
        let old = turn("old", 4)
        let invalid = turn("bad", 5)
        XCTAssertTrue(state.apply(.begin(turn: old, question: "Old question?")))
        XCTAssertTrue(state.apply(.publish(turn: old, card: card())))
        XCTAssertFalse(state.apply(.begin(turn: invalid, question: "Untrusted\u{0000}question")))
        XCTAssertNil(state.card)
        XCTAssertNil(state.currentTurn)
        XCTAssertEqual(state.status, .needsReview)
        XCTAssertFalse(state.apply(.publish(turn: old, card: card())))
    }

    func testPreStopQueuedButUnobservedTurnCannotEnterAfterResume() {
        var state = PanelState()
        let current = turn("current", 1)
        // This event exists BEFORE stop, but is not delivered until AFTER resume.
        // It may have a higher generation than anything the UI has observed.
        let delayed = turn("delayed", 900, epoch: 1)
        XCTAssertTrue(state.apply(.begin(turn: current, question: "Original?")))
        XCTAssertTrue(state.apply(.publish(turn: current, card: card())))
        XCTAssertTrue(state.apply(.stop))
        XCTAssertTrue(state.apply(.resume))
        XCTAssertEqual(state.sessionEpoch, 2)
        XCTAssertFalse(state.apply(.begin(turn: delayed, question: "Queued before stop?")))
        XCTAssertFalse(state.apply(.publish(turn: delayed, card: card())))
        XCTAssertNil(state.currentTurn)
        XCTAssertNil(state.card)
        XCTAssertEqual(state.status, .idle)
        // Rejecting stale epochs does not poison new authorized generations.
        let newTurn = turn("fresh", 2, epoch: 2)
        XCTAssertTrue(state.apply(.begin(turn: newTurn, question: "New session?")))
        XCTAssertTrue(state.apply(.publish(turn: newTurn, card: card())))
        XCTAssertFalse(state.apply(.withhold(turn: delayed, reason: .interrupted)))
        XCTAssertNotNil(state.card)
    }

    func testObservedStoppedGenerationCannotPoisonNextSession() {
        var state = PanelState()
        let beforeStop = turn("before", 3)
        XCTAssertTrue(state.apply(.begin(turn: beforeStop, question: "First?")))
        XCTAssertTrue(state.apply(.stop))
        XCTAssertFalse(state.apply(.begin(
            turn: turn("invalid-while-stopped", 1_000_000),
            question: "Never accepted?"
        )))
        XCTAssertTrue(state.apply(.resume))
        XCTAssertEqual(state.sessionEpoch, 2)
        // Generation numbers are monotonic per epoch, not across the
        // separate authorization lifetime identified by sessionEpoch.
        let afterResume = turn("after", 1, epoch: 2)
        XCTAssertTrue(state.apply(.begin(turn: afterResume, question: "Authorized new session?")))
        XCTAssertFalse(state.apply(.publish(turn: beforeStop, card: card())))
        XCTAssertTrue(state.apply(.publish(turn: afterResume, card: card())))
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
