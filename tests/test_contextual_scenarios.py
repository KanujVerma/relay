"""Held-out conversation scenarios authored against requirements, not catalog IDs.

Injected transport outputs are reviewed test fixtures. Only the static LRU
fixture below is executed for its own oracle; arbitrary model code is never run.
These tests prove context/routing/shape behavior, not live interview usefulness.
"""
import json
import unittest
from relay_spike.session_host import SessionHost
from test_session_host import start,speech,end,final

LRU_FIXTURE='''from collections import OrderedDict

class LRUCache:
    def __init__(self, capacity):
        if capacity < 1:
            raise ValueError("positive capacity required")
        self.capacity = capacity
        self.values = OrderedDict()

    def get(self, key):
        if key not in self.values:
            return None
        self.values.move_to_end(key)
        return self.values[key]

    def put(self, key, value):
        self.values[key] = value
        self.values.move_to_end(key)
        if len(self.values) > self.capacity:
            self.values.popitem(last=False)
'''

def card(lead,*,code=None,coverage='current_stage'):
    return json.dumps(dict(lead=lead,points=['State the constraints and check boundary cases.'],detail={'kind':'code','language':'python','text':code} if code else None,assumptions=['Keys are hashable; concurrency is not specified.'] if code else [],coverage=[coverage],personal_fact_ids=[]))

class ConversationScenarioTests(unittest.IsolatedAsyncioTestCase):
    async def send(self,host,text,source=2):
        base=self.sequence;self.sequence+=3;self.activity+=1
        if source==2:self.generation+=1
        await host.handle(speech(base,self.activity,self.generation,source));await host.handle(end(base+1,self.activity,self.generation,source));await host.handle(final(base+2,text,self.activity,self.generation,source))
        await host.drain()

    async def test_engineer_coding_task_clarify_attempt_feedback_code_improvement(self):
        prompts=[];out=[]
        async def model(prompt,instructions):
            parsed=json.loads(prompt);prompts.append(parsed)
            if len(prompts)==1:return card('Ask about capacity, key types, eviction rules and concurrency.')
            if len(prompts)==2:return card('Use a map plus recency ordering; move accessed keys to the newest position.',code=LRU_FIXTURE)
            return card('Keep map access and recency updates consistent; discuss a lock if callers are concurrent.')
        h=SessionHost(complete=model,emit=out.append,role='developer');self.sequence=2;self.activity=0;self.generation=1
        await h.handle(start());await self.send(h,"Let us implement an LRU cache. What should you clarify first?")
        self.assertIsNone(out[-1]['card']['detail'])
        await self.send(h,'I would start with a dictionary and a list of keys.',1)
        await self.send(h,'Capacity is positive and bounded. Write Python code supporting get and put with LRU eviction.')
        self.assertEqual(out[-1]['card']['detail']['text'],LRU_FIXTURE)
        task=prompts[-1]['conversation']['task'];self.assertEqual(task['kind'],'coding')
        self.assertIn('dictionary',str(task['user_attempt']));self.assertIn('Capacity',str(task['engineer_feedback']))
        await self.send(h,'How would you improve this for concurrent callers?')
        self.assertEqual(prompts[-1]['conversation']['task']['stage'],'tradeoffs')
        self.assertEqual(h.model_requests,3);self.assertEqual(len(out),6)
        self.assertEqual(out[-1]['provenance']['checks'],['format_checked'])

    async def test_feature_case_users_requirements_flows_tradeoffs_validation(self):
        prompts=[];out=[]
        async def model(prompt,instructions):
            parsed=json.loads(prompt);prompts.append(parsed)
            stage=parsed['conversation']['task']['stage']
            return card('Discuss '+stage+' using the supplied nurse handoff problem.')
        h=SessionHost(complete=model,emit=out.append);self.sequence=2;self.activity=0;self.generation=1
        await h.handle(start())
        await self.send(h,'Case study: design a nurse handoff feature. Who are its users?')
        await self.send(h,'Nurses want fewer missed tasks at shift change.',1)
        await self.send(h,'What requirements should we confirm before choosing a design?')
        await self.send(h,'How should the user workflow handle an incomplete handoff?')
        await self.send(h,'What tradeoffs would you discuss for real time updates?')
        await self.send(h,'How would you validate the feature and measure success?')
        self.assertEqual([p['conversation']['task']['stage'] for p in prompts],['users','requirements','flows','tradeoffs','validation'])
        self.assertTrue(all(p['conversation']['task']['kind']=='case_study' for p in prompts))
        self.assertIn('missed tasks',str(prompts[-1]['conversation']['task']['user_attempt']))
        self.assertEqual(h.model_requests,5)

    async def test_missing_starter_code_schema_and_user_story_remain_unknown(self):
        prompts=[];out=[]
        async def model(prompt,instructions):
            prompts.append(json.loads(prompt));return card('Ask for the starter code and table schema before choosing an implementation.')
        h=SessionHost(complete=model,emit=out.append);self.sequence=2;self.activity=0;self.generation=1
        await h.handle(start());await self.send(h,'How should we improve the code on my screen?')
        self.assertIsNone(prompts[-1]['task_input'])
        self.assertIsNone(out[-1]['card']['detail'])
        await self.send(h,'I led a team of forty at a famous company.',1)
        await self.send(h,'What did you personally build at that company?')
        self.assertEqual(out[-1]['reasonCode'],'personal_context_missing')
        self.assertEqual(h.model_requests,1)

class ReviewedFixtureOracleTests(unittest.TestCase):
    def test_static_lru_fixture_update_eviction_recency_and_capacity_boundaries(self):
        # This is a reviewed local fixture oracle, never execution of model text.
        namespace={};exec(LRU_FIXTURE,namespace);cache_type=namespace['LRUCache']
        with self.assertRaises(ValueError):cache_type(0)
        for capacity in (1,2,3):
            cache=cache_type(capacity)
            for key in range(capacity):cache.put(key,key*10)
            self.assertEqual(cache.get(0),0)
            cache.put(capacity,99)
            evicted=0 if capacity==1 else 1
            self.assertIsNone(cache.get(evicted));self.assertEqual(cache.get(capacity),99)
            cache.put(capacity,88);self.assertEqual(cache.get(capacity),88)
            self.assertLessEqual(len(cache.values),capacity)
