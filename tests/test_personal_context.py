"""Synthetic reviewed facts; never read user files or credentials."""
from dataclasses import replace
import unittest

from relay_spike.personal_brain import BrainStore, UserConfirmation
from relay_spike.resume_candidates import ReviewGateway
from relay_spike.personal_context import BrainContextProvider

STAMP = "2026-10-23T00:00:00+00:00"


class PersonalContextTests(unittest.TestCase):
    def setUp(self):
        self.store = BrainStore()
        self.cap = object()
        self.gateway = ReviewGateway(self.store, host_capability=self.cap)
        self.provider = BrainContextProvider(self.store)

    def tearDown(self):
        self.store.close()

    def approve(self, text, key, actor="self"):
        source = self.gateway.select_source(text, observed_at=STAMP, capability=self.cap)
        card, = self.gateway.stage(source, text, observed_at=STAMP)
        self.gateway.decide(card, decision="approve", capability=self.cap,
                            approved_actor=actor, claim_key=key)
        return source, card

    def test_relevant_reviewed_spans_only_and_no_skill_inference(self):
        source, card = self.approve("I implemented SQL validation for Atlas.", "atlas.sql")
        self.approve("We designed Atlas dashboards.", "atlas.dashboards", "team")
        self.gateway.stage(self.gateway.select_source("I used Power BI.", observed_at=STAMP,
                          capability=self.cap), "I used Power BI.", observed_at=STAMP)
        bundle = self.provider.retrieve("How did you validate SQL in Atlas?", "data analyst", budget=1)
        self.assertEqual(bundle.status, "ready")
        fact, = bundle.facts
        self.assertEqual((fact.fact_id, fact.source_id, fact.actor, fact.text),
                         (card.fact_id, source, "self", "I implemented SQL validation for Atlas."))
        self.assertEqual(fact.evidence.source_sha256, card.source_sha256)
        self.assertEqual((fact.evidence.span_start, fact.evidence.span_end), (0, 39))
        self.assertTrue(self.provider.validate_current(bundle))
        absent = self.provider.retrieve("What Power BI reports did you build?", "data analyst")
        self.assertEqual(absent.facts, ())
        self.assertEqual(absent.status, "no_evidence")

    def test_team_and_teammate_ownership_survives_retrieval(self):
        self.approve("We built Atlas reporting.", "atlas.reporting", "team")
        self.approve("My teammate built Atlas ingestion.", "atlas.ingestion", "teammate")
        bundle = self.provider.retrieve("Tell me about Atlas", "developer", project_hint="Atlas")
        self.assertEqual({f.actor for f in bundle.facts}, {"team", "teammate"})

    def test_revocation_and_supersession_retire_existing_bundle(self):
        source, old = self.approve("I built Atlas SQL tests.", "atlas.tests")
        original = self.provider.retrieve("Atlas SQL tests?", "developer")
        other_source = self.gateway.select_source("I wrote Atlas SQL integration tests.",
                              observed_at=STAMP, capability=self.cap)
        new, = self.gateway.stage(other_source, "I wrote Atlas SQL integration tests.", observed_at=STAMP)
        self.gateway.decide(new, decision="approve", capability=self.cap, approved_actor="self",
                            claim_key="atlas.tests", replaces_fact_id=old.fact_id)
        self.assertFalse(self.provider.validate_current(original))
        current = self.provider.retrieve("Atlas SQL tests?", "developer")
        self.assertEqual([f.fact_id for f in current.facts], [new.fact_id])
        self.gateway.revoke_selected_source(other_source, capability=self.cap)
        self.assertFalse(self.provider.validate_current(current))
        self.assertEqual(self.provider.retrieve("Atlas SQL tests?", "developer").status, "revoked")

    def test_a_copied_bundle_is_not_host_authority(self):
        self.approve("I wrote Atlas SQL tests.", "atlas.tests")
        current = self.provider.retrieve("Atlas SQL tests?", "developer")
        self.assertFalse(self.provider.validate_current(replace(current)))
        self.assertFalse(self.provider.validate_current(replace(current, facts=())))
        self.assertFalse(BrainContextProvider(self.store).validate_current(current))

    def test_cross_source_experience_revocation_removes_dependent_fact(self):
        source, card = self.approve("I wrote Atlas SQL tests.", "atlas.tests")
        grouping_source = self.store.register_source(kind="user_statement", observed_at=STAMP)
        self.store.grant_consent(grouping_source, confirmation=UserConfirmation("group-consent"))
        experience = self.store.add_experience(source_id=grouping_source, label="Atlas")
        self.store.db.execute("UPDATE candidate_fact SET experience_id=? WHERE id=?", (experience, card.fact_id))
        bundle = self.provider.retrieve("Atlas SQL tests?", "developer")
        self.store.revoke_source(grouping_source, confirmation=UserConfirmation("group-revoke"))
        self.assertFalse(self.provider.validate_current(bundle))
        self.assertEqual(self.provider.retrieve("Atlas SQL tests?", "developer").facts, ())

    def test_legacy_without_exact_reviewed_evidence_is_not_emitted(self):
        source = self.store.register_source(kind="user_statement", observed_at=STAMP)
        self.store.grant_consent(source, confirmation=UserConfirmation("source-consent"))
        fact = self.store.add_candidate(source_id=source, claim_key="atlas.sql",
                claim_text="I built Atlas SQL.", actor="self", observed_at=STAMP)
        self.store.confirm_fact(fact, confirmation=UserConfirmation("legacy-approval"))
        result = self.provider.retrieve("Atlas SQL?", "developer")
        self.assertEqual(result.facts, ())
        self.assertIn("reviewed_source_spans", result.missing_fields)

    def test_pending_contradiction_is_distinct_from_absence(self):
        source, _ = self.approve("I built Atlas SQL in Python.", "atlas.sql")
        self.store.add_candidate(source_id=source, claim_key="atlas.sql",
                claim_text="I built Atlas SQL in Java.", actor="self", observed_at=STAMP)
        result = self.provider.retrieve("Atlas SQL?", "developer")
        self.assertEqual(result.status, "conflict")
        self.assertEqual(result.facts, ())
        self.assertIn("resolve_conflicting_facts", result.missing_fields)

    def test_invalid_bounds_and_missing_role_fail_closed(self):
        for budget in (True, 0, 17, -1, "2"):
            with self.subTest(budget=budget), self.assertRaises(ValueError):
                self.provider.retrieve("Atlas?", "developer", budget=budget)
        with self.assertRaises(ValueError):
            self.provider.retrieve("Atlas?", "")


if __name__ == "__main__":
    unittest.main()
