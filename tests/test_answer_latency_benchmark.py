import importlib.util
import json
from pathlib import Path
import unittest

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
