"""Offline Slice 01B-A synthetic benchmark and preview request tests."""
from __future__ import annotations

from contextlib import redirect_stdout
from io import StringIO
import json
import unittest
from unittest.mock import patch

from relay_spike import benchmark, stream
from relay_spike.__main__ import main


class PromptTests(unittest.TestCase):
    def test_preview_payload_uses_instructions_without_banned_fields(self):
        instructions = benchmark.instructions_for("analytics")
        payload = stream.response_payload("gpt-6-luna", "What is HAVING?",
                                          instructions=instructions)
        self.assertEqual(set(payload), {"model", "input", "stream", "store", "instructions"})
        self.assertIs(payload["store"], False)
        self.assertIs(payload["stream"], True)
        self.assertIn("Never invent", instructions)
        self.assertNotIn("max_output_tokens", payload)
        self.assertNotIn("temperature", payload)

    def test_empty_instructions_fail_closed(self):
        for invalid in ("", "   ", 12):
            with self.subTest(invalid=invalid):
                with self.assertRaises(stream.StreamError):
                    stream.response_payload("gpt-6-luna", "SQL?", instructions=invalid)

    def test_role_specific_instructions(self):
        self.assertIn("denominators", benchmark.instructions_for("analytics"))
        self.assertIn("complexity", benchmark.instructions_for("epic"))
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.instructions_for("unknown")


class PlanTests(unittest.TestCase):
    def test_default_plan_is_paired_and_limited(self):
        plan = benchmark.make_plan(benchmark.DEFAULT_MODELS, benchmark.DEFAULT_CASES)
        self.assertEqual(len(plan), 6)
        self.assertEqual([x["model"] for x in plan[:2]], list(benchmark.DEFAULT_MODELS))
        self.assertEqual(plan[0]["case"]["id"], plan[1]["case"]["id"])
        self.assertEqual(plan[0]["repetition"], 1)
        self.assertEqual(plan[0]["requested_reasoning_effort"], "default")

    def test_unknown_and_duplicate_case_or_model_rejected(self):
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.load_cases(["X00"])
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.load_cases(["D02", "D02"])
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.make_plan(["gpt-6-luna", "gpt-6-luna"], ["D02"])
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.make_plan(["gpt-6-luna"], ["D02"], repeats=0)
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.make_plan(["gpt-6-luna"], ["D02"], repeats=4)
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.make_plan(benchmark.DEFAULT_MODELS,
                                ["D02", "D01", "E01", "D08", "D03", "E04", "D04"])

    def test_result_metrics_are_not_fake_accuracy_scores(self):
        plan = benchmark.make_plan(["gpt-6-luna"], ["D02", "D08"])
        def synthetic(_model, _case, _effort):
            return ({"first_text_ms": 123, "total_ms": 700, "completed": True},
                    "WHERE filters rows. HAVING filters groups.")
        rows = benchmark.evaluate_plan(plan, synthetic)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["correctness"], "unreviewed")
        self.assertEqual(rows[0]["requested_reasoning_effort"], "default")
        self.assertEqual(rows[0]["first_text_ms"], 123)
        self.assertEqual(rows[0]["output_chars"],
                         len("WHERE filters rows. HAVING filters groups."))
        self.assertTrue(rows[0]["under_word_ceiling"])
        result = benchmark.summary(rows)
        self.assertEqual(result["gpt-6-luna / default"]["median_total_ms"], 700)
        self.assertTrue(result["gpt-6-luna"]["p95_not_reported"])
        self.assertIsNone(result["gpt-6-luna"]["p95_total_ms"])

    def test_failed_stream_does_not_get_quality_score(self):
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.evaluate_plan(
                benchmark.make_plan(["gpt-6-luna"], ["D02"]),
                lambda model, case, effort: ({"completed": False}, "Partial")
            )

    def test_format_checks_are_not_factual_accuracy(self):
        m = benchmark.format_metrics("| A | B |\n|---|---|\n", "sql")
        self.assertTrue(m["contains_markdown_table"])
        m2 = benchmark.format_metrics("word " * 112, "sql")
        self.assertFalse(m2["under_word_ceiling"])


class CliTests(unittest.TestCase):
    def test_p95_is_present_when_ten_or_more_runs_exist(self):
        self.assertIsNone(benchmark.percentile95([1, 2, 3]))
        rows = [
            {"model": "gpt-6-luna", "requested_reasoning_effort": "default", "first_text_ms": i * 10,
             "total_ms": 100 + i * 10, "under_word_ceiling": True,
             "contains_markdown_table": False}
            for i in range(12)
        ]
        report = benchmark.summary(rows)["gpt-6-luna / default"]
        self.assertFalse(report["p95_not_reported"])
        self.assertEqual(report["p95_total_ms"], 204)
        self.assertEqual(report["compact_no_table"], 12)

    def test_short_response_is_not_claimed_correct(self):
        one_word = benchmark.format_metrics("Okay", "sql")
        self.assertEqual(one_word["words"], 1)
        self.assertTrue(one_word["under_word_ceiling"])
        self.assertNotIn("correctness", one_word)
        self.assertIn("Never invent", benchmark.instructions_for("general"))

    def test_infer_role_is_explicit_or_general(self):
        fake_catalog = {"models": [{
            "slug": "gpt-6.1-sol", "display_name": "Sol", "visibility": "list"
        }]}
        fake_response = {"completed": True, "first_text_ms": 10,
                         "total_ms": 20, "output_chars": 4}
        for argv, expected in [
            (["infer", "--role", "epic"], "complexity"),
            (["infer", "--role", "analytics"], "denominators"),
            (["infer"], "Never invent"),
        ]:
            with self.subTest(argv=argv), \
                 patch("relay_spike.__main__.active_access_token",
                       return_value="synthetic-oauth"), \
                 patch("relay_spike.__main__.request_json",
                       return_value=fake_catalog), \
                 patch("relay_spike.__main__.stream_answer",
                       return_value=fake_response) as stream_call, \
                 redirect_stdout(StringIO()):
                self.assertEqual(main(argv), 0)
                self.assertIn(expected, stream_call.call_args.kwargs["instructions"])
                if argv == ["infer"]:
                    self.assertNotIn("denominators",
                                     stream_call.call_args.kwargs["instructions"])

    def test_dry_run_does_not_read_auth_or_call_network(self):
        output = StringIO()
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("auth must not run")), \
             patch("relay_spike.__main__.request_json",
                   side_effect=AssertionError("network must not run")), \
             patch("relay_spike.__main__.stream_answer",
                   side_effect=AssertionError("model must not run")), \
             redirect_stdout(output):
            code = main(["benchmark"])
        self.assertEqual(code, 0)
        data = json.loads(output.getvalue())
        self.assertTrue(data["dry_run"])
        self.assertEqual(data["requests_if_executed"], 6)
        self.assertIn("No authentication", data["note"])

    def test_invalid_or_oversized_plan_exits_before_auth(self):
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("auth must not run")):
            with redirect_stdout(StringIO()):
                code = main(["benchmark", "--cases", "X99"])
                self.assertEqual(code, 1)
                code2 = main(["benchmark", "--repeats", "3",
                              "--cases", "D02,D01,E01"])
                self.assertEqual(code2, 1)


if __name__ == "__main__":
    unittest.main()
