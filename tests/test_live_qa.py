"""Offline tests for the one-request OAuth-to-QA synthetic bridge.

Everything that looks like inference or authorization is mocked. This file
never reads a user's credentials, contacts a remote service or uses plan quota.
"""
from __future__ import annotations

from contextlib import contextmanager, redirect_stderr, redirect_stdout
from io import StringIO
import json
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from relay_spike import stream
from relay_spike.__main__ import main
from relay_spike.live_qa import (
    run_live_synthetic_case, synthetic_nonpersonal_classification,
    validate_live_case,
)
from relay_spike.streaming_qa import ActiveTurns, SyntheticContext, assess_synthetic_stream


DIRECT = (
    "WHERE filters input rows before grouping, while HAVING filters "
    "aggregated groups after grouping."
)
PERSONAL = "I built a Power BI dashboard for the team and managed its entire backend."
CODING = (
    "Binary search halves the sorted search range with each comparison, "
    "using logarithmic time and constant auxiliary space."
)


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


def completed_lines(answer=DIRECT):
    return (
        event_lines("response.output_text.delta", {
            "type": "response.output_text.delta",
            "sequence_number": 1, "delta": answer,
        })
        + event_lines("response.completed", {
            "type": "response.completed", "sequence_number": 2,
            "response": {"status": "completed"},
        })
    )


def timed_lines(clock, rows):
    for when, kind, data in rows:
        clock.now = when
        yield from event_lines(kind, data)


def source_for(clock, rows, calls):
    @contextmanager
    def fake_source(access_token, model, question, **kwargs):
        calls.append((access_token, model, question, kwargs))
        clock.now = 0.05  # Simulate latency opening the HTTPS stream.
        yield timed_lines(clock, rows)
    return fake_source


def response_rows(answer=DIRECT, *, completed=True):
    out = [
        (0.20, "response.output_text.delta", {
            "type": "response.output_text.delta",
            "sequence_number": 1, "delta": answer,
        }),
    ]
    if completed:
        out.append((0.50, "response.completed", {
            "type": "response.completed",
            "sequence_number": 2, "response": {"status": "completed"},
        }))
    return out


class FakeHTTPResponse:
    def __init__(self, lines):
        self.lines = iter(lines)

    def __enter__(self):
        return self

    def __exit__(self, typ, value, traceback):
        return False

    def readline(self):
        return next(self.lines, b"")


class BridgeUnitTests(unittest.TestCase):
    def test_preflight_is_technical_only_and_bounded(self):
        self.assertEqual(validate_live_case("D02", "gpt-6-luna", "default")["id"], "D02")
        self.assertEqual(validate_live_case("E09", "gpt-6.1-sol", "low")["id"], "E09")
        for case, model, effort in [
            ("E08", "gpt-6-luna", "default"),  # A personal fixture is never sent.
            ("E07", "gpt-6-luna", "default"),
            ("D12", "gpt-6-luna", "default"),  # Requires a real turn-state engine.
            ("NOPE", "gpt-6-luna", "default"),
            ("D02", "gpt-6-astra", "default"),
            ("D02", "gpt-6.1-sol", "none"),
            ("D02", "gpt-6-luna", "high"),
        ]:
            with self.subTest(case=case, model=model, effort=effort), self.assertRaises((ValueError, stream.StreamError)):
                validate_live_case(case, model, effort)

    def test_synthetic_first_person_negative_screen(self):
        self.assertEqual(synthetic_nonpersonal_classification(DIRECT, "sql"), "absent")
        for text in (
            PERSONAL,
            "In my internship the retention metric was different.",
            "The dashboard I created increased growth.",
            "We created the dataset and our team presented it.",
            "for i in range(3): print(i)",  # Conservative on code identifiers.
        ):
            with self.subTest(text=text):
                self.assertEqual(
                    synthetic_nonpersonal_classification(text, "sql"), "uncertain"
                )
        self.assertEqual(
            synthetic_nonpersonal_classification(DIRECT, "personal"), "uncertain"
        )

    def test_real_sse_bytes_flow_through_existing_qa_then_publish(self):
        clock, calls, shown = Clock(), [], []
        outcome = run_live_synthetic_case(
            "synthetic-oauth-token", case_id="D02", model="gpt-6-luna",
            on_present=shown.append, clock=clock,
            response_stream=source_for(clock, response_rows(), calls),
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], "gpt-6-luna")
        self.assertEqual(calls[0][3]["effort"], None)  # Do not force extra reasoning.
        self.assertIn("Where", calls[0][2].title())
        self.assertEqual(outcome.assessment.qa.status, "pass")
        self.assertTrue(outcome.assessment.completed)
        self.assertEqual(outcome.presentation.state, "final_unverified")
        self.assertEqual(outcome.presentation.text, DIRECT)
        self.assertEqual(shown, [outcome.presentation])
        self.assertEqual(
            (outcome.assessment.first_text_ms,
             outcome.assessment.first_scannable_candidate_ms,
             outcome.assessment.completed_ms, outcome.assessment.qa_decided_ms,
             outcome.presentation.presented_ms),
            (200, 200, 500, 500, 500),
        )
        self.assertIsNone(outcome.presentation.first_useful_verified_ms)
        self.assertFalse(outcome.presentation.review_executed)

    def test_no_output_during_stream_even_after_complete_sentence(self):
        clock, calls, shown = Clock(), [], []

        @contextmanager
        def source(*args, **kwargs):
            def gen():
                clock.now = 0.2
                yield from event_lines("response.output_text.delta", {
                    "type": "response.output_text.delta", "delta": DIRECT,
                    "sequence_number": 1,
                })
                self.assertEqual(shown, [])
                clock.now = 0.5
                yield from event_lines("response.completed", {
                    "type": "response.completed", "sequence_number": 2,
                    "response": {"status": "completed"},
                })
            calls.append(1)
            yield gen()

        outcome = run_live_synthetic_case(
            "token", case_id="D02", model="gpt-6-luna",
            on_present=shown.append, response_stream=source, clock=clock,
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(shown[0].text, DIRECT)
        self.assertEqual(outcome.presentation.state, "final_unverified")

    def test_first_person_hallucination_is_not_published(self):
        clock, calls, shown = Clock(), [], []
        out = run_live_synthetic_case(
            "token", case_id="D02", model="gpt-6-luna",
            on_present=shown.append, clock=clock,
            response_stream=source_for(clock, response_rows(PERSONAL), calls),
        )
        self.assertEqual(out.assessment.qa.status, "abstain")
        self.assertEqual(out.presentation.state, "unavailable")
        self.assertIsNone(out.presentation.text)
        self.assertIsNone(out.presentation.first_scannable_candidate_ms)
        self.assertEqual(len(shown), 1)
        self.assertIsNone(shown[0].text)

    def test_incomplete_and_malformed_after_partial_never_publish(self):
        for rows in (
            response_rows(DIRECT, completed=False),
            [response_rows()[0],
             (0.5, "response.completed", {
                 "type": "response.completed", "response": {"status": "incomplete"}
             })],
            response_rows("X" * 16_385),
            [(0.1, "response.failed", {
                "type": "response.failed", "response": {
                    "error": {"code": "subscription_sharing_usage_limit_exceeded"}
                }
            })],
        ):
            with self.subTest(rows=len(rows)):
                clock, calls, shown = Clock(), [], []
                out = run_live_synthetic_case(
                    "token", case_id="D02", model="gpt-6-luna",
                    on_present=shown.append, clock=clock,
                    response_stream=source_for(clock, rows, calls),
                )
                self.assertFalse(out.assessment.completed)
                self.assertEqual(out.presentation.state, "unavailable")
                self.assertIsNone(out.presentation.text)
                self.assertTrue(all(item.text is None for item in shown))
                self.assertEqual(len(calls), 1)

    def test_replaced_turn_discards_answer_without_callback(self):
        turns = ActiveTurns()
        token = turns.activate("D02", 1)
        clock, calls, shown = Clock(), [], []

        @contextmanager
        def source(*args, **kwargs):
            calls.append(1)

            def lines():
                clock.now = 0.2
                yield from event_lines("response.output_text.delta", {
                    "type": "response.output_text.delta", "delta": DIRECT,
                    "sequence_number": 1,
                })
                turns.activate("new-question", 2)
                clock.now = 0.5
                yield from event_lines("response.completed", {
                    "type": "response.completed", "sequence_number": 2,
                    "response": {"status": "completed"},
                })
            yield lines()

        out = run_live_synthetic_case(
            "token", case_id="D02", model="gpt-6-luna",
            turns=turns, token=token, clock=clock,
            on_present=shown.append, response_stream=source,
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(out.presentation.state, "suppressed")
        self.assertIsNone(out.presentation.text)
        self.assertEqual(shown, [])

    def test_stale_before_request_and_missing_callback_do_not_open_network(self):
        turns, clock, calls = ActiveTurns(), Clock(), []
        token = turns.activate("D02", 1)
        turns.cancel()
        source = source_for(clock, response_rows(), calls)
        with self.assertRaises(stream.StreamError):
            run_live_synthetic_case(
                "token", case_id="D02", model="gpt-6-luna",
                turns=turns, token=token, clock=clock,
                on_present=lambda _: None, response_stream=source,
            )
        with self.assertRaises(TypeError):
            run_live_synthetic_case(
                "token", case_id="D02", model="gpt-6-luna",
                on_present=None, response_stream=source,
            )
        self.assertEqual(calls, [])

    def test_selective_review_is_signal_only_and_never_retries(self):
        clock, calls, shown = Clock(), [], []
        out = run_live_synthetic_case(
            "token", case_id="E09", model="gpt-6-luna",
            on_present=shown.append, clock=clock,
            response_stream=source_for(clock, response_rows(CODING), calls),
        )
        self.assertTrue(out.assessment.qa.second_review_recommended)
        self.assertEqual(out.presentation.review_candidate, "gpt-6.1-sol")
        self.assertFalse(out.presentation.review_executed)
        self.assertEqual(len(calls), 1)

    def test_failed_attribution_classifier_fails_closed(self):
        turns, clock = ActiveTurns(), Clock()
        token = turns.activate("D02", 1)

        def failure(_answer, _category):
            raise RuntimeError("Fake classifier failure; do not show to user")

        assessed = assess_synthetic_stream(
            completed_lines(), turns=turns, token=token,
            context=SyntheticContext("D02"), clock=clock,
            attribution_classifier=failure,
        )
        self.assertEqual(assessed.qa.status, "needs_revision")
        self.assertIsNone(assessed.first_scannable_candidate_ms)


class TransportTests(unittest.TestCase):
    def test_real_transport_exposes_original_sse_without_independent_parser(self):
        response = FakeHTTPResponse(completed_lines())
        with patch("relay_spike.stream.urlopen", return_value=response) as send:
            with stream.response_sse_lines(
                "synthetic-plan-token", "gpt-6-luna", "Where versus having?",
                instructions="Only synthetic", effort="low",
            ) as lines:
                self.assertEqual(list(lines), completed_lines())
        self.assertEqual(send.call_count, 1)
        req = send.call_args.args[0]
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.get_header("Authorization"), "Bearer synthetic-plan-token")
        self.assertEqual(req.full_url, stream.RESPONSES)
        payload = json.loads(req.data)
        self.assertFalse(payload["store"])
        self.assertTrue(payload["stream"])
        self.assertEqual(payload["reasoning"], {"effort": "low"})
        self.assertEqual(payload["input"][0]["content"], "Where versus having?")

    def test_legacy_infer_consumer_still_uses_shared_transport(self):
        with patch("relay_spike.stream.urlopen",
                   return_value=FakeHTTPResponse(completed_lines())) as opened:
            emitted = []
            result = stream.stream_answer(
                "token", "gpt-6-luna", "Why HAVING?", on_delta=emitted.append
            )
        self.assertTrue(result["completed"])
        self.assertEqual(result["output_chars"], len(DIRECT))
        self.assertEqual("".join(emitted), DIRECT)
        self.assertEqual(opened.call_count, 1)

    def test_network_failure_is_sanitized(self):
        with patch("relay_spike.stream.urlopen",
                   side_effect=HTTPError(stream.RESPONSES, 401, "secret response", None, None)):
            with self.assertRaisesRegex(stream.StreamError, r"HTTP 401"):
                with stream.response_sse_lines("private-token", "gpt-6-luna", "SQL?"):
                    self.fail("No SSE bytes should be available")


class LiveCLIUnitTests(unittest.TestCase):
    def test_dry_run_never_loads_credentials_or_touches_network(self):
        out = StringIO()
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("auth in dry run")), \
             patch("relay_spike.__main__.request_json",
                   side_effect=AssertionError("model call in dry run")), \
             patch("relay_spike.__main__.run_live_synthetic_case",
                   side_effect=AssertionError("inference in dry run")), \
             redirect_stdout(out):
            exit_code = main(["live-qa", "--case", "D02", "--effort", "low"])
        self.assertEqual(exit_code, 0)
        data = json.loads(out.getvalue())
        self.assertTrue(data["dry_run"])
        self.assertEqual(data["requests_if_executed"], 1)

    def test_invalid_personal_case_rejected_before_auth(self):
        for args in (
            ["live-qa", "--execute", "--case", "D08"],
            ["live-qa", "--execute", "--case", "D12"],
            ["live-qa", "--execute", "--case", "NOPE"],
        ):
            with self.subTest(args=args), \
                 patch("relay_spike.__main__.active_access_token",
                       side_effect=AssertionError("auth for invalid case")), \
                 redirect_stderr(StringIO()):
                self.assertEqual(main(args), 1)

    def test_model_not_in_oauth_catalog_never_infers(self):
        with patch("relay_spike.__main__.active_access_token", return_value="token"), \
             patch("relay_spike.__main__.request_json", return_value={"models": []}), \
             patch("relay_spike.__main__.run_live_synthetic_case",
                   side_effect=AssertionError("unexpected inference")), \
             redirect_stderr(StringIO()):
            self.assertEqual(main(["live-qa", "--execute"]), 1)

    def test_explicit_execute_posts_once_and_prints_only_qa_pass(self):
        out = StringIO()
        catalog = {"models": [
            {"slug": "gpt-6-luna", "visibility": "list", "display_name": "Luna"}
        ]}
        with patch("relay_spike.__main__.active_access_token", return_value="mock-plan"), \
             patch("relay_spike.__main__.request_json", return_value=catalog), \
             patch("relay_spike.stream.urlopen",
                   return_value=FakeHTTPResponse(completed_lines())) as model_call, \
             redirect_stdout(out):
            exit_code = main(["live-qa", "--execute", "--case", "D02"])
        self.assertEqual(exit_code, 0)
        self.assertEqual(model_call.call_count, 1)
        data = json.loads(out.getvalue())
        self.assertFalse(data["dry_run"])
        self.assertEqual(data["requests_executed"], 1)
        self.assertEqual(data["state"], "final_unverified")
        self.assertEqual(data["qa_status"], "pass")
        self.assertEqual(data["answer"], DIRECT)
        self.assertIsNone(data["first_useful_verified_ms"])
        self.assertFalse(data["second_review_executed"])
        self.assertNotIn("mock-plan", out.getvalue())

    def test_execute_with_failed_stream_prints_no_provisional_text(self):
        out = StringIO()
        catalog = {"models": [
            {"slug": "gpt-6-luna", "visibility": "list"}
        ]}
        partial = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta", "delta": "SECRET_PARTIAL_MODEL_TEXT"
        })
        with patch("relay_spike.__main__.active_access_token", return_value="mock"), \
             patch("relay_spike.__main__.request_json", return_value=catalog), \
             patch("relay_spike.stream.urlopen",
                   return_value=FakeHTTPResponse(partial)), \
             redirect_stdout(out):
            exit_code = main(["live-qa", "--execute"])
        self.assertEqual(exit_code, 2)
        self.assertNotIn("SECRET_PARTIAL_MODEL_TEXT", out.getvalue())
        data = json.loads(out.getvalue())
        self.assertIsNone(data["answer"])
        self.assertEqual(data["state"], "unavailable")


if __name__ == "__main__":
    unittest.main()
