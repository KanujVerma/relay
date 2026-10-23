import asyncio
import json
import unittest
import uuid
from relay_spike.session_host import SessionHost
from relay_spike.panel_wire import FrameDecoder, WireError, encode_frame

SESSION=str(uuid.uuid4())
def event(kind, sequence, generation=1, source=None, payload=None, request=None):
    return dict(schemaVersion=1,captureSessionID=SESSION,sessionEpoch=1,eventSequence=sequence,presentationGeneration=generation,kind=kind,sourceCode=source,streamGeneration=1 if source else None,emittedUptimeNanoseconds=sequence*1000000000,payload=payload or {},requestID=request)
def start(): return event('session_started',1,payload={'selectedBundleID':'synthetic.fixture','microphoneEnabled':True})
def speech(sequence, activity=1, generation=2, source=2):
    return event('speech_started',sequence,generation,source,dict(activityID=activity,startHostTime=sequence*1000000000,detectedUptimeNanoseconds=sequence*1000000000,timebase=dict(hostTicksAtAnchor=0,uptimeNsAtAnchor=0,nsNumer=1,nsDenom=1)))
def end(sequence,activity=1,generation=2,source=2):
    return event('speech_ended',sequence,generation,source,dict(activityID=activity,endHostTime=sequence*1000000000,lastSpeechInputSequence=sequence,timebase=dict(hostTicksAtAnchor=0,uptimeNsAtAnchor=0,nsNumer=1,nsDenom=1)))
def final(sequence,text,activity=1,generation=2,source=2):
    inner=dict(version=1,status='final',sourceCode=source,streamGeneration=1,segmentID=sequence,revision=1,startHostTime=(sequence-2)*1000000000,endHostTime=(sequence-1)*1000000000,finalizedUptimeNanoseconds=sequence*1000000000,receivedUptimeNanoseconds=sequence*1000000000,text=text,confidence=None,timebase=dict(hostTicksAtAnchor=0,uptimeNsAtAnchor=0,nsNumer=1,nsDenom=1))
    return event('eou',sequence,generation,source,dict(event=inner,activityID=activity,firstInputSequence=sequence-2,lastInputSequence=sequence-1,activityClosed=True,lastSpeechInputSequence=sequence-1),str(uuid.uuid4()) if source==2 else None)

class FrameTests(unittest.TestCase):
    def test_fragmented_and_coalesced_and_overflow(self):
        frame=encode_frame(start()); d=FrameDecoder()
        self.assertEqual(d.feed(frame[:3]),())
        self.assertEqual(d.feed(frame[3:]+frame),(start(),start()))
        with self.assertRaises(WireError): FrameDecoder().feed((16385).to_bytes(4,'big'))
        with self.assertRaises(WireError): FrameDecoder().feed(b'\0\0\0\x0d{"x":1,"x":2}')

class HostTests(unittest.IsolatedAsyncioTestCase):
    async def test_reviewed_zero_model_and_original_fence_opaque_colon_token(self):
        calls=[]; out=[]
        async def model(prompt,instructions): calls.append(prompt); raise AssertionError('reviewed called model')
        h=SessionHost(complete=model,emit=out.append)
        await h.handle(start()); await h.handle(speech(2)); await h.handle(end(3))
        e=final(4,'What is the difference between WHERE and HAVING?')
        await h.handle(e); await h.drain()
        self.assertEqual(calls,[])
        self.assertEqual(out[-1]['answerKind'],'reviewed_reference')
        self.assertEqual(out[-1]['requestID'],e['requestID'])
        self.assertIn(':',out[-1]['pythonToken']['turnID'])
        self.assertNotIn(':',out[-1]['displayID'])
        self.assertEqual(out[-1]['eventSequence'],4)

    async def test_novel_multiturn_uses_one_dynamic_request_and_user_reply_only_context(self):
        prompts=[];out=[]
        async def complete(prompt,instructions):
            prompts.append(json.loads(prompt))
            return json.dumps(dict(lead='Discuss capacity and eviction before implementation.',points=['Keep lookup and recency updates constant time.'],detail=None,assumptions=['Thread safety is not specified.'],coverage=['approach'],personal_fact_ids=[]))
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));await h.handle(final(4,'Let us implement a cache. What questions would you ask?'));await h.drain()
        await h.handle(speech(5,2,2,1));await h.handle(end(6,2,2,1));await h.handle(final(7,'I would ask about eviction.',2,2,1))
        self.assertEqual(len(prompts),1)
        await h.handle(speech(8,3,3));await h.handle(end(9,3,3));await h.handle(final(10,'What about capacity 3 and LRU?',3,3));await h.drain()
        self.assertEqual(len(prompts),2)
        self.assertIn('eviction',str(prompts[-1]['conversation']['task']['user_attempt']))
        self.assertEqual(out[-1]['answerKind'],'generated_suggestion')

    async def test_late_success_after_stop_cannot_publish(self):
        ready=asyncio.Event();release=asyncio.Event();out=[]
        async def complete(*_):
            ready.set()
            try: await release.wait()
            except asyncio.CancelledError: await release.wait()
            return json.dumps(dict(lead='An obsolete answer.',points=[],detail=None,assumptions=[],coverage=['approach'],personal_fact_ids=[]))
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));await h.handle(final(4,'Explain hash collisions.'))
        await ready.wait();await h.handle(event('stopping',5,3,payload={'reasonCode':'user_stop'}));release.set();await h.drain()
        self.assertFalse(any(x['disposition']=='answer' for x in out))

    async def test_missing_closed_association_and_duplicate_remote_eou_no_calls(self):
        calls=[];out=[]
        async def complete(*a): calls.append(a)
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));e=final(4,'Explain queues.');e['payload']['activityClosed']=False
        await h.handle(e);await h.drain();self.assertEqual(calls,[])

def run_interactive_child(payload,expected_frames):
    import subprocess,sys,threading
    child=subprocess.Popen([sys.executable,'-m','relay_spike.session_host','--fixture-model'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    watchdog=threading.Timer(5,child.kill);watchdog.start()
    try:
        child.stdin.write(payload);child.stdin.flush();rows=[]
        for _ in range(expected_frames):
            header=child.stdout.read(4)
            if len(header)!=4:raise AssertionError('helper closed before expected decision')
            body=child.stdout.read(int.from_bytes(header,'big'))
            rows.append(json.loads(body))
        child.stdin.close();child.stdin=None
        rest,errors=child.communicate(timeout=5)
        if rest:rows.extend(FrameDecoder().feed(rest))
        return child.returncode,tuple(rows),errors
    finally:
        watchdog.cancel()
        if child.poll() is None:child.kill();child.wait()

class ChildTests(unittest.TestCase):
    def test_real_child_reviewed_and_novel_dynamic_route_and_clean_eof(self):
        import subprocess,sys
        payload=b''.join(encode_frame(e) for e in (start(),speech(2),end(3),final(4,'What is the difference between WHERE and HAVING?'),speech(5,2,3),end(6,2,3),final(7,'Discuss an LRU cache approach.',2,3)))
        code,decisions,errors=run_interactive_child(payload,3)
        self.assertEqual(code,0,errors)
        self.assertEqual([d['answerKind'] for d in decisions if d['disposition']=='answer'],['reviewed_reference','generated_suggestion'])
        self.assertEqual(errors,b'')

    def test_truncated_frame_exits_content_free(self):
        import subprocess,sys
        child=subprocess.run([sys.executable,'-m','relay_spike.session_host'],input=b'\0\0\0\x10secret',capture_output=True,timeout=5)
        self.assertEqual(child.returncode,2)
        self.assertEqual(child.stdout,b'');self.assertEqual(child.stderr,b'')

class LateContextTests(unittest.IsolatedAsyncioTestCase):
    async def test_late_old_final_updates_history_without_canceling_new_request(self):
        calls=[];out=[]
        async def complete(prompt,instructions):
            calls.append(json.loads(prompt));return json.dumps(dict(lead='A current explanation.',points=[],detail=None,assumptions=[],coverage=['current'],personal_fact_ids=[]))
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3))
        await h.handle(speech(4,2,3));await h.handle(end(5,2,3))
        newer=final(6,'Explain a queue.',2,3)
        await h.handle(newer);await h.drain()
        active=h.active
        late=final(7,'Explain the earlier cache.',1,2)
        late['payload']['event']['startHostTime']=2000000000;late['payload']['event']['endHostTime']=3000000000
        late['payload']['firstInputSequence']=2;late['payload']['lastInputSequence']=3;late['payload']['lastSpeechInputSequence']=3
        await h.handle(late)
        self.assertIs(h.active,active);self.assertTrue(h.live);self.assertEqual(len(calls),1)
        dialogue=h.context.snapshot().dialogue
        self.assertIn('earlier cache',dialogue[-2][1]);self.assertIn('queue',dialogue[-1][1])

class SchedulerTests(unittest.IsolatedAsyncioTestCase):
    async def test_one_active_worker_and_only_newest_pending_after_slow_cancellation(self):
        entered=asyncio.Event();release=asyncio.Event();calls=[];out=[]
        async def complete(prompt,instructions):
            calls.append(json.loads(prompt)['current_request'])
            if len(calls)==1:
                entered.set()
                try: await release.wait()
                except asyncio.CancelledError: await release.wait()
            return json.dumps(dict(lead='Current explanation.',points=[],detail=None,assumptions=[],coverage=['current'],personal_fact_ids=[]))
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));await h.handle(final(4,'Explain queues.'));await entered.wait()
        for base,activity in ((5,2),(8,3)):
            await h.handle(speech(base,activity,activity+1));await h.handle(end(base+1,activity,activity+1));await h.handle(final(base+2,'Explain cache '+str(activity)+'?',activity,activity+1))
            barrier=asyncio.Event();asyncio.get_running_loop().call_soon(barrier.set);await barrier.wait()
        self.assertEqual(len(calls),1)
        release.set();await h.drain()
        self.assertEqual(len(calls),2);self.assertIn('3',calls[-1])
        self.assertEqual(len([d for d in out if d['disposition']=='answer']),1)

class ProfileCompositionTests(unittest.TestCase):
    def test_profile_port_and_answer_session_use_one_real_child(self):
        import subprocess,sys
        request={'schemaVersion':1,'kind':'profile_request','requestID':str(uuid.uuid4()),'payload':{'command':'new'}}
        code,rows,errors=run_interactive_child(encode_frame(request)+b''.join(encode_frame(e) for e in (start(),speech(2),end(3),final(4,'Explain queues.'))),3)
        self.assertEqual(code,0,errors)
        self.assertEqual(rows[0]['kind'],'profile_response');self.assertTrue(rows[0]['payload']['ready'])
        self.assertEqual(rows[-1]['answerKind'],'generated_suggestion')

class GroundingTests(unittest.IsolatedAsyncioTestCase):
    async def test_exact_approved_self_and_team_points_and_revocation(self):
        import base64
        from hashlib import sha256
        from relay_spike.profile_bridge import ProfileBridge
        h=SessionHost(emit=lambda _:None,role='developer')
        profile=ProfileBridge(on_change=h.personal_context_changed);profile.handle({'command':'new'});h.provider=profile
        text=b'I implemented Atlas SQL tests.'
        profile.handle({'command':'select_begin','size':len(text),'sha256':sha256(text).hexdigest(),'file_type':'txt','purpose':'project','label':'Atlas','role':'developer','project_hint':'Atlas'})
        profile.handle({'command':'transfer_chunk','offset':0,'data':base64.b64encode(text).decode()})
        card=profile.handle({'command':'select_commit'})['card']
        profile.handle({'command':'decide','fact_id':card['fact_id'],'fingerprint':card['card_fingerprint'],'decision':'approve','actor':'self','claim_key':'atlas.tests'})
        out=[];h.emit=out.append
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));await h.handle(final(4,'What did you personally do on your Atlas project?'))
        self.assertEqual(out[-1]['reasonCode'],'grounded_personal')
        self.assertIn('I implemented Atlas SQL tests.',out[-1]['card']['points'][0])
        self.assertEqual(out[-1]['provenance']['facts'][0]['actor'],'self')
        profile.handle({'command':'revoke','source_id':card['source_id']})
        self.assertIsNone(h.active)
        await h.handle(speech(5,2,3));await h.handle(end(6,2,3));await h.handle(final(7,'What did you personally do on your Atlas project?',2,3))
        self.assertEqual(out[-1]['disposition'],'clarify')
        profile.close()

class ProfileReplayTests(unittest.TestCase):
    def test_profile_request_uuid_replay_never_repeats_mutation(self):
        import subprocess,sys
        ident=str(uuid.uuid4())
        first={'schemaVersion':1,'kind':'profile_request','requestID':ident,'payload':{'command':'new'}}
        conflicting={**first,'payload':{'command':'lock'}}
        check={'schemaVersion':1,'kind':'profile_request','requestID':str(uuid.uuid4()),'payload':{'command':'state'}}
        child=subprocess.run([sys.executable,'-m','relay_spike.session_host'],input=b''.join(encode_frame(v) for v in (first,first,conflicting,check)),capture_output=True,timeout=5)
        rows=FrameDecoder().feed(child.stdout)
        self.assertEqual(rows[0]['payload'],rows[1]['payload'])
        self.assertFalse(rows[2]['payload']['ok']);self.assertTrue(rows[3]['payload']['ready'])

class QuietWithholdTests(unittest.IsolatedAsyncioTestCase):
    async def test_statement_and_blank_final_seal_immediately_without_fake_token(self):
        for text,reason in (('Thanks for the explanation.','no_question'),('','blank_question')):
            out=[];h=SessionHost(emit=out.append)
            await h.handle(start());await h.handle(speech(2));await h.handle(end(3));await h.handle(final(4,'What is the difference between WHERE and HAVING?'))
            await h.handle(speech(5,2,3));await h.handle(end(6,2,3));await h.handle(final(7,text,2,3))
            self.assertEqual(out[-1]['disposition'],'abstain');self.assertEqual(out[-1]['reasonCode'],reason)
            self.assertIsNone(out[-1]['pythonToken']);self.assertIsNone(out[-1]['displayID']);self.assertIsNone(out[-1]['card'])

class ScreenPortTests(unittest.IsolatedAsyncioTestCase):
    async def test_changed_screen_revision_vetoes_result_at_publication(self):
        from relay_spike.conversation_context import ContextSnippet
        import time
        entered=asyncio.Event();release=asyncio.Event();out=[]
        class Provider:
            current=True
            def __call__(self,n):
                return ContextSnippet('screen_text','def existing(): return 1','selected IDE',time.monotonic_ns(),n['captureSessionID'],n['presentationGeneration'],'local_ocr')
            def validate_current(self,snippet,n):return self.current
        provider=Provider()
        async def complete(prompt,instructions):
            self.assertIn('def existing',prompt);entered.set();await release.wait()
            return json.dumps(dict(lead='Explain the supplied function first.',points=[],detail=None,assumptions=[],coverage=['current'],personal_fact_ids=[]))
        h=SessionHost(complete=complete,emit=out.append,supplemental_provider=provider)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));await h.handle(final(4,'How should we improve this function?'))
        await entered.wait();provider.current=False;release.set();await h.drain()
        self.assertFalse(any(v['disposition']=='answer' for v in out))

class SpokenFeedbackTests(unittest.IsolatedAsyncioTestCase):
    async def test_engineer_statement_and_natural_followup_retain_new_constraint(self):
        prompts=[];out=[]
        async def complete(prompt,instructions):
            prompts.append(json.loads(prompt));return json.dumps(dict(lead='Discuss the supplied constraints before implementation.',points=[],detail=None,assumptions=[],coverage=['approach'],personal_fact_ids=[]))
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start())
        for sequence,activity,text in ((2,1,'Let us implement an LRU cache. What should we clarify?'),(5,2,'Capacity is three and keys are strings.'),(8,3,'And if callers can be concurrent?')):
            await h.handle(speech(sequence,activity,activity+1));await h.handle(end(sequence+1,activity,activity+1));await h.handle(final(sequence+2,text,activity,activity+1));await h.drain()
        self.assertEqual(len(prompts),2)
        self.assertIn('Capacity is three',str(prompts[-1]['conversation']['task']['constraints']))
