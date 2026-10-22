"""Offline regression tests for optional reasoning.effort controls.

These tests do not authenticate, use ChatGPT plan capacity, or make API calls.
"""
from __future__ import annotations

from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
import json
import unittest
from unittest.mock import patch

from relay_spike import benchmark, stream
from relay_spike.__main__ import main


class EffortRequestTests(unittest.TestCase):
    def test_no_effort_preserves_existing_preview_request(self):
        for effort in (None, "default"):
            payload = stream.response_payload("gpt-6.1-sol", "What is WHERE?",
                                              effort=effort)
            self.assertNotIn("reasoning", payload)
            self.assertFalse(payload["store"])
            self.assertTrue(payload["stream"])

    def test_explicit_effort_is_well_formed_and_bounded(self):
        for model, effort in [
            ("gpt-6-luna", "none"), ("gpt-6-luna", "low"),
            ("gpt-6.1-sol", "low"), ("gpt-6.1-sol", "medium"),
            ("gpt-6.1-sol", "high"), ("gpt-6.1-sol", "xhigh"),
            ("gpt-6-astra", "max"),
        ]:
            with self.subTest(model=model, effort=effort):
                payload = stream.response_payload(model, "SQL?", effort=effort)
                self.assertEqual(payload["reasoning"], {"effort": effort})
                self.assertNotIn("max_output_tokens", payload)
                self.assertNotIn("temperature", payload)

    def test_unsupported_level_or_model_rejected(self):
        cases = [
            ("gpt-6.1-sol", "none"), ("gpt-6.1-sol", "minimal"),
            ("gpt-6-astra", "none"), ("gpt-6-luna", "minimal"),
            ("gpt-6-luna", "ultrafast"), ("gpt-daybreak-blue-latest", "low"),
            ("gpt-6.1-sol", 17)
        ]
        for model, effort in cases:
            with self.subTest(model=model, effort=effort):
                with self.assertRaises(stream.StreamError):
                    stream.response_payload(model, "SQL?", effort=effort)

    def test_completed_stream_reports_effort_only_if_server_sends_it(self):
        completed = [
            b"event: response.output_text.delta\n",
            b'data: {"type":"response.output_text.delta","delta":"Yes"}\n',
            b"\n",
            b"event: response.completed\n",
            b'data: {"type":"response.completed","response":{"status":"completed","reasoning":{"effort":"low"}}}\n',
            b"\n",
        ]
        # Two calls: one for first output, one for complete stream.
        times = iter([0.025, 0.080])
        result = stream.consume_stream(
            completed, started=0.0, clock=lambda: next(times))
        self.assertEqual(result["server_reported_reasoning_effort"], "low")
        self.assertTrue(result["completed"])


class BenchmarkEffortTests(unittest.TestCase):
    def test_cross_product_is_paired_and_grouped(self):
        plan = benchmark.make_plan(
            ["gpt-6-luna", "gpt-6.1-sol"], ["D02"], effort_levels=["low", "medium"])
        self.assertEqual(len(plan), 4)
        self.assertEqual(
            [(p["model"], p["requested_reasoning_effort"]) for p in plan],
            [("gpt-6-luna", "low"), ("gpt-6.1-sol", "low"),
             ("gpt-6-luna", "medium"), ("gpt-6.1-sol", "medium")]
        )

        def run_one(model, case, effort):
            return ({"completed": True, "first_text_ms": 100 if effort == "low" else 200,
                     "total_ms": 400 if effort == "low" else 800,
                     "server_reported_reasoning_effort": effort},
                    "WHERE filters rows and HAVING filters groups.")
        rows = benchmark.evaluate_plan(plan, run_one)
        sums = benchmark.summary(rows)
        self.assertEqual(len(sums), 4)
        self.assertEqual(sums["gpt-6-luna / low"]["median_total_ms"], 400)
        self.assertEqual(sums["gpt-6-luna / medium"]["median_total_ms"], 800)
        self.assertEqual(rows[0]["server_reported_reasoning_effort"], "low")
        self.assertTrue(all(r["correctness"] == "unreviewed" for r in rows))

    def test_pre_auth_validation_and_effort_multiplies_request_cap(self):
        bad = [
            (["gpt-6-luna", "gpt-6.1-sol"], ["D02"], ["none"]),
            (["gpt-6.1-sol"], ["D02"], ["minimal"]),
            (["gpt-6-luna"], ["D02"], ["bad"]),
            (["gpt-6-luna"], ["D02"], ["low", "low"]),
            (["gpt-6-luna"], ["D02"], []),
            (["gpt-6-luna", "gpt-6.1-sol"], ["D02","D01","E01"], 
             ["default", "low", "medium"]),
        ]
        for models, cases, efforts in bad:
            with self.subTest(efforts=efforts):
                with self.assertRaises(benchmark.BenchmarkError):
                    benchmark.make_plan(models, cases, effort_levels=efforts)
        self.assertEqual(len(benchmark.make_plan(
            ["gpt-6-luna", "gpt-6.1-sol"], ["D02", "D01", "E01"],
            effort_levels=["low","medium"])), 12)
        self.assertEqual(len(benchmark.make_plan(
            ["gpt-6-luna"], ["D02"], effort_levels=["none"])), 1)

    def test_cli_explicit_effort_dry_run_requires_no_network(self):
        stdout = StringIO()
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("unexpected auth")), \
             patch("relay_spike.__main__.request_json",
                   side_effect=AssertionError("unexpected network")), \
             patch("relay_spike.__main__.stream_answer",
                   side_effect=AssertionError("unexpected inference")), \
             redirect_stdout(stdout):
            status = main(["benchmark", "--cases", "D02",
                           "--efforts", "low,medium"])
        self.assertEqual(status, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["requests_if_executed"], 4)
        self.assertEqual(payload["requested_efforts"], ["low", "medium"])
        self.assertTrue(payload["dry_run"])

    def test_cli_rejects_sol_none_before_auth(self):
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("unexpected auth")), \
             redirect_stderr(StringIO()):
            status = main(["benchmark", "--efforts", "none", "--cases", "D02"])
            self.assertEqual(status, 1)
            status = main(["infer", "--model", "gpt-6.1-sol", "--effort", "none"])
            self.assertEqual(status, 1)

    def test_infer_explicit_low_is_forwarded_without_modifying_model(self):
        catalog = {"models": [
            {"slug": "gpt-6.1-sol", "display_name": "Sol", "visibility": "list"}]}
        response = {"completed": True, "first_text_ms": 17,
                    "total_ms": 99, "output_chars": 12}
        out = StringIO()
        with patch("relay_spike.__main__.active_access_token", return_value="mock"), \
             patch("relay_spike.__main__.request_json", return_value=catalog), \
             patch("relay_spike.__main__.stream_answer",
                   return_value=response) as mock_stream, \
             redirect_stdout(out):
            status = main(["infer", "--model", "gpt-6.1-sol", "--effort", "low"])
        self.assertEqual(status, 0)
        self.assertEqual(mock_stream.call_args.kwargs["effort"], "low")
        self.assertEqual(mock_stream.call_args.args[1], "gpt-6.1-sol")
        self.assertIn('"requested_reasoning_effort": "low"', out.getvalue())


if __name__ == "__main__":
    unittest.main()
