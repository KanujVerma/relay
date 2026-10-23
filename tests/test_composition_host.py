import asyncio
import json
import time
import unittest
import uuid
from relay_spike.session_host import SessionHost
from relay_spike.supplemental_context import SupplementalContextProvider
from tests.test_session_host import start,speech,end,final


def card():
    return json.dumps(dict(lead='State the supplied constraints before choosing an approach.',points=[],detail=None,
        assumptions=['Task context may be incomplete.'],coverage=['current_request'],personal_fact_ids=[]))

def selected(native):
    return json.dumps(dict(schemaVersion=1,kind='selected_text_context',
        **{key:native[key] for key in ('captureSessionID','sessionEpoch','presentationGeneration','requestID')},
        source={'bundleID':'com.example.editor','processID':42,'launchTimeMilliseconds':1234567},
        consentGeneration=str(uuid.uuid4()),observationID=str(uuid.uuid4()),capturedUptimeNanoseconds=time.monotonic_ns(),
        text='Assume duplicate keys and NULL values.',provenance='selected_accessibility_text')).encode()

def manual(host,question,**changes):
    value=dict(schemaVersion=1,kind='manual_help_request',captureSessionID=host.session[0],sessionEpoch=host.session[1],
        presentationGeneration=host.presentation+1,requestID=str(uuid.uuid4()),anchorEventSequence=host.sequence,
        emittedUptimeNanoseconds=time.monotonic_ns(),question=question)
    value.update(changes);return value

class CompositionHostTests(unittest.IsolatedAsyncioTestCase):
    async def prepared(self,question='Explain dictionary lookups.'):
        self.prompts=[];self.out=[]
        async def complete(prompt,instructions):self.prompts.append(json.loads(prompt));return card()
        host=SessionHost(complete=complete,emit=self.out.append)
        context=SupplementalContextProvider(current_request=host.supplemental_request_current,on_invalidation=host.supplemental_context_changed)
        host.supplemental_provider=context
        await host.handle(start());await host.handle(speech(2));await host.handle(end(3))
        return host,context,final(4,question)
    async def test_actual_context_is_admitted_before_routing_and_freezes_for_generation(self):
        host,context,eou=await self.prepared('What is the difference between WHERE and HAVING?')
        self.assertTrue(context.stage(selected(eou)))
        await host.handle(eou);await host.drain()
        self.assertEqual(len(self.prompts),1)
        self.assertEqual(self.prompts[0]['task_input']['provenance'],'selected_accessibility_text')
        self.assertEqual(self.out[-1]['answerKind'],'generated_suggestion')
        self.assertEqual(self.out[-1]['provenance']['taskContext']['source'],'Selected text: com.example.editor')
        self.assertFalse(context.stage(selected(eou)))
    async def test_unclosed_or_old_request_never_ingests_staged_context(self):
        host,context,eou=await self.prepared()
        self.assertTrue(context.stage(selected(eou)));eou['payload']['activityClosed']=False
        await host.handle(eou);await host.drain()
        self.assertEqual(self.prompts,[])
        self.assertIsNone(host.active)
    async def test_manual_help_reuses_current_semantic_question_without_audio_sequence(self):
        host,context,eou=await self.prepared()
        await host.handle(eou);await host.drain()
        token=self.out[-1]['pythonToken'];before=host.sequence
        request=manual(host,'Explain dictionary lookups.')
        self.assertTrue(context.stage(selected(request)))
        await host.handle_manual_help(request);await host.drain()
        self.assertEqual(host.sequence,before)
        self.assertEqual(self.out[-1]['eventSequence'],before)
        self.assertEqual(self.out[-1]['requestID'],request['requestID'])
        self.assertEqual(self.out[-1]['pythonToken'],token)
        self.assertEqual(len(self.prompts),2)
        self.assertEqual(self.prompts[-1]['task_input']['provenance'],'selected_accessibility_text')
        await host.handle(speech(5,2,request['presentationGeneration']+1));await host.handle(end(6,2,request['presentationGeneration']+1))
        self.assertEqual(host.sequence,6)
        self.assertIsNone(host.active)
    async def test_manual_unknown_question_stale_anchor_replay_and_missing_question_withhold(self):
        host,context,eou=await self.prepared()
        await host.handle(eou);await host.drain();count=len(self.prompts)
        for request in (manual(host,'Explain dictionary lookups.',anchorEventSequence=3),manual(host,'Explain dictionary lookups.',presentationGeneration=host.presentation)):
            self.assertFalse(await host.handle_manual_help(request))
        self.assertEqual(len(self.prompts),count)
        valid=manual(host,'Explain dictionary lookups.')
        self.assertTrue(await host.handle_manual_help(valid));await host.drain()
        self.assertFalse(await host.handle_manual_help(valid));await host.drain()
        self.assertEqual(len(self.prompts),count+1)
        self.assertFalse(await host.handle_manual_help(manual(host,'Invent a different question.')))
        self.assertEqual(self.out[-1]['reasonCode'],'manual_context_unavailable')
        await host.handle(speech(5,2,host.presentation+1))
        self.assertFalse(await host.handle_manual_help(manual(host,'Explain dictionary lookups.')))

class CompositionChildTests(unittest.TestCase):
    def test_actual_helper_context_manual_help_and_quiescence_keep_one_profile(self):
        import subprocess,sys,threading
        from relay_spike.panel_wire import encode_frame
        from tests.test_session_host import event
        child=subprocess.Popen([sys.executable,'-m','relay_spike.session_host','--fixture-model'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        watchdog=threading.Timer(8,child.kill);watchdog.start()
        def send(value):child.stdin.write(encode_frame(value));child.stdin.flush()
        def receive():
            header=child.stdout.read(4)
            self.assertEqual(len(header),4)
            return json.loads(child.stdout.read(int.from_bytes(header,'big')))
        try:
            send({'schemaVersion':1,'kind':'profile_request','requestID':str(uuid.uuid4()),'payload':{'command':'new'}})
            self.assertTrue(receive()['payload']['ready'])
            eou=final(4,'Explain dictionary lookups.')
            for value in (start(),speech(2),end(3)):send(value)
            send(json.loads(selected(eou)));send(eou)
            pending,answer=receive(),receive()
            self.assertEqual(pending['reasonCode'],'generating_with_task_context')
            self.assertEqual(answer['provenance']['taskContext']['provenance'],'selected_accessibility_text')
            request=dict(schemaVersion=1,kind='manual_help_request',captureSessionID=eou['captureSessionID'],sessionEpoch=1,
                presentationGeneration=3,requestID=str(uuid.uuid4()),anchorEventSequence=4,emittedUptimeNanoseconds=time.monotonic_ns(),question='Explain dictionary lookups.')
            send(request);self.assertEqual(receive()['disposition'],'pending');manual_answer=receive()
            self.assertEqual(manual_answer['requestID'],request['requestID']);self.assertNotIn('taskContext',manual_answer['provenance'])
            send(event('stopping',5,4,payload={'reasonCode':'user_stop'}))
            send(event('stopped',6,4,payload={'reasonCode':'user_stop','quiesced':True}))
            quiescence={'schemaVersion':1,'kind':'session_quiescence_request','requestID':str(uuid.uuid4()),'captureSessionID':eou['captureSessionID'],'sessionEpoch':1}
            send(quiescence);ack=receive()
            self.assertEqual(ack,{**quiescence,'kind':'session_quiescence_response','quiesced':True})
            send({'schemaVersion':1,'kind':'profile_request','requestID':str(uuid.uuid4()),'payload':{'command':'state'}})
            self.assertTrue(receive()['payload']['ready'])
            child.stdin.close();child.stdin=None
            rest,errors=child.communicate(timeout=4)
            self.assertEqual((child.returncode,rest,errors),(0,b'',b''))
        finally:
            watchdog.cancel()
            if child.poll() is None:child.kill();child.wait()
    def test_quiescence_before_stopped_or_replayed_control_fails_closed(self):
        import subprocess,sys
        from relay_spike.panel_wire import encode_frame
        from tests.test_session_host import event
        quiescence={'schemaVersion':1,'kind':'session_quiescence_request','requestID':str(uuid.uuid4()),'captureSessionID':start()['captureSessionID'],'sessionEpoch':1}
        for frames in ((start(),quiescence),(start(),event('stopping',2,2,payload={'reasonCode':'user_stop'}),quiescence),
            (start(),event('stopping',2,2,payload={'reasonCode':'user_stop'}),event('stopped',3,2,payload={'reasonCode':'user_stop','quiesced':False}),quiescence,quiescence)):
            child=subprocess.run([sys.executable,'-m','relay_spike.session_host'],input=b''.join(encode_frame(frame) for frame in frames),capture_output=True,timeout=5)
            self.assertEqual(child.returncode,2)
            self.assertEqual(child.stderr,b'')
