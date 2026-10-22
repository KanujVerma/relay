"""B3A-1: opt-in post-completion technical cards, mocked OAuth/SSE only."""
from __future__ import annotations

from contextlib import contextmanager, redirect_stdout
from io import StringIO
from types import SimpleNamespace
import json
import unittest
from unittest.mock import patch

from relay_spike.__main__ import main
from relay_spike.live_qa import run_live_synthetic_case, APPROVED_SMOKE_ANSWERS
from relay_spike.streaming_qa import ActiveTurns
from relay_spike.technical_gate import _SAFE_RENDER, load_fixture_rows


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


def event_lines(kind, payload):
    return [
        ("event: " + kind + "\n").encode(),
        ("data: " + json.dumps(payload) + "\n").encode(),
        b"\n",
    ]


def fixture(candidate_id):
    return next(x for x in load_fixture_rows() if x["id"] == candidate_id)["candidate"]


def events(answer, *, complete=True):
    result = event_lines("response.output_text.delta", {
        "type": "response.output_text.delta",
        "sequence_number": 1, "delta": answer
    })
    if complete:
        result += event_lines("response.completed", {
            "type": "response.completed", "sequence_number": 2,
            "response": {"status": "completed"}
        })
    return result


def fake_source(clock, lines, requests, *, turn_change=None):
    @contextmanager
    def source(token, model, question, **kwargs):
        requests.append({"model": model, "question": question, "token_was_present": bool(token)})
        def it():
            clock.now = 0.13
            for index, line in enumerate(lines):
                if index == 3:
                    clock.now = 0.40
                    if turn_change:
                        turn_change()
                yield line
        yield it()
    return source


class FakeHTTPResponse:
    def __init__(self, lines):
        self.lines = iter(lines)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def readline(self):
        return next(self.lines, b"")


class TechnicalCardRuntimeTests(unittest.TestCase):
    def test_sql_paraphrase_publishes_only_reviewed_card_after_completion(self):
        clock, requests, shown = Clock(), [], []
        candidate = fixture("D02-P02")
        @contextmanager
        def source(token, model, question, **kwargs):
            requests.append(1)
            def lines():
                clock.now = 0.1
                for row in event_lines("response.output_text.delta", {
                    "type": "response.output_text.delta", "delta": candidate,
                    "sequence_number": 1
                }):
                    yield row
                self.assertEqual(shown, [])  # Not displayed before completion.
                clock.now = 0.42
                yield from event_lines("response.completed", {
                    "type": "response.completed", "sequence_number": 2,
                    "response": {"status": "completed"}
                })
            yield lines()
        out = run_live_synthetic_case(
            "mock-token", case_id="D02", model="gpt-6-luna",
            technical_card=True, clock=clock,
            response_stream=source, on_present=shown.append,
        )
        self.assertEqual(out.presentation.state, "final_unverified")
        self.assertEqual(out.technical_gate_reason, "reviewed_synthetic_card")
        self.assertEqual(out.assessment.qa.status, "pass")
        self.assertEqual(out.assessment.answer, _SAFE_RENDER["D02"])
        self.assertEqual(out.presentation.text, _SAFE_RENDER["D02"])
        self.assertNotEqual(out.presentation.text, candidate)
        self.assertIsNone(out.presentation.first_useful_verified_ms)
        self.assertEqual(out.assessment.first_text_ms, 100)
        self.assertGreaterEqual(out.assessment.completed_ms, 420)
        self.assertEqual(shown, [out.presentation])
        self.assertEqual(len(requests), 1)

    def test_coding_paraphrase_publishes_static_card_and_review_is_advisory(self):
        clock, requests, shown = Clock(), [], []
        source = fake_source(clock, events(fixture("E09-P03")), requests)
        out = run_live_synthetic_case(
            "mock-token", case_id="E09", model="gpt-6-luna",
            technical_card=True, clock=clock, on_present=shown.append,
            response_stream=source,
        )
        self.assertTrue(out.assessment.qa.second_review_recommended)
        self.assertEqual(out.presentation.review_candidate, "gpt-6.1-sol")
        self.assertFalse(out.presentation.review_executed)
        self.assertEqual(out.presentation.state, "final_unverified")
        self.assertEqual(out.presentation.text, _SAFE_RENDER["E09"])
        self.assertEqual(out.technical_gate_reason, "reviewed_synthetic_card")
        self.assertEqual(len(requests), 1)

    def test_unsafe_personal_and_unreviewed_technical_text_never_leaks(self):
        for row_id in ("D02-N01", "D02-N02", "D02-N04", "E09-N04", "E09-N13"):
            with self.subTest(row_id=row_id):
                case_id = row_id.split("-")[0]
                clock, requests, shown = Clock(), [], []
                original = fixture(row_id)
                out = run_live_synthetic_case(
                    "mock-token", case_id=case_id, model="gpt-6-luna",
                    technical_card=True, clock=clock, on_present=shown.append,
                    response_stream=fake_source(clock, events(original), requests),
                )
                self.assertFalse(out.assessment.qa.status == "pass")
                self.assertIsNone(out.assessment.answer)
                self.assertIsNone(out.presentation.text)
                self.assertIn(out.presentation.state, ("unavailable", "needs_revision"))
                self.assertTrue(out.technical_gate_reason)
                self.assertNotIn(original, repr(out))
                self.assertNotIn(original, repr(out.presentation))
                self.assertEqual(len(requests), 1)
                self.assertTrue(all(envelope.text is None for envelope in shown))

    def test_completed_but_unknown_paraphrase_is_withheld(self):
        clock, requests, shown = Clock(), [], []
        sample = (
            "WHERE limits rows before grouping; HAVING limits grouped results after aggregation."
            " This line is novel."
        )
        out = run_live_synthetic_case(
            "mock-token", case_id="D02", model="gpt-6-luna",
            technical_card=True, clock=clock, on_present=shown.append,
            response_stream=fake_source(clock, events(sample), requests),
        )
        self.assertIsNone(out.assessment.answer)
        self.assertIsNone(out.presentation.text)
        self.assertIn("technical_candidate_not_reviewed", out.assessment.qa.reasons)
        self.assertEqual(len(requests), 1)

    def test_failed_incomplete_and_malformed_terminal_do_not_publish(self):
        base = fixture("D02-P01")
        responses = (
            events(base, complete=False),
            events(base, complete=False) + event_lines("response.failed", {
                "type": "response.failed", "response": {"error": {"code": "test_limit"}}
            }),
            events(base, complete=False) + event_lines("response.completed", {
                "type": "response.completed",
                "response": {"status": "incomplete"}
            }),
            event_lines("response.output_text.delta", {
                "type": "response.output_text.delta", "delta": "z" * 16_385
            }),
        )
        for data in responses:
            with self.subTest(length=len(data)):
                clock, requests, shown = Clock(), [], []
                out = run_live_synthetic_case(
                    "mock-token", case_id="D02", model="gpt-6-luna",
                    technical_card=True, clock=clock, on_present=shown.append,
                    response_stream=fake_source(clock, data, requests),
                )
                self.assertIsNone(out.assessment.answer)
                self.assertFalse(out.assessment.completed)
                self.assertEqual(out.presentation.state, "unavailable")
                self.assertTrue(all(e.text is None for e in shown))

    def test_adjacent_identical_sse_replay_fails_closed_only_in_new_mode(self):
        candidate = fixture("D02-P01")
        first = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta",
            "sequence_number": 1, "delta": candidate,
        })
        finish = event_lines("response.completed", {
            "type": "response.completed", "sequence_number": 2,
            "response": {"status": "completed"},
        })
        clock, requests, shown = Clock(), [], []
        out = run_live_synthetic_case(
            "mock-token", case_id="D02", model="gpt-6-luna",
            technical_card=True, clock=clock, on_present=shown.append,
            response_stream=fake_source(clock, first + first + finish, requests),
        )
        self.assertEqual(out.technical_gate_reason, "incomplete_or_failed_stream")
        self.assertFalse(out.assessment.completed)
        self.assertEqual(out.presentation.state, "unavailable")
        self.assertIsNone(out.assessment.answer)
        self.assertIsNone(out.presentation.text)
        self.assertTrue(all(item.text is None for item in shown))
        self.assertEqual(len(requests), 1)

    def test_strict_mode_rejects_unnumbered_or_replayed_sse_frames(self):
        # Even identical unnumbered whitespace frames can alter raw SSE while
        # still normalizing to a syntactically approved technical answer.
        # Requiring explicit sequence numbers prevents that invisible replay.
        candidate = fixture("D02-P01")
        first = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta",
            "sequence_number": 1,
            "delta": "WHERE filters individual rows before grouping.",
        })
        space = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta",
            "delta": " ",
        })
        remaining = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta",
            "sequence_number": 2,
            "delta": "HAVING filters aggregated groups after grouping.",
        })
        complete = event_lines("response.completed", {
            "type": "response.completed",
            "sequence_number": 3,
            "response": {"status": "completed"},
        })
        unsequenced_delta = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta",
            "delta": candidate,
        })
        no_number_completion = event_lines("response.completed", {
            "type": "response.completed",
            "response": {"status": "completed"},
        })
        for frames in (
            first + space + space + remaining + complete,
            unsequenced_delta + complete,
            events(candidate, complete=False) + no_number_completion,
        ):
            with self.subTest(frames=len(frames)):
                clock, requests, shown = Clock(), [], []
                out = run_live_synthetic_case(
                    "mock-token", case_id="D02", model="gpt-6-luna",
                    technical_card=True, clock=clock, on_present=shown.append,
                    response_stream=fake_source(clock, frames, requests),
                )
                self.assertFalse(out.assessment.completed)
                self.assertEqual(out.presentation.state, "unavailable")
                self.assertEqual(out.technical_gate_reason, "incomplete_or_failed_stream")
                self.assertIsNone(out.assessment.answer)
                self.assertIsNone(out.presentation.text)
                self.assertEqual(len(requests), 1)
                self.assertTrue(all(view.text is None for view in shown))
                self.assertNotIn(candidate, repr(out))

    def test_interrupted_turn_still_cannot_display_stale_canonical_card(self):
        clock, requests, shown = Clock(), [], []
        turns = ActiveTurns()
        token = turns.activate("old-question", 1)
        out = run_live_synthetic_case(
            "mock-token", case_id="D02", model="gpt-6-luna",
            technical_card=True, clock=clock, turns=turns, token=token,
            on_present=shown.append,
            response_stream=fake_source(
                clock, events(fixture("D02-P01")), requests,
                turn_change=lambda: turns.activate("new-question", 2),
            ),
        )
        self.assertEqual(out.presentation.state, "suppressed")
        self.assertIsNone(out.presentation.text)
        self.assertIsNone(out.assessment.answer)
        self.assertEqual(shown, [])
        self.assertEqual(len(requests), 1)

    def test_failed_candidate_gate_is_safe_and_does_not_raise_raw_text(self):
        clock, requests, shown = Clock(), [], []
        with patch("relay_spike.live_qa.review_technical_candidate",
                   side_effect=RuntimeError("arbitrary untrusted response")):
            out = run_live_synthetic_case(
                "mock-token", case_id="D02", model="gpt-6-luna",
                technical_card=True, clock=clock, on_present=shown.append,
                response_stream=fake_source(
                    clock, events(fixture("D02-P01")), requests,
                ),
            )
        self.assertEqual(out.technical_gate_reason, "candidate_gate_failed_closed")
        self.assertNotIn("arbitrary untrusted", repr(out))
        self.assertIsNone(out.assessment.answer)
        self.assertIsNone(out.presentation.text)
        self.assertEqual(len(requests), 1)

    def test_untrusted_verdict_fields_never_publish_or_escape(self):
        candidate = fixture("D02-P02")
        examples = (
            SimpleNamespace(
                case_id="D02", publishable=True, rendered_text=candidate,
                reason="reviewed_synthetic_card",
            ),
            SimpleNamespace(
                case_id="E09", publishable=True, rendered_text=_SAFE_RENDER["D02"],
                reason="reviewed_synthetic_card",
            ),
            SimpleNamespace(
                case_id="D02", publishable=True, rendered_text=_SAFE_RENDER["D02"],
                reason="I built a private dashboard",
            ),
            SimpleNamespace(
                case_id="D02", publishable=False, rendered_text=None,
                reason="SENSITIVE_PRIVATE_VERDICT_REASON",
            ),
            SimpleNamespace(
                case_id="D02", publishable=True,
                rendered_text="SENSITIVE_PRIVATE_CANDIDATE",
                reason="SENSITIVE_PRIVATE_VERDICT_REASON",
            ),
            SimpleNamespace(
                case_id="D02", publishable=True, rendered_text=_SAFE_RENDER["D02"],
                reason="reviewed_synthetic_card",
            ),  # Not an actual validated TechnicalVerdict.
        )
        for forged in examples:
            with self.subTest(reason=str(forged.reason)[:30]):
                clock, calls, shown = Clock(), [], []
                with patch("relay_spike.live_qa.review_technical_candidate",
                           return_value=forged):
                    out = run_live_synthetic_case(
                        "mock-token", case_id="D02", model="gpt-6-luna",
                        technical_card=True, clock=clock,
                        on_present=shown.append,
                        response_stream=fake_source(clock, events(candidate), calls),
                    )
                self.assertEqual(out.technical_gate_reason, "candidate_not_approved")
                self.assertIsNone(out.assessment.answer)
                self.assertIsNone(out.presentation.text)
                self.assertNotEqual(out.assessment.qa.status, "pass")
                self.assertEqual(out.presentation.state, "needs_revision")
                self.assertEqual(len(calls), 1)
                self.assertTrue(all(item.text is None for item in shown))
                for forbidden in (
                    "SENSITIVE_PRIVATE_VERDICT_REASON",
                    "SENSITIVE_PRIVATE_CANDIDATE",
                    "I built a private dashboard",
                ):
                    self.assertNotIn(forbidden, repr(out))

    def test_forged_same_type_verdict_cannot_bypass_post_init_validation(self):
        from relay_spike.technical_gate import TechnicalVerdict
        # Corrupt the frozen dataclass without running its guard, simulating
        # a compromised classifier/renderer integration boundary.
        forged = object.__new__(TechnicalVerdict)
        object.__setattr__(forged, "case_id", "D02")
        object.__setattr__(forged, "publishable", True)
        object.__setattr__(forged, "rendered_text", "UNTRUSTED_WORK_EXPERIENCE")
        object.__setattr__(forged, "reason", "reviewed_synthetic_card")
        clock, calls, shown = Clock(), [], []
        with patch("relay_spike.live_qa.review_technical_candidate",
                   return_value=forged):
            out = run_live_synthetic_case(
                "mock-token", case_id="D02", model="gpt-6-luna",
                technical_card=True, clock=clock, on_present=shown.append,
                response_stream=fake_source(clock, events(fixture("D02-P02")), calls),
            )
        self.assertEqual(out.technical_gate_reason, "candidate_not_approved")
        self.assertNotIn("UNTRUSTED_WORK_EXPERIENCE", repr(out))
        self.assertIsNone(out.assessment.answer)
        self.assertIsNone(out.presentation.text)
        self.assertTrue(all(view.text is None for view in shown))
        self.assertEqual(len(calls), 1)

    def test_default_old_b2_smoke_mode_remains_unchanged(self):
        clock, requests, shown = Clock(), [], []
        candidate = sorted(APPROVED_SMOKE_ANSWERS["D02"])[0]
        out = run_live_synthetic_case(
            "mock-token", case_id="D02", model="gpt-6-luna",
            on_present=shown.append, clock=clock,
            response_stream=fake_source(clock, events(candidate), requests),
        )
        self.assertIsNone(out.technical_gate_reason)
        self.assertEqual(out.presentation.state, "final_unverified")
        self.assertEqual(out.presentation.text, candidate)
        self.assertEqual(len(requests), 1)

    def test_cli_dry_run_requires_no_auth_and_is_explicit(self):
        result = StringIO()
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("unexpected auth")), \
             patch("relay_spike.__main__.request_json",
                   side_effect=AssertionError("unexpected model catalog")), \
             patch("relay_spike.__main__.run_live_synthetic_case",
                   side_effect=AssertionError("unexpected inference")), \
             redirect_stdout(result):
            code = main(["live-qa", "--case", "D02", "--technical-card"])
        self.assertEqual(code, 0)
        report = json.loads(result.getvalue())
        self.assertTrue(report["technical_card"])
        self.assertTrue(report["dry_run"])
        self.assertEqual(report["requests_if_executed"], 1)

    def test_cli_execute_posts_exactly_one_request_and_redacts_raw_answer(self):
        candidate = fixture("D02-P02")
        catalog = {"models": [
            {"slug": "gpt-6-luna", "visibility": "list", "display_name": "Luna"}
        ]}
        output = StringIO()
        with patch("relay_spike.__main__.active_access_token",
                   return_value="synthetic-plan-credential"), \
             patch("relay_spike.__main__.request_json", return_value=catalog), \
             patch("relay_spike.stream.urlopen",
                   return_value=FakeHTTPResponse(events(candidate))) as requests, \
             redirect_stdout(output):
            code = main(["live-qa", "--technical-card", "--execute", "--case", "D02"])
        self.assertEqual(code, 0)
        self.assertEqual(requests.call_count, 1)
        report = json.loads(output.getvalue())
        self.assertEqual(report["state"], "final_unverified")
        self.assertEqual(report["answer"], _SAFE_RENDER["D02"])
        self.assertEqual(report["technical_gate_reason"], "reviewed_synthetic_card")
        self.assertEqual(report["qa_status"], "pass")
        self.assertFalse(report["second_review_executed"])
        self.assertIsNone(report["first_useful_verified_ms"])
        self.assertNotIn(candidate, output.getvalue())
        self.assertNotIn("synthetic-plan-credential", output.getvalue())

    def test_cli_completed_rejected_text_reports_status_without_leak(self):
        unsafe = fixture("D02-N01")
        catalog = {"models": [
            {"slug": "gpt-6-luna", "visibility": "list"}
        ]}
        output = StringIO()
        with patch("relay_spike.__main__.active_access_token", return_value="token"), \
             patch("relay_spike.__main__.request_json", return_value=catalog), \
             patch("relay_spike.stream.urlopen",
                   return_value=FakeHTTPResponse(events(unsafe))) as requests, \
             redirect_stdout(output):
            code = main(["live-qa", "--technical-card", "--execute"])
        self.assertEqual(code, 2)
        self.assertEqual(requests.call_count, 1)
        data = json.loads(output.getvalue())
        self.assertEqual(data["requests_executed"], 1)
        self.assertIsNone(data["answer"])
        self.assertNotEqual(data["qa_status"], "pass")
        self.assertNotIn("Riley", output.getvalue())


if __name__ == "__main__":
    unittest.main()
