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

    def test_revision_after_final_requires_review_not_silent_replacement(self):
        q = remote("seg", "Explain a B-tree.", end_ms=300)
        first = self.machine.ingest(q)
        next_version = self.machine.ingest(replace(
            q, revision=2, text="Explain a B+ tree.", end_ms=330,
        ))
        self.assertEqual(next_version.state, "needs_review")
        self.assertEqual(next_version.reason, "final_transcript_revised")
        self.assertFalse(self.machine.turns.is_current(first.token))

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
