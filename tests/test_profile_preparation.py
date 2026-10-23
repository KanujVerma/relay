"""Selected synthetic bytes and injected host identity only."""
import unittest
from unittest.mock import patch

from relay_spike.document_conversion import _from_records

from relay_spike.personal_brain import BrainStore, MissingEvidence
from relay_spike.profile_preparation import ProfilePreparation, export_memory_snapshot, restore_memory_snapshot

STAMP = "2026-10-23T00:00:00+00:00"


class ProfilePreparationTests(unittest.TestCase):
    def setUp(self):
        self.store = BrainStore()
        self.cap = object()
        self.prep = ProfilePreparation(self.store, host_capability=self.cap)

    def tearDown(self):
        self.store.close()

    def select(self, text="I chose SQLite for Atlas because local transactions were needed.", **kw):
        return self.prep.select_bytes(text.encode(), file_type="txt", purpose="project",
                label="Atlas project notes", role="developer", project_hint="Atlas",
                observed_at=STAMP, capability=self.cap, **kw)

    def test_selection_stages_only_and_explicit_review_preserves_reason(self):
        prepared = self.select()
        card, = prepared.cards
        self.assertEqual(self.prep.provider.retrieve("Why SQLite for Atlas?", "developer").facts, ())
        self.prep.decide(card.fact_id, card.card_fingerprint, decision="approve",
                         actor="self", claim_key="atlas.rationale", capability=self.cap)
        bundle = self.prep.provider.retrieve("Why SQLite for Atlas?", "developer")
        self.assertEqual(bundle.facts[0].text,
                         "I chose SQLite for Atlas because local transactions were needed.")
        self.assertEqual(bundle.facts[0].evidence.locator, "text:line:1")

    def test_fake_capability_and_boolean_do_not_select_or_review(self):
        for cap in (True, {"authorized": True}, object()):
            with self.subTest(cap=cap), self.assertRaises(MissingEvidence):
                self.prep.select_bytes(b"I wrote Atlas tests.", file_type="txt", purpose="resume",
                    label="Selected resume", role="developer", observed_at=STAMP, capability=cap)
        prepared = self.select()
        card, = prepared.cards
        with self.assertRaises(MissingEvidence):
            self.prep.decide(card.fact_id, card.card_fingerprint, decision="approve",
                actor="self", claim_key="atlas.reason", capability=True)

    def test_job_context_is_reviewed_role_scoped_and_revocable(self):
        job = self.prep.select_bytes(b"Build SQL analytics with Python.", file_type="txt", purpose="job",
                label="Selected job", role="analyst", observed_at=STAMP, capability=self.cap)
        self.assertIsNone(self.prep.provider.retrieve("SQL?", "analyst").job_context)
        self.prep.approve_job(job.source_id, job.job_review.fingerprint, capability=self.cap)
        bundle = self.prep.provider.retrieve("SQL?", "analyst")
        self.assertEqual(bundle.job_context, "Build SQL analytics with Python.")
        self.assertEqual(bundle.facts, ())
        self.assertIsNone(self.prep.provider.retrieve("SQL?", "developer").job_context)
        self.prep.revoke(job.source_id, capability=self.cap)
        self.assertFalse(self.prep.provider.validate_current(bundle))
        self.assertIsNone(self.prep.provider.retrieve("SQL?", "analyst").job_context)
        self.assertIsNone(self.store.db.execute("SELECT text FROM profile_job_context").fetchone()[0])
        self.assertIsNone(self.store.db.execute("SELECT label FROM profile_source").fetchone()[0])

    def test_snapshot_reopen_preserves_pending_review_then_revocation_redacts(self):
        selected = self.select()
        card, = selected.cards
        snapshot = export_memory_snapshot(self.store)
        with restore_memory_snapshot(snapshot) as reopened:
            cap = object()
            prep = ProfilePreparation(reopened, host_capability=cap)
            live = prep.pending_cards()[0]
            self.assertEqual(live, card)
            prep.decide(live.fact_id, live.card_fingerprint, decision="approve", actor="self",
                        claim_key="atlas.reason", capability=cap)
            self.assertEqual(len(prep.provider.retrieve("Atlas SQLite?", "developer").facts), 1)
            prep.revoke(selected.source_id, capability=cap)
            redacted = export_memory_snapshot(reopened)
            self.assertNotIn(b"local transactions were needed", redacted)
            self.assertNotIn(b"Atlas project notes", redacted)

    def test_unsupported_or_invalid_bytes_leave_no_source(self):
        for data, typ in ((b"I wrote tests.", "html"), (b"\xff", "txt"), (b"", "txt")):
            with self.subTest(typ=typ), self.assertRaises(ValueError):
                self.prep.select_bytes(data, file_type=typ, purpose="resume", label="Selected",
                    role="developer", observed_at=STAMP, capability=self.cap)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM source").fetchone()[0], 0)

    def test_native_conversion_keeps_paragraph_locator(self):
        from hashlib import sha256
        data = b"synthetic-converter-input"
        result = _from_records([("I wrote Atlas SQL tests.", None, 3)], backend="native",
                               document_sha256=sha256(data).hexdigest())
        with patch("relay_spike.profile_preparation.convert_document", return_value=result):
            selected = self.prep.select_bytes(data, file_type="docx", purpose="project", label="Atlas",
                    role="developer", observed_at=STAMP, capability=self.cap)
        card, = selected.cards
        self.prep.decide(card.fact_id, card.card_fingerprint, decision="approve", actor="self",
                          claim_key="atlas.tests", capability=self.cap)
        self.assertEqual(self.prep.provider.retrieve("Atlas SQL?", "developer").facts[0].evidence.locator,
                         "docx:paragraph:3")

    def test_snapshots_fail_closed_on_corruption_and_limit(self):
        for snapshot in (b"", b"not a SQLite database", b"x" * (8*1024*1024+1)):
            with self.subTest(size=len(snapshot)), self.assertRaises(ValueError):
                restore_memory_snapshot(snapshot)

    def test_job_unicode_byte_and_control_bounds_preserve_frame_limit(self):
        for text in ("🧪" * 4000, "\x01" * 3000):
            with self.subTest(text_length=len(text)), self.assertRaises(ValueError):
                self.prep.select_bytes(text.encode(), file_type="txt", purpose="job", label="Selected job",
                    role="developer", observed_at=STAMP, capability=self.cap)
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM source").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
