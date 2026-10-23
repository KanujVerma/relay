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
        await ready.wait();await h.handle(event('stopping',5,3,payload={'reason':'user_stop'}));release.set();await h.drain()
        self.assertFalse(any(x['disposition']=='answer' for x in out))

    async def test_missing_closed_association_and_duplicate_remote_eou_no_calls(self):
        calls=[];out=[]
        async def complete(*a): calls.append(a)
        h=SessionHost(complete=complete,emit=out.append)
        await h.handle(start());await h.handle(speech(2));await h.handle(end(3));e=final(4,'Explain queues.');e['payload']['activityClosed']=False
        await h.handle(e);await h.drain();self.assertEqual(calls,[])

class ChildTests(unittest.TestCase):
    def test_real_child_reviewed_and_novel_dynamic_route_and_clean_eof(self):
        import subprocess,sys
        payload=b''.join(encode_frame(e) for e in (start(),speech(2),end(3),final(4,'What is the difference between WHERE and HAVING?'),speech(5,2,3),end(6,2,3),final(7,'Discuss an LRU cache approach.',2,3)))
        child=subprocess.run([sys.executable,'-m','relay_spike.session_host','--fixture-model'],input=payload,capture_output=True,timeout=5)
        self.assertEqual(child.returncode,0,child.stderr)
        decisions=FrameDecoder().feed(child.stdout)
        self.assertEqual([d['answerKind'] for d in decisions if d['disposition']=='answer'],['reviewed_reference','generated_suggestion'])
        self.assertEqual(child.stderr,b'')

    def test_truncated_frame_exits_content_free(self):
        import subprocess,sys
        child=subprocess.run([sys.executable,'-m','relay_spike.session_host'],input=b'\0\0\0\x10secret',capture_output=True,timeout=5)
        self.assertEqual(child.returncode,2)
        self.assertEqual(child.stdout,b'');self.assertEqual(child.stderr,b'')
