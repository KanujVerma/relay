"""Slice 01B-B0 offline QA safeguards, all data intentionally synthetic."""
from __future__ import annotations

from dataclasses import replace
import unittest

from relay_spike.qa import QAInput, CoverageIndicator, assess


def example(case_id="D02", category="sql", answer=None, **kwargs):
    if answer is None:
        answer = ("WHERE filters rows before grouping, while HAVING filters groups "
                  "after aggregation. A typical HAVING example uses COUNT(*).")
    values = {
        "case_id": case_id, "role": "epic" if case_id.startswith("E") else "analytics",
        "category": category, "answer": answer, "completed": True,
        "turn_id": "synthetic-turn-1", "turn_version": 3,
        "active_turn_version": 3,
    }
    values.update(kwargs)
    return QAInput(**values)


class GatingTests(unittest.TestCase):
    def test_simple_d02_passes_without_second_model_call(self):
        reviewed = assess(example())
        self.assertEqual(reviewed.status, "pass")
        self.assertEqual(reviewed.reasons, ())
        self.assertFalse(reviewed.second_review_recommended)
        self.assertEqual(reviewed.case_id, "D02")
        self.assertEqual(reviewed.turn_version, 3)
        self.assertGreater(reviewed.words, 4)

    def test_incomplete_and_stale_never_pass_or_request_model(self):
        for kwargs, reason in [
            ({"completed": False}, "incomplete_stream"),
            ({"active_turn_version": 4}, "superseded_turn"),
            ({"answer": " "}, "empty_answer"),
            ({"category": "not_a_real_category"}, "unknown_question_category"),
        ]:
            with self.subTest(kwargs=kwargs):
                result = assess(example(**kwargs))
                self.assertEqual(result.status, "abstain")
                self.assertIn(reason, result.reasons)
                self.assertFalse(result.second_review_recommended)

    def test_no_personal_facts_fail_closed_for_four_fixture_categories(self):
        for case, category in [
            ("E07", "behavioral"), ("E08", "personal"),
            ("E13", "personal"), ("D08", "personal"),
        ]:
            with self.subTest(case=case):
                req = example(case, category, answer=(
                    "I implemented the entire backend and delivered a measured "
                    "fifty percent improvement on my own."
                ))
                outcome = assess(req)
                self.assertEqual(outcome.status, "abstain")
                self.assertIn("missing_verified_personal_context", outcome.reasons)
                self.assertFalse(outcome.second_review_recommended)

    def test_source_pointer_alone_cannot_certify_personal_claim(self):
        result = assess(example(
            "E08", "personal", answer="I owned this deliverable and shipped it.",
            verified_source_ids=("approved-source-1",),
        ))
        self.assertEqual(result.status, "needs_revision")
        self.assertIn("personal_claims_need_actual_source_review", result.reasons)
        self.assertEqual(result.verified_source_ids, ("approved-source-1",))
        self.assertTrue(result.second_review_recommended)

    def test_personal_attribution_flag_takes_precedence_over_general_category(self):
        req = example("D02", risk_flags=("personal_claim",))
        self.assertEqual(assess(req).status, "abstain")

    def test_multi_part_e04_heuristic_flags_missing_collision_or_worst_case(self):
        indicators = (
            CoverageIndicator("definition", ("hash table", "hash map")),
            CoverageIndicator("collision", ("collision", "chaining", "probing")),
            CoverageIndicator("worst_case", ("worst-case", "worst case", "O(n)")),
        )
        missing = assess(example(
            "E04", "multi_part", answer="A hash table maps keys to values using buckets.",
            coverage_indicators=indicators,
        ))
        self.assertEqual(missing.status, "needs_revision")
        self.assertEqual(missing.missing_coverage_indicators,
                         ("collision", "worst_case"))
        self.assertTrue(missing.second_review_recommended)
        self.assertIn("keyword_coverage_is_not_semantic_verification", missing.warnings)

        all_terms = assess(example(
            "E04", "multi_part",
            answer=("A hash table stores key values. Collisions can use chaining; "
                    "a worst-case lookup can be O(n)."),
            coverage_indicators=indicators,
        ))
        self.assertEqual(all_terms.status, "pass")
        self.assertEqual(all_terms.missing_coverage_indicators, ())
        self.assertIn("keyword_coverage_is_not_semantic_verification", all_terms.warnings)
        self.assertTrue(all_terms.second_review_recommended)

    def test_d07_three_part_question_coverage_warning(self):
        markers = (
            CoverageIndicator("CTE", ("cte", "common table expression")),
            CoverageIndicator("subquery", ("subquery", "nested query")),
            CoverageIndicator("performance", ("performance", "optimizer", "execution plan")),
        )
        answer = ("A CTE is a named query defined with WITH. "
                  "A subquery is nested directly in a SELECT.")
        r = assess(example("D07", "multi_part", answer=answer,
                           coverage_indicators=markers))
        self.assertEqual(r.status, "needs_revision")
        self.assertEqual(r.missing_coverage_indicators, ("performance",))

    def test_technical_risk_decides_selective_review_without_extra_inference(self):
        for case, category, flags in [
            ("D01", "sql", ("join_fanout",)),
            ("D13", "sql", ("ranking_ties",)),
            ("E09", "coding", ()),
            ("E10", "edge_case", ()),
            ("E03", "ambiguity", ()),
        ]:
            with self.subTest(case=case):
                r = assess(example(case, category, risk_flags=flags))
                self.assertEqual(r.status, "pass")
                self.assertTrue(r.second_review_recommended)
        self.assertFalse(assess(example("D02", "sql")).second_review_recommended)

    def test_format_constraints_are_not_claims_of_factual_correctness(self):
        self.assertEqual(assess(example(answer="yes")).status, "needs_revision")
        table = assess(example(
            answer="Here is the result:\n| A | B |\n| --- | --- |\n| x | y |"
        ))
        self.assertEqual(table.status, "needs_revision")
        self.assertIn("markdown_table_not_scannable", table.reasons)

        too_long = assess(example(answer="token " * 200))
        self.assertIn("over_word_ceiling", too_long.reasons)
        self.assertEqual(too_long.status, "needs_revision")
        self.assertFalse(too_long.second_review_recommended)

    def test_code_first_is_warned_but_not_mislabeled_wrong(self):
        result = assess(example(
            "E09", "coding",
            answer="```python\nprint('example')\n```\nBinary search requires sorted input."
        ))
        self.assertEqual(result.status, "pass")
        self.assertIn("code_first_answer_may_be_hard_to_scan", result.warnings)

    def test_interruption_requires_a_turn_state_machine(self):
        result = assess(example(
            "E11", "interruption", answer="I will answer the latest question."
        ))
        self.assertEqual(result.status, "needs_revision")
        self.assertIn("turn_interruption_needs_state_confirmation", result.reasons)

    def test_contract_rejects_malformed_versions_and_evidence(self):
        cases = [
            {"turn_version": -1},
            {"turn_version": True},
            {"completed": "yes"},
            {"verified_source_ids": ("a", "a")},
            {"verified_source_ids": ("",)},
            {"risk_flags": ("",)},
            {"coverage_indicators": (CoverageIndicator("", ("term",)),)},
            {"coverage_indicators": (CoverageIndicator("part", ()),)},
        ]
        for mutation in cases:
            with self.subTest(mutation=mutation), self.assertRaises((TypeError, ValueError)):
                assess(example(**mutation))


if __name__ == "__main__":
    unittest.main()
