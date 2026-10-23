"""Second independent answer review repros; synthetic input and completions."""
import json
import unittest
from relay_spike.generated_answer import CardError,parse_generated_card,requires_personal_evidence
from relay_spike.session_host import SessionHost
from relay_spike.conversation_context import ConversationContext
from test_session_host import start,speech,end,final


def card(lead='Explain FIFO ordering.'):
    return json.dumps(dict(lead=lead,points=[],detail=None,assumptions=[],coverage=['current'],personal_fact_ids=[]))

class NamedAttributionTests(unittest.IsolatedAsyncioTestCase):
    async def test_named_and_third_person_history_require_provider_evidence(self):
        for question in ('What did Kanuj build at Acme?','Where does Priya work?','Describe Elena\'s contribution to the Atlas project.','What did the candidate implement on the project?'):
            calls=[];out=[]
            async def complete(*args):calls.append(args);return card('State Kanuj built the Atlas SQL pipeline at Acme.')
            host=SessionHost(complete=complete,emit=out.append)
            await host.handle(start());await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,question));await host.drain()
            with self.subTest(question=question):
                self.assertTrue(requires_personal_evidence(question));self.assertEqual(calls,[])
                self.assertEqual(out[-1]['reasonCode'],'personal_context_missing');self.assertIsNone(out[-1]['card'])

    async def test_unexpected_named_attribution_on_technical_request_rejects(self):
        for text in ('State Kanuj built the Atlas SQL pipeline at Acme.','Explain how Elena implemented the service at Beta.','Discuss the candidate built the application.','State the pipeline was built by Priya.','State morgan built the event pipeline at ember.','Explain sam implemented the storage service.','State the service was built by morgan.'):
            with self.subTest(text=text),self.assertRaises(CardError):parse_generated_card(card(text))
        out=[]
        async def complete(*args):return card('State Maya built the cache at Arbor.')
        host=SessionHost(complete=complete,emit=out.append)
        await host.handle(start());await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,'Explain hash table collisions.'));await host.drain()
        self.assertEqual(out[-1]['disposition'],'abstain');self.assertIsNone(out[-1]['card'])
        self.assertEqual(parse_generated_card(card()).lead,'Explain FIFO ordering.')

class CorrectionStateTests(unittest.IsolatedAsyncioTestCase):
    async def run_sequence(self,texts):
        prompts=[];out=[]
        async def complete(prompt,*args):prompts.append(json.loads(prompt));return card()
        host=SessionHost(complete=complete,emit=out.append);await host.handle(start())
        for i,text in enumerate(texts):
            seq=2+i*3;activity=i+1
            await host.handle(speech(seq,activity,activity+1));await host.handle(end(seq+1,activity,activity+1));await host.handle(final(seq+2,text,activity,activity+1));await host.drain()
        return host,prompts,out

    async def test_make_that_five_blocks_stale_capacity_generation(self):
        host,prompts,out=await self.run_sequence(('Implement an LRU cache. Capacity must be three; keys are strings.','Make that five.','Explain how the current capacity changes eviction.'))
        self.assertEqual(len(prompts),1);self.assertEqual(host.context.snapshot().task.state,'needs_clarification')
        self.assertEqual(out[-1]['reasonCode'],'task_context_unresolved')

    async def test_explicit_affected_field_restatement_recovers_without_new_task(self):
        for correction in ('Actually, make it five.','Make that five.'):
            host,prompts,out=await self.run_sequence(('Implement an LRU cache. Capacity must be three.',correction,'Capacity must be five.','Explain the current approach.'))
            with self.subTest(correction=correction):
                self.assertEqual(len(prompts),2);self.assertEqual(out[-1]['disposition'],'answer')
                task=prompts[-1]['conversation']['task'];self.assertEqual(task['state'],'ready')
                self.assertIn('five',str(task['constraints']));self.assertNotIn('three',str(task['constraints']))

    def test_named_unresolved_field_requires_that_field_and_overflow_stays_sticky(self):
        context=ConversationContext();context.observe('remote','Implement a cache. Capacity must be three; latency must be two seconds.')
        context.observe('remote','Actually, latency.');self.assertEqual(context.snapshot().task.state,'needs_clarification')
        context.observe('remote','Capacity must be five.');self.assertEqual(context.snapshot().task.state,'needs_clarification')
        context.observe('remote','Latency must be one second.');self.assertEqual(context.snapshot().task.state,'ready')
        context=ConversationContext();context.observe('remote','Implement '+('x'*4500)+'.')
        context.observe('remote','Make that five.');context.observe('remote','Capacity must be five.')
        self.assertEqual(context.snapshot().task.state,'overflow')

class NeutralTechnicalScopeTests(unittest.TestCase):
    def test_impersonal_passive_technical_explanation_remains_available(self):
        self.assertFalse(requires_personal_evidence('Explain how hash indexes are created.'))
        self.assertEqual(parse_generated_card(card('Explain how cache entries are created.')).lead,'Explain how cache entries are created.')

class BareCorrectionRecoveryTests(unittest.TestCase):
    def test_unrelated_or_unchanged_statement_does_not_resolve_bare_value_change(self):
        context=ConversationContext();context.observe('remote','Implement a cache. Capacity must be three; keys are strings.')
        context.observe('remote','Make that five.')
        context.observe('remote','Keys are strings.')
        self.assertEqual(context.snapshot().task.state,'needs_clarification')
        context.observe('remote','Capacity must be five.')
        self.assertEqual(context.snapshot().task.state,'ready')

class EmbeddedCorrectionRecoveryTests(unittest.TestCase):
    def test_matching_field_restatement_resolves_embedded_constraint_without_new_task(self):
        context=ConversationContext();context.observe('remote','Implement a cache where capacity must be three.')
        context.observe('remote','Actually, capacity must be five.')
        self.assertEqual(context.snapshot().task.state,'needs_clarification')
        context.observe('remote','Capacity must be five.')
        self.assertEqual(context.snapshot().task.state,'ready')
        self.assertIn('five',str(context.snapshot().task.constraints));self.assertNotIn('three',str(context.snapshot().task.constraints))
