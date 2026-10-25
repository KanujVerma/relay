"""Actual HTTPX/SSE with synthetic grants; no credentials or external IO."""
import asyncio
import base64
import json
import os
import pickle
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

import httpx
from relay_spike.notes_text_permit import NotesTextPermit,NotesPermitError,issue_notes_text_permit
from relay_spike.oauth_answer_stream import OAuthAnswerStream
from relay_spike.session_host import SessionHost
from relay_spike.session_notes_host import INSTRUCTIONS,model_prompt
from tests.test_session_notes_protocol import scope,transfer,chunk,end,generate
from tests.test_session_notes_data import output_value,encode
from tests.test_visual_input import completed_wire


class NotesTextPermitTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):self.streams=[];self.hosts=[];self.releases=[];self.posts=[]
    async def asyncTearDown(self):
        for release in self.releases:release.set()
        for host in self.hosts:host.close();await host.drain();await host.notes.drain()
        for stream in self.streams:await stream.aclose()
    def host(self,token=lambda:'synthetic',handler=None):
        async def completed(request):
            self.posts.append(request)
            return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=httpx.ByteStream(completed_wire(encode(output_value()).decode())))
        stream=OAuthAnswerStream(model='synthetic-notes-model',token_provider=token,
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler or completed),**kw))
        out=[];h=SessionHost(complete=stream.complete,visual_transport=stream,emit=out.append)
        self.streams.append(stream);self.hosts.append(h);return h,stream,out
    def staged(self,h):
        opened=scope();self.assertTrue(h.handle_notes(opened));begin,raw,source=transfer(opened)
        for frame in (begin,chunk(begin,raw),end(begin)):self.assertTrue(h.handle_notes(frame))
        return opened,begin,source
    async def test_actual_owned_request_posts_once_and_has_completed_cited_data(self):
        h,stream,out=self.host();_,begin,source=self.staged(h);h.handle_notes(generate(begin));await h.drain()
        self.assertEqual(out[-1]['status'],'completed');self.assertEqual(len(self.posts),1);self.assertEqual(h.model_requests,1)
        body=json.loads(self.posts[0].content);self.assertFalse(body['store']);self.assertTrue(body['stream'])
        self.assertEqual(body['model'],stream.model);self.assertEqual(body['instructions'],INSTRUCTIONS)
        self.assertEqual(body['input'][0]['content'],model_prompt(source))
        self.assertEqual(stream.last_timing.outcome,'completed');self.assertEqual(stream.last_timing.provider_terminal,'completed')
        permit=h.notes._request.permit;self.assertIsInstance(permit,NotesTextPermit)
        with self.assertRaises(TypeError):pickle.dumps(permit)
        with self.assertRaises(Exception):await stream.complete(model_prompt(source),INSTRUCTIONS,notes_text_permit=permit)
        self.assertEqual(len(self.posts),1)
    async def test_serialized_or_unissued_permit_never_reads_a_token_or_posts(self):
        calls=[];h,stream,_=self.host(token=lambda:calls.append(1) or 'synthetic')
        with self.assertRaises(NotesPermitError):NotesTextPermit()
        with self.assertRaises(NotesPermitError):issue_notes_text_permit(object(),object(),stream,'source','instructions')
        with self.assertRaises(Exception):await stream.complete('source','instructions',notes_text_permit={'current':True})
        with self.assertRaises(Exception):await stream.complete('source','instructions',notes_text_permit=object.__new__(NotesTextPermit))
        self.assertEqual(calls,[]);self.assertEqual(self.posts,[]);self.assertEqual(stream._spent,0)
    async def test_retire_during_actual_held_token_await_has_zero_post(self):
        entered=threading.Event();release=threading.Event();self.releases.append(release)
        def token():entered.set();release.wait(3);return 'synthetic'
        h,stream,out=self.host(token);_,begin,_=self.staged(h);h.handle_notes(generate(begin))
        self.assertTrue(await asyncio.to_thread(entered.wait,1))
        h.handle_notes(generate(begin,'notes_cancel'));joining=asyncio.create_task(h.notes.drain())
        release.set();await joining;await asyncio.sleep(.01)
        self.assertEqual(self.posts,[]);self.assertEqual(out[-1]['status'],'cancelled')
        self.assertEqual(stream.last_timing.outcome,'cancelled');self.assertIsNone(stream.last_timing.request_started_ms)
    async def test_actual_config_change_after_token_await_withholds_before_post(self):
        entered=threading.Event();release=threading.Event();self.releases.append(release)
        def token():entered.set();release.wait(3);return 'synthetic'
        h,stream,out=self.host(token);_,begin,_=self.staged(h);h.handle_notes(generate(begin))
        self.assertTrue(await asyncio.to_thread(entered.wait,1));stream.model='changed-config';release.set();await h.drain()
        self.assertEqual(self.posts,[]);self.assertEqual(out[-1]['status'],'unavailable')
        self.assertEqual(stream.last_timing.outcome,'failed')
    async def test_actual_stream_cancel_and_close_join_response_context_before_ack(self):
        entered=asyncio.Event();release=asyncio.Event();self.releases.append(release);closed=[]
        class Held(httpx.AsyncByteStream):
            async def __aiter__(self):
                entered.set()
                try:await release.wait()
                except asyncio.CancelledError:await release.wait()
                yield completed_wire(encode(output_value()).decode())
            async def aclose(self):closed.append(True)
        async def handler(request):
            self.posts.append(request)
            return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=Held())
        h,stream,out=self.host(handler=handler);opened,begin,_=self.staged(h);h.handle_notes(generate(begin));await entered.wait()
        h.handle_notes(generate(begin,'notes_cancel'));closing=scope('close',scopeID=opened['scopeID']);h.handle_notes(closing)
        await asyncio.sleep(0);self.assertFalse(any(x.get('status')=='closed' for x in out));self.assertEqual(closed,[])
        release.set();await h.drain();await h.notes.drain()
        self.assertEqual(len(self.posts),1);self.assertTrue(closed)
        self.assertFalse(any(x.get('status')=='completed' for x in out));self.assertEqual(out[-1]['status'],'closed');self.assertTrue(out[-1]['quiesced'])
        self.assertIsNone(stream.last_timing.response_completed_ms)
    async def test_actual_protected_factory_private_bootstrap_and_encrypted_provider_supply_notes(self):
        from relay_spike import auth
        from relay_spike.account_store import AccountCredentialStore
        from relay_spike.product_session import protected_answer_stream
        from relay_spike.panel_wire import encode_frame
        from tests.test_account_store import grant
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'Relay'/'Accounts';key=bytes(range(32));store=AccountCredentialStore(directory,key)
            hostID=store.initialize();saved=grant(hostID,saved_at=time.time());identity=store.save_registration(saved)
            generation=str(uuid.uuid4());store.select(identity,generation)
            bootstrap=dict(schemaVersion=1,kind='account_secret_bootstrap',purpose='oauth_session',key=base64.b64encode(key).decode(),
                vaultDirectory=str(directory),registrationID=identity,accountGeneration=generation)
            read,write=os.pipe()
            async def handler(request):
                self.posts.append(request)
                self.assertEqual(request.headers['authorization'],'Bearer '+saved['access_token'])
                return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=httpx.ByteStream(completed_wire(encode(output_value()).decode())))
            try:
                os.write(write,encode_frame(bootstrap));os.close(write);write=None
                with patch.object(auth,'load_auth',side_effect=AssertionError('legacy plaintext fallback')):
                    stream=protected_answer_stream('gpt-synthetic-first',input_fd=read,client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
                    out=[];h=SessionHost(complete=stream.complete,visual_transport=stream,emit=out.append)
                    self.streams.append(stream);self.hosts.append(h)
                    _,begin,_=self.staged(h);h.handle_notes(generate(begin));await h.drain()
                    self.assertEqual(out[-1]['status'],'completed');self.assertEqual(len(self.posts),1)
                    h.close();await h.drain();await h.notes.drain();await stream.aclose()
            finally:
                os.close(read)
                if write is not None:os.close(write)
    async def test_cancel_and_close_do_not_ack_until_the_actual_credential_thread_returns(self):
        entered=threading.Event();release=threading.Event();self.releases.append(release)
        def token():entered.set();release.wait();return 'synthetic'
        h,stream,out=self.host(token);opened,begin,_=self.staged(h);h.handle_notes(generate(begin))
        self.assertTrue(await asyncio.to_thread(entered.wait,1))
        h.handle_notes(generate(begin,'notes_cancel'));closing=scope('close',scopeID=opened['scopeID']);h.handle_notes(closing)
        joined=asyncio.create_task(h.notes.drain());await asyncio.sleep(.02)
        self.assertFalse(joined.done())
        self.assertFalse(any(x.get('status') in ('cancelled','closed') for x in out))
        self.assertTrue(stream._active);self.assertEqual(self.posts,[])
        release.set();await joined;await h.drain()
        self.assertEqual(out[-1]['status'],'closed');self.assertTrue(out[-1]['quiesced']);self.assertEqual(self.posts,[])
    async def test_actual_encrypted_generation_change_during_sse_withholds_completed_notes(self):
        from relay_spike.account_store import AccountCredentialStore
        from relay_spike.product_session import protected_answer_stream
        from relay_spike.panel_wire import encode_frame
        from tests.test_account_store import grant
        entered=asyncio.Event();release=asyncio.Event();self.releases.append(release)
        class Held(httpx.AsyncByteStream):
            async def __aiter__(self):entered.set();await release.wait();yield completed_wire(encode(output_value()).decode())
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'Relay'/'Accounts';key=bytes(range(32));store=AccountCredentialStore(directory,key)
            hostID=store.initialize();identity=store.save_registration(grant(hostID,saved_at=time.time()))
            generation=str(uuid.uuid4());store.select(identity,generation)
            bootstrap=dict(schemaVersion=1,kind='account_secret_bootstrap',purpose='oauth_session',key=base64.b64encode(key).decode(),
                vaultDirectory=str(directory),registrationID=identity,accountGeneration=generation)
            read,write=os.pipe()
            async def handler(request):self.posts.append(request);return httpx.Response(200,headers={'content-type':'text/event-stream'},stream=Held())
            try:
                os.write(write,encode_frame(bootstrap));os.close(write);write=None
                stream=protected_answer_stream('gpt-synthetic-first',input_fd=read,client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
                out=[];h=SessionHost(complete=stream.complete,visual_transport=stream,emit=out.append);self.streams.append(stream);self.hosts.append(h)
                _,begin,_=self.staged(h);h.handle_notes(generate(begin));await entered.wait()
                store.select(identity,str(uuid.uuid4()));release.set();await h.drain()
                self.assertFalse(any(x.get('status')=='completed' for x in out));self.assertEqual(out[-1]['status'],'unavailable')
                self.assertEqual(len(self.posts),1)
                h.close();await h.drain();await h.notes.drain();await stream.aclose()
            finally:
                os.close(read)
                if write is not None:os.close(write)


if __name__=='__main__':unittest.main()
