"""03B-A synthetic transcript turn state, no capture, persistence or inference."""
from __future__ import annotations

from dataclasses import replace
import json
import unittest

from relay_spike.question_turns import (
    InvalidTranscript, MAX_SEEN_SEGMENTS, QuestionTurnMachine,
    TranscriptEvent,
)
from relay_spike.streaming_qa import (
    ActiveTurns, SyntheticContext, assess_synthetic_stream, publish_assessment,
)


def remote(segment_id, text, *, status="final", intent="question",
           generation=1, revision=1, start_ms=0, end_ms=1000,
           source="remote", confidence=None):
    return TranscriptEvent(
        source_channel=source, stream_generation=generation,
        segment_id=segment_id, revision=revision, start_ms=start_ms,
        end_ms=end_ms, status=status, intent=intent,
        text=text, confidence=confidence,
    )


class TurnAcceptance(unittest.TestCase):
    def setUp(self):
        self.turns = ActiveTurns()
        self.machine = QuestionTurnMachine(self.turns)

    def test_E11_partial_project_discarded_when_interviewer_restarts(self):
        partial = remote(
            "project-partial", "Tell me about a project where you...",
            status="partial", intent="question", end_ms=150,
        )
        result = self.machine.ingest(partial)
        self.assertEqual(result.state, "pending")
        self.assertIsNone(self.machine.current())
        self.assertIsNone(result.token)
        restart = remote(
            "bug-restart", "Actually, describe a bug you fixed.",
            intent="correction", start_ms=151, end_ms=450,
        )
        latest = self.machine.ingest(restart)
        self.assertEqual(latest.state, "ready")
        self.assertIn("bug you fixed", latest.snapshot.prompt)
        self.assertNotIn("project-partial", latest.snapshot.prompt)
        self.assertNotIn("Tell me about a project", latest.snapshot.prompt)
        self.assertEqual(latest.snapshot.token.version, 1)

    def test_D12_correction_preserves_verbatim_metric_and_year(self):
        initial = self.machine.ingest(remote(
            "q1", "Write a query for top five customers.", end_ms=800,
        ))
        corrected = self.machine.ingest(remote(
            "correction", "No, top five by distinct orders in 2025.",
            intent="correction", start_ms=850, end_ms=1050,
        ))
        self.assertEqual(corrected.state, "ready")
        self.assertFalse(self.turns.is_current(initial.token))
        self.assertTrue(self.turns.is_current(corrected.token))
        self.assertEqual(corrected.token.turn_id, initial.token.turn_id)
        self.assertEqual(corrected.token.version, 2)
        self.assertGreater(corrected.token.generation, initial.token.generation)
        self.assertEqual(corrected.snapshot.current_utterance,
                         "No, top five by distinct orders in 2025.")
        self.assertIn("distinct orders in 2025", corrected.snapshot.prompt)
        self.assertIn("Superseded question", corrected.snapshot.prompt)
        self.assertIn("Write a query for top five customers.", corrected.snapshot.prompt)
        self.assertNotIn("total revenue", corrected.snapshot.prompt)

    def test_correction_partial_invalidates_active_before_final(self):
        initial = self.machine.ingest(remote(
            "base", "Write a query for top five customers.",
            end_ms=500,
        ))
        partial = self.machine.ingest(remote(
            "fix", "No, top five by",
            status="partial", intent="correction",
            start_ms=550, end_ms=620,
        ))
        self.assertEqual(partial.state, "pending")
        self.assertFalse(self.turns.is_current(initial.token))
        self.assertIsNone(self.machine.current())
        latest = self.machine.ingest(remote(
            "fix", "No, top five by distinct orders in 2025.",
            status="final", intent="correction", revision=1,
            start_ms=550, end_ms=850,
        ))
        self.assertEqual(latest.state, "ready")
        self.assertEqual(latest.token.version, 2)
        self.assertIn("Superseded question", latest.snapshot.prompt)
        self.assertIn("distinct orders", latest.snapshot.prompt)

    def test_chained_corrections_keep_latest_accepted_metric_and_original_separate(self):
        first = self.machine.ingest(remote(
            "root", "List the top five customers by revenue.",
            end_ms=250,
        ))
        second = self.machine.ingest(remote(
            "first-correction", "No, top five by distinct orders in 2025.",
            intent="correction", start_ms=280, end_ms=500,
        ))
        third = self.machine.ingest(remote(
            "second-correction", "Make that 2024.",
            intent="correction", start_ms=600, end_ms=720,
        ))
        self.assertEqual(third.state, "ready")
        self.assertEqual(third.token.version, 3)
        self.assertEqual(third.token.turn_id, first.token.turn_id)
        self.assertFalse(self.turns.is_current(second.token))
        self.assertIn("Make that 2024.", third.snapshot.prompt)
        self.assertIn("No, top five by distinct orders in 2025.", third.snapshot.prompt)
        self.assertIn("List the top five customers by revenue.", third.snapshot.prompt)
        self.assertIn("Original question (older, superseded", third.snapshot.prompt)
        self.assertIn("Superseded question (immediately previous accepted wording",
                      third.snapshot.prompt)
        # No fabricated SQL reconstruction is performed by this slice.
        self.assertNotIn("SELECT ", third.snapshot.prompt)

    def test_retraction_of_intermediate_correction_invalidates_current_chain(self):
        original = self.machine.ingest(remote(
            "root", "List top customers by revenue.",
            start_ms=0, end_ms=200,
        ))
        middle = self.machine.ingest(remote(
            "correction-B", "No, by distinct orders in 2025.",
            intent="correction", start_ms=250, end_ms=420,
        ))
        last = self.machine.ingest(remote(
            "correction-C", "Make that 2024.",
            intent="correction", start_ms=480, end_ms=620,
        ))
        self.assertEqual(last.state, "ready")
        self.assertEqual(last.snapshot.dependency_segment_ids,
                         ("root", "correction-B", "correction-C"))
        self.assertFalse(self.machine.turns.is_current(middle.token))
        retracted = self.machine.ingest(remote(
            "correction-B", "", revision=2, status="retracted",
            intent="unknown", start_ms=250, end_ms=700,
        ))
        self.assertEqual(retracted.state, "cancelled")
        self.assertFalse(self.machine.turns.is_current(last.token))
        self.assertIsNone(self.machine.current())
        self.assertFalse(self.machine.turns.is_current(original.token))

    def test_excessive_correction_chain_fails_closed_at_capacity(self):
        first = self.machine.ingest(remote(
            "root", "Explain a query.", start_ms=0, end_ms=100,
        ))
        self.assertEqual(first.state, "ready")
        for i in range(15):
            response = self.machine.ingest(remote(
                f"correction-{i}", f"Make that variant {i}.",
                intent="correction", start_ms=150+i*150,
                end_ms=230+i*150,
            ))
            self.assertEqual(response.state, "ready")
        rejected = self.machine.ingest(remote(
            "correction-too-long", "Make that another variant.",
            intent="correction", start_ms=2500, end_ms=2600,
        ))
        self.assertEqual(rejected.state, "needs_review")
        self.assertEqual(rejected.reason, "correction_chain_too_long")
        self.assertIsNone(self.machine.current())

    def test_follow_up_after_correction_keeps_both_reference_levels(self):
        self.machine.ingest(remote("root", "Explain RANK.", end_ms=200))
        self.machine.ingest(remote(
            "correction", "Actually, compare RANK and ROW_NUMBER on ties.",
            intent="correction", start_ms=250, end_ms=350,
        ))
        result = self.machine.ingest(remote(
            "follow-up", "What if there are duplicates?",
            intent="follow_up", start_ms=400, end_ms=600,
        ))
        self.assertEqual(result.state, "ready")
        self.assertIn("compare RANK and ROW_NUMBER", result.snapshot.prompt)
        self.assertIn("Original question (earlier context only)", result.snapshot.prompt)

    def test_follow_up_retains_earlier_question_as_context_only(self):
        initial = self.machine.ingest(remote(
            "q", "Explain SQL RANK and ROW_NUMBER on salary ties.",
            end_ms=350,
        ))
        follow = self.machine.ingest(remote(
            "f", "What happens if two employees have equal salaries?",
            intent="follow_up", start_ms=400, end_ms=800,
        ))
        self.assertEqual(follow.state, "ready")
        self.assertFalse(self.turns.is_current(initial.token))
        self.assertEqual(follow.token.version, 2)
        self.assertIn("Previous accepted question (context", follow.snapshot.prompt)
        self.assertIn("equal salaries", follow.snapshot.prompt)

    def test_new_independent_question_resets_old_segment_dependencies(self):
        old = self.machine.ingest(remote(
            "old", "Explain a SQL join.", start_ms=0, end_ms=200,
        ))
        newer = self.machine.ingest(remote(
            "new", "Explain database normalization.",
            start_ms=300, end_ms=550,
        ))
        self.assertEqual(newer.state, "ready")
        self.assertEqual(newer.snapshot.dependency_segment_ids, ("new",))
        self.assertNotIn("old", newer.snapshot.dependency_segment_ids)
        self.assertFalse(self.turns.is_current(old.token))
        stale_retraction = self.machine.ingest(remote(
            "old", "", status="retracted", revision=2,
            intent="unknown", start_ms=0, end_ms=650,
        ))
        self.assertEqual(stale_retraction.reason, "superseded_segment_retraction")
        self.assertEqual(self.machine.current().token, newer.token)

    def test_new_question_supersedes_old_without_conflating_context(self):
        old = self.machine.ingest(remote(
            "old", "Explain index selectivity.", end_ms=300,
        ))
        fresh = self.machine.ingest(remote(
            "new", "Explain database normalization.", start_ms=400, end_ms=850,
        ))
        self.assertEqual(fresh.state, "ready")
        self.assertNotEqual(fresh.token.turn_id, old.token.turn_id)
        self.assertEqual(fresh.token.version, 1)
        self.assertNotIn("index selectivity", fresh.snapshot.prompt)
        self.assertFalse(self.turns.is_current(old.token))

    def test_E04_D07_multipart_hints_are_verbatim_not_verified_checklist(self):
        samples = [
            "Explain a hash table, then what happens with collisions, and tell me its worst-case lookup time.",
            "Explain a CTE, compare it with a subquery, then tell me whether a CTE always improves performance.",
        ]
        for i, text in enumerate(samples):
            with self.subTest(index=i):
                result = self.machine.ingest(remote(
                    f"multipart-{i}", text, start_ms=i * 1200,
                    end_ms=(i+1) * 1200,
                ))
                self.assertEqual(result.state, "ready")
                self.assertTrue(result.snapshot.parts_are_heuristic)
                self.assertEqual(len(result.snapshot.parts_hint), 3)
                self.assertEqual(result.snapshot.current_utterance, text)
                for piece in result.snapshot.parts_hint:
                    self.assertIn(piece, text)
                self.assertNotIn("guaranteed", result.snapshot.prompt.lower())

    def test_no_routing_from_partial_mic_unknown_or_unlabeled_remote_text(self):
        for source in ("microphone", "unknown"):
            result = self.machine.ingest(remote(
                "not-interviewer", "Can you tell me about SQL joins?",
                source=source,
            ))
            self.assertEqual(result.state, "ignored")
        undecided = self.machine.ingest(remote(
            "unknown-intent", "The database query needs a join.",
            intent="unknown",
        ))
        self.assertEqual(undecided.state, "ignored")
        self.assertIsNone(self.machine.current())

    def test_orphan_followup_and_fragment_correction_require_review(self):
        orphan = self.machine.ingest(remote(
            "follow", "And what about ties?", intent="follow_up", end_ms=400,
        ))
        self.assertEqual(orphan.state, "needs_review")
        self.assertIsNone(orphan.token)
        fragment = self.machine.ingest(remote(
            "fix", "No, top five by distinct orders in 2025.",
            intent="correction", start_ms=410, end_ms=650,
        ))
        self.assertEqual(fragment.state, "needs_review")
        self.assertIsNone(self.machine.current())

    def test_low_confidence_correction_invalidates_pending_answer(self):
        initial = self.machine.ingest(remote(
            "original", "Explain a SQL join.", end_ms=250
        ))
        low = self.machine.ingest(remote(
            "uncertain", "No, make that a left join",
            intent="correction", confidence=0.2,
            start_ms=300, end_ms=700,
        ))
        self.assertEqual(low.state, "needs_review")
        self.assertEqual(low.reason, "low_asr_confidence")
        self.assertFalse(self.turns.is_current(initial.token))
        self.assertIsNone(self.machine.current())


class TurnSafety(unittest.TestCase):
    def setUp(self):
        self.machine = QuestionTurnMachine()

    def test_duplicate_final_and_older_partial_never_create_new_tokens(self):
        q = remote("q", "Explain WHERE and HAVING.", end_ms=750)
        first = self.machine.ingest(q)
        self.assertEqual(first.state, "ready")
        duplicate = self.machine.ingest(q)
        self.assertEqual(duplicate.state, "ignored")
        self.assertEqual(duplicate.reason, "duplicate_segment")
        old_partial = self.machine.ingest(replace(
            q, revision=0, status="partial", text="Explain WHERE",
        ))
        self.assertEqual(old_partial.state, "ignored")
        self.assertEqual(self.machine.current().token, first.token)

    def test_final_same_revision_can_replace_partial_but_not_another_final(self):
        partial = remote(
            "seg", "Explain a", status="partial", end_ms=100,
        )
        self.assertEqual(self.machine.ingest(partial).state, "pending")
        full = replace(partial, text="Explain a hash table.",
                       status="final", end_ms=350)
        first = self.machine.ingest(full)
        self.assertEqual(first.state, "ready")
        conflict = self.machine.ingest(replace(full, text="Explain a graph."))
        self.assertEqual(conflict.state, "conflict")
        self.assertFalse(self.machine.turns.is_current(first.token))
        self.assertEqual(self.machine.ingest(remote(
            "late", "Explain recursion.", start_ms=400,
            end_ms=500,
        )).reason, "stream_generation_stopped")

    def test_higher_revision_partial_reopens_final_and_cancels_immediately(self):
        original = remote(
            "seg", "Explain a binary tree.", end_ms=300,
        )
        first = self.machine.ingest(original)
        self.assertEqual(first.state, "ready")
        reopened = self.machine.ingest(replace(
            original, revision=2, status="partial",
            text="Explain a binary", end_ms=320,
        ))
        self.assertEqual(reopened.state, "pending")
        self.assertEqual(reopened.reason, "final_reopened_as_partial")
        self.assertFalse(self.machine.turns.is_current(first.token))
        self.assertIsNone(self.machine.current())
        revised = self.machine.ingest(replace(
            original, revision=3, text="Explain a binary search tree.",
            end_ms=470,
        ))
        self.assertEqual(revised.state, "needs_review")
        self.assertEqual(revised.reason, "final_transcript_revised")
        self.assertIsNone(self.machine.current())

    def test_higher_revision_partial_of_superseded_final_is_ignored(self):
        q1 = remote("old", "Explain hash joins.", end_ms=250)
        self.machine.ingest(q1)
        recent = self.machine.ingest(remote(
            "latest", "Explain merge joins.", start_ms=300, end_ms=500,
        ))
        stale_partial = self.machine.ingest(replace(
            q1, revision=2, status="partial",
            text="Explain hash", end_ms=350,
        ))
        self.assertEqual(stale_partial.state, "ignored")
        self.assertEqual(stale_partial.reason, "superseded_segment_revision")
        self.assertEqual(self.machine.current().token, recent.token)

    def test_reopened_final_at_same_timestamp_still_requires_review(self):
        original = remote("same-time", "Explain a hash table.", end_ms=300)
        initial = self.machine.ingest(original)
        self.assertEqual(initial.state, "ready")
        partial = self.machine.ingest(replace(
            original, revision=2, status="partial", text="Explain hash",
        ))
        self.assertEqual(partial.state, "pending")
        self.assertFalse(self.machine.turns.is_current(initial.token))
        revised = self.machine.ingest(replace(
            original, revision=3, text="Explain a hash map.",
        ))
        self.assertEqual(revised.state, "needs_review")
        self.assertEqual(revised.reason, "final_transcript_revised")
        self.assertIsNone(self.machine.current())

    def test_stale_retraction_preserves_reopened_segment_quarantine(self):
        self.machine.ingest(remote(
            "old", "Explain a hash table.",
            start_ms=0, end_ms=200,
        ))
        reopen_target = remote(
            "reopened", "Explain a B-tree.",
            start_ms=300, end_ms=500,
        )
        current = self.machine.ingest(reopen_target)
        self.assertEqual(current.state, "ready")
        reopened = self.machine.ingest(replace(
            reopen_target, revision=2, status="partial",
            text="Explain a B",
        ))
        self.assertEqual(reopened.reason, "final_reopened_as_partial")
        self.assertFalse(self.machine.turns.is_current(current.token))
        self.assertIn("reopened", self.machine._reopened)
        stale = self.machine.ingest(remote(
            "old", "", revision=2, status="retracted",
            intent="unknown", start_ms=0, end_ms=700,
        ))
        self.assertEqual(stale.reason, "superseded_segment_retraction")
        self.assertIn("reopened", self.machine._reopened)
        newest = self.machine.ingest(remote(
            "newest", "Explain a B+ tree.",
            intent="question", start_ms=750, end_ms=1000,
        ))
        self.assertEqual(newest.state, "ready")
        delayed_final = self.machine.ingest(replace(
            reopen_target, revision=3,
            text="Explain a binary search tree.", end_ms=1250,
        ))
        self.assertEqual(delayed_final.reason, "superseded_segment_revision")
        self.assertEqual(self.machine.current().token, newest.token)

    def test_active_final_remains_protected_when_replay_history_fills(self):
        original = remote(
            "active", "Explain a binary search tree.",
            intent="question", start_ms=0, end_ms=300,
        )
        initial = self.machine.ingest(original)
        self.assertEqual(initial.state, "ready")
        for i in range(MAX_SEEN_SEGMENTS + 17):
            statement = self.machine.ingest(remote(
                f"statement-{i}", f"Synthetic statement number {i}.",
                intent="statement", start_ms=400+i*10,
                end_ms=405+i*10,
            ))
            self.assertEqual(statement.state, "ignored")
        self.assertEqual(len(self.machine._seen), MAX_SEEN_SEGMENTS)
        self.assertIn("active", self.machine._seen)
        self.assertEqual(self.machine._seen["active"].status, "final")
        partial = self.machine.ingest(replace(
            original, revision=2, status="partial",
            text="Explain a binary", end_ms=1300,
        ))
        self.assertEqual(partial.state, "pending")
        self.assertEqual(partial.reason, "final_reopened_as_partial")
        self.assertFalse(self.machine.turns.is_current(initial.token))
        revised = self.machine.ingest(replace(
            original, revision=3,
            text="Explain a B+ tree instead.", end_ms=2500,
        ))
        self.assertEqual(revised.state, "needs_review")
        self.assertEqual(revised.reason, "final_transcript_revised")
        self.assertIsNone(self.machine.current())

    def test_retraction_of_evicted_old_segment_cannot_cancel_current(self):
        old = self.machine.ingest(remote(
            "first", "Explain a hash table.",
            start_ms=0, end_ms=200,
        ))
        latest = self.machine.ingest(remote(
            "latest", "Explain a B-tree.",
            start_ms=300, end_ms=500,
        ))
        self.assertFalse(self.machine.turns.is_current(old.token))
        # The replay ledger is intentionally bounded. Evict the old record
        # while maintaining a newer active question.
        for i in range(MAX_SEEN_SEGMENTS - 1):
            result = self.machine.ingest(remote(
                f"statement-{i}", f"Ordinary meeting statement {i}.",
                intent="statement",
                start_ms=600 + i * 10, end_ms=609 + i * 10,
            ))
            self.assertEqual(result.state, "ignored")
        self.assertNotIn("first", self.machine._seen)
        stale = self.machine.ingest(remote(
            "first", "", revision=2, status="retracted",
            intent="unknown", start_ms=0, end_ms=2500,
        ))
        self.assertEqual(stale.state, "ignored")
        self.assertEqual(stale.reason, "superseded_segment_retraction")
        self.assertEqual(self.machine.current().token, latest.token)

    def test_retraction_of_superseded_final_never_cancels_latest_question(self):
        old = self.machine.ingest(remote(
            "old", "Explain recursion.", end_ms=250,
        ))
        latest = self.machine.ingest(remote(
            "new", "Explain binary search.", start_ms=300, end_ms=600,
        ))
        self.assertFalse(self.machine.turns.is_current(old.token))
        late_retract = self.machine.ingest(remote(
            "old", "", revision=2, status="retracted", intent="unknown",
            start_ms=0, end_ms=650,
        ))
        self.assertEqual(late_retract.state, "ignored")
        self.assertEqual(late_retract.reason, "superseded_segment_retraction")
        self.assertEqual(self.machine.current().token, latest.token)

    def test_revision_after_final_requires_review_not_silent_replacement(self):
        q = remote("seg", "Explain a B-tree.", end_ms=300)
        first = self.machine.ingest(q)
        next_version = self.machine.ingest(replace(
            q, revision=2, text="Explain a B+ tree.", end_ms=330,
        ))
        self.assertEqual(next_version.state, "needs_review")
        self.assertEqual(next_version.reason, "final_transcript_revised")
        self.assertFalse(self.machine.turns.is_current(first.token))

    def test_newer_partial_suppresses_older_final_until_newer_final_arrives(self):
        first = self.machine.ingest(remote(
            "partial-A", "Explain hash",
            status="partial", intent="question",
            start_ms=0, end_ms=200,
        ))
        self.assertEqual(first.state, "pending")
        newer = self.machine.ingest(remote(
            "partial-B", "Explain merge",
            status="partial", intent="question",
            start_ms=250, end_ms=350,
        ))
        self.assertEqual(newer.state, "pending")
        late_first = self.machine.ingest(remote(
            "partial-A", "Explain hash joins.",
            status="final", intent="question",
            start_ms=0, end_ms=250,
        ))
        self.assertEqual(late_first.state, "ignored")
        self.assertEqual(late_first.reason, "superseded_by_newer_partial")
        self.assertIsNone(self.machine.current())
        current = self.machine.ingest(remote(
            "partial-B", "Explain merge joins.",
            status="final", intent="question",
            start_ms=250, end_ms=650,
        ))
        self.assertEqual(current.state, "ready")
        self.assertIn("merge joins", current.snapshot.prompt)
        self.assertNotIn("hash joins", current.snapshot.prompt)

    def test_final_overlapping_pending_remote_utterance_requires_review(self):
        self.assertEqual(self.machine.ingest(remote(
            "pending-A", "Explain database",
            status="partial", intent="question",
            start_ms=0, end_ms=300,
        )).state, "pending")
        unclear = self.machine.ingest(remote(
            "overlapping-B", "Explain transaction isolation.",
            status="final", intent="question",
            start_ms=240, end_ms=500,
        ))
        self.assertEqual(unclear.state, "needs_review")
        self.assertEqual(unclear.reason, "overlapping_pending_utterances")
        self.assertIsNone(self.machine.current())

    def test_abandoned_correction_final_cannot_override_newer_complete_question(self):
        self.machine.ingest(remote(
            "root", "List five customers by revenue.",
            start_ms=0, end_ms=100,
        ))
        self.assertEqual(self.machine.ingest(remote(
            "abandoned-correction", "No, list five by",
            intent="correction", status="partial",
            start_ms=150, end_ms=200,
        )).state, "pending")
        latest = self.machine.ingest(remote(
            "new-question", "Explain database indexing.",
            intent="question", status="final",
            start_ms=230, end_ms=420,
        ))
        self.assertEqual(latest.state, "ready")
        # The old correction extends beyond the new complete question.
        # End-time-only ordering would accidentally route it as version 2.
        delayed = self.machine.ingest(remote(
            "abandoned-correction", "No, list five by distinct orders.",
            intent="correction", status="final",
            start_ms=150, end_ms=650,
        ))
        self.assertEqual(delayed.state, "ignored")
        self.assertEqual(delayed.reason, "superseded_source_start")
        self.assertEqual(self.machine.current().token, latest.token)
        self.assertEqual(latest.token.version, 1)
        self.assertNotIn("distinct orders", self.machine.current().prompt)

    def test_abandoned_correction_cannot_revise_its_start_past_new_question(self):
        root = self.machine.ingest(remote(
            "root", "Top five customers by revenue.",
            start_ms=0, end_ms=100,
        ))
        partial = self.machine.ingest(remote(
            "abandoned", "No, top five by",
            intent="correction", status="partial", revision=1,
            start_ms=150, end_ms=200,
        ))
        self.assertEqual(partial.state, "pending")
        latest = self.machine.ingest(remote(
            "replacement", "Explain database indexing.",
            intent="question", start_ms=230, end_ms=430,
        ))
        self.assertEqual(latest.state, "ready")
        # The ASR revised both the start AND end of old correction A.
        # The earliest observed start 150ms, not the revised 460ms,
        # determines whether it can supersede B.
        delayed = self.machine.ingest(remote(
            "abandoned", "No, top five by distinct orders.",
            intent="correction", status="final", revision=2,
            start_ms=460, end_ms=760,
        ))
        self.assertEqual(delayed.state, "ignored")
        self.assertEqual(delayed.reason, "superseded_source_start")
        self.assertEqual(self.machine.current().token, latest.token)
        self.assertFalse(self.machine.turns.is_current(root.token))

    def test_newer_partial_correction_retains_context_after_prior_partial(self):
        original = self.machine.ingest(remote(
            "original", "Explain top five customers by revenue.", end_ms=300,
        ))
        self.machine.ingest(remote(
            "partial-A", "No, top five",
            status="partial", intent="correction",
            start_ms=350, end_ms=450,
        ))
        self.machine.ingest(remote(
            "partial-B", "No, top five by distinct orders",
            status="partial", intent="correction",
            start_ms=500, end_ms=600,
        ))
        late = self.machine.ingest(remote(
            "partial-A", "No, top five by orders.",
            status="final", intent="correction",
            start_ms=350, end_ms=650,
        ))
        self.assertEqual(late.reason, "superseded_by_newer_partial")
        accepted = self.machine.ingest(remote(
            "partial-B", "No, top five by distinct orders in 2025.",
            status="final", intent="correction",
            start_ms=500, end_ms=850,
        ))
        self.assertEqual(accepted.state, "ready")
        self.assertEqual(accepted.token.turn_id, original.token.turn_id)
        self.assertEqual(accepted.token.version, 2)
        self.assertIn("Superseded question", accepted.snapshot.prompt)
        self.assertIn("top five customers by revenue", accepted.snapshot.prompt)

    def test_revised_partial_keeps_first_leading_interval_not_later_interval(self):
        self.machine.ingest(remote(
            "root", "Top five customers by revenue.",
            start_ms=0, end_ms=100,
        ))
        self.assertEqual(self.machine.ingest(remote(
            "older-A", "No, top five",
            status="partial", intent="correction", revision=1,
            start_ms=150, end_ms=200,
        )).state, "pending")
        self.assertEqual(self.machine.ingest(remote(
            "older-A", "No, top five by orders",
            status="partial", intent="correction", revision=2,
            start_ms=300, end_ms=350,
        )).state, "pending")
        self.assertEqual(self.machine._leading_partial,
                         ("older-A", 150, 200))
        newer = self.machine.ingest(remote(
            "newer-B", "Explain database indexing.",
            intent="question", start_ms=230, end_ms=280,
        ))
        self.assertEqual(newer.state, "ready")
        late = self.machine.ingest(remote(
            "older-A", "No, top five by distinct orders.",
            intent="correction", revision=3, status="final",
            start_ms=340, end_ms=600,
        ))
        self.assertEqual(late.state, "ignored")
        self.assertEqual(late.reason, "superseded_source_start")
        self.assertEqual(self.machine.current().token, newer.token)

    def test_old_partial_revisions_cannot_retake_lead(self):
        self.machine.ingest(remote(
            "partial-A", "Write a",
            status="partial", intent="question",
            start_ms=0, end_ms=100,
        ))
        self.machine.ingest(remote(
            "partial-B", "Explain a",
            status="partial", intent="question",
            start_ms=200, end_ms=300,
        ))
        stale = self.machine.ingest(remote(
            "partial-A", "Write a query",
            revision=2, status="partial", intent="question",
            start_ms=0, end_ms=150,
        ))
        self.assertEqual(stale.reason, "superseded_partial_revision")
        final = self.machine.ingest(remote(
            "partial-B", "Explain an index.",
            status="final", intent="question",
            start_ms=200, end_ms=350,
        ))
        self.assertEqual(final.state, "ready")

    def test_stale_final_and_generation_reboot_do_not_restore_old_question(self):
        initial = self.machine.ingest(remote(
            "q", "Explain hash joins.", end_ms=200,
        ))
        newer = self.machine.ingest(remote(
            "g2", "Explain merge joins.", generation=2,
            start_ms=210, end_ms=550,
        ))
        self.assertFalse(self.machine.turns.is_current(initial.token))
        self.assertEqual(newer.state, "ready")
        late = self.machine.ingest(remote(
            "old", "Explain incorrect stale behavior.", generation=1,
            start_ms=300, end_ms=650,
        ))
        self.assertEqual(late.reason, "stale_stream_generation")
        self.assertEqual(self.machine.current().token, newer.token)
        old_time = self.machine.ingest(remote(
            "out-of-order", "Explain another older question.",
            generation=2, start_ms=100, end_ms=500,
        ))
        self.assertEqual(old_time.reason, "late_final_after_newer_utterance")

    def test_old_partial_final_cannot_reactivate_after_newer_question(self):
        first = self.machine.ingest(remote(
            "initial", "Explain indexing.", end_ms=300,
        ))
        self.assertEqual(first.state, "ready")
        self.assertEqual(self.machine.ingest(remote(
            "late-segment", "Explain a",
            status="partial", start_ms=200, end_ms=280,
        )).state, "pending")
        newer = self.machine.ingest(remote(
            "newer", "Explain query optimization.",
            start_ms=400, end_ms=800,
        ))
        self.assertEqual(newer.state, "ready")
        late = self.machine.ingest(remote(
            "late-segment", "Explain a SQL index.",
            intent="question", status="final",
            start_ms=200, end_ms=350,
        ))
        self.assertEqual(late.reason, "late_final_after_newer_utterance")
        self.assertEqual(self.machine.current().token, newer.token)

    def test_revision_of_superseded_question_does_not_preempt_current(self):
        old = self.machine.ingest(remote(
            "old", "Explain database transactions.", end_ms=300,
        ))
        latest = self.machine.ingest(remote(
            "latest", "Explain isolation levels.",
            start_ms=400, end_ms=600,
        ))
        self.assertFalse(self.machine.turns.is_current(old.token))
        revised = self.machine.ingest(remote(
            "old", "Explain transaction isolation with new constraints.",
            revision=2, start_ms=0, end_ms=700,
        ))
        self.assertEqual(revised.reason, "superseded_segment_revision")
        self.assertEqual(self.machine.current().token, latest.token)

    def test_overlapping_remote_final_questions_do_not_assume_same_speaker(self):
        first = self.machine.ingest(remote(
            "interviewer-a", "Explain a hash join.",
            start_ms=0, end_ms=600,
        ))
        overlap = self.machine.ingest(remote(
            "interviewer-unknown", "Explain merge joins instead.",
            intent="question", start_ms=500, end_ms=880,
        ))
        self.assertEqual(overlap.state, "needs_review")
        self.assertEqual(overlap.reason, "overlapping_remote_utterances")
        self.assertFalse(self.machine.turns.is_current(first.token))
        self.assertIsNone(self.machine.current())

    def test_unclassified_remote_final_cancels_previous_answer(self):
        initial = self.machine.ingest(remote(
            "q", "Explain database indexes.", end_ms=350,
        ))
        unclassified = self.machine.ingest(remote(
            "speech", "Actually there may be another requirement.",
            intent="unknown", start_ms=400, end_ms=650,
        ))
        self.assertEqual(unclassified.state, "needs_review")
        self.assertEqual(unclassified.reason, "unclassified_remote_utterance")
        self.assertFalse(self.machine.turns.is_current(initial.token))
        self.assertIsNone(self.machine.current())

    def test_contained_unclassified_final_preempts_active_question(self):
        initial = self.machine.ingest(remote(
            "main-question", "Explain database normalization.",
            start_ms=0, end_ms=1000,
        ))
        self.assertEqual(initial.state, "ready")
        contained = self.machine.ingest(remote(
            "unclassified", "I may need to correct that requirement.",
            intent="unknown", start_ms=500, end_ms=800,
        ))
        self.assertEqual(contained.state, "needs_review")
        self.assertEqual(contained.reason,
                         "unclassified_overlapping_remote_utterance")
        self.assertFalse(self.machine.turns.is_current(initial.token))
        self.assertIsNone(self.machine.current())

    def test_late_unknown_inside_original_root_invalidates_corrected_turn(self):
        root = self.machine.ingest(remote(
            "A", "Explain top customer revenue in 2025.",
            start_ms=0, end_ms=1000,
        ))
        self.assertEqual(root.state, "ready")
        correction = self.machine.ingest(remote(
            "B", "No, use distinct orders instead.",
            intent="correction", start_ms=1100, end_ms=1200,
        ))
        self.assertEqual(correction.state, "ready")
        self.assertEqual(correction.snapshot.dependency_segment_ids, ("A", "B"))
        self.assertEqual(correction.snapshot.dependency_intervals,
                         (("A", 0, 1000), ("B", 1100, 1200)))
        self.assertTrue(self.machine.turns.is_current(correction.token))
        # The unknown final is late relative to B but overlaps source A,
        # which B still quotes and depends on. It must invalidate B.
        unknown = self.machine.ingest(remote(
            "unknown-within-A", "There's another constraint.",
            intent="unknown", start_ms=500, end_ms=800,
        ))
        self.assertEqual(unknown.state, "needs_review")
        self.assertEqual(unknown.reason,
                         "unclassified_overlapping_remote_utterance")
        self.assertFalse(self.machine.turns.is_current(correction.token))
        self.assertIsNone(self.machine.current())

    def test_late_unknown_inside_middle_correction_invalidates_final_chain(self):
        self.assertEqual(self.machine.ingest(remote(
            "A", "Explain SQL joins.", start_ms=0, end_ms=200,
        )).state, "ready")
        self.assertEqual(self.machine.ingest(remote(
            "B", "No, focus on LEFT JOIN and duplicates.",
            intent="correction", start_ms=300, end_ms=400,
        )).state, "ready")
        last = self.machine.ingest(remote(
            "C", "Make that LEFT JOIN and NULL handling.",
            intent="correction", start_ms=500, end_ms=600,
        ))
        self.assertEqual(last.state, "ready")
        self.assertEqual(last.snapshot.dependency_intervals,
                         (("A", 0, 200), ("B", 300, 400), ("C", 500, 600)))
        late = self.machine.ingest(remote(
            "unknown-in-B", "Maybe that's incorrect.",
            intent="unknown", start_ms=325, end_ms=350,
        ))
        self.assertEqual(late.reason,
                         "unclassified_overlapping_remote_utterance")
        self.assertFalse(self.machine.turns.is_current(last.token))
        self.assertIsNone(self.machine.current())

    def test_independent_new_question_does_not_inherit_old_overlap_intervals(self):
        self.assertEqual(self.machine.ingest(remote(
            "A", "Explain an index.", start_ms=0, end_ms=200,
        )).state, "ready")
        independent = self.machine.ingest(remote(
            "B", "Explain a binary heap.", start_ms=300, end_ms=500,
        ))
        self.assertEqual(independent.state, "ready")
        self.assertEqual(independent.snapshot.dependency_intervals,
                         (("B", 300, 500),))
        delayed = self.machine.ingest(remote(
            "late-old", "A vague earlier statement.",
            intent="unknown", start_ms=100, end_ms=150,
        ))
        self.assertEqual(delayed.state, "ignored")
        self.assertEqual(delayed.reason, "late_final_after_newer_utterance")
        self.assertEqual(self.machine.current().token, independent.token)

    def test_late_unknown_during_pending_correction_invalidates_its_context(self):
        original = self.machine.ingest(remote(
            "A", "Explain top five customers by revenue.",
            start_ms=0, end_ms=1000,
        ))
        self.assertEqual(original.state, "ready")
        pending = self.machine.ingest(remote(
            "B", "No, top five by distinct orders",
            status="partial", intent="correction",
            start_ms=1100, end_ms=1200,
        ))
        self.assertEqual(pending.state, "pending")
        self.assertIsNone(self.machine.current())
        self.assertEqual(self.machine._interrupted[1].dependency_intervals,
                         (("A", 0, 1000),))
        late = self.machine.ingest(remote(
            "X", "I may have another requirement.",
            intent="unknown", start_ms=500, end_ms=800,
        ))
        self.assertEqual(late.state, "needs_review")
        self.assertEqual(late.reason, "unclassified_overlapping_remote_utterance")
        self.assertIsNone(self.machine._interrupted)
        self.assertIsNone(self.machine._leading_partial)
        self.assertFalse(self.machine.turns.is_current(original.token))
        attempted = self.machine.ingest(remote(
            "B", "No, top five by distinct orders in 2025.",
            status="final", intent="correction",
            start_ms=1100, end_ms=1300,
        ))
        self.assertEqual(attempted.state, "needs_review")
        self.assertEqual(attempted.reason, "pending_context_retracted")
        self.assertIsNone(self.machine.current())

    def test_revised_root_final_invalidates_current_correction(self):
        original = self.machine.ingest(remote(
            "A", "Explain total revenue by customer.",
            start_ms=0, end_ms=250,
        ))
        correction = self.machine.ingest(remote(
            "B", "No, rank by distinct orders.",
            intent="correction", start_ms=300, end_ms=450,
        ))
        self.assertEqual(correction.state, "ready")
        revision = self.machine.ingest(remote(
            "A", "Explain gross profit instead of revenue.",
            revision=2, start_ms=0, end_ms=275,
        ))
        self.assertEqual(revision.state, "needs_review")
        self.assertEqual(revision.reason, "contributing_final_revised")
        self.assertFalse(self.machine.turns.is_current(correction.token))
        self.assertIsNone(self.machine.current())
        self.assertFalse(self.machine.turns.is_current(original.token))

    def test_conflicting_same_revision_root_final_invalidates_correction(self):
        root = self.machine.ingest(remote(
            "root", "Describe total revenue.",
            revision=1, start_ms=0, end_ms=250,
        ))
        correction = self.machine.ingest(remote(
            "correction", "No, by distinct orders.",
            intent="correction", start_ms=300, end_ms=400,
        ))
        self.assertEqual(correction.state, "ready")
        # A same-ID/same-revision conflicting final cannot bypass the
        # earlier-root dependency gate merely because it is older than B.
        conflicting = self.machine.ingest(remote(
            "root", "Describe average revenue.",
            revision=1, start_ms=0, end_ms=250,
        ))
        self.assertEqual(conflicting.state, "needs_review")
        self.assertEqual(conflicting.reason, "contributing_final_revised")
        self.assertFalse(self.machine.turns.is_current(correction.token))
        self.assertFalse(self.machine.turns.is_current(root.token))
        self.assertIsNone(self.machine.current())

    def test_reopened_root_partial_invalidates_current_correction(self):
        self.machine.ingest(remote(
            "A", "Explain revenue.", start_ms=0, end_ms=200,
        ))
        current = self.machine.ingest(remote(
            "B", "Make that distinct orders.",
            intent="correction", start_ms=250, end_ms=400,
        ))
        reopened = self.machine.ingest(remote(
            "A", "Explain gross",
            status="partial", revision=2,
            start_ms=0, end_ms=150,
        ))
        self.assertEqual(reopened.state, "needs_review")
        self.assertEqual(reopened.reason, "contributing_final_revised")
        self.assertFalse(self.machine.turns.is_current(current.token))
        self.assertIn("A", self.machine._reopened)
        late = self.machine.ingest(remote(
            "A", "Explain gross profit.",
            revision=3, start_ms=0, end_ms=600,
        ))
        self.assertNotEqual(late.state, "ready")
        self.assertIsNone(self.machine.current())

    def test_repeated_partial_of_quarantined_reopened_segment_preserves_new_question(self):
        self.assertEqual(self.machine.ingest(remote(
            "A", "Explain a hash table.", start_ms=0, end_ms=200,
        )).state, "ready")
        opened = self.machine.ingest(remote(
            "A", "Explain a hash", revision=2,
            status="partial", start_ms=0, end_ms=210,
        ))
        self.assertEqual(opened.reason, "final_reopened_as_partial")
        next_question = self.machine.ingest(remote(
            "C", "Explain data normalization.", start_ms=400, end_ms=600,
        ))
        self.assertEqual(next_question.state, "ready")
        # Revised partial A's reported start is now well past C, but the
        # original finalized A was already reopened and quarantined.
        replay = self.machine.ingest(remote(
            "A", "Explain something else", revision=3,
            status="partial", start_ms=800, end_ms=950,
        ))
        self.assertEqual(replay.state, "ignored")
        self.assertEqual(replay.reason, "reopened_segment_quarantined")
        self.assertEqual(self.machine.current().token, next_question.token)
        self.assertTrue(self.machine.turns.is_current(next_question.token))

    def test_partial_history_survives_lru_noise_and_revised_start_cannot_preempt(self):
        old = self.machine.ingest(remote(
            "abandoned-A", "Explain a join",
            status="partial", start_ms=100, end_ms=200,
        ))
        self.assertEqual(old.state, "pending")
        newer = self.machine.ingest(remote(
            "new-B", "Explain a B-tree.",
            start_ms=300, end_ms=450,
        ))
        self.assertEqual(newer.state, "ready")
        for i in range(MAX_SEEN_SEGMENTS + 17):
            ordinary = self.machine.ingest(remote(
                f"ordinary-statement-{i}", f"Ordinary statement {i}.",
                intent="statement", start_ms=600 + i * 10,
                end_ms=609 + i * 10,
            ))
            self.assertEqual(ordinary.state, "ignored")
        self.assertIn("abandoned-A", self.machine._seen)
        self.assertEqual(self.machine._seen["abandoned-A"].status, "partial")
        self.assertEqual(self.machine._seen["abandoned-A"].first_start_ms, 100)
        revised = self.machine.ingest(remote(
            "abandoned-A", "Explain a different join",
            status="partial", revision=2,
            start_ms=5000, end_ms=5100,
        ))
        self.assertEqual(revised.state, "ignored")
        self.assertEqual(revised.reason, "stale_partial_after_newer_question")
        self.assertEqual(self.machine.current().token, newer.token)
        self.assertTrue(self.machine.turns.is_current(newer.token))

    def test_retraction_of_unrelated_reopened_segment_does_not_cancel_new_question(self):
        first = self.machine.ingest(remote(
            "A", "Explain a hash table.", start_ms=0, end_ms=200,
        ))
        self.assertEqual(first.state, "ready")
        reopened = self.machine.ingest(remote(
            "A", "Explain a hash",
            status="partial", revision=2,
            start_ms=0, end_ms=230,
        ))
        self.assertEqual(reopened.reason, "final_reopened_as_partial")
        self.assertIn("A", self.machine._reopened)
        new_question = self.machine.ingest(remote(
            "C", "Explain database normalization.",
            start_ms=400, end_ms=600,
        ))
        self.assertEqual(new_question.state, "ready")
        retract = self.machine.ingest(remote(
            "A", "", status="retracted", intent="unknown",
            revision=3, start_ms=0, end_ms=650,
        ))
        self.assertEqual(retract.state, "ignored")
        self.assertEqual(retract.reason, "superseded_segment_retraction")
        self.assertEqual(self.machine.current().token, new_question.token)
        self.assertTrue(self.machine.turns.is_current(new_question.token))
        self.assertIn("A", self.machine._reopened)

    def test_stale_unseen_partial_cannot_cancel_newer_active_question(self):
        current = self.machine.ingest(remote(
            "B", "Explain binary search.",
            start_ms=1000, end_ms=1200,
        ))
        self.assertEqual(current.state, "ready")
        stale = self.machine.ingest(remote(
            "old-A", "Explain an",
            status="partial", intent="correction",
            start_ms=100, end_ms=200,
        ))
        self.assertEqual(stale.state, "ignored")
        self.assertEqual(stale.reason, "stale_partial_after_newer_question")
        self.assertEqual(self.machine.current().token, current.token)
        self.assertTrue(self.machine.turns.is_current(current.token))
        self.assertIsNone(self.machine._leading_partial)

    def test_discontinuity_cancels_and_blocks_old_generation(self):
        initial = self.machine.ingest(remote(
            "question", "Explain a query plan.", end_ms=300
        ))
        discontinuity = self.machine.ingest(remote(
            "gap", "", status="discontinuity", intent="unknown",
            start_ms=400, end_ms=400,
        ))
        self.assertEqual(discontinuity.state, "cancelled")
        self.assertFalse(self.machine.turns.is_current(initial.token))
        rejected = self.machine.ingest(remote(
            "q2", "Explain an index.", start_ms=500, end_ms=900,
        ))
        self.assertEqual(rejected.reason, "stream_generation_stopped")
        resumed = self.machine.ingest(remote(
            "new", "Explain an index.", generation=2,
            start_ms=1000, end_ms=1400,
        ))
        self.assertEqual(resumed.state, "ready")

    def test_retraction_cancels_without_republishing(self):
        first = self.machine.ingest(remote(
            "q", "Explain an index.", end_ms=300
        ))
        out = self.machine.ingest(remote(
            "q", "", revision=2, status="retracted", intent="unknown",
            start_ms=0, end_ms=400,
        ))
        self.assertEqual(out.state, "cancelled")
        self.assertFalse(self.machine.turns.is_current(first.token))
        self.assertIsNone(self.machine.current())

    def test_retracted_root_invalidates_partial_correction_dependency(self):
        initial = self.machine.ingest(remote(
            "root", "List five customers by revenue.",
            start_ms=0, end_ms=200,
        ))
        partial = self.machine.ingest(remote(
            "pending-correction", "No, list five by",
            intent="correction", status="partial",
            start_ms=220, end_ms=280,
        ))
        self.assertEqual(partial.state, "pending")
        self.assertFalse(self.machine.turns.is_current(initial.token))
        retracted = self.machine.ingest(remote(
            "root", "", revision=2, status="retracted",
            intent="unknown", start_ms=0, end_ms=310,
        ))
        self.assertEqual(retracted.state, "cancelled")
        self.assertEqual(retracted.reason, "transcript_retracted")
        for revision in (1, 2):
            with self.subTest(revision=revision):
                completed = self.machine.ingest(remote(
                    "pending-correction", "No, list five by distinct orders.",
                    intent="correction", status="final", revision=revision,
                    start_ms=220, end_ms=520,
                ))
                self.assertEqual(completed.state, "needs_review")
                self.assertEqual(completed.reason, "pending_context_retracted")
                self.assertIsNone(self.machine.current())
        # A segment-level retraction must not disable the whole stream.
        fresh = self.machine.ingest(remote(
            "new-unrelated", "Explain a database index.",
            intent="question", start_ms=600, end_ms=900,
        ))
        self.assertEqual(fresh.state, "ready")

    def test_retraction_current_question_allows_later_same_generation(self):
        first = self.machine.ingest(remote(
            "first", "Explain query planning.", end_ms=200,
        ))
        retracted = self.machine.ingest(remote(
            "first", "", status="retracted", revision=2,
            intent="unknown", start_ms=0, end_ms=250,
        ))
        self.assertEqual(retracted.state, "cancelled")
        self.assertFalse(self.machine.turns.is_current(first.token))
        subsequent = self.machine.ingest(remote(
            "next", "Explain database normalization.",
            intent="question", start_ms=300, end_ms=650,
        ))
        self.assertEqual(subsequent.state, "ready")

    def test_explicit_stop_blocks_any_generation_until_explicit_resume(self):
        first = self.machine.ingest(remote(
            "old", "Explain arrays.", end_ms=100
        ))
        self.machine.cancel()
        self.assertFalse(self.machine.turns.is_current(first.token))
        for generation in (1, 2, 500):
            with self.subTest(generation=generation):
                blocked = self.machine.ingest(remote(
                    f"blocked-{generation}", "Explain linked lists.",
                    generation=generation, start_ms=1000,
                    end_ms=1500,
                ))
                self.assertEqual(blocked.reason, "stopped_until_explicit_resume")
        self.machine.resume()
        fresh = self.machine.ingest(remote(
            "fresh", "Explain linked lists.",
            generation=501, end_ms=2000,
        ))
        self.assertEqual(fresh.state, "ready")

    def test_bounded_replay_history_never_stores_all_transcripts(self):
        for i in range(MAX_SEEN_SEGMENTS + 28):
            self.machine.ingest(remote(
                f"statement-{i}", f"The meeting stated synthetic value {i}.",
                intent="statement", start_ms=i*100, end_ms=i*100+50,
            ))
        self.assertEqual(len(self.machine._seen), MAX_SEEN_SEGMENTS)
        self.assertTrue(all(not hasattr(item, "text")
                            for item in self.machine._seen.values()))
        self.assertIsNone(self.machine.current())

    def test_unbounded_remote_counter_rejected_before_hash_and_cancels_answer(self):
        # Python accepts arbitrarily large ints, but native wire metadata is
        # UInt64. JSON fingerprinting can throw on 10K-digit values unless
        # validation rejects them before serialization.
        enormous = 1 << 20_000
        for field in ("stream_generation", "revision", "start_ms", "end_ms"):
            with self.subTest(field=field):
                machine = QuestionTurnMachine()
                accepted = machine.ingest(remote(
                    "A", "Explain SQL JOIN grain.", start_ms=0, end_ms=250,
                ))
                self.assertEqual(accepted.state, "ready")
                malformed = replace(remote(
                    "B", "No, use distinct orders.",
                    status="partial", intent="correction",
                    start_ms=300, end_ms=450,
                ), **{field: enormous})
                with self.assertRaises(InvalidTranscript) as error:
                    machine.ingest(malformed)
                self.assertEqual(str(error.exception),
                                 "Invalid revision or timing.")
                self.assertFalse(machine.turns.is_current(accepted.token))
                self.assertIsNone(machine.current())

    def test_invalid_utf8_remote_partial_cancels_old_answer_before_hash(self):
        # Python can hold lone surrogates in str, but UTF-8 hashing cannot.
        # Regression: previously raised UnicodeEncodeError before cancel.
        for field in ("text", "segment_id"):
            with self.subTest(field=field):
                machine = QuestionTurnMachine()
                old = machine.ingest(remote(
                    "root", "Explain an index.", start_ms=0, end_ms=250,
                ))
                self.assertEqual(old.state, "ready")
                malformed = replace(remote(
                    "changed", "No, use a B-tree.",
                    status="partial", intent="correction",
                    start_ms=300, end_ms=440,
                ), **{field: "\ud800"})
                with self.assertRaises(InvalidTranscript) as error:
                    machine.ingest(malformed)
                self.assertEqual(str(error.exception),
                                 "Invalid UTF-8 event text.")
                self.assertFalse(machine.turns.is_current(old.token))
                self.assertIsNone(machine.current())

    def test_invalid_microphone_counter_does_not_cancel_remote_question(self):
        accepted = self.machine.ingest(remote(
            "A", "Explain binary search.", start_ms=0, end_ms=200,
        ))
        self.assertEqual(accepted.state, "ready")
        with self.assertRaises(InvalidTranscript):
            self.machine.ingest(replace(
                remote("mic", "Noise", source="microphone"),
                revision=1 << 20_000,
            ))
        self.assertTrue(self.machine.turns.is_current(accepted.token))
        self.assertEqual(self.machine.current().token, accepted.token)

    def test_invalid_metadata_fails_without_leaking_private_text(self):
        valid = remote("q", "Private synthetic transcript.", end_ms=100)
        cases = [
            replace(valid, source_channel="speaker_1"),
            replace(valid, stream_generation=True),
            replace(valid, revision=-1),
            replace(valid, start_ms=101),
            replace(valid, segment_id=""),
            replace(valid, status="final", text=""),
            replace(valid, status="retracted", text="should not appear"),
            replace(valid, confidence=float("nan")),
            replace(valid, confidence=True),
            replace(valid, text="x" * 1201),
            replace(valid, intent="new personal fact"),
        ]
        for candidate in cases:
            with self.subTest(value=type(candidate).__name__):
                with self.assertRaises(InvalidTranscript) as error:
                    self.machine.ingest(candidate)
                self.assertNotIn("Private synthetic transcript", str(error.exception))
        self.assertIsNone(self.machine.current())


class StreamingQAIntegration(unittest.TestCase):
    def test_corrected_remote_turn_suppresses_prior_completed_qa_publication(self):
        machine = QuestionTurnMachine()
        first = machine.ingest(remote(
            "q", "Explain WHERE and HAVING in SQL.", end_ms=300,
        ))
        self.assertEqual(first.state, "ready")
        answer = "WHERE filters source rows before grouping, while HAVING filters grouped results afterward."
        entries = [
            {"type": "response.output_text.delta", "sequence_number": 1,
             "delta": answer},
            {"type": "response.completed", "sequence_number": 2,
             "response": {"status": "completed"}},
        ]
        def frames():
            for event in entries:
                yield ("event: " + event["type"] + "\n").encode()
                yield ("data: " + json.dumps(event) + "\n").encode()
                yield b"\n"
        result = assess_synthetic_stream(
            frames(), turns=machine.turns, token=first.token,
            context=SyntheticContext("D02", attribution="absent"),
            clock=lambda: 1.0,
        )
        self.assertTrue(result.completed)
        self.assertEqual(result.qa.status, "pass")
        partial = machine.ingest(remote(
            "correct", "Actually, explain HAVING with COUNT.",
            status="partial", intent="correction",
            start_ms=310, end_ms=350,
        ))
        self.assertEqual(partial.state, "pending")
        emitted = []
        presentation = publish_assessment(
            result, turns=machine.turns, on_present=emitted.append, clock=lambda: 1.2,
        )
        self.assertEqual(presentation.state, "suppressed")
        self.assertEqual(emitted, [])
        latest = machine.ingest(remote(
            "correct", "Actually, explain HAVING with COUNT.",
            intent="correction", start_ms=310, end_ms=650,
        ))
        self.assertEqual(latest.state, "ready")
        self.assertEqual(latest.token.version, 2)

    def test_current_uses_exact_shared_active_turns_not_copied_ones(self):
        turns = ActiveTurns()
        machine = QuestionTurnMachine(turns)
        d = machine.ingest(remote("q", "Explain transactions."))
        self.assertIs(machine.turns, turns)
        self.assertTrue(turns.is_current(d.token))
        turns.cancel()
        self.assertIsNone(machine.current())


if __name__ == "__main__":
    unittest.main()
