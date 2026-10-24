"""Controller-owned canonical schema fixtures, imported unchanged from ec2f109."""
import asyncio
import json
from pathlib import Path
import unittest
from relay_spike.panel_wire import decode_event
from relay_spike.session_host import SessionHost

ROOT=Path(__file__).resolve().parents[1]/'contracts'

class GoldenWireTests(unittest.IsolatedAsyncioTestCase):
    async def test_canonical_schema_and_reviewed_route(self):
        cases=json.loads((ROOT/'session-v1-golden.json').read_text())['cases']
        for case in cases:
            for event in case['events']:
                with self.subTest(case=case['name']):decode_event(event)
        reviewed=next(c for c in cases if c['name']=='reviewed_question')
        out=[];host=SessionHost(emit=out.append)
        for event in reviewed['events']:await host.handle(event)
        self.assertEqual(out[-1]['answerKind'],'reviewed_reference');self.assertEqual(host.model_requests,0)
        late=next(c for c in cases if c['name']=='late_final_after_new_onset')
        out=[];host=SessionHost(emit=out.append)
        for event in late['events']:await host.handle(event)
        self.assertEqual(out,[]);self.assertEqual(host.presentation,3)
        self.assertIn('WHERE',host.context.snapshot().dialogue[-1][1])

    async def test_all_canonical_invalid_envelopes_reject(self):
        for case in json.loads((ROOT/'session-v1-invalid.json').read_text())['cases']:
            with self.subTest(case=case['name']),self.assertRaises(ValueError):decode_event(case['value'])
