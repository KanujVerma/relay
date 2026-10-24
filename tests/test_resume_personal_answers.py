"""Actual review/restore/provider/Host, fictional résumé and zero model IO."""
import unittest
from dataclasses import replace

from relay_spike.personal_brain import BrainStore
from relay_spike.profile_preparation import ProfilePreparation, export_memory_snapshot, restore_memory_snapshot
from relay_spike.session_host import SessionHost
from tests.test_resume_structure import RESUME, STAMP
from tests.test_session_host import start
from tests.test_user_question import question


class ResumePersonalAnswers(unittest.IsolatedAsyncioTestCase):
    async def prepared(self, text=RESUME, choose=lambda c: True):
        store = BrainStore(); cap = object(); prep = ProfilePreparation(store, host_capability=cap)
        selected = prep.select_bytes(text.encode(), file_type='txt', purpose='resume',
            label='Fictional résumé', role='developer', observed_at=STAMP, capability=cap)
        self.assertTrue(all(getattr(c, 'schema_version', None) == 2 for c in selected.cards))
        for card in selected.cards:
            if choose(card):
                prep.decide_v2(card.fact_id, card.card_fingerprint, decision='approve',
                    actor=card.actor_hint if card.actor_hint != 'unknown' else 'self',
                    claim_key='fixture.'+card.fact_id, replaces_fact_id=None, card_version=2,
                    context_sha256=card.context_sha256, capability=cap)
        snapshot = export_memory_snapshot(store); store.close()
        restored = restore_memory_snapshot(snapshot); self.addCleanup(restored.close)
        self.reopen_cap = object()
        reopened = ProfilePreparation(restored, host_capability=self.reopen_cap)
        emitted = []
        async def forbidden(*args): self.fail('Personal renderer called inference')
        host = SessionHost(personal_provider=reopened.provider, complete=forbidden, emit=emitted.append)
        await host.handle(start()); self.addCleanup(host.close); self.addAsyncCleanup(host.drain)
        return host, emitted, reopened, selected

    async def ask(self, host, out, text):
        self.assertTrue(await host.handle_user_question(question(host, text)))
        await host.drain(); return out[-1]

    async def test_education_expected_gpa_and_employment_context_survive_actual_restore(self):
        host, out, _, _ = await self.prepared()
        for text, expected in (
            ('Where were you educated?', ('BSc Computing', 'Cedar University', 'Expected 2027', 'GPA: 3.8/4.0')),
            ('What is your GPA?', ('GPA: 3.8/4.0',)),
            ('Where were you employed?', ('Software Engineer', 'Harbor Labs', 'June–August 2024')),
            ('Which certifications do you list?', ('Data Foundations', 'Cedar Institute', 'In progress'))):
            with self.subTest(text=text):
                result = await self.ask(host, out, text)
                self.assertEqual(result['reasonCode'], 'grounded_personal')
                points = ' '.join(result['card']['points'])
                for value in expected: self.assertIn(value, points)
                self.assertLessEqual(len(result['card']['points']), 2)
                self.assertTrue(all(len(p.encode()) <= 180 for p in result['card']['points']))
        self.assertEqual(host.model_requests, 0)

    async def test_literal_completed_degree_and_certification_status_are_not_inferred(self):
        text = RESUME.replace('Expected 2027', 'Completed 2024').replace('In progress', 'Awarded 2025')
        host, out, _, _ = await self.prepared(text)
        degree = await self.ask(host, out, 'What education is on your resume?')
        self.assertIn('Completed 2024', str(degree['card']))
        cert = await self.ask(host, out, 'Which certifications do you list?')
        self.assertIn('Awarded 2025', str(cert['card']))
        self.assertNotIn('years', str(cert['card']))

    async def test_cpp_and_r_retrieval_preserves_listed_skill_semantics(self):
        host, out, prep, _ = await self.prepared()
        for skill in ('C++', 'R'):
            with self.subTest(skill=skill):
                bundle = prep.provider.retrieve('Is '+skill+' in your listed skills?', 'developer')
                self.assertEqual({f.text for f in bundle.facts}, {skill})
                result = await self.ask(host, out, 'Is '+skill+' in your listed skills?')
                self.assertEqual(result['reasonCode'], 'grounded_personal')
                self.assertIn('Listed skill: '+skill, str(result['card']))
                self.assertNotIn('proficient', str(result['card']).casefold())
        unknown = await self.ask(host, out, 'Is Swift in your listed skills?')
        self.assertEqual(unknown['reasonCode'], 'personal_context_missing')

    async def test_listed_skill_does_not_prove_actual_use_or_proficiency(self):
        host, out, prep, _ = await self.prepared(choose=lambda c: c.claim_kind == 'listed_skill')
        for text in ('How did you use Python?', 'How proficient are you in R?', 'How many years of C++ experience do you have?'):
            with self.subTest(text=text):
                result = await self.ask(host, out, text)
                self.assertEqual(result['reasonCode'], 'personal_context_missing')
                self.assertIsNone(result['card'])
        self.assertEqual(prep.provider.retrieve('How did you use Python?', 'developer').facts, ())

    async def test_actual_tool_use_uses_only_the_self_contribution_mention(self):
        host, out, _, _ = await self.prepared()
        result = await self.ask(host, out, 'How did you use Python?')
        self.assertEqual(result['reasonCode'], 'grounded_personal')
        self.assertIn('I implemented a queue using Python.', str(result['card']))
        self.assertNotIn('Listed skill:', str(result['card']))
        missing = await self.ask(host, out, 'Have you used Swift?')
        self.assertEqual(missing['reasonCode'], 'personal_context_missing')

    async def test_current_typed_intent_keeps_but_does_not_render_an_earlier_category(self):
        host, out, _, _ = await self.prepared()
        earlier = question(host, 'Where were you educated?')
        self.assertTrue(await host.handle_user_question(earlier)); await host.drain()
        self.assertEqual(out[-1]['reasonCode'], 'grounded_personal')
        follow = question(host, 'Is C++ in your listed skills?', basis=earlier['requestID'])
        self.assertTrue(await host.handle_user_question(follow)); await host.drain()
        self.assertIn('Listed skill: C++', str(out[-1]['card']))
        self.assertNotIn('Education:', str(out[-1]['card']))

    async def test_team_role_date_cannot_establish_self_biography(self):
        text = 'Experience\nHarbor Labs | Engineer | 2024\n- Our team built the Python service.\n'
        host, out, prep, _ = await self.prepared(text, choose=lambda c: c.claim_kind == 'contribution')
        for text in ('Where were you employed at Harbor Labs?', 'What was your job title at Harbor Labs?', 'What did you personally implement at Harbor Labs?'):
            with self.subTest(text=text):
                self.assertEqual(prep.provider.retrieve(text, 'developer').facts, ())
                result = await self.ask(host, out, text)
                self.assertEqual(result['reasonCode'], 'personal_context_missing')
        honest = await self.ask(host, out, 'What did your team build at Harbor Labs?')
        self.assertEqual(honest['reasonCode'], 'grounded_personal')
        self.assertTrue(honest['card']['points'][0].startswith('Team contribution:'))
        self.assertNotIn('Your contribution:', str(honest['card']))

    async def test_entry_name_finds_actual_self_contribution_and_revoke_retires_bundle(self):
        host, out, prep, selected = await self.prepared()
        bundle = prep.provider.retrieve('What did you personally do on Nurse Handoff?', 'developer')
        self.assertTrue(bundle.facts)
        self.assertTrue(all(f.actor == 'self' and f.text.startswith('I designed') for f in bundle.facts))
        self.assertFalse(prep.provider.validate_current(replace(bundle)))
        result = await self.ask(host, out, 'What did you personally do on Nurse Handoff?')
        self.assertIn('Nurse Handoff', str(result['card']))
        prep.revoke(selected.source_id, capability=self.reopen_cap)
        self.assertFalse(prep.provider.validate_current(bundle))
        result = await self.ask(host, out, 'What did you personally do on Nurse Handoff?')
        self.assertEqual(result['reasonCode'], 'personal_context_missing')

    async def test_whole_long_unit_is_withheld_without_dropping_a_date(self):
        text = 'Projects\nHarbor Monitor | Expected 2027\n- I designed '+('reliable '*20)+'storage.\n'
        host, out, _, _ = await self.prepared(text, choose=lambda c: c.claim_kind == 'contribution')
        result = await self.ask(host, out, 'What did you personally design on Harbor Monitor?')
        self.assertEqual(result['reasonCode'], 'personal_detail_budget')
        self.assertIsNone(result['card'])

    async def test_context_text_counts_toward_the_existing_provider_budget(self):
        text = 'Projects\n'+''.join(
            'Project '+str(i)+'x'*120+' | Expected 2027 '+'x'*120+'\n- I designed '+('storage '*60)+'tests.\n'
            for i in range(16))
        _, _, prep, _ = await self.prepared(text, choose=lambda c: c.claim_kind == 'contribution')
        bundle = prep.provider.retrieve('Tell me about yourself.', 'developer', budget=16)
        self.assertTrue(bundle.facts)
        size = sum(len(f.text)+sum(len(field.text) for field in f.resume_context.context.fields) for f in bundle.facts)
        self.assertLessEqual(size, 8000)

    async def test_named_employer_selection_does_not_leak_another_entry_sharing_labs(self):
        text = ('Experience\nBirch Labs | Engineer | 2023\n- I implemented a cache using C++.\n'
                'Cedar Labs | Analyst | Expected 2027\n- I built a dashboard using R.\n'
                'Skills\nLanguages: C++, R\n')
        host, out, prep, _ = await self.prepared(text)
        for name, other, qualifier in (('Birch Labs','Cedar Labs','2023'), ('Cedar Labs','Birch Labs','Expected 2027')):
            with self.subTest(name=name):
                value = await self.ask(host, out, 'What did you personally do at '+name+'?')
                self.assertEqual(value['reasonCode'], 'grounded_personal')
                self.assertIn(name, str(value['card'])); self.assertIn(qualifier, str(value['card']))
                self.assertNotIn(other, str(value['card']))
        for name in ('Ash Labs', 'Labs'):
            with self.subTest(unknown=name):
                value = await self.ask(host, out, 'What did you personally do at '+name+'?')
                self.assertEqual(value['reasonCode'], 'personal_context_missing')
                self.assertEqual(prep.provider.retrieve('What did you personally do at '+name+'?', 'developer').facts, ())
        broad = await self.ask(host, out, 'What did you personally implement?')
        self.assertEqual(broad['reasonCode'], 'grounded_personal')
        self.assertIn('Birch Labs', str(broad['card'])); self.assertIn('Cedar Labs', str(broad['card']))

    async def test_named_project_selection_requires_its_whole_reviewed_name(self):
        text = ('Projects\nHarbor Monitor | 2024\n- I wrote monitor checks using Python.\n'
                'Harbor Forecast | Expected 2027\n- I wrote forecasts using R.\n')
        host, out, _, _ = await self.prepared(text)
        for name, other in (('Harbor Monitor','Harbor Forecast'), ('Harbor Forecast','Harbor Monitor')):
            result = await self.ask(host, out, 'What did you personally do on '+name+'?')
            self.assertEqual(result['reasonCode'], 'grounded_personal')
            self.assertIn(name, str(result['card'])); self.assertNotIn(other, str(result['card']))
        for name in ('Harbor', 'Harbor Archive'):
            result = await self.ask(host, out, 'What did you personally do on '+name+'?')
            self.assertEqual(result['reasonCode'], 'personal_context_missing')
