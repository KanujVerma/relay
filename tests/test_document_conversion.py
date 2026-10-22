"""Worker-owned checks for document conversion failure boundaries."""
from __future__ import annotations

from dataclasses import replace
from hashlib import sha256
import os
from pathlib import Path
import sys
from types import ModuleType
import unittest
from unittest.mock import patch

from relay_spike.document_conversion import (
    convert_document,
    stage_converted,
)
from relay_spike.personal_brain import BrainError, BrainStore
from relay_spike.resume_candidates import ReviewGateway


WHEN = "2026-10-22T12:00:00-05:00"
FIXTURES = Path(__file__).parent / "fixtures" / "documents"


class DocumentConversionFailureTests(unittest.TestCase):
    def test_markitdown_comparator_bypasses_magika_inference(self):
        source = (FIXTURES / "synthetic-two-page.pdf").read_bytes()
        fake_magika = ModuleType("magika")

        def forbidden_magika(*args, **kwargs):
            raise AssertionError("Magika classifier instantiated")

        fake_magika.Magika = forbidden_magika

        with patch.dict(os.environ, {"ORT_DISABLE_TELEMETRY": "0"}):
            with patch.dict(sys.modules, {"magika": fake_magika}):
                result = convert_document(source, file_type="pdf", backend="markitdown")
            self.assertEqual(os.environ["ORT_DISABLE_TELEMETRY"], "1")

        self.assertEqual(result.status, "needs_review")
        self.assertTrue(result.text)
        self.assertEqual(result.segments, ())

    def test_native_parser_failure_does_not_echo_source_bytes(self):
        sentinel = b"PRIVATE-SYNTHETIC-FAILURE-SENTINEL"

        result = convert_document(sentinel, file_type="pdf")

        self.assertIn(result.status, {"invalid", "unsupported", "unavailable"})
        self.assertEqual(result.text, "")
        self.assertEqual(result.segments, ())
        self.assertNotIn(sentinel.decode("ascii"), result.reason or "")

    def test_ambiguous_overlapping_locations_fail_before_source_write(self):
        source = (FIXTURES / "synthetic-two-page.pdf").read_bytes()
        converted = convert_document(source, file_type="pdf")
        self.assertEqual(converted.status, "converted")
        self.assertGreaterEqual(len(converted.segments), 2)
        result = replace(
            converted,
            segments=(converted.segments[0], converted.segments[0],
                      *converted.segments[1:]),
        )
        with BrainStore() as brain:
            host = object()
            gateway = ReviewGateway(brain, host_capability=host)

            with self.assertRaises((BrainError, ValueError)):
                stage_converted(
                    result,
                    gateway,
                    observed_at=WHEN,
                    capability=host,
                )

            self.assertEqual(
                brain.db.execute("SELECT COUNT(*) FROM source").fetchone()[0], 0
            )
            self.assertEqual(
                brain.db.execute("SELECT COUNT(*) FROM candidate_fact").fetchone()[0], 0
            )

    def test_old_gateway_selection_still_uses_derived_text_checksum(self):
        text = "I built a synthetic API."
        with BrainStore() as brain:
            host = object()
            gateway = ReviewGateway(brain, host_capability=host)
            source = gateway.select_source(
                text,
                observed_at=WHEN,
                capability=host,
            )

            row = brain.db.execute(
                "SELECT external_ref, checksum FROM source WHERE id=?", (source,)
            ).fetchone()
            self.assertIsNone(row["external_ref"])
            self.assertEqual(row["checksum"], sha256(text.encode("utf-8")).hexdigest())


if __name__ == "__main__":
    unittest.main()
