"""Fictional selected text, actual ledger/review/snapshot boundaries."""
from dataclasses import asdict, replace
from hashlib import sha256
import json
import sqlite3
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from relay_spike.personal_brain import BrainStore, BrainError, SCHEMA, EVIDENCE_SCHEMA
from relay_spike.profile_preparation import ProfilePreparation, export_memory_snapshot, restore_memory_snapshot

STAMP = '2026-10-23T00:00:00+00:00'
RESUME = '''Education
Cedar University | BSc Computing | Expected 2027 | GPA: 3.8/4.0
Experience
Harbor Labs | Software Engineer | June–August 2024
- I implemented a queue using Python.
- Our team reduced handoff errors.
Projects
Nurse Handoff | 2024
- I designed the review workflow in R.
Skills
Languages: Python, C++, R
Certifications
Data Foundations | Cedar Institute | In progress
Summary
Student interested in reliable systems.
'''


class ResumeStructureTests(unittest.TestCase):
    def setUp(self):
        self.store = BrainStore(); self.addCleanup(self.store.close)
        self.cap = object(); self.prep = ProfilePreparation(self.store, host_capability=self.cap)

    def select(self, text=RESUME):
        return self.prep.select_bytes(text.encode(), file_type='txt', purpose='resume',
            label='Fictional résumé', role='developer', observed_at=STAMP, capability=self.cap)

    def structured(self, selected):
        self.assertTrue(selected.cards)
        self.assertTrue(all(getattr(c, 'schema_version', None) == 2 for c in selected.cards))
        return selected.cards

    def approve(self, card, actor='self', key='fixture.one'):
        self.assertTrue(callable(getattr(self.prep, 'decide_v2', None)))
        self.prep.decide_v2(card.fact_id, card.card_fingerprint, decision='approve',
            actor=actor, claim_key=key, replaces_fact_id=None, card_version=2,
            context_sha256=card.context_sha256, capability=self.cap)

    def test_sections_and_relationships_are_separate_exact_unverified_spans(self):
        selected = self.select(); cards = self.structured(selected)
        self.assertEqual({c.claim_kind for c in cards},
            {'education', 'employment', 'contribution', 'project', 'listed_skill', 'certification', 'summary'})
        for card in cards:
            self.assertEqual(RESUME[card.span_start:card.span_end], card.snippet)
            self.assertEqual(card.snippet_sha256, sha256(card.snippet.encode()).hexdigest())
            self.assertLessEqual(len(json.dumps(asdict(card), ensure_ascii=False).encode()), 12*1024)
            for field in card.review_context.fields:
                self.assertEqual(RESUME[field.span_start:field.span_end], field.text)
                self.assertEqual(field.sha256, sha256(field.text.encode()).hexdigest())
                self.assertTrue(field.locator.startswith('text:line:'))
        self.assertEqual(self.prep.provider.retrieve('Cedar Python education?', 'developer').facts, ())

    def test_old_decision_cannot_approve_v2_even_with_the_actual_fingerprint(self):
        card = self.structured(self.select())[0]
        before = export_memory_snapshot(self.store)
        with self.assertRaises(BrainError):
            self.prep.decide(card.fact_id, card.card_fingerprint, decision='approve',
                actor='self', claim_key='education.one', capability=self.cap)
        self.assertEqual(export_memory_snapshot(self.store), before)

    def test_explicit_review_survives_restore_and_source_revocation_redacts_context(self):
        selected = self.select(); card = self.structured(selected)[0]
        self.approve(card)
        with restore_memory_snapshot(export_memory_snapshot(self.store)) as restored:
            cap = object(); prep = ProfilePreparation(restored, host_capability=cap)
            row = restored.db.execute('SELECT * FROM candidate_resume_context WHERE fact_id=?', (card.fact_id,)).fetchone()
            self.assertEqual(row['approved_context_sha256'], card.context_sha256)
            self.assertIsNotNone(row['confirmation_event_id'])
            self.assertEqual(restored.verified_claims()[0].claim_text, card.snippet)
            prep.revoke(selected.source_id, capability=cap)
            self.assertEqual(restored.db.execute('SELECT COUNT(*) FROM candidate_resume_context').fetchone()[0], 0)
            self.assertNotIn(b'Cedar University', export_memory_snapshot(restored))

    def test_changed_context_receipt_rolls_back_approval(self):
        card = self.structured(self.select())[0]
        before = export_memory_snapshot(self.store)
        with self.assertRaises(BrainError):
            self.prep.decide_v2(card.fact_id, card.card_fingerprint, decision='approve',
                actor='self', claim_key='education.one', replaces_fact_id=None, card_version=2,
                context_sha256='0'*64, capability=self.cap)
        self.assertEqual(export_memory_snapshot(self.store), before)

    def test_unicode_offsets_and_literal_gpa_skill_status_values(self):
        text = RESUME.replace('Cedar University', 'Ce\u0301dar 🧪 University')
        cards = self.structured(self.select(text))
        self.assertTrue(any(c.snippet == 'C++' for c in cards))
        self.assertTrue(any(c.snippet == 'R' for c in cards))
        fields = [f for c in cards for f in c.review_context.fields]
        self.assertTrue(any(f.kind == 'gpa' and f.text == 'GPA: 3.8/4.0' for f in fields))
        self.assertTrue(any(f.kind == 'status' and f.text == 'In progress' for f in fields))
        for field in fields:
            self.assertEqual(text[field.span_start:field.span_end], field.text)

    def test_unparsed_long_entry_retires_context_instead_of_dropping_qualifiers(self):
        text = 'Experience\nHarbor | Engineer | Expected 2027\n' + 'Ambiguous ' + 'x'*601 + '\n- I wrote tests.\n'
        selected = self.select(text); cards = self.structured(selected)
        last = cards[-1]
        self.assertEqual(last.snippet, 'I wrote tests.')
        self.assertFalse(any(f.kind in ('employer','title','date') for f in last.review_context.fields))
        row = self.store.db.execute('SELECT coverage_json FROM profile_resume_coverage WHERE source_id=?', (selected.source_id,)).fetchone()
        self.assertIn('line_budget', json.loads(row[0])['codes'])

    def test_unresolved_two_line_header_is_partial_and_not_a_guessed_employer(self):
        selected = self.select('Experience\nUnresolved Employer\n- I wrote tests.\n')
        card, = self.structured(selected)
        self.assertFalse(any(f.kind == 'employer' for f in card.review_context.fields))
        coverage = json.loads(self.store.db.execute('SELECT coverage_json FROM profile_resume_coverage WHERE source_id=?', (selected.source_id,)).fetchone()[0])
        self.assertEqual(coverage['unclassified_lines'], 1)
        self.assertIn('ambiguous_entry', coverage['codes'])

    def test_reimport_adds_v2_without_mutating_confirmed_v1_claim(self):
        text = 'Projects\nHarbor Monitor | 2024\nI wrote Python tests.\n'
        source = self.prep.gateway.select_source(text, observed_at=STAMP, capability=self.cap)
        old, = self.prep.gateway.stage(source, text, observed_at=STAMP)
        self.prep.gateway.decide(old, decision='approve', capability=self.cap,
            approved_actor='self', claim_key='old.tests')
        selected = self.select(text); cards = self.structured(selected)
        self.assertNotEqual(selected.source_id, source)
        self.assertTrue(any(c.snippet == old.snippet for c in cards))
        self.assertEqual(self.store.verified_claims()[0].fact_id, old.fact_id)
        self.assertEqual(self.store.verified_claims()[0].claim_text, old.snippet)
        self.assertIsNone(self.store.db.execute('SELECT 1 FROM candidate_resume_context WHERE fact_id=?', (old.fact_id,)).fetchone())

    def test_produced_cross_source_field_rolls_back_the_whole_import(self):
        from relay_spike.resume_structure import extract_resume_structure
        extracted = extract_resume_structure(RESUME, lambda start, end: 'text:line:'+str(RESUME.count('\n', 0, start)+1))
        card = extracted.candidates[0]; field = card.context.fields[-1]
        changed = 'x'*len(field.text)
        forged = replace(field, text=changed, sha256=sha256(changed.encode()).hexdigest())
        context = replace(card.context, fields=(*card.context.fields[:-1], forged))
        result = replace(extracted, candidates=(replace(card, context=context), *extracted.candidates[1:]))
        with patch('relay_spike.profile_preparation.extract_resume_structure', return_value=result):
            with self.assertRaises(BrainError): self.select()
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM source').fetchone()[0], 0)

    def test_produced_oversized_primary_rolls_back_instead_of_publishing_a_bad_card(self):
        from relay_spike.resume_structure import extract_resume_structure
        claim = 'I '+('x'*600)
        text = 'Projects\nAlpha | Expected 2027\n- '+claim+'\n'
        extracted = extract_resume_structure(text, lambda start, end: 'text:line:'+str(text.count('\n', 0, start)+1))
        start = text.index(claim)
        bad = replace(extracted.candidates[0], claim_kind='contribution', snippet=claim,
                      span_start=start, span_end=start+len(claim), locator='text:line:3')
        with patch('relay_spike.profile_preparation.extract_resume_structure', return_value=replace(extracted, candidates=(bad,))):
            with self.assertRaises(BrainError): self.select(text)
        self.assertEqual(self.store.db.execute('SELECT COUNT(*) FROM source').fetchone()[0], 0)


class ResumeMigrationTests(unittest.TestCase):
    def test_v2_upgrade_and_repeat_open_preserve_records(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'synthetic.sqlite'
            db = sqlite3.connect(path)
            db.executescript(SCHEMA+EVIDENCE_SCHEMA+'PRAGMA user_version=2;')
            db.close()
            for _ in range(2):
                with BrainStore(path) as store:
                    self.assertEqual(store.db.execute('PRAGMA user_version').fetchone()[0], 3)
                    self.assertEqual(store.db.execute('SELECT COUNT(*) FROM candidate_resume_context').fetchone()[0], 0)

    def test_invalid_v2_foreign_key_does_not_commit_schema3(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)/'synthetic.sqlite'
            db = sqlite3.connect(path)
            db.executescript(SCHEMA+EVIDENCE_SCHEMA+'PRAGMA user_version=2;')
            db.execute("INSERT INTO candidate_fact (id,source_id,actor,state,observed_at,created_at) VALUES ('bad','missing','unknown','candidate',?,?)", (STAMP, STAMP))
            db.commit(); db.close()
            with self.assertRaises(BrainError): BrainStore(path)
            db = sqlite3.connect(path)
            try:
                self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 2)
                self.assertIsNone(db.execute("SELECT 1 FROM sqlite_master WHERE name='candidate_resume_context'").fetchone())
            finally: db.close()
