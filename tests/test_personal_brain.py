"""Synthetic-only Personal Brain 02A-A migrations, consent and fact lifecycle."""
from __future__ import annotations

from pathlib import Path
import sqlite3
import tempfile
import unittest

from relay_spike.personal_brain import (
    BrainError, BrainStore, FactConflict, InvalidState, MissingEvidence,
    UserConfirmation, SCHEMA,
)

WHEN = "2026-10-22T09:00:00-05:00"


class BrainStoreTests(unittest.TestCase):
    def setUp(self):
        self.brain = BrainStore()
        self._counter = 0

    def tearDown(self):
        self.brain.close()

    def approval(self):
        self._counter += 1
        return UserConfirmation("synthetic-click-" + str(self._counter))

    def consented_source(self, *, kind="user_statement", ref=None):
        sid = self.brain.register_source(
            kind=kind, observed_at=WHEN, external_ref=ref,
            checksum="synthetic-checksum",
        )
        self.brain.grant_consent(sid, confirmation=self.approval())
        return sid

    def candidate(self, source, key="project.backend_owner",
                  text="I implemented the client only.", actor="self",
                  experience=None):
        return self.brain.add_candidate(
            source_id=source, claim_key=key, claim_text=text,
            actor=actor, observed_at=WHEN, experience_id=experience
        )

    def test_zero_dependency_sqlite_integrity_and_migration_idempotent(self):
        self.assertEqual(self.brain.db.execute("PRAGMA user_version").fetchone()[0], 2)
        self.assertEqual(self.brain.db.execute("PRAGMA foreign_keys").fetchone()[0], 1)
        self.assertEqual(self.brain.db.execute("PRAGMA secure_delete").fetchone()[0], 1)
        self.assertIsNone(self.brain.db.execute("PRAGMA foreign_key_check").fetchone())
        self.brain._migrate()
        self.assertEqual(self.brain.db.execute("PRAGMA user_version").fetchone()[0], 2)

    def test_version_reopens_on_disk_and_rejects_future_migration(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "only-synthetic-brain.db"
            with BrainStore(path) as first:
                sid = first.register_source(kind="resume", observed_at=WHEN)
                first.grant_consent(sid, confirmation=UserConfirmation("disk-consent"))
                fact = first.add_candidate(
                    source_id=sid, claim_key="role.owner",
                    claim_text="My own synthetic contribution.",
                    actor="self", observed_at=WHEN
                )
                first.confirm_fact(fact, confirmation=UserConfirmation("disk-approve"))
            with BrainStore(path) as second:
                self.assertEqual(second.verified_claims()[0].fact_id, fact)
                second.db.execute("PRAGMA user_version=99")
            with self.assertRaises(BrainError):
                BrainStore(path)

    def test_migrates_existing_v1_disk_database_without_losing_records(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "legacy-synthetic.db"
            with sqlite3.connect(path) as legacy:
                legacy.executescript(SCHEMA)
                legacy.execute("PRAGMA user_version=1")
                legacy.execute(
                    "INSERT INTO source (id,kind,observed_at) VALUES (?,?,?)",
                    ("existing-v1-id", "resume", WHEN),
                )
            with BrainStore(path) as migrated:
                self.assertEqual(migrated.db.execute(
                    "PRAGMA user_version").fetchone()[0], 2)
                self.assertEqual(migrated.db.execute(
                    "SELECT id FROM source WHERE id=?",
                    ("existing-v1-id",)).fetchone()[0], "existing-v1-id")
                self.assertIsNotNone(migrated.db.execute(
                    "SELECT name FROM sqlite_master WHERE name='candidate_evidence'"
                ).fetchone())
                migrated._migrate()
                self.assertEqual(migrated.db.execute(
                    "PRAGMA user_version").fetchone()[0], 2)

    def test_corrupt_legacy_v1_migration_rolls_back_schema_and_version(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "synthetic-orphan-v1.db"
            with sqlite3.connect(path) as legacy:
                legacy.executescript(SCHEMA)
                self.assertEqual(legacy.execute(
                    "PRAGMA foreign_keys").fetchone()[0], 0)
                legacy.execute(
                    "INSERT INTO candidate_fact "
                    "(id,source_id,claim_key,claim_text,actor,state,"
                    "observed_at,created_at) VALUES (?,?,?,?,?,?,?,?)",
                    ("orphan", "missing-source-id", "project.test",
                     "Untrusted synthetic claim", "self", "candidate",
                     WHEN, WHEN),
                )
                legacy.execute("PRAGMA user_version=1")
            with self.assertRaises(BrainError):
                BrainStore(path)
            with sqlite3.connect(path) as after:
                self.assertEqual(after.execute(
                    "PRAGMA user_version").fetchone()[0], 1)
                self.assertIsNone(after.execute(
                    "SELECT name FROM sqlite_master "
                    "WHERE name='candidate_evidence'"
                ).fetchone())
                self.assertIsNotNone(after.execute(
                    "PRAGMA foreign_key_check").fetchone())

    def test_migration_preserves_previously_confirmed_legacy_resume(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "synthetic-verified-v1.db"
            with sqlite3.connect(path) as legacy:
                legacy.executescript(SCHEMA)
                legacy.execute(
                    "INSERT INTO source "
                    "(id,kind,observed_at,consent_scope,consented_at)"
                    " VALUES (?,?,?,?,?)",
                    ("source-legacy", "resume", WHEN, "personal_brain", WHEN),
                )
                legacy.execute(
                    "INSERT INTO candidate_fact "
                    "(id,source_id,claim_key,claim_text,actor,state,"
                    "observed_at,created_at) VALUES (?,?,?,?,?,?,?,?)",
                    ("fact-legacy", "source-legacy", "project.legacy",
                     "Synthetic previously user-confirmed fact.",
                     "self", "confirmed", WHEN, WHEN),
                )
                legacy.execute(
                    "INSERT INTO history_event "
                    "(id,fact_id,action,confirmation_id,recorded_at)"
                    " VALUES (?,?,?,?,?)",
                    ("event-legacy", "fact-legacy", "fact_confirmed",
                     "synthetic-legacy-click", WHEN),
                )
                legacy.execute(
                    "INSERT INTO verified_fact "
                    "(fact_id,claim_key,confirmation_event_id,confirmed_at)"
                    " VALUES (?,?,?,?)",
                    ("fact-legacy", "project.legacy", "event-legacy", WHEN),
                )
                legacy.execute("PRAGMA user_version=1")
            with BrainStore(path) as upgraded:
                self.assertEqual(upgraded.db.execute(
                    "PRAGMA user_version").fetchone()[0], 2)
                self.assertEqual(upgraded.verified_claims(actor="self")[0].fact_id,
                                 "fact-legacy")

    def test_source_registration_requires_separate_consent(self):
        sid = self.brain.register_source(
            kind="github", observed_at=WHEN, external_ref="synthetic/repo"
        )
        self.assertEqual(self.brain.verified_claims(), ())
        with self.assertRaises(MissingEvidence):
            self.candidate(sid)
        self.brain.grant_consent(sid, confirmation=self.approval())
        pending = self.candidate(sid)
        self.assertEqual(self.brain.verified_claims(), ())
        self.brain.confirm_fact(pending, confirmation=self.approval())
        self.assertEqual(len(self.brain.verified_claims()), 1)
        self.assertEqual(self.brain.verified_claims()[0].source_id, sid)

    def test_explicit_user_approval_required_and_replay_rejected(self):
        sid = self.consented_source()
        fid = self.candidate(sid)
        with self.assertRaises(MissingEvidence):
            self.brain.confirm_fact(fid, confirmation="the assistant said yes")
        with self.assertRaises(MissingEvidence):
            self.brain.confirm_fact(fid, confirmation=None)
        self.assertEqual(self.brain.verified_claims(), ())
        approval = self.approval()
        self.brain.confirm_fact(fid, confirmation=approval)
        second = self.candidate(sid, "project.stack", "User confirmed a CLI build.")
        with self.assertRaises(InvalidState):
            self.brain.confirm_fact(second, confirmation=approval)
        self.assertEqual([c.fact_id for c in self.brain.verified_claims()], [fid])

    def test_unverified_ai_or_transcript_candidates_never_autopromote(self):
        for kind in ("model_suggestion", "transcript"):
            with self.subTest(kind=kind):
                sid = self.consented_source(kind=kind)
                self.candidate(sid, "candidate." + kind,
                               "The assistant suggested an unverified result.")
        self.assertEqual(self.brain.verified_claims(), ())
        self.assertEqual(
            [h.action for h in self.brain.history()].count("fact_confirmed"), 0
        )

    def test_known_ownership_and_team_attribution_are_not_conflated(self):
        sid = self.consented_source()
        experience = self.brain.add_experience(
            source_id=sid, label="Synthetic project"
        )
        mine = self.candidate(sid, "project.ui", "I designed the scanner UI.",
                              "self", experience)
        teammate = self.candidate(sid, "project.backend",
                                  "Another teammate built the backend.",
                                  "teammate", experience)
        team = self.candidate(sid, "project.pilot",
                              "We ran a pilot.", "team", experience)
        for fid in (mine, teammate, team):
            self.brain.confirm_fact(fid, confirmation=self.approval())
        self.assertEqual({v.actor for v in self.brain.verified_claims()},
                         {"self", "teammate", "team"})
        self.assertEqual([x.fact_id for x in self.brain.verified_claims(actor="self")],
                         [mine])
        self.assertIsNotNone(self.brain.verified_by_fact_id(teammate))
        unknown = self.candidate(sid, "project.unknown",
                                 "Unattributed code change.", "unknown")
        with self.assertRaises(MissingEvidence):
            self.brain.confirm_fact(unknown, confirmation=self.approval())

    def test_conflicting_claim_requires_explicit_atomic_supersession(self):
        sid = self.consented_source()
        first = self.candidate(sid, "project.backend_owner",
                               "I built the backend.", "self")
        self.brain.confirm_fact(first, confirmation=self.approval())
        replacement = self.candidate(sid, "project.backend_owner",
                                     "Teammate built backend.", "teammate")
        count = len(self.brain.history())
        with self.assertRaises(FactConflict):
            self.brain.confirm_fact(replacement, confirmation=self.approval())
        self.assertEqual(len(self.brain.history()), count)
        self.assertEqual(self.brain.verified_claims()[0].fact_id, first)
        with self.assertRaises(FactConflict):
            self.brain.confirm_fact(replacement, confirmation=self.approval(),
                                    replaces_fact_id="nonexistent")
        self.brain.confirm_fact(replacement, confirmation=self.approval(),
                                replaces_fact_id=first)
        self.assertEqual(len(self.brain.verified_claims()), 1)
        self.assertEqual(self.brain.verified_claims()[0].fact_id, replacement)
        self.assertEqual(self.brain.verified_claims()[0].actor, "teammate")
        old = self.brain.db.execute(
            "SELECT invalidation_reason FROM verified_fact WHERE fact_id=?",
            (first,)
        ).fetchone()
        self.assertEqual(old["invalidation_reason"], "superseded")
        self.assertIn("fact_superseded", [x.action for x in self.brain.history()])

    def test_cannot_replace_nonexistent_or_differently_keyed_fact(self):
        sid = self.consented_source()
        a = self.candidate(sid, "skill.python", "My Python skill.")
        b = self.candidate(sid, "skill.sql", "My SQL skill.")
        self.brain.confirm_fact(a, confirmation=self.approval())
        with self.assertRaises(FactConflict):
            self.brain.confirm_fact(b, confirmation=self.approval(),
                                    replaces_fact_id=a)
        self.assertEqual(self.brain.verified_by_fact_id(a).claim_key, "skill.python")

    def test_rejection_and_individual_revocation_redact_claim_text(self):
        sid = self.consented_source()
        pending = self.candidate(sid, "claim.rejected", "An incorrect claim.")
        self.brain.reject_candidate(pending, confirmation=self.approval())
        with self.assertRaises(InvalidState):
            self.brain.confirm_fact(pending, confirmation=self.approval())
        row = self.brain.db.execute(
            "SELECT claim_text FROM candidate_fact WHERE id=?", (pending,)
        ).fetchone()
        self.assertIsNone(row["claim_text"])
        fact = self.candidate(sid, "claim.active", "Approved only temporarily.")
        self.brain.confirm_fact(fact, confirmation=self.approval())
        self.brain.revoke_fact(fact, confirmation=self.approval())
        self.assertIsNone(self.brain.verified_by_fact_id(fact))
        self.assertEqual(self.brain.verified_claims(), ())
        self.assertIsNone(self.brain.db.execute(
            "SELECT claim_text FROM candidate_fact WHERE id=?", (fact,)
        ).fetchone()["claim_text"])

    def test_source_revocation_redacts_source_and_dependent_facts(self):
        sid = self.consented_source(ref="synthetic/private/path")
        exp = self.brain.add_experience(source_id=sid, label="Private synthetic label")
        approved = self.candidate(sid, "private.claim", "Secret sample value",
                                  experience=exp)
        draft = self.candidate(sid, "private.draft", "Candidate sample value")
        self.brain.confirm_fact(approved, confirmation=self.approval())
        self.brain.revoke_source(sid, confirmation=self.approval())
        self.assertEqual(self.brain.verified_claims(), ())
        self.assertIsNone(self.brain.verified_by_fact_id(approved))
        self.assertEqual(self.brain.db.execute(
            "SELECT consent_scope,external_ref,checksum FROM source WHERE id=?",
            (sid,)
        ).fetchone()["consent_scope"], "none")
        row = self.brain.db.execute(
            "SELECT external_ref,checksum FROM source WHERE id=?", (sid,)
        ).fetchone()
        self.assertIsNone(row["external_ref"])
        self.assertIsNone(row["checksum"])
        for fact in (approved, draft):
            candidate = self.brain.db.execute(
                "SELECT claim_text,claim_key,state FROM candidate_fact WHERE id=?",
                (fact,)
            ).fetchone()
            self.assertEqual(candidate["state"], "revoked")
            self.assertIsNone(candidate["claim_text"])
            self.assertIsNone(candidate["claim_key"])
        self.assertIsNone(self.brain.db.execute(
            "SELECT label FROM experience WHERE id=?", (exp,)
        ).fetchone()["label"])
        self.assertIn("source_invalidated", [x.action for x in self.brain.history()])
        with self.assertRaises(MissingEvidence):
            self.candidate(sid)
        with self.assertRaises(InvalidState):
            self.brain.grant_consent(sid, confirmation=self.approval())

    def test_revoking_experience_source_redacts_all_cross_source_dependencies(self):
        primary = self.consented_source(ref="synthetic/context")
        secondary = self.consented_source(ref="synthetic/other")
        exp = self.brain.add_experience(source_id=primary, label="Project scope")
        superseded = self.candidate(
            secondary, "cross.source", "Initial private project claim.",
            experience=exp
        )
        active = self.candidate(
            secondary, "cross.source", "Updated private project claim.",
            experience=exp
        )
        pending = self.candidate(
            secondary, "cross.pending", "Pending private draft.",
            experience=exp
        )
        self.brain.confirm_fact(superseded, confirmation=self.approval())
        self.brain.confirm_fact(active, confirmation=self.approval(),
                                replaces_fact_id=superseded)
        self.assertEqual(len(self.brain.verified_claims()), 1)
        self.brain.revoke_source(primary, confirmation=self.approval())
        self.assertEqual(self.brain.verified_claims(), ())
        for fact in (superseded, active, pending):
            row = self.brain.db.execute(
                "SELECT state,claim_text,claim_key FROM candidate_fact WHERE id=?",
                (fact,),
            ).fetchone()
            self.assertEqual(row["state"], "revoked")
            self.assertIsNone(row["claim_text"])
            self.assertIsNone(row["claim_key"])
        historical = self.brain.db.execute(
            "SELECT claim_key FROM verified_fact WHERE fact_id IN (?,?)",
            (superseded, active),
        ).fetchall()
        self.assertEqual(len(historical), 2)
        self.assertTrue(all(row["claim_key"] is None for row in historical))
        # The secondary source remains valid for unrelated new experiences.
        self.assertEqual(
            self.brain.db.execute(
                "SELECT consent_scope FROM source WHERE id=?", (secondary,)
            ).fetchone()["consent_scope"], "personal_brain"
        )
        self.assertGreaterEqual(
            [e.action for e in self.brain.history()].count("source_invalidated"), 3
        )

    def test_source_revocation_scrubs_superseded_historical_keys(self):
        sid = self.consented_source()
        old = self.candidate(sid, "sensitive.project_key", "Initial candidate work.")
        new = self.candidate(sid, "sensitive.project_key", "Corrected ownership work.")
        self.brain.confirm_fact(old, confirmation=self.approval())
        self.brain.confirm_fact(new, confirmation=self.approval(),
                                replaces_fact_id=old)
        self.assertEqual(self.brain.verified_claims()[0].fact_id, new)
        self.brain.revoke_source(sid, confirmation=self.approval())
        rows = self.brain.db.execute(
            "SELECT fact_id,claim_key,invalidation_reason FROM verified_fact"
        ).fetchall()
        self.assertEqual({r["fact_id"] for r in rows}, {old, new})
        self.assertTrue(all(r["claim_key"] is None for r in rows))
        self.assertTrue(all(r["invalidation_reason"] for r in rows))
        self.assertNotIn("sensitive.project_key",
                         repr(self.brain.verified_claims()))

    def test_history_is_immutable_and_does_not_store_claim_text(self):
        sid = self.consented_source()
        fact = self.candidate(sid, "synthetic.claim", "Private-synthetic-only-text")
        self.brain.confirm_fact(fact, confirmation=self.approval())
        events = self.brain.history()
        self.assertTrue(all(isinstance(e.id, str) for e in events))
        self.assertNotIn("Private-synthetic-only-text", repr(events))
        with self.assertRaises(sqlite3.IntegrityError):
            self.brain.db.execute(
                "UPDATE history_event SET action='fact_rejected'"
                " WHERE id=?", (events[-1].id,)
            )
        with self.assertRaises(sqlite3.IntegrityError):
            self.brain.db.execute(
                "DELETE FROM history_event WHERE id=?", (events[-1].id,)
            )

    def test_failure_cases_do_not_leak_personal_text(self):
        sid = self.consented_source()
        fact = self.candidate(sid, "claim", "Private synthetic detail")
        self.brain.confirm_fact(fact, confirmation=self.approval())
        candidate = self.candidate(sid, "claim", "Second private synthetic detail")
        try:
            self.brain.confirm_fact(candidate, confirmation=self.approval())
        except FactConflict as exc:
            self.assertNotIn("private", str(exc).lower())
            self.assertNotIn("detail", str(exc).lower())
        else:
            self.fail("Conflict should fail closed")

    def test_reject_invalid_source_actor_observation_and_approval(self):
        with self.assertRaises(BrainError):
            self.brain.register_source(kind="something_else", observed_at=WHEN)
        with self.assertRaises(BrainError):
            self.brain.register_source(kind="resume",
                                       observed_at="2026-10-22T09:00:00")
        sid = self.consented_source()
        with self.assertRaises(BrainError):
            self.candidate(sid, actor="assistant")
        with self.assertRaises(BrainError):
            self.candidate(sid, key="", text="test")
        with self.assertRaises(BrainError):
            self.candidate(sid, text="   ")

    def test_confirmation_event_replay_cannot_approve_two_sources(self):
        a = self.brain.register_source(kind="resume", observed_at=WHEN)
        b = self.brain.register_source(kind="github", observed_at=WHEN)
        confirm = self.approval()
        self.brain.grant_consent(a, confirmation=confirm)
        with self.assertRaises(InvalidState):
            self.brain.grant_consent(b, confirmation=confirm)
        self.assertEqual(self.brain.db.execute(
            "SELECT consent_scope FROM source WHERE id=?", (b,)
        ).fetchone()["consent_scope"], "none")


if __name__ == "__main__":
    unittest.main()
