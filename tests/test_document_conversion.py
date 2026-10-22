"""Worker-owned checks for document conversion failure boundaries."""
from __future__ import annotations

from hashlib import sha256
import os
from pathlib import Path
import subprocess
import sys
import unittest

from relay_spike.document_conversion import convert_document
from relay_spike.personal_brain import BrainStore
from relay_spike.resume_candidates import ReviewGateway


WHEN = "2026-10-22T12:00:00-05:00"


class DocumentConversionUnitTests(unittest.TestCase):
    def test_native_parser_failure_does_not_echo_source_bytes(self):
        sentinel = b"PRIVATE-SYNTHETIC-FAILURE-SENTINEL"

        result = convert_document(sentinel, file_type="pdf")

        self.assertIn(result.status, {"invalid", "unsupported", "unavailable"})
        self.assertEqual(result.text, "")
        self.assertEqual(result.segments, ())
        self.assertNotIn(sentinel.decode("ascii"), result.reason or "")

    def test_document_vendor_integration_cases_are_opt_in_for_base_ci(self):
        environment = os.environ.copy()
        environment.pop("RELAY_DOCUMENT_INTEGRATION", None)
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        completed = subprocess.run(
            [
                sys.executable,
                "-S",
                "-m",
                "unittest",
                "discover",
                "-s",
                "tests",
                "-p",
                "test_document_conversion_integration.py",
                "-v",
            ],
            cwd=Path(__file__).parent.parent,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        output = completed.stdout + completed.stderr
        self.assertEqual(completed.returncode, 0, output)
        self.assertRegex(output, r"OK \(skipped=[1-9][0-9]*\)")

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
