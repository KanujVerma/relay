"""Actual notes scope/source/worker tests with fictional local DATA only."""
import asyncio
import base64
import copy
import json
import unittest
from unittest.mock import patch

from relay_spike.session_notes_host import HostNotesCoordinator
from relay_spike.session_host import SessionHost
from relay_spike.panel_wire import WireError
from relay_spike.session_notes_protocol import decode_result
from relay_spike.asr_turn_adapter import SyntheticEOUBridge
from tests.test_session_notes_protocol import scope,transfer,chunk,end,generate
from tests.test_session_notes_data import output_value,encode
from tests.test_session_host import start
from tests.test_assistant_scope import control as assistant_control


class NotesHostTests(unittest.IsolatedAsyncioTestCase):
    def host(self,complete=None,clock=None):
        self.out=[]
        h=SessionHost(complete=complete,emit=self.out.append)
        if clock is not None:h.notes._clock=clock
        self.addAsyncCleanup(h.notes.drain);self.addAsyncCleanup(h.drain);self.addCleanup(h.close)
        self.assertIsInstance(h.notes,HostNotesCoordinator)
        return h
    def staged(self,h,opened=None):
        opened=opened or scope();self.assertTrue(h.handle_notes(opened))
        begin,raw,source=transfer(opened)
        self.assertTrue(h.handle_notes(begin));self.assertTrue(h.handle_notes(chunk(begin,raw)));self.assertTrue(h.handle_notes(end(begin)))
        return opened,begin,source
    async def test_open_and_source_staging_never_grant_audio_or_call_a_model(self):
        calls=[]
        async def complete(*args):calls.append(args);return encode(output_value()).decode()
        h=self.host(complete)
        with patch.object(SyntheticEOUBridge,'resume_after_host_authorization',side_effect=AssertionError('notes cannot authorize capture')):
            opened,begin,_=self.staged(h)
        self.assertEqual(self.out[0]['status'],'ready');self.assertIsNone(self.out[0]['quiesced'])
        self.assertFalse(h.live);self.assertFalse(h._microphone_available);self.assertEqual(h.scope_kind,'notes')
        self.assertEqual(h.context.snapshot().dialogue,());self.assertEqual(h.model_requests,0);self.assertEqual(calls,[])
        self.assertEqual(h.notes.source_size,len(transfer(opened)[1]))
    async def test_completed_cited_output_has_one_model_attempt_and_no_local_metadata_in_prompt(self):
        calls=[]
        async def complete(prompt,instructions):calls.append((json.loads(prompt),instructions));return encode(output_value()).decode()
        h=self.host(complete);opened,begin,source=self.staged(h)
        self.assertTrue(h.handle_notes(generate(begin)));await h.drain()
        replies=[x for x in self.out if x['kind']=='notes_result']
        self.assertEqual([x['resultRevision'] for x in replies],[1,2]);self.assertEqual(replies[-1]['status'],'completed')
        self.assertEqual(decode_result(replies[-1],source=source),replies[-1]);self.assertEqual(h.model_requests,1);self.assertEqual(len(calls),1)
        prompt=calls[0][0]
        self.assertEqual(set(prompt),{'task','scope','recordState','gaps','rows'})
        self.assertEqual(prompt['rows'],[{'id':r.row_id,'source':r.source,'text':r.text} for r in source.rows])
        for forbidden in ('scopeID','operationID','requestID','transferID','recordID','recordRevision','sourceDigest','modelID','accountID'):
            self.assertNotIn(forbidden,json.dumps(prompt))
        self.assertFalse(h.handle_notes(generate(begin)));self.assertEqual(self.out[-1],replies[-1]);self.assertEqual(len(calls),1)
    async def test_incomplete_source_and_inference_off_withhold_without_a_model_attempt(self):
        h=self.host();opened=scope();h.handle_notes(opened);begin,_,_=transfer(opened);h.handle_notes(begin)
        self.assertFalse(h.handle_notes(generate(begin)));self.assertEqual(self.out[-1]['reasonCode'],'source_unavailable');self.assertEqual(h.model_requests,0)
        h.close();await h.drain()
        _,begin,_=self.staged(h)
        self.assertFalse(h.handle_notes(generate(begin)));self.assertEqual(self.out[-1]['reasonCode'],'inference_disabled');self.assertEqual(h.model_requests,0)
    async def test_capture_assistant_and_notes_scopes_cannot_replace_each_other(self):
        h=self.host();await h.handle(start());self.assertFalse(h.handle_notes(scope()))
        self.assertEqual(self.out[-1]['reasonCode'],'busy');h.close();await h.drain()
        opened=scope();self.assertTrue(h.handle_notes(opened))
        self.assertFalse(await h.handle(start()));self.assertFalse(h.handle_assistant_scope(assistant_control()))
        self.assertEqual(h.scope_kind,'notes');self.assertEqual(h.notes.scope_identity,(opened['scopeID'],1))
    async def test_source_replay_is_bounded_exact_and_cannot_skip_chunks(self):
        h=self.host();opened=scope();h.handle_notes(opened);begin,raw,_=transfer(opened);h.handle_notes(begin)
        one=chunk(begin,raw);h.handle_notes(one);size=h.notes.source_size
        self.assertFalse(h.handle_notes(one));self.assertEqual(h.notes.source_size,size)
        changed={**one,'data':base64.b64encode(b'changed').decode()}
        with self.assertRaises(WireError):h.handle_notes(changed)
        self.assertEqual(h.notes.source_size,0)
        h.close();await h.drain();opened=scope();h.handle_notes(opened);begin,raw,_=transfer(opened);h.handle_notes(begin)
        with self.assertRaises(WireError):h.handle_notes(chunk(begin,raw,index=1))
    async def test_staging_deadline_does_not_extend_on_chunk_or_duplicate(self):
        clock=[10.0];h=self.host(clock=lambda:clock[0]);opened=scope();h.handle_notes(opened)
        begin,raw,_=transfer(opened);h.handle_notes(begin);clock[0]=14.9;h.handle_notes(chunk(begin,raw));h.handle_notes(end(begin))
        clock[0]=15.1;self.assertFalse(h.handle_notes(generate(begin)))
        self.assertEqual(self.out[-1]['reasonCode'],'source_expired');self.assertEqual(h.notes.source_size,0);self.assertEqual(h.model_requests,0)
    async def test_exact_control_duplicate_replays_and_changed_action_reuse_is_rejected(self):
        h=self.host();opened=scope();self.assertTrue(h.handle_notes(opened));reply=copy.deepcopy(self.out[-1])
        self.assertFalse(h.handle_notes(opened));self.assertEqual(self.out[-1],reply)
        with self.assertRaises(WireError):h.handle_notes({**opened,'action':'close'})
        self.assertFalse(h.notes.busy)
    async def test_cancel_before_admission_tombstones_original_without_a_late_model_call(self):
        calls=[]
        async def complete(*args):calls.append(args);return encode(output_value()).decode()
        h=self.host(complete);opened=scope();h.handle_notes(opened);begin,raw,_=transfer(opened)
        self.assertTrue(h.handle_notes(generate(begin,'notes_cancel')));await h.notes.drain()
        terminal=copy.deepcopy(self.out[-1]);self.assertEqual(terminal['status'],'cancelled')
        for value in (begin,chunk(begin,raw),end(begin),generate(begin)):
            self.assertFalse(h.handle_notes(value))
        self.assertEqual(self.out[-1],terminal);self.assertEqual(calls,[]);self.assertEqual(h.model_requests,0)
    async def test_cancel_close_wait_for_actual_uncooperative_worker_and_reader_stays_responsive(self):
        entered=asyncio.Event();release=asyncio.Event()
        async def complete(*_):
            entered.set()
            try:await release.wait()
            except asyncio.CancelledError:await release.wait()
            return encode(output_value()).decode()
        h=self.host(complete);self.addCleanup(release.set);opened,begin,_=self.staged(h)
        h.handle_notes(generate(begin));await entered.wait()
        self.assertTrue(h.handle_notes(generate(begin,'notes_cancel')))
        closed=scope('close',scopeID=opened['scopeID']);self.assertTrue(h.handle_notes(closed));await asyncio.sleep(0)
        self.assertFalse(any(x.get('status') in ('cancelled','closed') for x in self.out))
        self.assertFalse(h.handle_notes(scope()));self.assertEqual(self.out[-1]['reasonCode'],'busy')
        release.set();await h.drain();await h.notes.drain()
        results=[x for x in self.out if x.get('requestID')==begin['requestID'] and x['kind']=='notes_result']
        self.assertEqual([x['status'] for x in results],['pending','cancelled'])
        replies=[x for x in self.out if x.get('operationID')==closed['operationID']]
        self.assertEqual(len(replies),1);self.assertTrue(replies[0]['quiesced']);self.assertEqual(replies[0]['status'],'closed')
        self.assertEqual(h.notes.source_size,0)
        self.assertTrue(h.handle_notes(scope()))
    async def test_profile_change_does_not_cancel_history_only_notes(self):
        entered=asyncio.Event();release=asyncio.Event()
        async def complete(*_):entered.set();await release.wait();return encode(output_value()).decode()
        h=self.host(complete);self.addCleanup(release.set);_,begin,_=self.staged(h)
        h.handle_notes(generate(begin));await entered.wait();h.personal_context_changed();release.set();await h.drain()
        self.assertEqual(self.out[-1]['status'],'completed')
    async def test_changed_end_digest_and_second_request_cannot_create_another_generation(self):
        h=self.host();opened=scope();h.handle_notes(opened);begin,raw,_=transfer(opened)
        h.handle_notes(begin);h.handle_notes(chunk(begin,raw))
        with self.assertRaises(WireError):h.handle_notes({**end(begin),'sourceDigest':'0'*64})
        self.assertEqual(h.notes.source_size,0);self.assertEqual(h.model_requests,0)
        async def complete(*_):return encode(output_value()).decode()
        h=self.host(complete);_,begin,_=self.staged(h);h.handle_notes(generate(begin));await h.drain()
        self.assertEqual(h.model_requests,1)
        changed=generate(begin);changed['requestID']=scope()['operationID']
        with self.assertRaises(WireError):h.handle_notes(changed)
        self.assertEqual(h.model_requests,1)
    async def test_control_replay_budget_is_data_free_and_does_not_evict_fences(self):
        h=self.host()
        for _ in range(256):
            opened=scope();self.assertTrue(h.handle_notes(opened))
            self.assertTrue(h.handle_notes(scope('close',scopeID=opened['scopeID'])))
            await h.notes.drain()
        self.assertEqual(len(h.notes._ledger),512);self.assertLessEqual(len(h.notes._controls),8)
        with self.assertRaises(WireError):h.handle_notes(scope())
        self.assertEqual(h.model_requests,0);self.assertEqual(h.notes.source_size,0)


if __name__=='__main__':unittest.main()
