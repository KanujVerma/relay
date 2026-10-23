"""Independent-review reproductions and boundary regressions, offline fixtures."""
import json
import unittest
from relay_spike.session_host import SessionHost
from relay_spike.generated_answer import CardError, parse_generated_card
from relay_spike.conversation_context import ConversationContext
from test_session_host import start,speech,end,final,event


def card(lead='Explain FIFO ordering.'):
    return json.dumps(dict(lead=lead,points=[],detail=None,assumptions=[],coverage=['current'],personal_fact_ids=[]))

class PersonalBoundaryTests(unittest.IsolatedAsyncioTestCase):
    async def test_personal_requests_never_reach_general_generation_without_evidence(self):
        for question in ('Where were you educated?','What is your employment history?','What is your GPA?','Which certifications do you hold?','Who was your previous employer?','Tell me about a time you resolved a disagreement.'):
            calls=[];out=[]
            async def complete(*args):calls.append(args);return card('I graduated from Stanford University in 2022.')
            host=SessionHost(complete=complete,emit=out.append)
            await host.handle(start());await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,question));await host.drain()
            with self.subTest(question=question):
                self.assertEqual(calls,[]);self.assertEqual(out[-1]['reasonCode'],'personal_context_missing');self.assertIsNone(out[-1]['card'])

    async def test_unexpected_biography_on_technical_request_is_rejected(self):
        for text in ('I graduated from Stanford University in 2022.','I hold an AWS certification.','I was a senior engineer at Acme for five years.','My GPA is 3.9.','Kanuj graduated from Stanford.','Explain my five years at Acme.','Use an AWS certification earned in 2022 as evidence.'):
            with self.subTest(text=text),self.assertRaises(CardError):parse_generated_card(card(text))
        out=[]
        async def complete(*args):return card('I hold an AWS certification.')
        host=SessionHost(complete=complete,emit=out.append)
        await host.handle(start());await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,'Explain hash table collisions.'));await host.drain()
        self.assertEqual(out[-1]['disposition'],'abstain');self.assertIsNone(out[-1]['card'])
        self.assertEqual(parse_generated_card(card()).lead,'Explain FIFO ordering.')

class SourceScopeTests(unittest.IsolatedAsyncioTestCase):
    async def test_mic_failure_keeps_remote_session_and_records_context_gap(self):
        for kind in ('source_unavailable','discontinuity'):
            prompts=[];out=[]
            async def complete(prompt,*args):prompts.append(json.loads(prompt));return card()
            host=SessionHost(complete=complete,emit=out.append)
            await host.handle(start());await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,'Explain queues.'));await host.drain()
            await host.handle(event(kind,5,2,1,{'reasonCode':'capture_error'}))
            await host.handle(speech(6,2,3));await host.handle(end(7,2,3));await host.handle(final(8,'Explain hash tables.',2,3));await host.drain()
            with self.subTest(kind=kind):
                self.assertTrue(host.live);self.assertEqual(len(prompts),2);self.assertEqual(out[-1]['disposition'],'answer')
                self.assertIn('microphone',str(prompts[-1]['conversation']['task']['context_gaps']))

class DisplayContextTests(unittest.IsolatedAsyncioTestCase):
    async def test_long_root_and_short_followup_display_verbatim_with_full_semantics(self):
        root='How would you implement a bounded LRU cache for a service that accepts arbitrary string keys, stores JSON values, handles concurrent callers, and must evict the least recently used item when capacity is reached? Explain what you would clarify before choosing the data structures, especially around missing keys, updates, capacity limits, and error handling.'
        follow='What about updating an existing key while another caller reads it?'
        prompts=[];out=[]
        async def complete(prompt,*args):prompts.append(json.loads(prompt));return card()
        host=SessionHost(complete=complete,emit=out.append)
        await host.handle(start())
        for seq,activity,text in ((2,1,root),(5,2,follow)):
            await host.handle(speech(seq,activity,activity+1));await host.handle(end(seq+1,activity,activity+1));await host.handle(final(seq+2,text,activity,activity+1));await host.drain()
        self.assertEqual(len(prompts),2);self.assertEqual(out[-1]['question'],follow)
        self.assertEqual(prompts[-1]['current_request'],follow);self.assertIn(root,prompts[-1]['semantic_request'])
        self.assertIn(follow,prompts[-1]['semantic_request'])

class DurableTaskTests(unittest.TestCase):
    def test_task_problem_and_constraints_survive_raw_history_eviction_and_correction(self):
        for intro in ('Implement an LRU cache. Capacity must be three; keys are strings.','Case study: design a nurse handoff feature. Users must be nurses; latency must be two seconds.'):
            context=ConversationContext();context.observe('remote',intro)
            for i in range(10):
                context.observe('microphone',f'The attempt at step {i} uses the previous approach.')
                context.observe('remote',f'How would the approach handle example {i}?')
            snapshot=context.snapshot()
            with self.subTest(intro=intro):
                self.assertEqual(len(snapshot.dialogue),12)
                self.assertIn(intro.split('.')[0],str(snapshot.task.known_problem))
                self.assertIn('must be',str(snapshot.task.constraints))
            correction='Actually, capacity must be five.' if 'LRU' in intro else 'Actually, latency must be one second.'
            context.observe('remote',correction)
            current=context.snapshot().task
            self.assertIn('five' if 'LRU' in intro else 'one second',str(current.constraints))
            self.assertNotIn('three' if 'LRU' in intro else 'two seconds',str(current.constraints))
            self.assertIn('strings' if 'LRU' in intro else 'nurses',str(current.constraints))
            context.observe('remote','New task: implement binary search. Input must be sorted.')
            replaced=context.snapshot().task
            self.assertIn('binary search',str(replaced.known_problem));self.assertNotIn('LRU',str(replaced.known_problem))
            self.assertNotIn('five',str(replaced.constraints))

class IntegratedTaskTests(unittest.IsolatedAsyncioTestCase):
    async def test_coding_and_case_task_survive_long_dialogue_then_explicit_correction(self):
        for intro,correction,old,new in (
            ('Implement an LRU cache. Capacity must be three; keys are strings.','Actually, capacity must be five.','three','five'),
            ('Case study: design a handoff feature. Users must be nurses; latency must be two seconds.','Actually, latency must be one second.','two seconds','one second')):
            prompts=[];out=[]
            async def complete(prompt,*args):prompts.append(json.loads(prompt));return card()
            host=SessionHost(complete=complete,emit=out.append);await host.handle(start());seq=2;activity=0;gen=1
            async def send(text,source=2):
                nonlocal seq,activity,gen
                activity+=1
                if source==2:gen+=1
                await host.handle(speech(seq,activity,gen,source));await host.handle(end(seq+1,activity,gen,source));await host.handle(final(seq+2,text,activity,gen,source));seq+=3;await host.drain()
            await send(intro)
            for i in range(7):
                await send(f'The attempt at step {i} follows the plan.',1)
                await send(f'Discuss the next test example {i}.')
            await send(correction);await send('How would the approach change under the current constraints?')
            task=prompts[-1]['conversation']['task']
            with self.subTest(intro=intro):
                self.assertIn(intro.split('.')[0],str(task['known_problem']))
                self.assertIn(new,str(task['constraints']));self.assertNotIn(old,str(task['constraints']))
                self.assertEqual(task['state'],'ready')

    async def test_task_overflow_withholds_until_explicit_bounded_restatement(self):
        context=ConversationContext();context.observe('remote','Implement '+('x'*4500)+'.')
        self.assertEqual(context.snapshot().task.state,'overflow')
        context.observe('remote','Explain the next step.');self.assertEqual(context.snapshot().task.state,'overflow')
        context.observe('remote','New task: implement binary search. Input must be sorted.')
        self.assertEqual(context.snapshot().task.state,'ready')
        self.assertIn('binary search',str(context.snapshot().task.known_problem))

class NeutralCodeTests(unittest.TestCase):
    def test_code_identifiers_are_not_biography_but_embedded_claims_reject(self):
        value=json.loads(card());value['detail']={'kind':'code','language':'python','text':'def indices():\n    return [i for i in range(3)]\n'}
        self.assertIn('python_syntax_checked',parse_generated_card(json.dumps(value)).checks)
        value['detail']['text']='def story():\n    return "I graduated from Stanford."\n'
        with self.assertRaises(CardError):parse_generated_card(json.dumps(value))

class IntegratedOverflowTests(unittest.IsolatedAsyncioTestCase):
    async def test_accumulated_constraints_overflow_is_explicit_and_blocks_generation(self):
        calls=[];out=[]
        async def complete(*args):calls.append(args);return card()
        host=SessionHost(complete=complete,emit=out.append);await host.handle(start());seq=2;activity=0
        async def send(text):
            nonlocal seq,activity
            activity+=1;await host.handle(speech(seq,activity,activity+1));await host.handle(end(seq+1,activity,activity+1));await host.handle(final(seq+2,text,activity,activity+1));seq+=3;await host.drain()
        await send('Implement an LRU cache.')
        for requirement in ('Capacity must be three.','Keys are strings.','Values must be JSON.','Input must be validated.','Latency must be bounded.','Users must be authenticated.','Concurrency must be supported.','Throughput must be measured.','Privacy must be preserved.'):
            await send(requirement)
        await send('Explain the next implementation step.')
        self.assertEqual(len(calls),1);self.assertEqual(out[-1]['reasonCode'],'task_context_overflow')
        self.assertEqual(host.context.snapshot().task.state,'overflow')

class ApprovedBiographyTests(unittest.IsolatedAsyncioTestCase):
    async def test_education_can_only_render_exact_approved_provider_text(self):
        import base64
        from hashlib import sha256
        from relay_spike.profile_bridge import ProfileBridge
        out=[];calls=[]
        async def complete(*args):calls.append(args);return card('I graduated from an invented university.')
        host=SessionHost(complete=complete,emit=out.append,role='developer')
        profile=ProfileBridge(on_change=host.personal_context_changed);profile.handle({'command':'new'});host.provider=profile
        text=b'I was educated at Stanford University.'
        profile.handle({'command':'select_begin','size':len(text),'sha256':sha256(text).hexdigest(),'file_type':'txt','purpose':'resume','label':'Synthetic education','role':'developer'})
        profile.handle({'command':'transfer_chunk','offset':0,'data':base64.b64encode(text).decode()})
        review=profile.handle({'command':'select_commit'})['card']
        profile.handle({'command':'decide','fact_id':review['fact_id'],'fingerprint':review['card_fingerprint'],'decision':'approve','actor':'self','claim_key':'education.institution'})
        await host.handle(start());await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,'Where were you educated?'));await host.drain()
        self.assertEqual(calls,[]);self.assertEqual(out[-1]['reasonCode'],'grounded_personal')
        self.assertIn(text.decode(),out[-1]['card']['points'][0])
        self.assertEqual(out[-1]['provenance']['facts'][0]['factID'],review['fact_id'])
        profile.close()
