"""Synthetic streaming-to-QA tests. No OAuth, network calls or real transcripts."""
from __future__ import annotations

import json
import unittest

from relay_spike.benchmark import BenchmarkError
from relay_spike.streaming_qa import (
    ActiveTurns, ModelPolicy, SyntheticContext, assess_synthetic_stream,
    publish_assessment,
)


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


def frames(clock, rows):
    """Rows are (time, event kind, delta, sequence number)."""
    for time_at, kind, delta, seq in rows:
        clock.now = time_at
        data = {"type": kind, "sequence_number": seq}
        if kind == "response.output_text.delta":
            data["delta"] = delta
        if kind == "response.completed":
            data["response"] = {"status": "completed"}
        if kind == "response.failed":
            data["response"] = {"error": {"code": "test_failure"}}
        yield ("event: " + kind + "\n").encode()
        yield ("data: " + json.dumps(data) + "\n").encode()
        yield b"\n"


def complete(clock, answer):
    return frames(clock, [
        (0.1, "response.output_text.delta", answer, 1),
        (0.4, "response.completed", None, 2),
    ])


def setup(case="D02", attribution="absent", sources=()):
    turns = ActiveTurns()
    token = turns.activate("question-one", 1)
    clock = Clock()
    ctx = SyntheticContext(case, attribution, sources)
    return turns, token, clock, ctx


def run(frames_or_factory, *, case="D02", attribution="absent", sources=()):
    turns, token, clock, ctx = setup(case, attribution, sources)
    lines = frames_or_factory(clock)
    out = assess_synthetic_stream(lines, turns=turns, token=token,
                                  context=ctx, clock=clock)
    return turns, token, clock, out


def deliver(out, turns, clock):
    emitted = []
    sent = publish_assessment(out, turns=turns, on_present=emitted.append,
                              clock=clock)
    return sent, emitted


DIRECT = "WHERE filters source rows before grouping, while HAVING filters grouped results afterward."


class StreamTimingTests(unittest.TestCase):
    def test_first_text_scannable_sentence_completion_and_presentation_differ(self):
        t, key, clock, ctx = setup()
        s = frames(clock, [
            (0.1, "response.output_text.delta", "WHERE filters ", 1),
            (0.28, "response.output_text.delta",
             "source rows before grouping, while HAVING filters grouped results afterward.", 2),
            (0.52, "response.completed", None, 3),
        ])
        out = assess_synthetic_stream(s, turns=t, token=key, context=ctx, clock=clock)
        self.assertTrue(out.completed)
        self.assertEqual((out.first_text_ms, out.first_scannable_candidate_ms,
                          out.completed_ms), (100, 280, 520))
        self.assertEqual(out.qa.status, "pass")
        clock.now = 0.66
        view, events = deliver(out, t, clock)
        self.assertEqual(view.state, "final_unverified")
        self.assertEqual(view.presented_ms, 660)
        self.assertEqual(events, [view])
        self.assertEqual(view.text, DIRECT)
        self.assertIsNone(view.first_useful_verified_ms)
        self.assertFalse(view.review_executed)

    def test_no_complete_sentence_means_no_scannable_timestamp(self):
        t, _, clock, out = run(lambda c: complete(
            c, "WHERE filters rows before grouping and HAVING filters aggregates"))
        self.assertTrue(out.completed)
        self.assertIsNone(out.first_scannable_candidate_ms)

    def test_code_first_never_counts_as_scannable_early_answer(self):
        fenced = chr(96) * 3
        answer = (fenced + "python\nprint('synthetic')\n" + fenced +
                  "\nBinary search uses sorted input, O(log n) time and O(1) space.")
        t, _, clock, out = run(lambda c: complete(c, answer), case="E09")
        self.assertIsNone(out.first_scannable_candidate_ms)
        self.assertEqual(out.qa.status, "pass")
        self.assertIn("code_first_answer_may_be_hard_to_scan", out.qa.warnings)
        view, _ = deliver(out, t, clock)
        self.assertEqual(view.review_candidate, "gpt-6.1-sol")
        self.assertFalse(view.review_executed)

    def test_uncertain_personal_attribution_never_claims_clean_final(self):
        t, _, clock, out = run(lambda c: complete(c, DIRECT),
                               attribution="uncertain")
        self.assertIsNone(out.first_scannable_candidate_ms)
        self.assertEqual(out.qa.status, "needs_revision")
        view, messages = deliver(out, t, clock)
        self.assertEqual(view.state, "needs_revision")
        self.assertIsNone(view.text)
        self.assertEqual(len(messages), 1)


class StreamSafetyTests(unittest.TestCase):
    def test_failed_after_partial_text_is_unavailable_no_partial_presentation(self):
        def failed(c):
            return frames(c, [
                (0.1, "response.output_text.delta", DIRECT, 1),
                (0.3, "response.failed", None, 2),
            ])
        t, _, clock, out = run(failed)
        self.assertFalse(out.completed)
        self.assertEqual(out.error_code, "stream_error")
        self.assertIsNone(out.answer)
        self.assertEqual(out.qa.status, "abstain")
        self.assertIsNone(out.completed_ms)
        view, messages = deliver(out, t, clock)
        self.assertEqual(view.state, "unavailable")
        self.assertIsNone(view.text)
        self.assertEqual(len(messages), 1)

    def test_truncated_and_malformed_streams_fail_closed(self):
        variants = [
            lambda c: frames(c, [
                (0.1, "response.output_text.delta", DIRECT, 1)
            ]),
            lambda c: iter([
                b"event: response.output_text.delta\n", b"data: {broken\n", b"\n"
            ]),
            lambda c: iter([
                b"event: response.output_text.delta\n", b"data: \xff\n", b"\n"
            ]),
        ]
        for source in variants:
            with self.subTest(source=source):
                t, _, clock, out = run(source)
                self.assertFalse(out.completed)
                self.assertIsNone(out.answer)
                self.assertEqual(out.qa.status, "abstain")
                view, _ = deliver(out, t, clock)
                self.assertEqual(view.state, "unavailable")
                self.assertIsNone(view.text)

    def test_replayed_sequenced_event_deduplicates_and_late_delta_ignored(self):
        def duplicated(c):
            return frames(c, [
                (0.1, "response.output_text.delta", DIRECT, 1),
                (0.2, "response.output_text.delta", DIRECT, 1),
                (0.3, "response.completed", None, 2),
                (0.5, "response.output_text.delta", "SHOULD_NOT_APPEAR", 3),
            ])
        t, _, clock, out = run(duplicated)
        self.assertTrue(out.completed)
        self.assertEqual(out.answer, DIRECT)
        self.assertEqual(out.completed_ms, 300)
        view, _ = deliver(out, t, clock)
        self.assertEqual(view.state, "final_unverified")
        self.assertNotIn("SHOULD_NOT_APPEAR", view.text)

    def test_terminal_completion_requires_explicit_status_object(self):
        for payload in ({}, {"status": "incomplete"}, None, [], "completed"):
            with self.subTest(response=payload):
                def malformed(clock):
                    yield from frames(clock, [
                        (0.1, "response.output_text.delta", DIRECT, 1)
                    ])
                    clock.now = 0.4
                    yield b"event: response.completed\n"
                    yield ("data: " + json.dumps({
                        "type": "response.completed", "response": payload,
                        "sequence_number": 2,
                    }) + "\n").encode()
                    yield b"\n"
                t, _, clock, out = run(malformed)
                self.assertFalse(out.completed)
                self.assertEqual(out.error_code, "stream_error")
                view, shown = deliver(out, t, clock)
                self.assertEqual(view.state, "unavailable")
                self.assertIsNone(view.text)
                self.assertEqual(len(shown), 1)

    def test_nonadjacent_old_sse_sequence_rejected_not_replayed(self):
        def out_of_order(clock):
            return frames(clock, [
                (0.1, "response.output_text.delta", "Partial ", 1),
                (0.2, "response.created", None, 2),
                (0.3, "response.output_text.delta", "Partial ", 1),
                (0.5, "response.completed", None, 3),
            ])
        t, _, clock, out = run(out_of_order)
        self.assertFalse(out.completed)
        self.assertEqual(out.error_code, "stream_error")

    def test_conflicting_sequence_replay_aborts(self):
        t, _, clock, out = run(lambda c: frames(c, [
            (0.1, "response.output_text.delta", "first", 1),
            (0.2, "response.output_text.delta", "conflict", 1),
            (0.4, "response.completed", None, 2),
        ]))
        self.assertFalse(out.completed)
        self.assertEqual(out.error_code, "stream_error")

    def test_supersession_during_stream_aborts_and_suppresses(self):
        t, key, clock, ctx = setup()
        def generator():
            yield from frames(clock, [
                (0.1, "response.output_text.delta", "Partial text.", 1)
            ])
            t.activate("new-interview-question", 1)
            yield from frames(clock, [(0.5, "response.completed", None, 2)])
        out = assess_synthetic_stream(generator(), turns=t, token=key,
                                      context=ctx, clock=clock)
        self.assertFalse(out.completed)
        self.assertEqual(out.error_code, "superseded_turn")
        view, shown = deliver(out, t, clock)
        self.assertEqual(view.state, "suppressed")
        self.assertEqual(shown, [])

    def test_stale_after_qa_before_presentation_never_calls_callback(self):
        t, key, clock, ctx = setup()
        out = assess_synthetic_stream(complete(clock, DIRECT), turns=t,
                                      token=key, context=ctx, clock=clock)
        self.assertEqual(out.qa.status, "pass")
        t.activate("another-turn", 1)  # same version, new ID
        view, shown = deliver(out, t, clock)
        self.assertEqual(view.state, "suppressed")
        self.assertEqual(shown, [])

    def test_aba_same_id_and_version_reactivation_also_suppressed(self):
        t, key, clock, ctx = setup()
        out = assess_synthetic_stream(complete(clock, DIRECT), turns=t,
                                      token=key, context=ctx, clock=clock)
        t.activate("question-one", 1)
        view, shown = deliver(out, t, clock)
        self.assertEqual((view.state, shown), ("suppressed", []))

    def test_cancel_during_stream_suppresses_without_new_turn(self):
        t, key, clock, ctx = setup()
        def aborting():
            yield from frames(clock, [
                (0.1, "response.output_text.delta", "Unfinished answer.", 1)
            ])
            t.cancel()
            yield from frames(clock, [(0.5, "response.completed", None, 2)])
        out = assess_synthetic_stream(aborting(), turns=t, token=key,
                                      context=ctx, clock=clock)
        self.assertEqual(out.error_code, "superseded_turn")
        view, shown = deliver(out, t, clock)
        self.assertEqual(view.state, "suppressed")
        self.assertEqual(shown, [])

    def test_oversized_synthetic_stream_aborts_without_answer(self):
        t, _, clock, out = run(lambda c: complete(c, "word " * 4000))
        self.assertFalse(out.completed)
        self.assertEqual(out.error_code, "stream_error")
        view, _ = deliver(out, t, clock)
        self.assertEqual(view.state, "unavailable")
        self.assertIsNone(view.text)

    def test_stale_at_start_does_not_even_iterate_stream(self):
        t, key, clock, ctx = setup()
        t.activate("new-question", 1)
        def should_not_read():
            raise AssertionError("Stale source should never be read")
            yield b""
        out = assess_synthetic_stream(should_not_read(), turns=t, token=key,
                                      context=ctx, clock=clock)
        self.assertEqual(out.error_code, "superseded_turn")
        self.assertIsNone(out.qa)


class FixtureAndPolicyTests(unittest.TestCase):
    def test_unverified_personal_responses_never_display_raw_text(self):
        for case in ("E07", "E08", "E13", "D08", "D11"):
            with self.subTest(case=case):
                t, _, clock, out = run(lambda c: complete(
                    c, "I built the entire stack and shipped the system."),
                    case=case)
                self.assertEqual(out.qa.status, "abstain")
                self.assertIsNone(out.first_scannable_candidate_ms)
                view, shown = deliver(out, t, clock)
                self.assertEqual(view.state, "unavailable")
                self.assertIsNone(view.text)
                self.assertEqual(len(shown), 1)

    def test_source_pointer_does_not_certify_personal_claim(self):
        t, _, clock, out = run(lambda c: complete(
            c, "I worked on the client backend and designed architecture."),
            case="E08", sources=("source-1",))
        self.assertEqual(out.qa.status, "needs_revision")
        view, _ = deliver(out, t, clock)
        self.assertEqual(view.state, "needs_revision")
        self.assertIsNone(view.text)

    def test_first_person_work_claim_inside_sql_fails_closed(self):
        t, _, clock, out = run(lambda c: complete(
            c, "A join duplicates revenue. I built the reporting stack."),
            case="D01")
        self.assertEqual(out.qa.status, "abstain")
        view, _ = deliver(out, t, clock)
        self.assertIsNone(view.text)

    def test_multipart_markers_are_conservative_and_non_authoritative(self):
        for case, answer, missing in (
            ("E04", "A hash table stores keys and handles collisions.", "worst_case"),
            ("D07", "A CTE is a named subquery using WITH.", "performance"),
        ):
            with self.subTest(case=case):
                t, _, clock, out = run(lambda c: complete(c, answer), case=case)
                self.assertEqual(out.qa.status, "needs_revision")
                self.assertIn(missing, out.qa.missing_coverage_indicators)
                view, _ = deliver(out, t, clock)
                self.assertEqual(view.state, "needs_revision")
                self.assertEqual(view.review_candidate, "gpt-6.1-sol")
                self.assertFalse(view.review_executed)

    def test_interruption_synthetic_fixture_requires_real_turn_confirmation(self):
        for case in ("E11", "D12"):
            with self.subTest(case=case):
                t, _, clock, out = run(lambda c: complete(
                    c, "Respond to the updated interviewer request."),
                    case=case)
                self.assertEqual(out.qa.status, "needs_revision")
                self.assertIn("turn_interruption_needs_state_confirmation",
                              out.qa.reasons)
                view, _ = deliver(out, t, clock)
                self.assertEqual(view.state, "needs_revision")

    def test_technical_case_risks_recommend_but_never_call_sol(self):
        for case in ("D01", "D13", "E09"):
            with self.subTest(case=case):
                t, _, clock, out = run(lambda c: complete(
                    c, "The answer involves careful assumptions and edge cases."),
                    case=case)
                self.assertTrue(out.qa.second_review_recommended)
                view, _ = deliver(out, t, clock)
                self.assertEqual(view.review_candidate, "gpt-6.1-sol")
                self.assertFalse(view.review_executed)

    def test_model_policy_is_editable_without_auto_routing(self):
        policy = ModelPolicy()
        self.assertEqual(policy.choose(), "gpt-6-luna")
        self.assertEqual(policy.choose("gpt-6.1-sol"), "gpt-6.1-sol")
        self.assertEqual(ModelPolicy(preferred_model="gpt-6.1-sol").choose(),
                         "gpt-6.1-sol")
        self.assertEqual(policy.requested_effort, "default")
        with self.assertRaises(ValueError):
            ModelPolicy(preferred_model="gpt-6-astra")
        with self.assertRaises(ValueError):
            ModelPolicy(requested_effort="high")
        with self.assertRaises(ValueError):
            policy.choose("unknown")

    def test_unknown_fixture_and_invalid_turn_values_rejected(self):
        t, key, clock, ctx = setup()
        with self.assertRaises(BenchmarkError):
            assess_synthetic_stream(complete(clock, "test"), turns=t,
                token=key, context=SyntheticContext("UNKNOWN"), clock=clock)
        with self.assertRaises(ValueError):
            t.activate("", 1)
        with self.assertRaises(ValueError):
            t.activate("turn", True)


if __name__ == "__main__":
    unittest.main()
