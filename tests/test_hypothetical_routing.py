"""Prospective design routing regressions with synthetic native input and output."""
import json
import unittest

from relay_spike.generated_answer import requires_personal_evidence
from relay_spike.panel_wire import FrameDecoder, encode_frame
from relay_spike.session_host import SessionHost
from test_session_host import start, speech, end, final


CLINIC_CASE = 'Case study: design a workflow for a clinic intake team. What would you build?'
NEUTRAL_BUILD_REQUESTS = (
    CLINIC_CASE,
    'What would you build for these users?',
    'How would you build a booking system?',
    'Could you build a bounded cache for this service?',
    'Can you please build a workflow for the clinic intake team?',
    'How do you build an LRU cache?',
)
PERSONAL_REQUESTS = (
    'What did you build at Acme?',
    'What would you say you built at Acme?',
    'Case study: what did you build at Acme?',
    'What would you build, and what did you deliver at Acme?',
    'What would you build based on your resume?',
    'What would you build based on my project experience?',
    'What would you build based on the project you wrote?',
    'What would you build? Explain how Kanuj built the Atlas pipeline.',
    "What would you build based on Priya's contribution to the Atlas project?",
    'What would you build? The service was built by Morgan.',
    'Case study: describe a time you built a workflow.',
    'What have you built for these users?',
    'What would you build after describing where you were educated?',
)


def synthetic_card():
    return json.dumps(dict(
        lead='Clarify intake roles and required handoffs before choosing a workflow.',
        points=['Outline the current intake steps and identify delays.'],
        detail=None,
        assumptions=['The current intake process is unspecified.'],
        coverage=['users', 'workflow'],
        personal_fact_ids=[],
    ))


class HypotheticalClassifierTests(unittest.TestCase):
    def test_prospective_build_requests_use_the_neutral_route(self):
        for question in NEUTRAL_BUILD_REQUESTS:
            with self.subTest(question=question):
                self.assertFalse(requires_personal_evidence(question))

    def test_build_or_case_study_framing_never_overrides_personal_evidence(self):
        for question in PERSONAL_REQUESTS:
            with self.subTest(question=question):
                self.assertTrue(requires_personal_evidence(question))


class HypotheticalHostTests(unittest.IsolatedAsyncioTestCase):
    async def run_request(self, question):
        prompts, decisions = [], []

        async def complete(prompt, instructions):
            prompts.append(json.loads(prompt))
            return synthetic_card()

        host = SessionHost(complete=complete, emit=decisions.append)
        native = final(4, question)
        # Exercise actual length framing, native envelope validation, activity
        # association, task recording, routing and final card publication.
        frames = b''.join(encode_frame(row) for row in (start(), speech(2), end(3), native))
        for row in FrameDecoder().feed(frames):
            await host.handle(row)
        await host.drain()
        return host, native, prompts, decisions

    async def test_clinic_case_reaches_one_generated_card_with_current_task(self):
        host, native, prompts, decisions = await self.run_request(CLINIC_CASE)
        self.assertEqual(len(prompts), 1)
        self.assertEqual(host.model_requests, 1)
        self.assertEqual(prompts[0]['current_request'], CLINIC_CASE)
        self.assertEqual(prompts[0]['semantic_request'], CLINIC_CASE)
        task = prompts[0]['conversation']['task']
        self.assertEqual(task['kind'], 'case_study')
        self.assertEqual(task['known_problem'], [
            'Case study: design a workflow for a clinic intake team.',
            'What would you build?',
        ])
        self.assertEqual(task['state'], 'ready')
        self.assertEqual(task['stage'], 'flows')
        self.assertEqual(task['constraints'], [])
        answers = [row for row in decisions if row['disposition'] == 'answer']
        self.assertEqual(len(answers), 1)
        self.assertEqual(answers[0]['answerKind'], 'generated_suggestion')
        self.assertEqual(answers[0]['requestID'], native['requestID'])
        self.assertEqual(answers[0]['eventSequence'], 4)
        self.assertEqual(answers[0]['question'], CLINIC_CASE)
        self.assertEqual(answers[0]['card']['lead'],
                         'Clarify intake roles and required handoffs before choosing a workflow.')

    async def test_personal_and_mixed_build_requests_withhold_before_model(self):
        for question in PERSONAL_REQUESTS:
            with self.subTest(question=question):
                host, native, prompts, decisions = await self.run_request(question)
                self.assertEqual(prompts, [])
                self.assertEqual(host.model_requests, 0)
                self.assertEqual(decisions[-1]['disposition'], 'clarify')
                self.assertEqual(decisions[-1]['reasonCode'], 'personal_context_missing')
                self.assertEqual(decisions[-1]['requestID'], native['requestID'])
                self.assertIsNone(decisions[-1]['card'])
                self.assertFalse(any(row['disposition'] == 'answer' for row in decisions))
