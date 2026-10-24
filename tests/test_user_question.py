import asyncio
import copy
import json
import subprocess
import sys
import time
import unittest
import uuid

from relay_spike.panel_wire import WireError, encode_frame, FrameDecoder
from relay_spike.session_host import SessionHost
from relay_spike.user_question import decode_user_question, decode_retirement, decode_cancel
from tests.test_session_host import start


def question(host, text='Explain event loops.', *, basis=None, intent='ask', **changes):
    value=dict(schemaVersion=1,kind='user_question_request',captureSessionID=host.session[0],
        sessionEpoch=host.session[1],presentationGeneration=host.presentation+1,
        requestID=str(uuid.uuid4()),anchorEventSequence=host.sequence,
        emittedUptimeNanoseconds=time.monotonic_ns(),intent=intent,
        question=text if intent=='ask' else None,baseRequestID=basis)
    value.update(changes)
    return value


def retirement(request):
    return {**{k:request[k] for k in ('captureSessionID','sessionEpoch','presentationGeneration','requestID')},
        'schemaVersion':1,'kind':'answer_request_retired','reasonCode':'request_retired'}


def cancel(host, target, **changes):
    value=dict(schemaVersion=1,kind='answer_cancel_request',captureSessionID=host.session[0],
        sessionEpoch=host.session[1],presentationGeneration=host.presentation+1,
        requestID=str(uuid.uuid4()),targetRequestID=target['requestID'],
        anchorEventSequence=host.sequence,emittedUptimeNanoseconds=time.monotonic_ns())
    value.update(changes)
    return value


def card():
    return json.dumps(dict(lead='Explain the supplied problem before choosing an approach.',
        points=['Check the stated constraints.'],detail=None,assumptions=[],
        coverage=['current_request'],personal_fact_ids=[]))


class UserQuestionDecoderTests(unittest.TestCase):
    def test_exact_text_integer_and_intent_domains(self):
        host=SessionHost();host.session=(str(uuid.uuid4()),1);host.sequence=1;host.presentation=1
        good=question(host,'Explain '+'🧠'*100+'.')
        self.assertEqual(decode_user_question(good)['eventSequence'],1)
        for changes in ({'question':'🧠'*126},{'question':'line\nbreak'}, {'question':'hidden\u200btext'},
                {'anchorEventSequence':True},{'presentationGeneration':2.0},{'question':''},
                {'intent':'recap'},{'baseRequestID':'wrong'},{'authority':True}):
            with self.subTest(changes=changes),self.assertRaises(WireError):
                decode_user_question({**good,**changes})
        with self.assertRaises(WireError):decode_user_question({**good,'intent':'help_current','question':None})
        help_value={**good,'intent':'help_current','question':None,'baseRequestID':str(uuid.uuid4())}
        self.assertEqual(decode_user_question(help_value)['intent'],'help_current')
        with self.assertRaises(WireError):decode_retirement({**retirement(good),'reasonCode':'provider detail'})
        with self.assertRaises(WireError):decode_cancel({**cancel(host,good),'targetRequestID':None})


class UserQuestionHostTests(unittest.IsolatedAsyncioTestCase):
    async def prepared(self, complete=None):
        self.out=[];self.prompts=[]
        async def ordinary(prompt,instructions):
            self.prompts.append(json.loads(prompt));return card()
        host=SessionHost(complete=complete or ordinary,emit=self.out.append)
        await host.handle(start())
        self.addAsyncCleanup(host.drain);self.addCleanup(host.close)
        return host

    async def test_explicit_before_first_remote_question_reuses_reference_without_a_model(self):
        host=await self.prepared()
        request=question(host,'What is the difference between WHERE and HAVING?')
        self.assertTrue(await host.handle_user_question(request));await host.drain()
        self.assertEqual(host.sequence,1)
        self.assertEqual(self.out[-1]['answerKind'],'reviewed_reference')
        self.assertEqual(self.out[-1]['question'],request['question'])
        self.assertEqual(self.prompts,[])
        self.assertTrue(self.out[-1]['pythonToken']['turnID'].startswith('user-request:'))
        self.assertIsNone(host.machine.current())

    async def test_personal_question_cannot_promote_typed_claims_or_call_model(self):
        host=await self.prepared()
        await host.handle_user_question(question(host,'What did you personally do on your Atlas project?'))
        await host.drain()
        self.assertEqual(self.out[-1]['disposition'],'clarify')
        self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
        self.assertEqual(self.prompts,[])

    async def test_retained_basis_is_context_not_old_token_or_unrelated_task(self):
        host=await self.prepared()
        first=question(host,'Implement an LRU cache. Capacity is 2.')
        await host.handle_user_question(first);await host.drain()
        old_token=self.out[-1]['pythonToken']
        await host.handle_user_question(question(host,'Design a shopping app.'));await host.drain()
        follow=question(host,'Which eviction approach fits?',basis=first['requestID'])
        self.assertTrue(await host.handle_user_question(follow));await host.drain()
        self.assertNotEqual(self.out[-1]['pythonToken'],old_token)
        task=self.prompts[-1]['conversation']['task']
        self.assertIn('Implement an LRU cache.',task['known_problem'][0])
        self.assertIn('Capacity is 2.',task['constraints'])
        self.assertNotIn('shopping',str(task))
        self.assertEqual(host.context.snapshot().dialogue,())
        await host.handle_user_question(question(host,'Explain event loops.'));await host.drain()
        self.assertEqual(self.prompts[-1]['conversation']['task']['known_problem'],['Explain event loops.'])
        self.assertEqual(self.prompts[-1]['conversation']['task']['constraints'],[])

    async def test_help_current_keeps_personal_followup_semantics_without_general_model(self):
        host=await self.prepared()
        first=question(host,'What did you personally do on your Atlas project?')
        await host.handle_user_question(first);await host.drain()
        follow=question(host,'What else?',basis=first['requestID'])
        await host.handle_user_question(follow);await host.drain()
        self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
        help_request=question(host,basis=follow['requestID'],intent='help_current')
        self.assertTrue(await host.handle_user_question(help_request));await host.drain()
        self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
        self.assertEqual(self.out[-1]['question'],'What else?')
        self.assertEqual(self.prompts,[]);self.assertEqual(host.model_requests,0)
        repeated=question(host,basis=help_request['requestID'],intent='help_current')
        self.assertTrue(await host.handle_user_question(repeated));await host.drain()
        self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
        self.assertEqual(self.prompts,[]);self.assertEqual(host.model_requests,0)

    async def test_help_current_keeps_technical_followup_semantics_and_task_with_fresh_token(self):
        host=await self.prepared();first=question(host,'Implement an LRU cache. Capacity is 2.')
        await host.handle_user_question(first);await host.drain()
        follow=question(host,'Which eviction approach fits?',basis=first['requestID'])
        await host.handle_user_question(follow);await host.drain()
        semantic=self.prompts[-1]['semantic_request'];task=self.prompts[-1]['conversation']['task']
        old_token=self.out[-1]['pythonToken']
        self.assertTrue(await host.handle_user_question(question(host,basis=follow['requestID'],intent='help_current')))
        await host.drain()
        self.assertEqual(self.prompts[-1]['semantic_request'],semantic)
        self.assertEqual(self.prompts[-1]['current_request'],follow['question'])
        self.assertEqual(self.prompts[-1]['conversation']['task'],task)
        self.assertEqual(self.out[-1]['disposition'],'answer')
        self.assertEqual(self.out[-1]['question'],follow['question'])
        self.assertNotEqual(self.out[-1]['pythonToken'],old_token)

    async def test_short_ask_chain_keeps_original_personal_semantics_without_nested_labels(self):
        host=await self.prepared();first=question(host,'What did you personally do on your Atlas project?')
        await host.handle_user_question(first);await host.drain()
        basis=first['requestID']
        for text in ('What else?','Why?','How so?'):
            follow=question(host,text,basis=basis)
            self.assertTrue(await host.handle_user_question(follow));await host.drain()
            self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
            self.assertEqual(self.out[-1]['question'],text)
            self.assertIn(first['question'],host.active.question)
            self.assertEqual(host.active.question.count('Current user question (verbatim):'),1)
            basis=follow['requestID']
        self.assertEqual(self.prompts,[]);self.assertEqual(host.model_requests,0)

    async def test_semantic_ancestry_budget_withholds_instead_of_dropping_personal_basis(self):
        host=await self.prepared()
        text='What did you personally do on your Atlas project? '
        first=question(host,text+'x'*(500-len(text)))
        await host.handle_user_question(first);await host.drain();basis=first['requestID']
        for index in range(12):
            follow=question(host,str(index)+'x'*(500-len(str(index))),basis=basis)
            admitted=await host.handle_user_question(follow);await host.drain()
            if not admitted:
                self.assertEqual(self.out[-1]['reasonCode'],'user_request_context_unavailable')
                break
            self.assertEqual(self.out[-1]['reasonCode'],'personal_context_missing')
            self.assertLessEqual(len(host.active.question.encode()),6000)
            self.assertLessEqual(len(host.user.bases),8)
            basis=follow['requestID']
        else:self.fail('semantic ancestry did not hit its bounded budget')
        self.assertEqual(self.prompts,[]);self.assertEqual(host.model_requests,0)

    async def test_audio_legacy_help_becomes_read_only_basis_for_a_fresh_typed_followup(self):
        from tests.test_session_host import speech,end,final
        from tests.test_composition_host import manual
        host=await self.prepared()
        await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,'Explain event loops.'))
        await host.drain();semantic=host.active.question;token=host.active.token
        current_projection=host.context.snapshot()
        legacy=manual(host,'Explain event loops.')
        self.assertTrue(await host.handle_manual_help(legacy));await host.drain()
        self.assertIn(legacy['requestID'],host.user.bases)
        self.assertEqual(host.active.question,semantic);self.assertEqual(host.active.token,token)
        self.assertEqual(host.active.projection.snapshot(),current_projection)
        follow=question(host,'How does that queue work?',basis=legacy['requestID'])
        self.assertTrue(await host.handle_user_question(follow));await host.drain()
        self.assertEqual(self.out[-1]['disposition'],'answer')
        self.assertEqual(self.out[-1]['question'],follow['question'])
        self.assertIn(semantic,self.prompts[-1]['semantic_request'])
        self.assertNotEqual(host.active.token,token)
        self.assertEqual(host.sequence,4)

    async def test_rejected_legacy_help_never_creates_basis_or_additional_model_work(self):
        from tests.test_session_host import speech,end,final
        from tests.test_composition_host import manual
        host=await self.prepared()
        await host.handle(speech(2));await host.handle(end(3));await host.handle(final(4,'Explain event loops.'))
        await host.drain();calls=len(self.prompts)
        stale=manual(host,'Explain event loops.',anchorEventSequence=host.sequence-1)
        self.assertFalse(await host.handle_manual_help(stale));await host.drain()
        self.assertNotIn(stale['requestID'],host.user.bases)
        mismatch=manual(host,'Invent a different question.')
        self.assertFalse(await host.handle_manual_help(mismatch));await host.drain()
        self.assertNotIn(mismatch['requestID'],host.user.bases)
        self.assertEqual(len(self.prompts),calls)

    async def test_evicted_basis_and_noncurrent_help_never_reactivate_old_permission(self):
        host=await self.prepared()
        first=question(host)
        await host.handle_user_question(first);await host.drain()
        for index in range(8):
            await host.handle_user_question(question(host,f'Explain event loop {index}.'));await host.drain()
        count=len(self.prompts)
        self.assertFalse(await host.handle_user_question(question(host,'Why?',basis=first['requestID'])))
        self.assertEqual(self.out[-1]['reasonCode'],'user_request_context_unavailable')
        self.assertEqual(len(self.prompts),count)
        self.assertFalse(await host.handle_user_question(question(host,basis=first['requestID'],intent='help_current')))
        self.assertEqual(len(self.prompts),count)

    async def test_retained_basis_keeps_current_microphone_gap_in_new_projection(self):
        host=await self.prepared();first=question(host,'Implement an LRU cache.')
        await host.handle_user_question(first);await host.drain()
        host.context.mark_gap('microphone_unavailable')
        await host.handle_user_question(question(host,'Which edge case matters?',basis=first['requestID']));await host.drain()
        self.assertIn('microphone_unavailable',self.prompts[-1]['conversation']['task']['context_gaps'])

    async def test_exact_replay_returns_original_without_new_work_and_changed_reuse_closes(self):
        host=await self.prepared();request=question(host)
        await host.handle_user_question(request);await host.drain();answer=copy.deepcopy(self.out[-1])
        await host.handle_user_question(request);await host.drain()
        self.assertEqual(self.out[-1],answer);self.assertEqual(len(self.prompts),1)
        with self.assertRaises(WireError):
            await host.handle_user_question({**request,'question':'Explain a different topic.'})
        self.assertFalse(host.live)

    async def test_retirement_before_original_request_prevents_any_inference(self):
        host=await self.prepared();request=question(host)
        host.handle_answer_retirement(retirement(request))
        await host.handle_user_question(request)
        receipt=cancel(host,request)
        host.handle_answer_cancel(receipt);await host.drain()
        self.assertEqual(self.prompts,[])
        self.assertEqual(host.model_requests,0)
        self.assertEqual(self.out[-1]['kind'],'answer_cancel_response')
        self.assertTrue(self.out[-1]['quiesced'])
        self.assertEqual(self.out[-1]['targetRequestID'],request['requestID'])

    async def test_retirement_releases_the_original_issued_screen_observation(self):
        from relay_spike.supplemental_context import SupplementalContextProvider
        from tests.test_visual_host_backend import screen_frames
        host=await self.prepared();request=question(host)
        class TrackingProvider(SupplementalContextProvider):
            retired_native=None
            def retire_current(self,native):
                self.retired_native=native
                return super().retire_current(native)
        provider=TrackingProvider(current_request=host.supplemental_request_current)
        host.supplemental_provider=provider
        text,images=screen_frames(request)
        self.assertTrue(provider.stage(json.dumps(text).encode()))
        for image in images:self.assertTrue(provider.stage_image(json.dumps(image).encode()))
        await host.handle_user_question(request)
        native=host.active.native
        self.assertIsNotNone(provider(native))
        host.handle_answer_retirement(retirement(request))
        self.assertIs(provider.retired_native,native)

    async def test_old_target_cannot_cancel_or_advance_a_newer_request(self):
        host=await self.prepared();first=question(host)
        await host.handle_user_question(first);await host.drain()
        host.handle_answer_retirement(retirement(first))
        newer=question(host,'Explain the newer topic.')
        await host.handle_user_question(newer);await host.drain()
        before=host.presentation
        self.assertFalse(host.handle_answer_cancel(cancel(host,first)))
        self.assertEqual(host.presentation,before)
        self.assertEqual(host.active.native['requestID'],newer['requestID'])

    async def test_fresh_cancel_of_denied_expired_original_acknowledges_without_inference(self):
        host=await self.prepared();request=question(host)
        host.handle_answer_retirement(retirement(request))
        request['emittedUptimeNanoseconds']=time.monotonic_ns()-2_100_000_000
        self.assertFalse(await host.handle_user_question(request))
        self.assertEqual(host.presentation,1)
        operation=cancel(host,request,presentationGeneration=request['presentationGeneration']+1)
        self.assertTrue(host.handle_answer_cancel(operation));await host.drain()
        self.assertEqual(host.presentation,operation['presentationGeneration'])
        self.assertEqual(self.prompts,[]);self.assertEqual(host.model_requests,0)
        self.assertEqual(self.out[-1]['requestID'],operation['requestID'])
        self.assertEqual(self.out[-1]['targetRequestID'],request['requestID'])
        self.assertEqual(self.out[-1]['reasonCode'],'already_finished')
        self.assertTrue(self.out[-1]['quiesced'])

    async def test_session_operation_budget_stays_bounded_without_model_calls(self):
        host=await self.prepared()
        for index in range(512):
            await host.handle_user_question(question(host,'What did you personally do on Atlas?'))
        self.assertEqual(len(host.used_requests),512)
        self.assertLessEqual(len(host.user.bases),8)
        self.assertLessEqual(len(host.user.replies),8)
        with self.assertRaises(WireError):
            await host.handle_user_question(question(host))
        self.assertFalse(host.live);self.assertEqual(self.prompts,[])

    async def test_cancel_receipt_waits_for_target_and_newest_pending_does_not_overlap(self):
        entered=asyncio.Event();release=asyncio.Event();calls=[]
        async def stubborn(prompt,instructions):
            calls.append(json.loads(prompt)['current_request']);entered.set()
            try:await release.wait()
            except asyncio.CancelledError:await release.wait()
            return card()
        host=await self.prepared(stubborn);first=question(host)
        await host.handle_user_question(first);await entered.wait()
        host.handle_answer_retirement(retirement(first))
        receipt=cancel(host,first);host.handle_answer_cancel(receipt)
        await asyncio.sleep(0)
        self.assertFalse(any(x.get('kind')=='answer_cancel_response' for x in self.out))
        await host.handle_user_question(question(host,'Explain a replacement.'))
        await host.handle_user_question(question(host,'Explain the newest replacement.'))
        await asyncio.sleep(0)
        self.assertEqual(len(calls),1)
        release.set();await host.drain()
        self.assertEqual(calls,['Explain event loops.','Explain the newest replacement.'])
        acknowledgements=[x for x in self.out if x.get('kind')=='answer_cancel_response']
        self.assertEqual(len(acknowledgements),1)
        self.assertEqual(acknowledgements[0]['requestID'],receipt['requestID'])
        self.assertTrue(acknowledgements[0]['quiesced'])
        self.assertEqual(self.out[-1].get('question','Explain the newest replacement.'),'Explain the newest replacement.')


class UserQuestionChildTests(unittest.TestCase):
    def test_actual_helper_accepts_typed_question_before_any_remote_final(self):
        native=start();stub=SessionHost();stub.session=(native['captureSessionID'],1);stub.sequence=1;stub.presentation=1
        request=question(stub)
        result=subprocess.run([sys.executable,'-m','relay_spike.session_host','--fixture-model'],
            input=encode_frame(native)+encode_frame(request),capture_output=True,timeout=8)
        self.assertEqual(result.returncode,0,result.stderr.decode()[:200])
        decoder=FrameDecoder();rows=decoder.feed(result.stdout);decoder.finish()
        # EOF retires the session; keep the existing reference path synchronous.
        # A child kept open is covered by the interactive transport regressions.
        self.assertTrue(any(row.get('requestID')==request['requestID'] for row in rows))
