"""One contextual coordinator and bounded stdio executable.

Default CLI is no-inference. --fixture-model runs the same engine with a local
synthetic transport. --oauth is an explicit existing-plan transport selection.
"""
from __future__ import annotations
import argparse
from collections import OrderedDict
from hashlib import sha256
import asyncio
from dataclasses import dataclass
import json
import re
import sys
import time
import uuid
from .asr_turn_adapter import SyntheticEOUBridge, CaptureContext, FinalizedASRObservation, classify_question_intent
from .conversation_context import ConversationContext
from .generated_answer import INSTRUCTIONS, GeneratedCard, CardDetail, CardError, make_prompt, parse_generated_card, requires_personal_evidence
from .panel_wire import decode_event, encode_frame, FrameDecoder, WireError, host_ms
from .question_turns import QuestionTurnMachine
from .reference_host import ReferencePermission, publish_reference, render_queued_card
from .publication_policy import PolicyInput


class CompositeEligibility:
    """Tentative evaluated syntax policy, not a confidence/speaker assertion."""
    version='contextual-intent-v1'
    def __init__(self,dialogue=None):self.dialogue=dialogue
    def assess(self,event,*,has_current_question):
        if event.confidence is not None and event.confidence < .8: return 'unknown'
        intent=classify_question_intent(event.text,has_current_question=has_current_question)
        prior=self.dialogue.snapshot().dialogue[:-1] if self.dialogue is not None else ()
        if intent=='unknown' and any(channel=='remote' for channel,_ in prior) and re.match(r'^(?:and if|and then|what about|how about|and what about|and how about)\b',event.text,re.I):
            intent='question'
        if intent=='unknown' and re.match(r"^(?:let(?:'s| us)|case study|now |given |suppose |design |discuss |improve |optimi[sz]e )",event.text,re.I):
            intent='question'
        if intent=='unknown' and re.search(r'(?:^|[.!?]\s+)(?:write|show|provide|implement|design|explain|describe|discuss|compare|optimi[sz]e)\b',event.text,re.I):
            intent='follow_up' if has_current_question else 'question'
        if intent=='unknown' and event.text.rstrip().endswith('?') and re.search(r'\b(?:what|how|why|can you|could you|would you)\b',event.text,re.I):
            intent='follow_up' if has_current_question else 'question'
        if intent=='unknown' and has_current_question and event.text.rstrip().endswith('?'):
            intent='follow_up'
        return intent


@dataclass(frozen=True)
class Request:
    native: dict
    token: object
    display_id: str
    question: str
    display_question: str
    bundle: object
    accepted_at: float
    origin: str = "remote_final"
    projection: object = None


class SessionHost:
    def __init__(self,*,complete=None,emit=None,personal_provider=None,supplemental_provider=None,role='analytics',deadline=15,visual_transport=None):
        self.context=ConversationContext()
        self.machine=QuestionTurnMachine()
        self.bridge=SyntheticEOUBridge(self.machine,eligibility_strategy=CompositeEligibility(self.context))
        self.permission=ReferencePermission(self.machine.turns)
        self.complete,self.emit,self.provider,self.role=complete,emit or (lambda _:None),personal_provider,role
        self.deadline=deadline
        self.supplemental_provider=supplemental_provider
        self._supplemental={}
        self.session=None;self.sequence=0;self.presentation=0;self.live=False;self.stopped_session=None;self.scope_kind=None
        self.activities={};self.used_requests=set();self.terminal=set();self.tasks=set();self.active=None
        self.model_requests=0
        self._worker=None;self._worker_request=None;self._pending_work=None
        self._microphone_available=False
        from .user_question import UserQuestionCoordinator
        self.user=UserQuestionCoordinator(self)
        from .visual_host import HostVisualInput
        self.visual=HostVisualInput(self,visual_transport)
        from .assistant_scope import AssistantScopeCoordinator
        self.assistant=AssistantScopeCoordinator(self)

    def _invalidate(self):
        self.user.invalidate_retired_help()
        self.visual.retire_request()
        if self.active is not None:
            self.terminal.add(self.active.native['requestID'])
        self.active=None
        self._pending_work=None
        self._supplemental.clear()
        for task in self.tasks:
            if not task.cancelling(): task.cancel()

    def _clear_context_provider(self):
        invalidate=getattr(self.supplemental_provider,'invalidate',None)
        if callable(invalidate):invalidate()

    def close(self,*,preserve_visual=False):
        if not preserve_visual:self.visual.disable(cancel_work=False)
        self.user.close()
        self._clear_context_provider()
        self._invalidate();self.permission.revoke();self.bridge.stop();self.live=False;self.scope_kind=None;self.context.clear();self.activities.clear()

    def _begin_assistant_scope(self,identity):
        self.visual.session_starting()
        self.close(preserve_visual=True)
        self.machine=QuestionTurnMachine()
        self.bridge=SyntheticEOUBridge(self.machine,eligibility_strategy=CompositeEligibility(self.context))
        self.bridge.stop()
        self.machine.resume()  # Explicit-question permission; bridge stays stopped.
        self.permission=ReferencePermission(self.machine.turns);self.permission.grant()
        self.session=identity;self.sequence=1;self.presentation=1;self.live=True;self.stopped_session=None
        self.scope_kind='assistant';self._microphone_available=False

    def handle_assistant_scope(self,raw):return self.assistant.handle(raw)

    async def drain(self):
        await self.visual.drain_probe()
        while self.tasks:
            batch=tuple(self.tasks)
            await asyncio.gather(*batch,return_exceptions=True)
            self.tasks.difference_update(task for task in batch if task.done())
        await self.user.drain()

    def _current(self,request):
        try:
            snippet=self._supplemental.get(request.native['requestID'])
            if snippet is not None:
                if not snippet.current(session_id=request.native['captureSessionID'],presentation_generation=request.native['presentationGeneration'],now_ns=time.monotonic_ns()): return False
                validator=getattr(self.supplemental_provider,'validate_current',None)
                if snippet.kind=='screen_text' and (not callable(validator) or not validator(snippet,request.native)): return False
            return (self.live and self.active is request and request.native['requestID'] not in self.terminal
                    and self.machine.turns.is_current(request.token) and self.permission.authorized()
                    and (request.bundle is None or self.provider.validate_current(request.bundle))
                    and self.visual.current_for(request))
        except Exception:
            return False

    def _result(self,request,disposition,reason,card=None,*,kind=None,provenance=None,pending=False):
        if not self._current(request): return False
        n=request.native
        value={key:n[key] for key in ('captureSessionID','sessionEpoch','presentationGeneration','requestID','eventSequence')}
        value.update(schemaVersion=1,resultRevision=1 if pending else 2,disposition=disposition,reasonCode=reason,
            pythonToken={'turnID':request.token.turn_id,'version':request.token.version,'generation':request.token.generation},
            displayID=request.display_id,question=request.display_question,answerID=uuid.uuid4().hex if disposition=='answer' else None,answerKind=kind,card=card,provenance=provenance)
        # Encode before sealing: overflow fails closed; no truncation of facts/code.
        encode_frame(value)
        if not pending: self.terminal.add(n['requestID'])
        self.user.note_result(value)
        self.emit(value)
        return True

    def _withhold_native(self,n,reason):
        # A classifier/blank terminal does not invent a semantic turn token.
        if not self.live or n['presentationGeneration']!=self.presentation or n['requestID'] in self.terminal: return
        value={key:n[key] for key in ('captureSessionID','sessionEpoch','presentationGeneration','requestID','eventSequence')}
        value.update(schemaVersion=1,resultRevision=2,disposition='abstain',reasonCode=reason,
                     pythonToken=None,displayID=None,question='',answerID=None,answerKind=None,card=None,provenance=None)
        encode_frame(value);self.terminal.add(n['requestID']);self.user.note_result(value);self.emit(value)

    async def handle(self,raw):
        try: n,inner=decode_event(raw)
        except Exception:
            self.close();raise WireError('invalid_session_event') from None
        identity=(n['captureSessionID'].lower(),n['sessionEpoch'])
        kind,source,p=n['kind'],n['sourceCode'],n['payload']
        if self.scope_kind=='assistant' or self.assistant.closing:return False
        if kind=='session_started':
            if self.live or n['eventSequence']!=1 or identity==self.session:
                self.close();raise WireError('session_restart')
            self.visual.session_starting()
            self.close(preserve_visual=True)
            # Fresh native UUID permits source counters to restart. Old worker
            # results still fail request-object/session identity checks.
            self.machine=QuestionTurnMachine()
            self.bridge=SyntheticEOUBridge(self.machine,eligibility_strategy=CompositeEligibility(self.context))
            self.permission=ReferencePermission(self.machine.turns)
            self.session=identity;self.sequence=1;self.presentation=n['presentationGeneration'];self.live=True;self.stopped_session=None
            self.scope_kind='capture'
            self._microphone_available=p['microphoneEnabled']
            self.bridge.resume_after_host_authorization(CaptureContext('authorized',True));self.permission.grant()
            return
        if not self.live:
            if identity==self.session and kind in ('stopping','stopped') and n['eventSequence']==self.sequence+1:
                self.sequence=n['eventSequence'];self.presentation=max(self.presentation,n['presentationGeneration'])
                if kind=='stopped':self.stopped_session=identity
            return
        if identity!=self.session:return
        if n['eventSequence']<=self.sequence: return
        if n['eventSequence']!=self.sequence+1 or (n['presentationGeneration']<self.presentation and kind!='eou' and not (source==1 and kind=='speech_ended')):
            self.close();raise WireError('session_sequence_gap')
        previous_presentation=self.presentation
        self.sequence=n['eventSequence'];self.presentation=max(self.presentation,n['presentationGeneration'])
        if source==1 and kind in ('source_unavailable','discontinuity'):
            self.user.invalidate_retired_help()
            self._microphone_available=False
            self.activities={k:v for k,v in self.activities.items() if k[0]!=1}
            self.context.mark_gap('microphone_unavailable' if kind=='source_unavailable' else 'microphone_discontinuity')
            return
        if source==1 and not self._microphone_available: return
        if kind in ('stopping','stopped','source_unavailable','discontinuity'):
            self.close();return
        key=(source,n['streamGeneration'],p['activityID'])
        logical=f"activity-{source}-{n['streamGeneration']}-{p['activityID']}"
        if kind=='speech_started':
            if source==2 and n['presentationGeneration']<=previous_presentation:
                self.close();raise WireError('activity_fence')
            if len(self.activities)>=64:
                retired=next((k for k,v in self.activities.items() if v['used']),None)
                if retired is not None: del self.activities[retired]
            if key in self.activities or len(self.activities)>=64: self.close();raise WireError('activity_replay')
            self.activities[key]={'start':p,'end':None,'used':False,'presentation':n['presentationGeneration']}
            if source==2:
                self._clear_context_provider()
                self._invalidate()
                start=host_ms(p['startHostTime'],p['timebase'])
                self.machine.remote_speech_started(stream_generation=n['streamGeneration'],segment_id=logical,start_ms=start,end_ms=start)
            return
        activity=self.activities.get(key)
        if activity is None: self.close();raise WireError('unassociated_activity')
        if kind=='speech_ended':
            if activity['end'] is not None: self.close();raise WireError('activity_replay')
            activity['end']=p;return
        end=activity['end'];start=activity['start']
        complete=(end is not None and p['activityClosed'] and p['lastInputSequence']==p['lastSpeechInputSequence']==end['lastSpeechInputSequence']
            and p['firstInputSequence']<=p['lastInputSequence'] and p['event']['startHostTime']==start['startHostTime']
            and p['event']['endHostTime']==end['endHostTime'] and p['event']['timebase']==start['timebase']==end['timebase']
            and n['presentationGeneration']==activity['presentation']
            and n['emittedUptimeNanoseconds']>=p['event']['receivedUptimeNanoseconds'])
        if activity['used']: return
        if not complete:
            if source==2 and n['presentationGeneration']<self.presentation: return
            if source==2:
                self._invalidate();self.machine.cancel();self._withhold_native(n,'question_unavailable')
            return
        activity['used']=True
        if source==2 and n['presentationGeneration']<self.presentation:
            # A validated final from an older closed activity is history only.
            # Its original lease cannot authorize a request or mutate turn state.
            if inner.text: self.context.observe('remote',inner.text,order=inner.start_ms)
            return
        if source==1:
            if inner.text: self.context.observe('microphone',inner.text,order=inner.start_ms)
            return
        request_id=n['requestID'].lower()
        if request_id in self.used_requests: return
        if len(self.used_requests)>=512: self.close();raise WireError('request_ledger_budget')
        self.used_requests.add(request_id)
        if inner.text: self.context.observe('remote',inner.text,order=inner.start_ms)
        if self.user.is_retired(n):return
        observation=FinalizedASRObservation('remote',inner.stream_generation,logical,inner.revision,inner.start_ms,inner.end_ms,inner.received_ms,'final',inner.text or '',inner.finalized_ms,inner.confidence)
        result=self.bridge.ingest(observation,context=CaptureContext('authorized',True))
        if result.disposition!='ready' or result.token is None:
            if result.disposition!='ignored': self._withhold_native(n,'blank_question' if not inner.text else 'no_question')
            return
        snap=result.question.snapshot
        question=snap.prompt if snap.current_utterance!=snap.root_question else snap.current_utterance
        # UI question has its own strict bound; never rewrite semantic content.
        display_question=inner.text
        if len(display_question.encode())>500:
            self._withhold_native(n,'question_overflow');return
        try: bundle=self.provider.retrieve(question,self.role) if self.provider else None
        except ValueError: bundle=None
        projection=self.context.fork()
        req=Request(dict(n),result.token,uuid.uuid4().hex,question,display_question,bundle,time.monotonic(),projection=projection);self.active=req
        self.user.note_request(req,projection)
        self._route(req)

    def supplemental_request_current(self,native):
        # Provider callbacks require the actual accepted Request.native object.
        # Keep this base check independent of supplemental validators (no recursion).
        req=self.active
        return bool(req is not None and req.native is native and self.live
            and (native['captureSessionID'].lower(),native['sessionEpoch'])==self.session
            and native['presentationGeneration']==self.presentation
            and native['requestID'] not in self.terminal and self.machine.turns.is_current(req.token)
            and self.permission.authorized() and (req.bundle is None or self.provider.validate_current(req.bundle)))

    def handle_visual_control(self,value):
        self.visual.handle_control(value)

    def handle_supplemental_retirement(self,value):
        from .panel_wire import exact,uuid_string,u64
        exact(value,('schemaVersion','kind','captureSessionID','sessionEpoch','presentationGeneration','requestID','reasonCode'))
        if (type(value['schemaVersion']) is not int or value['schemaVersion']!=1
            or value['kind']!='supplemental_context_retired' or value['reasonCode']!='context_changed'):
            raise WireError('supplemental_retirement')
        uuid_string(value['captureSessionID']);uuid_string(value['requestID'])
        u64(value['sessionEpoch'],True);u64(value['presentationGeneration'],True)
        provider=self.supplemental_provider
        if provider is None:return
        retire_staged=getattr(provider,'retire_staged',None)
        if callable(retire_staged):retire_staged(value)
        current=self.active
        if (current is not None and current.native['requestID'] in self._supplemental
            and uuid_string(value['captureSessionID'])==uuid_string(current.native['captureSessionID'])
            and uuid_string(value['requestID'])==uuid_string(current.native['requestID'])
            and value['sessionEpoch']==current.native['sessionEpoch']
            and value['presentationGeneration']==current.native['presentationGeneration']):
            retire_current=getattr(provider,'retire_current',None)
            if callable(retire_current):retire_current(current.native)

    def _admit_supplemental(self,req):
        if self.supplemental_provider is None or not self.supplemental_request_current(req.native):return None
        from .conversation_context import ContextSnippet
        value=self.supplemental_provider(req.native)
        if not isinstance(value,ContextSnippet) or not value.current(session_id=req.native['captureSessionID'],presentation_generation=req.native['presentationGeneration'],now_ns=time.monotonic_ns()):return None
        validator=getattr(self.supplemental_provider,'validate_current',None)
        if value.kind=='screen_text' and (not callable(validator) or not validator(value,req.native)):return None
        self._supplemental[req.native['requestID']]=value
        return value

    def _route(self,req):
        if self._personal_question(req.question):
            discard=getattr(self.supplemental_provider,'discard_staged',None)
            if callable(discard):discard()
            self._personal(req);return
        supplemental=self._admit_supplemental(req)
        if supplemental is None:
            route=publish_reference(PolicyInput(req.question,self.role,'sql',source_channel=req.origin,question_status='final',host_authorized=True),turns=self.machine.turns,token=req.token,consent=self.permission,on_present=lambda _:None)
            if route.card:
                authorized=[]
                render_queued_card(route.card,turns=self.machine.turns,consent=self.permission,on_paint=authorized.append)
                if authorized:
                    card=authorized[0]
                    self._result(req,'answer','reviewed_full_question',{'lead':card.text,'points':['Filter rows with WHERE; filter grouped results with HAVING.'],'detail':None},kind='reviewed_reference',provenance={'referenceID':card.reference_id,'sourceRef':card.source_ref})
                return
            if route.reason_code=='reviewed_fixture_changed':
                self._result(req,'abstain','reference_unavailable');return
        dialogue=(req.projection or self.context).snapshot()
        if dialogue.task.state!='ready':
            self._result(req,'clarify','task_context_'+('overflow' if dialogue.task.state=='overflow' else 'unresolved'));return
        if self.complete is None:
            self._result(req,'abstain','inference_disabled');return
        self._result(req,'pending','generating_with_task_context' if supplemental is not None else 'generating',pending=True)
        self._queue_work(req,dialogue)

    async def handle_user_question(self,raw):
        return await self.user.question(raw)

    def handle_answer_retirement(self,raw):
        self.user.retire(raw)

    def handle_answer_cancel(self,raw):
        return self.user.cancel(raw)

    async def handle_manual_help(self,raw):
        from .manual_help import decode_manual_help
        try:n=decode_manual_help(raw)
        except Exception:
            self.close();raise WireError('invalid_manual_request') from None
        identity=(n['captureSessionID'].lower(),n['sessionEpoch'])
        request_id=n['requestID'].lower()
        if (not self.live or identity!=self.session or n['anchorEventSequence']!=self.sequence
            or n['presentationGeneration']<=self.presentation or request_id in self.used_requests
            or not 0<=time.monotonic_ns()-n['emittedUptimeNanoseconds']<=2_000_000_000):return False
        if len(self.used_requests)>=512:self.close();raise WireError('request_ledger_budget')
        previous=self.active;snapshot=self.machine.current()
        eligible=(previous is not None and snapshot is not None and snapshot.token==previous.token
            and n['question']==previous.display_question and self.machine.turns.is_current(previous.token)
            and self.permission.authorized())
        self.presentation=n['presentationGeneration'];self.used_requests.add(request_id);self._invalidate()
        if not eligible:
            self._withhold_native(n,'manual_context_unavailable');return False
        try:bundle=self.provider.retrieve(previous.question,self.role) if self.provider else None
        except ValueError:bundle=None
        projection=self.context.fork()
        req=Request(n,previous.token,uuid.uuid4().hex,previous.question,previous.display_question,bundle,time.monotonic(),projection=projection)
        self.active=req;self.user.note_request(req,projection);self._route(req);return True

    def _queue_work(self,req,dialogue):
        self._pending_work=(req,dialogue)
        if self._worker is not None and not self._worker.done(): return
        self._start_pending()

    def _start_pending(self):
        work,self._pending_work=self._pending_work,None
        if work is None or not self._current(work[0]): return
        task=asyncio.create_task(self._generate(*work));self._worker=task;self._worker_request=work[0]
        self.tasks.add(task)
        def finished(done):
            if not done.cancelled(): done.exception()  # consume; never log provider/private errors
            self.tasks.discard(done)
            if self._worker is done:
                self._worker=None;self._worker_request=None
                self._start_pending()
        task.add_done_callback(finished)

    def supplemental_context_changed(self):
        self._invalidate()

    def personal_context_changed(self):
        # Called before native-selected review/revocation changes the ledger.
        self._invalidate();self.user.replies.clear()

    @staticmethod
    def _personal_question(question):
        return requires_personal_evidence(question)

    def _personal(self,req):
        bundle=req.bundle
        if bundle is None or not bundle.facts or bundle.status=='conflict':
            self._result(req,'clarify','personal_context_missing');return
        try:
            from .resume_personal import render_personal
            facts,card=render_personal(bundle)
            self._result(req,'answer','grounded_personal',card,kind='generated_suggestion',provenance={'personal':True,'contextRevision':bundle.revision,'facts':[{'factID':f.fact_id,'sourceID':f.source_id,'actor':f.actor,'revision':f.revision} for f in facts],'checks':['host_exact_approved_facts']})
        except (CardError,WireError): self._result(req,'abstain','personal_detail_budget')

    async def _generate(self,req,dialogue):
        try:
            self.model_requests+=1
            async with asyncio.timeout(max(0,self.deadline-(time.monotonic()-req.accepted_at))):
                # A just-started session may have cancelled an idle probe. The
                # same stream must actually quiesce before the answer uses it.
                await self.visual.drain_probe()
                supplemental=self._supplemental.get(req.native['requestID'])
                permit=self.visual.prepare(req,supplemental)
                prompt=make_prompt(req.question,dialogue,req.bundle,supplemental=supplemental,current_utterance=req.display_question)
                candidate=await self.complete(prompt,INSTRUCTIONS,visual_attachment=permit) if permit is not None else await self.complete(prompt,INSTRUCTIONS)
                if not await self.visual.validate_publication(req,permit=permit):
                    self.visual.failed_request(req);self._result(req,'abstain','answer_unavailable');return
            if not self._current(req): return
            code_required=bool(re.search(r'\b(?:write|show|provide)\b.{0,30}\b(?:code|function|query|sql)\b',req.display_question,re.I))
            card=parse_generated_card(candidate,code_required=code_required)
            provenance={'model':getattr(getattr(self.complete,'__self__',None),'model','injected_fixture_transport'),'checks':list(card.checks),'independentlyReviewed':False}
            if supplemental is not None:
                provenance['taskContext']={'provenance':supplemental.provenance,'source':supplemental.source,'capturedUptimeNanoseconds':supplemental.captured_uptime_ns}
                digest=self.visual.used_image_digest(req)
                if digest is not None:provenance['taskContext']['imageDigest']=digest
            self._result(req,'answer','format_checked',card.as_dict(),kind='generated_suggestion',provenance=provenance)
        except asyncio.CancelledError:
            self.visual.failed_request(req);return
        except TimeoutError:
            self.visual.failed_request(req);self._result(req,'error','answer_timeout')
        except Exception:
            self.visual.failed_request(req);self._result(req,'abstain','answer_unavailable')


async def run_stdio(args,*,oauth_stream=None):
    loop=asyncio.get_running_loop()
    reader=asyncio.StreamReader(limit=32768)
    await loop.connect_read_pipe(lambda:asyncio.StreamReaderProtocol(reader),sys.stdin.buffer)
    transport,protocol=await loop.connect_write_pipe(asyncio.streams.FlowControlMixin,sys.stdout.buffer)
    writer=asyncio.StreamWriter(transport,protocol,None,loop)
    queue=asyncio.Queue(maxsize=32)
    queued_bytes=0
    def emit(value):
        nonlocal queued_bytes
        frame=encode_frame(value)
        if queued_bytes+len(frame)>262144: raise WireError('writer_overflow')
        try:
            queue.put_nowait(frame)
            queued_bytes+=len(frame)
        except asyncio.QueueFull: raise WireError('writer_overflow') from None
    complete=None;visual_transport=None
    if args.oauth:
        from .oauth_answer_stream import OAuthAnswerStream
        visual_transport=oauth_stream or OAuthAnswerStream(model=args.model)
        complete=visual_transport.complete
    elif args.fixture_model:
        async def complete(prompt,instructions):
            obj=json.loads(prompt);task=obj['conversation']['task']
            if task['kind']=='case_study':
                return json.dumps({'lead':'Start with the users, workflow, and problem that needs to improve.',
                    'points':['Clarify the information needed and where the current workflow fails.',
                        'Choose the smallest useful flow and define a success measure.'],
                    'detail':None,'assumptions':['This is injected synthetic output for offline transport checks.'],
                    'coverage':['current_request'],'personal_fact_ids':[]})
            code=bool(re.search(r'\b(?:write|show|provide)\b.{0,30}\b(?:code|function|query|sql)\b',obj['current_request'],re.I))
            return json.dumps({'lead':'Check the input contract, then explain the invariant before implementing.','points':['Discuss '+task['stage']+' and the supplied constraints.','Check empty input and boundary cases.'],'detail':{'kind':'code','language':'python','text':'def first_or_none(items):\n    return items[0] if items else None\n'} if code else None,'assumptions':['This is injected synthetic output for offline transport checks.'],'coverage':['current_request'],'personal_fact_ids':[]})
    from .profile_bridge import ProfileBridge
    host=SessionHost(complete=complete,emit=emit,role=args.role,visual_transport=visual_transport)
    profile=ProfileBridge(on_change=host.personal_context_changed)
    host.provider=profile
    from .supplemental_context import SupplementalContextProvider
    supplemental=SupplementalContextProvider(current_request=host.supplemental_request_current,on_invalidation=host.supplemental_context_changed)
    host.supplemental_provider=supplemental
    async def output():
        nonlocal queued_bytes
        while True:
            value=await queue.get()
            try:
                writer.write(value)
                await asyncio.wait_for(writer.drain(),2)
            finally:
                queued_bytes-=len(value)
                queue.task_done()
    output_task=asyncio.create_task(output());decoder=FrameDecoder()
    profile_seen={};profile_replies=OrderedDict();quiescence_seen=set()
    try:
        while True:
            # A partial header/body has a deadline; idle readiness has no timeout.
            chunk=await (asyncio.wait_for(reader.read(4096),3) if decoder.buffer or decoder.length else reader.read(4096))
            if not chunk: decoder.finish();host.close();break
            for value in decoder.feed(chunk):
                if isinstance(value,dict) and value.get('kind')=='assistant_scope_request':
                    host.handle_assistant_scope(value)
                elif isinstance(value,dict) and value.get('kind')=='visual_input_request':
                    host.handle_visual_control(value)
                elif isinstance(value,dict) and value.get('kind')=='profile_request':
                    from .panel_wire import exact,uuid_string
                    exact(value,('schemaVersion','kind','requestID','payload'))
                    if value['schemaVersion']!=1: raise WireError('profile_schema')
                    identity=uuid_string(value['requestID'])
                    fingerprint=sha256(json.dumps(value['payload'],sort_keys=True,separators=(',',':')).encode()).digest()
                    if identity in profile_seen:
                        response=profile_replies.get(identity) if profile_seen[identity]==fingerprint else None
                        response=response or {'ok':False,'reasonCode':'profile_replay'}
                    else:
                        if len(profile_seen)>=8192: raise WireError('profile_request_budget')
                        profile_seen[identity]=fingerprint
                        try: response=profile.handle(value['payload'])
                        except ValueError: response={'ok':False,'reasonCode':'profile_unavailable'}
                        profile_replies[identity]=response
                        while len(profile_replies)>8: profile_replies.popitem(last=False)
                    emit({'schemaVersion':1,'kind':'profile_response','requestID':value['requestID'],'payload':response})
                elif isinstance(value,dict) and value.get('kind') in ('screen_context','selected_text_context'):
                    raw=json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode()
                    if not supplemental.stage(raw):raise WireError('supplemental_frame')
                elif isinstance(value,dict) and value.get('kind') in ('screen_image_begin','screen_image_chunk','screen_image_end'):
                    raw=json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode()
                    if not supplemental.stage_image(raw):raise WireError('supplemental_image')
                elif isinstance(value,dict) and value.get('kind')=='session_quiescence_request':
                    from .panel_wire import exact,uuid_string,u64
                    exact(value,('schemaVersion','kind','requestID','captureSessionID','sessionEpoch'))
                    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1:raise WireError('quiescence_schema')
                    uuid_string(value['requestID']);identity=(uuid_string(value['captureSessionID']),u64(value['sessionEpoch'],True))
                    if host.live or identity!=host.stopped_session:raise WireError('quiescence_session')
                    if value['requestID'] in quiescence_seen or len(quiescence_seen)>=512:raise WireError('quiescence_replay')
                    quiescence_seen.add(value['requestID'])
                    await host.drain()
                    emit({'schemaVersion':1,'kind':'session_quiescence_response','requestID':value['requestID'],
                        'captureSessionID':value['captureSessionID'],'sessionEpoch':value['sessionEpoch'],'quiesced':True})
                elif isinstance(value,dict) and value.get('kind')=='user_question_request':
                    await host.handle_user_question(value)
                elif isinstance(value,dict) and value.get('kind')=='answer_request_retired':
                    host.handle_answer_retirement(value)
                elif isinstance(value,dict) and value.get('kind')=='answer_cancel_request':
                    host.handle_answer_cancel(value)
                elif isinstance(value,dict) and value.get('kind')=='manual_help_request':
                    await host.handle_manual_help(value)
                elif isinstance(value,dict) and value.get('kind')=='supplemental_context_retired':
                    host.handle_supplemental_retirement(value)
                else: await host.handle(value)
            if output_task.done(): await output_task
        await host.drain()
        await host.assistant.drain()
        await asyncio.wait_for(queue.join(),2)
    except Exception:
        return 2
    finally:
        host.close();profile.close();output_task.cancel()
        await asyncio.gather(output_task,return_exceptions=True)
        writer.close()
    return 0


def main():
    parser=argparse.ArgumentParser(description='Relay contextual stdio helper; no capture or network by default.')
    mode=parser.add_mutually_exclusive_group();mode.add_argument('--oauth',action='store_true');mode.add_argument('--fixture-model',action='store_true')
    parser.add_argument('--model',default='gpt-6-luna')
    parser.add_argument('--role',default='analytics')
    return asyncio.run(run_stdio(parser.parse_args()))
if __name__=='__main__': raise SystemExit(main())
