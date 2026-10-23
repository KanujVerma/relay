"""Deterministic synthetic intent corpus, never real ASR accuracy evidence."""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import unittest

from relay_spike.asr_turn_adapter import classify_question_intent

FIXTURE = (Path(__file__).resolve().parents[1]
           / "EVALS" / "asr-intent-cases.jsonl")
KINDS = frozenset(("question", "correction", "follow_up", "unknown"))


class IntentCorpusTests(unittest.TestCase):
    def test_all_synthetic_intent_cases_match_reviewed_expected_labels(self):
        entries = [json.loads(line) for line in FIXTURE.read_text(
            encoding="utf-8").splitlines() if line.strip()]
        self.assertEqual(len(entries), 40)
        self.assertEqual(len({row["id"] for row in entries}), len(entries))
        self.assertTrue(all(row.get("synthetic_only") is True for row in entries))
        confusion = Counter()
        for row in entries:
            with self.subTest(id=row["id"]):
                self.assertIs(type(row["has_current_question"]), bool)
                self.assertIn(row["expected_intent"], KINDS)
                actual = classify_question_intent(
                    row["utterance"],
                    has_current_question=row["has_current_question"],
                )
                confusion[(row["expected_intent"], actual)] += 1
                self.assertEqual(actual, row["expected_intent"])
        self.assertEqual(
            sum(count for (expected, actual), count in confusion.items()
                if expected != actual), 0
        )
        self.assertEqual(sum(confusion.values()), 40)

    def test_fixture_labels_cover_all_four_classes_and_context_contrasts(self):
        entries = [json.loads(line) for line in FIXTURE.read_text(
            encoding="utf-8").splitlines() if line.strip()]
        counts = Counter(row["expected_intent"] for row in entries)
        self.assertEqual(set(counts), KINDS)
        self.assertGreaterEqual(min(counts.values()), 5)
        phrases = {}
        for row in entries:
            phrases.setdefault(row["utterance"], set()).add(
                (row["has_current_question"], row["expected_intent"])
            )
        self.assertIn(
            ((True, "follow_up"), (False, "unknown")),
            [( (True, "follow_up"), (False, "unknown") )
             for labels in phrases.values()
             if (True, "follow_up") in labels
             and (False, "unknown") in labels],
        )
        self.assertIn(
            ((True, "correction"), (False, "unknown")),
            [( (True, "correction"), (False, "unknown") )
             for labels in phrases.values()
             if (True, "correction") in labels
             and (False, "unknown") in labels],
        )


if __name__ == "__main__":
    unittest.main()
