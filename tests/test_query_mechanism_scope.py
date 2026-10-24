"""Query admission and final biography publication are separate authorities."""
import json
import unittest

from relay_spike.generated_answer import CardError, parse_generated_card, requires_personal_evidence
from relay_spike.session_host import SessionHost
from tests.test_session_host import start
from tests.test_user_question import question

TECHNICAL = (
    'How does that queue work?',
    'How does a queue work?',
    'What does this function do?',
    'How does Python work?',
    'What does PostgreSQL do?',
    'How does React handle state?',
    'How does Python implement lists?',
    'How does PostgreSQL execute a query?',
    # Admission allows generic coaching about this ambiguous present process;
    # it supplies no evidence of Morgan's real implementation or biography.
    'How does Morgan implement a queue?',
    'How does Morgan work?',
)
PERSONAL = (
    'How did you build that queue?',
    'What did you personally implement?',
    'How did Morgan implement the queue?',
    'How did morgan implement the queue?',
    'How does your queue work?',
    'What does your resume say about education?',
    'How does my team implement the queue?',
    'How does our team implement the queue?',
    'Where does Priya work?',
    "Describe Elena's contribution to the Atlas project.",
    'State service was built by morgan.',
    'How does Python implement lists when Morgan built the allocator?',
    'How does Python implement lists and Morgan implements the allocator?',
    'How does Python implement lists built by morgan?',
    'How does Python implement lists? State service was built by morgan.',
    'How does Python implement lists Morgan built?',
)


def card(lead='Explain FIFO ordering.'):
    return json.dumps(dict(lead=lead, points=['Check bounded storage and empty input.'],
        detail=None, assumptions=[], coverage=['current_request'], personal_fact_ids=[]))


class QueryMechanismClassificationTests(unittest.TestCase):
    def test_present_processes_do_not_require_a_personal_vault(self):
        for value in TECHNICAL:
            with self.subTest(value=value):
                self.assertFalse(requires_personal_evidence(value))

    def test_history_ownership_and_other_attributed_clauses_still_require_facts(self):
        for value in PERSONAL:
            with self.subTest(value=value):
                self.assertTrue(requires_personal_evidence(value))

    def test_generated_attribution_guard_remains_unchanged(self):
        for lead in ('State service was built by morgan.',
                     'Explain how Morgan implemented the queue.',
                     'State morgan built the allocator.'):
            with self.subTest(lead=lead), self.assertRaises(CardError):
                parse_generated_card(card(lead))


class QueryMechanismHostTests(unittest.IsolatedAsyncioTestCase):
    async def host(self, lead='Explain FIFO ordering.'):
        emitted, prompts = [], []
        async def complete(prompt, instructions):
            prompts.append(json.loads(prompt)); return card(lead)
        host = SessionHost(complete=complete, emit=emitted.append)
        await host.handle(start())
        self.addAsyncCleanup(host.drain); self.addCleanup(host.close)
        return host, emitted, prompts

    async def test_actual_typed_technical_basis_routes_followups_without_personal_context(self):
        for text in TECHNICAL:
            with self.subTest(text=text):
                host, emitted, prompts = await self.host()
                basis = question(host, 'Implement a bounded queue.')
                self.assertTrue(await host.handle_user_question(basis)); await host.drain()
                self.assertEqual(emitted[-1]['disposition'], 'answer')
                request = question(host, text, basis=basis['requestID'])
                self.assertTrue(await host.handle_user_question(request)); await host.drain()
                self.assertEqual(emitted[-1]['disposition'], 'answer')
                self.assertEqual(emitted[-1]['reasonCode'], 'format_checked')
                self.assertEqual(emitted[-1]['question'], text)
                self.assertEqual(prompts[-1]['current_request'], text)
                self.assertIn('bounded queue', str(prompts[-1]['conversation']['task']))
                self.assertEqual(host.model_requests, 2)

    async def test_personal_negative_matrix_never_falls_through_to_the_model(self):
        host, emitted, prompts = await self.host()
        for text in PERSONAL:
            with self.subTest(text=text):
                self.assertTrue(await host.handle_user_question(question(host, text))); await host.drain()
                self.assertEqual(emitted[-1]['reasonCode'], 'personal_context_missing')
                self.assertIsNone(emitted[-1]['card'])
        self.assertEqual(prompts, []); self.assertEqual(host.model_requests, 0)

    async def test_eligible_ambiguous_process_cannot_publish_an_unsupported_person_claim(self):
        host, emitted, prompts = await self.host('State service was built by morgan.')
        self.assertTrue(await host.handle_user_question(question(host, 'How does Morgan implement a queue?')))
        await host.drain()
        self.assertEqual(len(prompts), 1)
        self.assertEqual(emitted[-1]['disposition'], 'abstain')
        self.assertEqual(emitted[-1]['reasonCode'], 'answer_unavailable')
        self.assertIsNone(emitted[-1]['card'])
