import asyncio
import copy
import json
import subprocess
import sys
import threading
import time
import unittest
import uuid
from unittest.mock import patch

from relay_spike.assistant_scope import decode_assistant_scope
from relay_spike.asr_turn_adapter import SyntheticEOUBridge
from relay_spike.panel_wire import WireError, encode_frame
from relay_spike.session_host import SessionHost
from tests.test_session_host import start
from tests.test_user_question import question, card, retirement, cancel


def control(action='open', *, session=None, generation=1, **changes):
    value=dict(schemaVersion=1,kind='assistant_scope_request',action=action,requestID=str(uuid.uuid4()),
        assistantSessionID=session or str(uuid.uuid4()),sessionEpoch=1,presentationGeneration=generation,
        controlSequence=1 if action=='open' else 2,emittedUptimeNanoseconds=time.monotonic_ns())
    value.update(changes)
    return value


class AssistantScopeDecoderTests(unittest.TestCase):
    def test_exact_identity_counter_and_action_domains(self):
        good=control();self.assertEqual(decode_assistant_scope(good),good)
        for changes in ({'schemaVersion':True},{'action':'capture'},{'requestID':'bad'},
                        {'assistantSessionID':None},{'sessionEpoch':0},{'controlSequence':True},
                        {'presentationGeneration':2**64},{'emittedUptimeNanoseconds':-1},
                        {'microphoneEnabled':False},{'kind':'session_started'}):
            with self.subTest(changes=changes),self.assertRaises(WireError):
                decode_assistant_scope({**good,**changes})
        for field in good:
            incomplete=copy.copy(good);del incomplete[field]
            with self.subTest(missing=field),self.assertRaises(WireError):decode_assistant_scope(incomplete)


class AssistantScopeHostTests(unittest.IsolatedAsyncioTestCase):
    def host(self, complete=None, visual_transport=None):
        self.out=[]
        host=SessionHost(complete=complete,visual_transport=visual_transport,emit=self.out.append)
        self.addAsyncCleanup(host.drain);self.addCleanup(host.close)
        return host

    async def test_assistant_reference_never_grants_capture_or_calls_a_model(self):
        host=self.host();opened=control()
        with patch.object(SyntheticEOUBridge,'resume_after_host_authorization',side_effect=AssertionError('assistant cannot authorize capture')):
            self.assertTrue(host.handle_assistant_scope(opened))
            self.assertEqual(self.out[-1]['status'],'ready')
            self.assertEqual(host.scope_kind,'assistant')
            self.assertFalse(host._microphone_available)
            request=question(host,'What is the difference between WHERE and HAVING?')
            self.assertTrue(await host.handle_user_question(request));await host.drain()
        self.assertEqual(self.out[-1]['answerKind'],'reviewed_reference')
        self.assertEqual(self.out[-1]['requestID'],request['requestID'])
        self.assertEqual(host.model_requests,0);self.assertEqual(host.sequence,1)
        self.assertEqual(host.context.snapshot().dialogue,())

    async def test_capture_and_assistant_cannot_replace_a_live_other_scope(self):
        host=self.host();await host.handle(start());original=host.session
        self.assertFalse(host.handle_assistant_scope(control()))
        self.assertEqual(self.out[-1]['status'],'busy');self.assertEqual(host.session,original)
        self.assertEqual(host.scope_kind,'capture')
        host.close();await host.drain()
        opened=control();self.assertTrue(host.handle_assistant_scope(opened))
        self.assertFalse(await host.handle(start()))
        self.assertEqual(host.session,(opened['assistantSessionID'],1));self.assertEqual(host.scope_kind,'assistant')

    async def test_non_capture_help_after_denial_preserves_personal_gates_and_fresh_tokens(self):
        host=self.host();host.handle_assistant_scope(control())
        first=question(host,'What did you personally do on your Atlas project?')
        await host.handle_user_question(first);await host.drain();original=host.active.token
        host.handle_answer_retirement(retirement(first))
        help_request=question(host,basis=first['requestID'],intent='help_current')
        self.assertTrue(await host.handle_user_question(help_request));await host.drain()
        self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
        self.assertNotEqual(host.active.token,original);self.assertEqual(host.model_requests,0)

    async def test_stale_open_and_wrong_close_cannot_retire_the_current_scope(self):
        host=self.host();stale=control(emittedUptimeNanoseconds=time.monotonic_ns()-2_100_000_000)
        self.assertFalse(host.handle_assistant_scope(stale));self.assertFalse(host.live)
        opened=control();self.assertTrue(host.handle_assistant_scope(opened))
        self.assertFalse(host.handle_assistant_scope(control('close',generation=2)))
        self.assertTrue(host.live);self.assertEqual(host.session,(opened['assistantSessionID'],1))
        self.assertFalse(self.out[-1].get('quiesced',False))

    async def test_actual_close_waits_for_its_uncooperative_worker_and_blocks_new_open(self):
        entered=asyncio.Event();release=asyncio.Event()
        async def stubborn(*_):
            entered.set()
            try:await release.wait()
            except asyncio.CancelledError:await release.wait()
            return card()
        host=self.host(stubborn);self.addCleanup(release.set)
        opened=control();host.handle_assistant_scope(opened)
        await host.handle_user_question(question(host));await entered.wait()
        closing=control('close',session=opened['assistantSessionID'],generation=host.presentation+1)
        self.assertTrue(host.handle_assistant_scope(closing));self.assertFalse(host.live)
        await asyncio.sleep(0)
        self.assertFalse(any(row.get('requestID')==closing['requestID'] for row in self.out))
        self.assertFalse(host.handle_assistant_scope(control()));self.assertEqual(self.out[-1]['status'],'busy')
        release.set();await host.drain();await host.assistant.drain()
        replies=[row for row in self.out if row.get('requestID')==closing['requestID']]
        self.assertEqual(len(replies),1);self.assertTrue(replies[0]['quiesced'])
        self.assertEqual(replies[0]['status'],'closed')
        self.assertFalse(any(row.get('disposition')=='answer' for row in self.out))
        replacement=control();self.assertTrue(host.handle_assistant_scope(replacement))
        self.assertFalse(host.handle_assistant_scope(closing))
        self.assertEqual(host.session,(replacement['assistantSessionID'],1));self.assertTrue(host.live)

    async def test_exact_open_replay_does_not_restart_and_changed_uuid_reuse_closes(self):
        host=self.host();opened=control();self.assertTrue(host.handle_assistant_scope(opened))
        reply=copy.deepcopy(self.out[-1]);request=question(host,'What did you personally do on Atlas?')
        await host.handle_user_question(request);await host.drain();active=host.active
        self.assertFalse(host.handle_assistant_scope(opened));self.assertEqual(self.out[-1],reply)
        self.assertIs(host.active,active)
        with self.assertRaises(WireError):host.handle_assistant_scope({**opened,'assistantSessionID':str(uuid.uuid4())})
        self.assertFalse(host.live)

    async def test_close_joins_and_delivers_original_cancel_receipt_before_scope_completion(self):
        entered=asyncio.Event();release=asyncio.Event()
        async def stubborn(*_):
            entered.set()
            try:await release.wait()
            except asyncio.CancelledError:await release.wait()
            return card()
        host=self.host(stubborn);self.addCleanup(release.set)
        opened=control();host.handle_assistant_scope(opened)
        request=question(host);await host.handle_user_question(request);await entered.wait()
        host.handle_answer_retirement(retirement(request))
        cancellation=cancel(host,request);self.assertTrue(host.handle_answer_cancel(cancellation))
        closing=control('close',session=opened['assistantSessionID'],generation=host.presentation+1)
        self.assertTrue(host.handle_assistant_scope(closing));await asyncio.sleep(0)
        self.assertFalse(any(row.get('requestID') in (cancellation['requestID'],closing['requestID']) for row in self.out))
        release.set();await host.drain();await host.assistant.drain()
        completed=[row for row in self.out if row.get('requestID') in (cancellation['requestID'],closing['requestID'])]
        self.assertEqual([row['requestID'] for row in completed],[cancellation['requestID'],closing['requestID']])
        self.assertTrue(all(row['quiesced'] for row in completed))

    async def test_real_probe_cleanup_blocks_open_until_the_original_task_finishes(self):
        import httpx
        from relay_spike.oauth_answer_stream import OAuthAnswerStream
        from tests.test_visual_host_backend import MODEL, control as visual_control
        from tests.test_visual_input import completed_wire, read_probe_pixels
        entered=asyncio.Event();release=asyncio.Event()
        async def handler(request):
            if request.method=='GET':
                payload={'models':[{'slug':MODEL,'display_name':'Synthetic','visibility':'list'}]}
                return httpx.Response(200,stream=httpx.ByteStream(json.dumps(payload).encode()))
            entered.set()
            try:await release.wait()
            except asyncio.CancelledError:await release.wait()
            return httpx.Response(200,stream=httpx.ByteStream(completed_wire(read_probe_pixels(json.loads(request.content))[0])),headers={'content-type':'text/event-stream'})
        stream=OAuthAnswerStream(model=MODEL,token_provider=lambda:'synthetic-probe-bearer',
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
        host=self.host(stream.complete,stream)
        self.addCleanup(release.set)
        host.handle_visual_control(visual_control('verify'))
        try:await asyncio.wait_for(entered.wait(),1)
        except TimeoutError:self.fail(f'probe did not reach its synthetic HTTP boundary: {self.out!r}')
        host.handle_visual_control(visual_control('disable'))
        self.assertFalse(host.handle_assistant_scope(control()))
        self.assertEqual(self.out[-1]['status'],'busy');self.assertFalse(host.live)
        release.set();await asyncio.wait_for(host.drain(),1)
        await asyncio.sleep(0)
        self.assertTrue(host.handle_assistant_scope(control()))
        self.assertEqual(self.out[-1]['status'],'ready')

    async def test_control_ledger_bounds_stale_operations_without_any_model_work(self):
        host=self.host()
        for _ in range(512):
            self.assertFalse(host.handle_assistant_scope(control(emittedUptimeNanoseconds=0)))
        with self.assertRaises(WireError):host.handle_assistant_scope(control())
        self.assertFalse(host.live);self.assertEqual(host.model_requests,0)

    async def test_scope_close_fences_held_account_token_thread_without_claiming_it_finished(self):
        import httpx
        from relay_spike.oauth_answer_stream import OAuthAnswerStream
        from tests.test_visual_input import completed_wire
        entered=threading.Event();release=threading.Event();finished=threading.Event();registry=threading.Lock()
        invocations=0;posts=[]
        def token():
            nonlocal invocations
            with registry:
                invocations+=1
                if invocations==1:
                    entered.set()
                    if not release.wait(3):raise RuntimeError('synthetic token gate timeout')
                    finished.set()
                return 'synthetic-same-account-bearer'
        async def handler(request):
            posts.append(json.loads(request.content))
            return httpx.Response(200,stream=httpx.ByteStream(completed_wire(card())),headers={'content-type':'text/event-stream'})
        stream=OAuthAnswerStream(model='synthetic-token-model',token_provider=token,
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))
        host=self.host(stream.complete,stream);self.addCleanup(release.set)
        opened=control();host.handle_assistant_scope(opened)
        original=question(host,'Explain the old queue.');await host.handle_user_question(original)
        self.assertTrue(await asyncio.to_thread(entered.wait,1))
        closing=control('close',session=opened['assistantSessionID'],generation=host.presentation+1)
        host.handle_assistant_scope(closing);await host.drain();await host.assistant.drain()
        self.assertTrue(self.out[-1]['quiesced'])
        self.assertFalse(finished.is_set(),'scope completion must not be reported as token-thread completion')
        self.assertEqual(posts,[])
        replacement=control();host.handle_assistant_scope(replacement)
        current=question(host,'Explain the new cache.');await host.handle_user_question(current)
        await asyncio.sleep(.01);self.assertEqual(posts,[])
        release.set();await asyncio.wait_for(host.drain(),1)
        self.assertTrue(finished.is_set())
        self.assertEqual([json.loads(body['input'][0]['content'])['current_request'] for body in posts],['Explain the new cache.'])
        answers=[row for row in self.out if row.get('disposition')=='answer']
        self.assertEqual([row['requestID'] for row in answers],[current['requestID']])


class AssistantScopeChildTests(unittest.TestCase):
    def test_actual_stdio_opens_answers_and_closes_without_any_capture_frame(self):
        child=subprocess.Popen([sys.executable,'-m','relay_spike.session_host'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        watchdog=threading.Timer(8,child.kill);watchdog.start()
        def send(value):child.stdin.write(encode_frame(value));child.stdin.flush()
        def read():
            header=child.stdout.read(4)
            self.assertEqual(len(header),4,'helper closed before its owned response')
            return json.loads(child.stdout.read(int.from_bytes(header,'big')))
        try:
            opening=control();send(opening)
            ready=read();self.assertEqual(ready['status'],'ready');self.assertEqual(len(ready),9)
            stub=SessionHost();stub.session=(opening['assistantSessionID'],1);stub.sequence=1;stub.presentation=1
            request=question(stub,'What is the difference between WHERE and HAVING?');send(request)
            answer=read();self.assertEqual(answer['answerKind'],'reviewed_reference')
            self.assertEqual(answer['requestID'],request['requestID']);self.assertEqual(answer['eventSequence'],1)
            closing=control('close',session=opening['assistantSessionID'],generation=3);send(closing)
            closed=read();self.assertEqual(closed['status'],'closed');self.assertIs(closed['quiesced'],True)
            self.assertEqual(len(closed),10)
            child.stdin.close();child.stdin=None
            rest,errors=child.communicate(timeout=5)
            self.assertEqual(child.returncode,0,errors.decode()[:100]);self.assertEqual(rest,b'')
        finally:
            watchdog.cancel()
            if child.poll() is None:child.kill();child.wait()
