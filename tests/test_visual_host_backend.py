"""Actual helper/backend ports, using synthetic PNGs and injected HTTP only."""
import asyncio
import json
import time
import unittest
import uuid

from relay_spike.session_host import SessionHost
from relay_spike.supplemental_context import SupplementalContextProvider
from relay_spike.screen_context import SupplementalScreenProvider
from relay_spike.oauth_answer_stream import OAuthAnswerStream
from relay_spike.panel_wire import WireError
from tests.test_session_host import start, speech, end, final
from tests.test_visual_input import completed_wire, read_probe_pixels
from tests.test_screen_context import FRAME, REQUEST, png, image_frames, wire

MODEL = 'synthetic-image-model'


def control(action, request_id=None):
    return {'schemaVersion': 1, 'kind': 'visual_input_request',
            'requestID': str(uuid.uuid4()) if request_id is None else request_id, 'action': action}


def retired(native):
    return {'schemaVersion':1,'kind':'supplemental_context_retired',
        **{key:native[key] for key in ('captureSessionID','sessionEpoch','presentationGeneration','requestID')},
        'reasonCode':'context_changed'}


def generated_card():
    return json.dumps({'lead': 'Explain the supplied constraints before implementation.',
        'points': [], 'detail': None, 'assumptions': ['Task context may be incomplete.'],
        'coverage': ['current_request'], 'personal_fact_ids': []})


def screen_frames(native, now=None, data=None):
    text = dict(FRAME)
    text.update({key: native[key] for key in ('captureSessionID', 'sessionEpoch', 'presentationGeneration', 'requestID')})
    text['capturedUptimeNanoseconds'] = time.monotonic_ns() if now is None else now
    frames = image_frames(data)
    for frame in frames:
        frame.update({key: text[key] for key in ('captureSessionID', 'sessionEpoch', 'presentationGeneration',
                     'requestID', 'capturedUptimeNanoseconds')})
    return text, frames


class StagedVisualTests(unittest.TestCase):
    def setUp(self):
        self.now = time.monotonic_ns()
        self.native = dict(REQUEST)
        self.current = None
        self.provider = SupplementalContextProvider(current_request=lambda native: native is self.current,
                                                    now_ns=lambda: self.now)
        self.text, self.images = screen_frames(self.native, self.now)

    def test_screen_accessors_require_actual_issued_observation_identity(self):
        screen = SupplementalScreenProvider(now_ns=lambda: self.now)
        self.assertTrue(screen.ingest(wire(self.text), self.native))
        owner = screen.current_observation(self.native)
        self.assertTrue(screen.owns_observation(owner, self.native))
        from dataclasses import replace
        self.assertFalse(screen.owns_observation(replace(owner), self.native))
        self.assertIsNone(screen.current_observation(dict(self.native, sessionEpoch=2)))
        screen.invalidate()
        self.assertFalse(screen.owns_observation(owner, self.native))

    def test_untrusted_image_stages_locally_and_binds_to_actual_admitted_observation(self):
        self.assertFalse(self.provider.stage_image(wire(self.images[0])))
        self.assertTrue(self.provider.stage(wire(self.text)))
        for frame in self.images: self.assertTrue(self.provider.stage_image(wire(frame)))
        self.assertIsNone(self.provider.image_for_request(self.native))
        self.current = self.native
        snippet = self.provider(self.native)
        owner, data, width, height = self.provider.image_for_request(self.native)
        self.assertEqual((data, width, height), (png(), 1, 1))
        self.assertEqual(owner.identity[-1], 'b' * 64)
        self.assertTrue(self.provider.owns_image_observation(owner, self.native))
        self.provider.release_image_bytes(owner, self.native)
        self.assertIsNone(self.provider.image_for_request(self.native))
        self.assertTrue(self.provider.owns_image_observation(owner, self.native))
        self.assertTrue(self.provider.validate_current(snippet, self.native))
        self.provider.discard_images()
        self.assertFalse(self.provider.owns_image_observation(owner, self.native))
        self.assertTrue(self.provider.validate_current(snippet, self.native))

    def test_bad_image_identity_order_or_timeout_never_survives_admission(self):
        for change in ('identity', 'order', 'expiry'):
            with self.subTest(change=change):
                self.provider.discard_staged()
                self.assertTrue(self.provider.stage(wire(self.text)))
                self.assertTrue(self.provider.stage_image(wire(self.images[0])))
                bad = dict(self.images[1])
                if change == 'identity': bad['imageDigest'] = 'c' * 64
                elif change == 'order': bad['index'] = 1
                else: self.now += 2_000_000_001
                self.assertFalse(self.provider.stage_image(wire(bad)))
                self.current = self.native
                self.provider(self.native)
                self.assertIsNone(self.provider.image_for_request(self.native))
                self.provider.invalidate()
                self.now = self.text['capturedUptimeNanoseconds']

    def test_replacement_image_cannot_replace_completed_bytes_for_same_text(self):
        self.assertTrue(self.provider.stage(wire(self.text)))
        for frame in self.images:self.assertTrue(self.provider.stage_image(wire(frame)))
        self.assertFalse(self.provider.stage_image(wire(self.images[0])))
        self.current=self.native
        self.assertIsNotNone(self.provider(self.native))
        self.assertIsNone(self.provider.image_for_request(self.native))

    def test_old_retirement_preserves_newer_staged_text_and_image(self):
        self.provider.stage(wire(self.text));self.current=self.native;self.provider(self.native)
        newer=dict(self.native,presentationGeneration=3,requestID=str(uuid.uuid4()))
        text,images=screen_frames(newer,self.now)
        self.assertTrue(self.provider.stage(wire(text)))
        for frame in images:self.assertTrue(self.provider.stage_image(wire(frame)))
        self.assertFalse(self.provider.retire_staged(self.native))
        self.assertTrue(self.provider.retire_current(self.native))
        self.current=newer
        self.assertIsNotNone(self.provider(newer))
        self.assertIsNotNone(self.provider.image_for_request(newer))


class VisualBackendTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX dependency')
        self.httpx, self.calls, self.out = httpx, [], []
        self.token = 'synthetic-current-bearer'
        self.pause_probe = None
        self.reject_image = False

        async def handler(request):
            body = json.loads(request.content) if request.content else None
            self.calls.append((request.method, body))
            if request.method == 'GET':
                payload = {'models': [{'slug': MODEL, 'display_name': 'Synthetic', 'visibility': 'list'}]}
                return httpx.Response(200, stream=httpx.ByteStream(json.dumps(payload).encode()))
            if body['instructions'].startswith('Relay synthetic visual check'):
                if self.pause_probe is not None: await self.pause_probe.wait()
                text = read_probe_pixels(body)[0]
            else:
                parts = body['input'][0]['content']
                if self.reject_image and isinstance(parts, list):
                    payload = {'error': {'code': 'subscription_sharing_unsupported_capability', 'param': 'input', 'message': 'synthetic private'}}
                    return httpx.Response(400, stream=httpx.ByteStream(json.dumps(payload).encode()))
                text = generated_card()
            return httpx.Response(200, stream=httpx.ByteStream(completed_wire(text)), headers={'content-type': 'text/event-stream'})

        self.handler = handler
        self.stream = OAuthAnswerStream(model=MODEL, token_provider=lambda: self.token,
            client_factory=lambda **kw: httpx.AsyncClient(transport=httpx.MockTransport(self.handler), **kw))
        self.host = SessionHost(complete=self.stream.complete, visual_transport=self.stream, emit=self.out.append)
        self.provider = SupplementalContextProvider(current_request=self.host.supplemental_request_current,
                                                   on_invalidation=self.host.supplemental_context_changed)
        self.host.supplemental_provider = self.provider

    async def asyncTearDown(self):
        self.host.close()
        await self.host.drain()

    async def verify(self):
        value = control('verify')
        self.host.handle_visual_control(value)
        await self.host.drain()
        replies = [v for v in self.out if v.get('kind') == 'visual_input_response' and v['requestID'] == value['requestID']]
        self.assertEqual([(r['status'], r['resultRevision']) for r in replies], [('checking', 1), ('verified', 2)])
        return value

    async def question(self, *, images=True, selected=False):
        await self.host.handle(start()); await self.host.handle(speech(2)); await self.host.handle(end(3))
        event = final(4, 'Explain dictionary lookups.')
        text, frames = screen_frames(event)
        if selected:
            from tests.test_composition_host import selected as selected_wire
            self.assertTrue(self.provider.stage(selected_wire(event)))
        else:
            self.assertTrue(self.provider.stage(wire(text)))
            if images:
                for frame in frames: self.assertTrue(self.provider.stage_image(wire(frame)))
        await self.host.handle(event); await self.host.drain()
        return self.out[-1]

    async def test_idle_control_replay_and_status_never_repeat_auth_or_model_work(self):
        verify = await self.verify()
        before = len(self.calls)
        self.host.handle_visual_control(verify)
        self.assertEqual(len(self.calls), before)
        self.assertEqual(self.out[-1]['status'], 'verified')
        self.host.handle_visual_control(control('status'))
        self.assertEqual(len(self.calls), before)
        self.assertEqual(self.out[-1]['status'], 'verified')
        with self.assertRaises(WireError): self.host.handle_visual_control(dict(verify, action='disable'))
        self.host.handle_visual_control(control('status'))
        self.assertEqual(self.out[-1]['status'], 'disabled')

    async def test_actual_image_generation_preserves_original_pixel_digest_metadata(self):
        await self.verify()
        answer = await self.question()
        self.assertEqual(answer['disposition'], 'answer')
        self.assertEqual(answer['provenance']['taskContext']['imageDigest'], 'b' * 64)
        self.assertEqual(answer['provenance']['taskContext']['provenance'], 'local_ocr')
        self.assertEqual([method for method, _ in self.calls], ['GET', 'POST', 'POST'])
        self.assertIsInstance(self.calls[-1][1]['input'][0]['content'], list)
        self.assertEqual(self.host.model_requests, 1)
        self.assertIsNone(self.provider.image_for_request(self.host.active.native))

    async def test_unknown_images_and_selected_text_are_honest_single_text_fallbacks(self):
        answer = await self.question()
        self.assertNotIn('imageDigest', answer['provenance']['taskContext'])
        self.assertEqual([method for method, _ in self.calls], ['POST'])
        self.assertIsInstance(self.calls[-1][1]['input'][0]['content'], str)
        self.host.close(); await self.host.drain()
        await self.verify()
        # Fresh capture session identity is required after close.
        self.host.session = None
        answer = await self.question(selected=True)
        self.assertEqual(answer['provenance']['taskContext']['provenance'], 'selected_accessibility_text')
        self.assertNotIn('imageDigest', answer['provenance']['taskContext'])
        self.assertIsInstance(self.calls[-1][1]['input'][0]['content'], str)

    async def test_image_failure_has_no_automatic_second_model_post(self):
        await self.verify(); self.reject_image = True
        answer = await self.question()
        self.assertNotEqual(answer['disposition'], 'answer')
        self.assertEqual([method for method, _ in self.calls], ['GET', 'POST', 'POST'])

    async def test_probe_is_tracked_and_disable_stays_responsive_with_pending_http(self):
        self.pause_probe = asyncio.Event()
        value = control('verify'); self.host.handle_visual_control(value)
        for _ in range(100):
            if len(self.calls) >= 2: break
            await asyncio.sleep(.001)
        self.assertEqual(self.out[-1]['status'], 'checking')
        self.host.handle_visual_control(value)
        self.assertEqual(self.out[-1]['resultRevision'], 1)
        self.host.handle_visual_control(control('disable'))
        self.assertEqual(self.out[-1]['status'], 'disabled')
        await asyncio.wait_for(self.host.drain(), 1)
        final_replies = [v for v in self.out if v.get('requestID') == value['requestID'] and v['resultRevision'] == 2]
        self.assertEqual([v['status'] for v in final_replies], ['cancelled'])
        self.assertEqual([method for method, _ in self.calls], ['GET', 'POST'])

    async def test_probe_terminal_is_emitted_only_after_actual_task_quiescence(self):
        original=self.host.emit
        def checked_emit(value):
            if value.get('kind')=='visual_input_response' and value['action']=='verify' and value['resultRevision']==2:
                task=self.host.visual._probe_task
                self.assertTrue(task is None or task.done())
            original(value)
        self.host.emit=checked_emit
        await self.verify()

    async def test_disable_before_probe_task_starts_still_emits_one_quiesced_terminal(self):
        request=control('verify');self.host.handle_visual_control(request)
        self.host.handle_visual_control(control('disable'))
        await self.host.drain()
        terminal=[v for v in self.out if v['requestID']==request['requestID'] and v['resultRevision']==2]
        self.assertEqual([v['status'] for v in terminal],['cancelled'])
        self.assertEqual(self.calls,[])

    async def test_answer_waits_for_cancelled_probe_cleanup_on_the_same_stream(self):
        entered,release=asyncio.Event(),asyncio.Event();original=self.handler
        async def blocked_probe(request):
            body=json.loads(request.content) if request.content else None
            if request.method=='POST' and body['instructions'].startswith('Relay synthetic visual check'):
                self.calls.append(('POST',body));entered.set()
                try:await asyncio.Event().wait()
                finally:await release.wait()
            return await original(request)
        self.handler=blocked_probe
        self.host.handle_visual_control(control('verify'));await asyncio.wait_for(entered.wait(),1)
        for value in (start(),speech(2),end(3),final(4,'Explain dictionary lookups.')):await self.host.handle(value)
        await asyncio.sleep(.01)
        self.assertEqual([method for method,_ in self.calls],['GET','POST'])
        release.set();await asyncio.wait_for(self.host.drain(),1)
        self.assertEqual(self.out[-1]['disposition'],'answer')
        self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])

    async def test_partial_png_falls_back_once_to_valid_ocr_without_image_digest(self):
        await self.verify()
        await self.host.handle(start());await self.host.handle(speech(2));await self.host.handle(end(3))
        event=final(4,'Explain dictionary lookups.');text,frames=screen_frames(event)
        self.assertTrue(self.provider.stage(wire(text)))
        for frame in frames[:-1]:self.assertTrue(self.provider.stage_image(wire(frame)))
        await self.host.handle(event);await self.host.drain()
        self.assertEqual(self.out[-1]['disposition'],'answer')
        self.assertEqual(self.out[-1]['provenance']['taskContext']['provenance'],'local_ocr')
        self.assertNotIn('imageDigest',self.out[-1]['provenance']['taskContext'])
        self.assertIsInstance(self.calls[-1][1]['input'][0]['content'],str)
        self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])

    async def test_disable_cancels_only_image_dependent_work_and_never_retries(self):
        await self.verify()
        original=self.handler;entered=asyncio.Event()
        async def stalled_image(request):
            body=json.loads(request.content)
            if isinstance(body['input'][0]['content'],list):
                self.calls.append(('POST',body));entered.set();await asyncio.Event().wait()
            return await original(request)
        self.handler=stalled_image
        await self.host.handle(start());await self.host.handle(speech(2));await self.host.handle(end(3))
        event=final(4,'Explain dictionary lookups.');text,frames=screen_frames(event)
        self.provider.stage(wire(text))
        for frame in frames:self.provider.stage_image(wire(frame))
        await self.host.handle(event);await asyncio.wait_for(entered.wait(),1)
        self.host.handle_visual_control(control('disable'))
        await asyncio.wait_for(self.host.drain(),1)
        self.assertIsNone(self.host.active)
        self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])
        self.assertFalse(any(value.get('disposition')=='answer' for value in self.out))

    async def test_bearer_change_after_image_response_withholds_and_does_not_retry(self):
        await self.verify();original=self.handler
        async def changed(request):
            response=await original(request)
            if request.method=='POST':self.token='synthetic-replacement-bearer'
            return response
        self.handler=changed
        answer=await self.question()
        self.assertEqual(answer['disposition'],'abstain')
        self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])

    async def test_token_config_or_consent_changes_at_publication_veto_image_answer(self):
        for change in ('token','config','consent'):
            with self.subTest(change=change):
                # A fresh host models a fresh native helper configuration.
                if change!='token':
                    await self.asyncTearDown();await self.asyncSetUp()
                await self.verify()
                validate=self.stream.validate_visual_publication
                async def changed(permit):
                    if change=='token':self.token='synthetic-new-grant-at-publication'
                    elif change=='config':self.stream.model='different-synthetic-model'
                    else:self.host.handle_visual_control(control('disable'))
                    return await validate(permit)
                self.stream.validate_visual_publication=changed
                answer=await self.question()
                self.assertFalse(any(v.get('disposition')=='answer' for v in self.out))
                if change!='consent':self.assertEqual(answer.get('resultRevision'),2)
                self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])

    async def test_lost_image_permit_cannot_downgrade_completed_image_to_text_metadata(self):
        await self.verify();original=self.host.visual.validate_publication
        async def changed(request,**kwargs):
            self.host.visual.retire_request()
            return await original(request,**kwargs)
        self.host.visual.validate_publication=changed
        answer=await self.question()
        self.assertEqual(answer['disposition'],'abstain')
        self.assertFalse(any(v.get('disposition')=='answer' for v in self.out))
        self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])

    async def test_newer_native_onset_clears_large_partial_staging_without_model_io(self):
        import struct,zlib
        await self.host.handle(start());await self.host.handle(speech(2));await self.host.handle(end(3))
        base=png();payload=b'synthetic'*9000;kind=b'tEXt'
        extra=struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload))
        data=base[:33]+extra+base[33:]
        event=final(4,'Explain dictionary lookups.');text,frames=screen_frames(event,data=data)
        self.assertGreater(len(frames),10)
        self.provider.stage(wire(text));self.assertTrue(self.provider.stage_image(wire(frames[0])))
        self.assertTrue(self.provider.stage_image(wire(frames[1])))
        await self.host.handle(speech(4,2,3))
        self.assertFalse(self.provider.stage_image(wire(frames[2])))
        self.assertIsNone(self.host.active)
        self.assertEqual(self.calls,[])

    async def test_retirement_before_eou_clears_staged_image_and_text_without_an_active_request(self):
        await self.verify()
        await self.host.handle(start());await self.host.handle(speech(2));await self.host.handle(end(3))
        event=final(4,'Explain dictionary lookups.');text,frames=screen_frames(event)
        self.provider.stage(wire(text))
        for frame in frames:self.provider.stage_image(wire(frame))
        self.assertIsNone(self.host.active)
        self.host.handle_supplemental_retirement(retired(event))
        await self.host.handle(event);await self.host.drain()
        self.assertEqual(self.out[-1]['disposition'],'answer')
        self.assertNotIn('taskContext',self.out[-1]['provenance'])
        self.assertIsInstance(self.calls[-1][1]['input'][0]['content'],str)
        self.assertEqual([method for method,_ in self.calls],['GET','POST','POST'])

    async def test_live_verify_rejects_without_affecting_existing_reference(self):
        await self.host.handle(start())
        self.host.handle_visual_control(control('verify'))
        self.assertEqual((self.out[-1]['status'], self.out[-1]['reasonCode']), ('busy', 'session_active'))
        self.assertEqual(self.calls, [])
        await self.host.handle(speech(2)); await self.host.handle(end(3))
        await self.host.handle(final(4, 'What is the difference between WHERE and HAVING?'))
        answer = self.out[-1]
        self.assertEqual(answer['answerKind'], 'reviewed_reference')
        active = self.host.active
        self.host.handle_visual_control(control('disable'))
        self.assertIs(self.host.active, active)

    async def test_mismatched_fixture_complete_cannot_read_oauth_credentials_or_probe(self):
        reads=[]
        def provider():reads.append('credential_read');return self.token
        self.stream._token_provider=provider
        async def fixture(prompt,instructions):return generated_card()
        self.host.complete=fixture
        self.host.handle_visual_control(control('verify'));await self.host.drain()
        self.assertEqual(reads,[])
        self.assertEqual(self.calls,[])
        self.assertEqual((self.out[-1]['status'],self.out[-1]['reasonCode']),('unavailable','inference_disabled'))


class NoInferenceVisualTests(unittest.TestCase):
    def test_default_helper_control_is_inert_and_strict(self):
        out = []; host = SessionHost(emit=out.append)
        host.handle_visual_control(control('verify'))
        self.assertEqual((out[-1]['status'], out[-1]['reasonCode'], out[-1]['model']), ('unavailable', 'inference_disabled', None))
        for changes in ({'authorized': True}, {'schemaVersion': True}, {'action': 'upload'}, {'model': MODEL}):
            with self.assertRaises(WireError): host.handle_visual_control(dict(control('verify'), **changes))

    def test_same_uuid_with_changed_payload_rejects_and_ledger_is_bounded(self):
        host=SessionHost();request=control('status')
        host.handle_visual_control(request)
        with self.assertRaises(WireError):host.handle_visual_control(dict(request,requestID=request['requestID'].upper()))
        for _ in range(511):host.handle_visual_control(control('status'))
        with self.assertRaises(WireError):host.handle_visual_control(control('verify'))


def helper_stream(*,stall_probe=False):
    """Test-only transport injection for the actual run_stdio child process."""
    import httpx
    async def handler(request):
        if request.method=='GET':
            data={'models':[{'slug':MODEL,'display_name':'Synthetic','visibility':'list'}]}
            return httpx.Response(200,stream=httpx.ByteStream(json.dumps(data).encode()))
        body=json.loads(request.content)
        if body['instructions'].startswith('Relay synthetic visual check'):
            if stall_probe:await asyncio.Event().wait()
            text=read_probe_pixels(body)[0]
        else:text=generated_card()
        return httpx.Response(200,stream=httpx.ByteStream(completed_wire(text)),headers={'content-type':'text/event-stream'})
    return OAuthAnswerStream(model=MODEL,token_provider=lambda:'synthetic-child-bearer',
        client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(handler),**kw))


class HelperVisualProcessTests(unittest.TestCase):
    def setUp(self):
        try:import httpx
        except ImportError:self.skipTest('optional HTTPX dependency')
        import subprocess,sys,threading
        self.subprocess,self.sys,self.threading=subprocess,sys,threading

    def child(self,*,stall=False,fixture=False):
        if fixture:command=[self.sys.executable,'-m','relay_spike.session_host','--fixture-model']
        else:
            code=('import asyncio\nfrom types import SimpleNamespace\n'
                  'from relay_spike.session_host import run_stdio\n'
                  'from tests.test_visual_host_backend import helper_stream,MODEL\n'
                  f'raise SystemExit(asyncio.run(run_stdio(SimpleNamespace(oauth=True,fixture_model=False,model=MODEL,role="analytics"),oauth_stream=helper_stream(stall_probe={stall!r}))))')
            command=[self.sys.executable,'-c',code]
        child=self.subprocess.Popen(command,stdin=self.subprocess.PIPE,stdout=self.subprocess.PIPE,stderr=self.subprocess.PIPE)
        watchdog=self.threading.Timer(10,child.kill);watchdog.start()
        self.addCleanup(watchdog.cancel)
        def cleanup():
            if child.poll() is None:child.kill();child.wait()
            for pipe in (child.stdin,child.stdout,child.stderr):
                if pipe is not None:pipe.close()
        self.addCleanup(cleanup)
        return child

    def send(self,child,value):
        from relay_spike.panel_wire import encode_frame
        child.stdin.write(encode_frame(value));child.stdin.flush()

    def receive(self,child):
        header=child.stdout.read(4);self.assertEqual(len(header),4)
        return json.loads(child.stdout.read(int.from_bytes(header,'big')))

    def finish(self,child,code=0):
        child.stdin.close();child.stdin=None
        rest,errors=child.communicate(timeout=4)
        self.assertEqual((child.returncode,rest,errors),(code,b'',b''))

    def test_actual_helper_probe_image_answer_and_exact_safe_status_schema(self):
        child=self.child();request=control('verify');self.send(child,request)
        pending,verified=self.receive(child),self.receive(child)
        self.assertEqual([(v['status'],v['resultRevision']) for v in (pending,verified)],[('checking',1),('verified',2)])
        self.assertEqual(set(verified),{'schemaVersion','kind','requestID','action','resultRevision','status','reasonCode','model'})
        self.send(child,request);self.assertEqual(self.receive(child),verified)
        event=final(4,'Explain dictionary lookups.');text,images=screen_frames(event)
        for value in (start(),speech(2),end(3),text,*images,event):self.send(child,value)
        pending,answer=self.receive(child),self.receive(child)
        self.assertEqual(pending['disposition'],'pending')
        self.assertEqual(answer['provenance']['taskContext']['imageDigest'],'b'*64)
        self.assertEqual(answer['disposition'],'answer')
        self.finish(child)

    def test_actual_helper_reader_handles_pending_replay_status_disable_and_quiescence(self):
        child=self.child(stall=True);request=control('verify');self.send(child,request)
        checking=self.receive(child);self.assertEqual(checking['status'],'checking')
        self.send(child,request);self.assertEqual(self.receive(child),checking)
        status=control('status');self.send(child,status)
        busy=self.receive(child);self.assertEqual((busy['status'],busy['resultRevision']),('busy',2))
        disable=control('disable');self.send(child,disable)
        replies=[self.receive(child),self.receive(child)]
        by_id={reply['requestID']:reply for reply in replies}
        self.assertEqual(by_id[disable['requestID']]['status'],'disabled')
        self.assertEqual(by_id[request['requestID']]['status'],'cancelled')
        self.finish(child)

    def test_actual_fixture_helper_never_enables_visual_inference(self):
        child=self.child(fixture=True);self.send(child,control('verify'))
        reply=self.receive(child)
        self.assertEqual((reply['status'],reply['reasonCode'],reply['model']),('unavailable','inference_disabled',None))
        self.finish(child)

    def test_actual_case_fixture_uses_workflow_points_and_never_invents_code(self):
        child=self.child(fixture=True)
        event=final(4,'Case study: design a workflow for a clinic intake team. What are the first steps?')
        for value in (start(),speech(2),end(3),event):self.send(child,value)
        self.receive(child);answer=self.receive(child)
        self.assertEqual(answer['disposition'],'answer')
        card=answer['card'];self.assertIsNone(card['detail'])
        self.assertIn('workflow',card['lead'].lower())
        text=' '.join([card['lead'],*card['points']]).lower()
        self.assertIn('success',text)
        self.assertNotIn('empty input',text);self.assertNotIn('invariant',text)
        self.finish(child)

    def test_actual_helper_applies_staged_retirement_before_original_eou(self):
        child=self.child();self.send(child,control('verify'));self.receive(child);self.receive(child)
        event=final(4,'Explain dictionary lookups.');text,images=screen_frames(event)
        for value in (start(),speech(2),end(3),text,*images,retired(event),event):self.send(child,value)
        self.receive(child);answer=self.receive(child)
        self.assertEqual(answer['disposition'],'answer')
        self.assertNotIn('taskContext',answer['provenance'])
        self.finish(child)

    def test_actual_helper_reused_uuid_different_action_rejects_channel(self):
        child=self.child(stall=True);request=control('verify');self.send(child,request)
        self.assertEqual(self.receive(child)['status'],'checking')
        self.send(child,dict(request,action='disable'))
        self.finish(child,code=2)
