import importlib.util
import asyncio
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from relay_spike.oauth_answer_stream import OAuthAnswerStream
from tests.test_answer_transport_lifetime import events, wire

spec = importlib.util.spec_from_file_location('answer_latency_benchmark',
    Path(__file__).resolve().parents[1] / 'EVALS' / 'benchmark_answer_latency.py')
benchmark = importlib.util.module_from_spec(spec); spec.loader.exec_module(benchmark)


class AnswerLatencyBenchmarkTests(unittest.IsolatedAsyncioTestCase):
    async def test_same_synthetic_cases_alternate_prompts_preserve_code_and_never_infer_personal_history(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        calls = []
        async def handler(request):
            body = json.loads(request.content); calls.append(body)
            question = json.loads(body['input'][0]['content'])['current_request']
            detail = ({'kind': 'code', 'language': 'python', 'text':
                'def search(items, target):\n    lo, hi = 0, len(items) - 1\n    while lo <= hi:\n        mid = (lo + hi) // 2\n        if items[mid] == target:\n            return mid\n        if items[mid] < target:\n            lo = mid + 1\n        else:\n            hi = mid - 1\n    return -1\n'}
                if 'Python code' in question else None)
            raw = json.dumps({'lead': 'Explain the complete requested behavior.', 'points': [],
                'detail': detail, 'assumptions': [], 'coverage': ['current_request'], 'personal_fact_ids': []})
            return httpx.Response(200, headers={'content-type': 'text/event-stream'},
                                  stream=httpx.ByteStream(wire(events(raw))))
        stream = OAuthAnswerStream(token_provider=lambda: 'synthetic', client_factory=lambda **kw:
            httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw))
        self.addAsyncCleanup(stream.aclose)
        result = await benchmark.compare_prompt_variants(stream, 'historical baseline', include_answers=True)
        self.assertEqual(len(calls), 6)
        self.assertEqual([c['instructions']=='historical baseline' for c in calls], [True, False, False, True, True, False])
        for offset in (0, 2, 4):
            self.assertEqual(calls[offset]['input'], calls[offset+1]['input'])
        self.assertEqual([r['outcome'] for r in result['results']], ['completed']*6 + ['personal_context_missing']*2)
        self.assertTrue(all(r.get('modelAttempts')==0 for r in result['results'] if r['caseID']=='P00'))
        coding = [r for r in result['results'] if r['caseID']=='E09']
        for row in coding:
            scope = {}; exec(row['card']['detail']['text'], scope)
            self.assertEqual(scope['search']([], 1), -1)
            self.assertEqual(scope['search']([1, 3, 5], 3), 1)
            self.assertEqual(scope['search']([1, 3, 5], 4), -1)
        self.assertTrue(all(r['firstUsefulVerifiedMs'] is None for r in result['results']))

    async def test_no_implicit_credential_fallback_and_failed_streams_remain_failures(self):
        with self.assertRaisesRegex(ValueError, 'explicit_product_stream_required'):
            await benchmark.compare_prompt_variants(OAuthAnswerStream(), 'baseline')
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        calls = []
        async def handler(request):
            calls.append(request)
            return httpx.Response(200, headers={'content-type': 'text/event-stream'},
                stream=httpx.ByteStream(wire(events('partial')[:4])))
        stream = OAuthAnswerStream(token_provider=lambda: 'synthetic', client_factory=lambda **kw:
            httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw))
        self.addAsyncCleanup(stream.aclose)
        result = await benchmark.compare_prompt_variants(stream, 'baseline')
        self.assertEqual(len(calls), 6)
        for row in result['results'][:6]:
            self.assertEqual(row['outcome'], 'failed')
            self.assertEqual(row['transport']['outcome'], 'failed')
            self.assertIsNone(row['transport']['response_completed_ms'])
            self.assertNotIn('card', row)

    async def test_refusal_and_incomplete_observations_are_retained_without_success(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        for terminal, category in (('response.refusal.delta', 'refused'), ('response.incomplete', 'incomplete')):
            with self.subTest(terminal=terminal):
                rows = events('partial')[:4]
                rows.append({'type': terminal, 'response': {'id': 'r', 'status': 'incomplete'}}
                            if category=='incomplete' else {'type': terminal, 'delta': 'synthetic refusal'})
                async def handler(_):
                    return httpx.Response(200, headers={'content-type': 'text/event-stream'},
                        stream=httpx.ByteStream(wire(rows)))
                stream = OAuthAnswerStream(token_provider=lambda: 'synthetic', client_factory=lambda **kw:
                    httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw))
                self.addAsyncCleanup(stream.aclose)
                result = await benchmark.compare_prompt_variants(stream, 'baseline')
                for row in result['results'][:6]:
                    self.assertEqual(row['outcome'], 'failed')
                    self.assertEqual(row['transport']['provider_terminal'], category)
                    self.assertIsNone(row['transport']['response_completed_ms'])
                    self.assertNotIn('card', row)

    async def test_effort_comparison_holds_compact_prompt_and_inputs_constant_and_restores_original(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        calls=[]
        async def handler(request):
            body=json.loads(request.content);calls.append(body)
            raw=json.dumps({'lead':'Explain the requested contract and edge cases.','points':[],
                'detail':{'kind':'code','language':'python','text':'def search(values, target):\n    lo, hi = 0, len(values)-1\n    while lo <= hi:\n        mid = (lo+hi)//2\n        if values[mid] == target:\n            return mid\n        if values[mid] < target:\n            lo = mid+1\n        else:\n            hi = mid-1\n    return -1\n'},
                'assumptions':[],'coverage':['current_request'],'personal_fact_ids':[]})
            return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=httpx.ByteStream(wire(events(raw))))
        stream=OAuthAnswerStream(model='gpt-6-luna',effort='low',token_provider=lambda:'synthetic',
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
        self.addAsyncCleanup(stream.aclose)
        result=await benchmark.compare_effort_variants(stream,include_answers=True)
        self.assertEqual(stream.effort,'low')
        self.assertEqual(len(calls),6)
        self.assertEqual([body.get('reasoning') for body in calls],
            [None,{'effort':'none'},{'effort':'none'},None,None,{'effort':'none'}])
        self.assertTrue(all(body['instructions']==benchmark.INSTRUCTIONS for body in calls))
        for offset in (0,2,4):self.assertEqual(calls[offset]['input'],calls[offset+1]['input'])
        self.assertEqual([r['outcome'] for r in result['results']],['completed']*6+['personal_context_missing']*2)
        self.assertTrue(all(r['modelAttempts']==0 for r in result['results'] if r['caseID']=='P00'))
        self.assertEqual(result['comparison'],'reasoning_effort')
        self.assertTrue(all(r['correctness']=='unreviewed' for r in result['results']))

    async def test_effort_comparison_rejects_unsupported_sol_none_before_token_or_client_access(self):
        from relay_spike.stream import StreamError
        token_reads=[];clients=[]
        stream=OAuthAnswerStream(model='gpt-6.1-sol',effort='low',token_provider=lambda:token_reads.append(True),
            client_factory=lambda **kw:clients.append(kw))
        with self.assertRaises(StreamError):await benchmark.compare_effort_variants(stream)
        self.assertEqual(token_reads,[]);self.assertEqual(clients,[])
        self.assertEqual(stream.effort,'low');self.assertIsNone(stream.last_timing)

    async def test_cancelled_effort_comparison_restores_setting_and_does_not_continue_or_retry(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        entered=asyncio.Event();calls=[]
        async def handler(request):
            calls.append(request);entered.set();await asyncio.Event().wait()
        stream=OAuthAnswerStream(model='gpt-6-luna',effort='low',token_provider=lambda:'synthetic',
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
        self.addAsyncCleanup(stream.aclose)
        task=asyncio.create_task(benchmark.compare_effort_variants(stream))
        await asyncio.wait_for(entered.wait(),1);task.cancel()
        with self.assertRaises(asyncio.CancelledError):await task
        self.assertEqual(stream.effort,'low');self.assertEqual(len(calls),1)
        self.assertEqual(stream.last_timing.outcome,'cancelled')

    async def test_effort_failures_and_completed_but_rejected_cards_remain_in_comparison(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        calls=[]
        async def handler(request):
            body=json.loads(request.content);calls.append(body)
            if body.get('reasoning')=={'effort':'none'}:
                return httpx.Response(400,stream=httpx.ByteStream(b'{"error":{"message":"private provider diagnostic"}}'))
            raw=json.dumps({'lead':'Explain the requested contract.','points':[],'detail':None,
                'assumptions':[],'coverage':['current_request'],'personal_fact_ids':[]})
            return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=httpx.ByteStream(wire(events(raw))))
        stream=OAuthAnswerStream(model='gpt-6-luna',effort='low',token_provider=lambda:'synthetic',
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
        self.addAsyncCleanup(stream.aclose)
        result=await benchmark.compare_effort_variants(stream)
        self.assertEqual(len(calls),6);self.assertEqual(stream.effort,'low')
        self.assertEqual([row['outcome'] for row in result['results'][:6]],
            ['completed','failed','failed','withheld','completed','failed'])
        coding=next(row for row in result['results'] if row['caseID']=='E09' and row['variant']=='default')
        self.assertEqual(coding['qa'],'card_rejected')
        self.assertEqual(coding['transport']['outcome'],'completed')
        self.assertNotIn('private',json.dumps(result))
        self.assertTrue(all(row['serverReportedEffort'] is None for row in result['results']))

    async def test_effort_hard_cap_never_exceeds_six_even_if_case_inventory_expands(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        calls=[]
        async def handler(request):
            calls.append(request)
            return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=httpx.ByteStream(wire(events('invalid card'))))
        stream=OAuthAnswerStream(model='gpt-6-luna',token_provider=lambda:'synthetic',
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
        self.addAsyncCleanup(stream.aclose)
        with patch.object(benchmark,'CASES',benchmark.CASES*2):
            result=await benchmark.compare_effort_variants(stream)
        self.assertEqual(len(calls),6);self.assertEqual(result['declaredModelAttempts'],6)
        self.assertEqual(sum(row['modelAttempts'] for row in result['results']),6)
        self.assertTrue(any(row['outcome']=='request_cap_reached' for row in result['results']))
