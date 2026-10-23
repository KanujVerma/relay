"""One contextual coordinator and bounded stdio executable.

Default CLI is no-inference. --fixture-model runs the same engine with a local
synthetic transport. --oauth is an explicit existing-plan transport selection.
"""
from __future__ import annotations
import argparse
import asyncio
from dataclasses import dataclass
import json
import re
import sys
import uuid
from .asr_turn_adapter import SyntheticEOUBridge, CaptureContext, FinalizedASRObservation, classify_question_intent
from .conversation_context import ConversationContext
from .generated_answer import INSTRUCTIONS, GeneratedCard, CardDetail, CardError, make_prompt, parse_generated_card
from .panel_wire import decode_event, encode_frame, FrameDecoder, WireError, host_ms
from .question_turns import QuestionTurnMachine
from .reference_host import ReferencePermission, publish_reference, render_queued_card
from .publication_policy import PolicyInput


class CompositeEligibility:
    """Tentative evaluated syntax policy, not a confidence/speaker assertion."""
    version='contextual-intent-v1'
    def assess(self,event,*,has_current_question):
        if event.confidence is not None and event.confidence < .8: return 'unknown'
        intent=classify_question_intent(event.text,has_current_question=has_current_question)
        if intent=='unknown' and re.match(r"^(?:let(?:'s| us)|now |given |suppose |design |discuss |improve |optimi[sz]e )",event.text,re.I):
            intent='question'
        if intent=='unknown' and has_current_question and event.text.rstrip().endswith('?'):
            intent='follow_up'
        return intent


@dataclass(frozen=True)
class Request:
    native: dict
    token: object
    display_id: str
    question: str
    bundle: object


class SessionHost:
    def __init__(self,*,complete=None,emit=None,personal_provider=None,role='analytics',deadline=15):
        self.machine=QuestionTurnMachine()
        self.bridge=SyntheticEOUBridge(self.machine,eligibility_strategy=CompositeEligibility())
        self.permission=ReferencePermission(self.machine.turns)
        self.context=ConversationContext()
        self.complete,self.emit,self.provider,self.role=complete,emit or (lambda _:None),personal_provider,role
        self.deadline=deadline
        self.session=None;self.sequence=0;self.presentation=0;self.live=False
        self.activities={};self.used_requests=set();self.terminal=set();self.tasks=set();self.active=None
        self.model_requests=0

    def _invalidate(self):
        if self.active is not None:
            self.terminal.add(self.active.native['requestID'])
        self.active=None
        for task in self.tasks: task.cancel()

    def close(self):
        self._invalidate();self.permission.revoke();self.bridge.stop();self.live=False;self.context.clear();self.activities.clear()

    async def drain(self):
        while self.tasks:
            batch=tuple(self.tasks)
            await asyncio.gather(*batch,return_exceptions=True)
            self.tasks.difference_update(task for task in batch if task.done())

    def _current(self,request):
        return (self.live and self.active is request and request.native['requestID'] not in self.terminal
                and self.machine.turns.is_current(request.token) and self.permission.authorized()
                and (request.bundle is None or self.provider.validate_current(request.bundle)))

    def _result(self,request,disposition,reason,card=None,*,kind=None,provenance=None,pending=False):
        if not self._current(request): return False
        n=request.native
        value={key:n[key] for key in ('captureSessionID','sessionEpoch','presentationGeneration','requestID','eventSequence')}
        value.update(schemaVersion=1,resultRevision=1 if pending else 2,disposition=disposition,reasonCode=reason,
            pythonToken={'turnID':request.token.turn_id,'version':request.token.version,'generation':request.token.generation},
            displayID=request.display_id,question=request.question,answerID=uuid.uuid4().hex if disposition=='answer' else None,answerKind=kind,card=card,provenance=provenance)
        # Encode before sealing: overflow fails closed; no truncation of facts/code.
        encode_frame(value)
        if not pending: self.terminal.add(n['requestID'])
        self.emit(value)
        return True

    async def handle(self,raw):
        try: n,inner=decode_event(raw)
        except Exception:
            self.close();raise WireError('invalid_session_event') from None
        identity=(n['captureSessionID'].lower(),n['sessionEpoch'])
        kind,source,p=n['kind'],n['sourceCode'],n['payload']
        if kind=='session_started':
            if self.live or n['eventSequence']!=1 or identity==self.session:
                self.close();raise WireError('session_restart')
            self.close();self.session=identity;self.sequence=1;self.presentation=n['presentationGeneration'];self.live=True
            self.bridge.resume_after_host_authorization(CaptureContext('authorized',True));self.permission.grant()
            return
        if not self.live or identity!=self.session: return
        if n['eventSequence']<=self.sequence: return
        if n['eventSequence']!=self.sequence+1 or (n['presentationGeneration']<self.presentation and kind!='eou'):
            self.close();raise WireError('session_sequence_gap')
        self.sequence=n['eventSequence'];self.presentation=max(self.presentation,n['presentationGeneration'])
        if kind in ('stopping','stopped','source_unavailable','discontinuity'):
            self.close();return
        key=(source,n['streamGeneration'],p['activityID'])
        logical=f"activity-{source}-{n['streamGeneration']}-{p['activityID']}"
        if kind=='speech_started':
            if key in self.activities or len(self.activities)>=64: self.close();raise WireError('activity_replay')
            self.activities[key]={'start':p,'end':None,'used':False,'presentation':n['presentationGeneration']}
            if source==2:
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
            and p['event']['endHostTime']==end['endHostTime'] and p['event']['timebase']==start['timebase']==end['timebase'])
        if not complete or activity['used']:
            if source==2: self._invalidate();self.machine.cancel()
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
        observation=FinalizedASRObservation('remote',inner.stream_generation,logical,inner.revision,inner.start_ms,inner.end_ms,inner.received_ms,'final',inner.text or '',inner.finalized_ms,inner.confidence)
        result=self.bridge.ingest(observation,context=CaptureContext('authorized',True))
        if result.disposition!='ready' or result.token is None: return
        snap=result.question.snapshot
        self.context.observe('remote',inner.text,order=inner.start_ms)
        question=snap.prompt if snap.current_utterance!=snap.root_question else snap.current_utterance
        # UI question has its own strict bound; never rewrite semantic content.
        if len(question.encode())>500: return
        bundle=self.provider.retrieve(question,self.role) if self.provider else None
        req=Request(dict(n),result.token,uuid.uuid4().hex,question,bundle);self.active=req
        route=publish_reference(PolicyInput(question,self.role,'sql',source_channel='remote_final',question_status='final',host_authorized=True),turns=self.machine.turns,token=req.token,consent=self.permission,on_present=lambda _:None)
        if route.card:
            authorized=[]
            render_queued_card(route.card,turns=self.machine.turns,consent=self.permission,on_paint=authorized.append)
            if authorized:
                card=authorized[0]
                self._result(req,'answer','reviewed_full_question',{'lead':card.text,'points':['Filter rows with WHERE; filter grouped results with HAVING.'],'detail':None},kind='reviewed_reference',provenance={'referenceID':card.reference_id,'sourceRef':card.source_ref})
            return
        if route.reason_code=='reviewed_fixture_changed':
            self._result(req,'abstain','reference_unavailable');return
        if self._personal_question(question):
            self._personal(req);return
        if self.complete is None:
            self._result(req,'abstain','inference_disabled');return
        self._result(req,'pending','generating',pending=True)
        task=asyncio.create_task(self._generate(req,self.context.snapshot()))
        self.tasks.add(task);task.add_done_callback(self.tasks.discard)

    @staticmethod
    def _personal_question(question):
        return bool(re.search(r'\b(?:your (?:resume|résumé|project|experience|role|contribution|background)|you (?:built|worked|led|developed|contributed)|tell me about yourself|my (?:project|experience))\b',question,re.I))

    def _personal(self,req):
        bundle=req.bundle
        if bundle is None or not bundle.facts:
            self._result(req,'clarify','personal_context_missing');return
        facts=bundle.facts[:2]
        labels={'self':'Your contribution','team':'Team contribution','teammate':'Teammate contribution'}
        try:
            points=tuple(labels[f.actor]+': '+f.text for f in facts)
            from .generated_answer import bounded_text
            for point in points: bounded_text(point,180)
            card={'lead':'Use these confirmed details; add only what you can personally support.','points':list(points),'detail':None}
            self._result(req,'answer','grounded_personal',card,kind='generated_suggestion',provenance={'personal':True,'contextRevision':bundle.revision,'facts':[{'factID':f.fact_id,'sourceID':f.source_id,'actor':f.actor,'revision':f.revision} for f in facts],'checks':['host_exact_approved_facts']})
        except (CardError,WireError): self._result(req,'abstain','personal_detail_budget')

    async def _generate(self,req,dialogue):
        try:
            self.model_requests+=1
            async with asyncio.timeout(self.deadline):
                candidate=await self.complete(make_prompt(req.question,dialogue,req.bundle),INSTRUCTIONS)
            if not self._current(req): return
            code_required=bool(re.search(r'\b(?:write|show|provide)\b.{0,30}\b(?:code|function|query|sql)\b',req.question,re.I))
            card=parse_generated_card(candidate,code_required=code_required)
            self._result(req,'answer','format_checked',card.as_dict(),kind='generated_suggestion',provenance={'model':getattr(self.complete,'model','configured_oauth_model'),'checks':list(card.checks),'independentlyReviewed':False})
        except asyncio.CancelledError: return
        except TimeoutError: self._result(req,'error','answer_timeout')
        except Exception: self._result(req,'abstain','answer_unavailable')


async def run_stdio(args):
    loop=asyncio.get_running_loop()
    reader=asyncio.StreamReader(limit=32768)
    await loop.connect_read_pipe(lambda:asyncio.StreamReaderProtocol(reader),sys.stdin.buffer)
    transport,protocol=await loop.connect_write_pipe(asyncio.streams.FlowControlMixin,sys.stdout.buffer)
    writer=asyncio.StreamWriter(transport,protocol,None,loop)
    queue=asyncio.Queue(maxsize=32)
    def emit(value):
        try: queue.put_nowait(encode_frame(value))
        except asyncio.QueueFull: raise WireError('writer_overflow') from None
    complete=None
    if args.oauth:
        from .oauth_answer_stream import OAuthAnswerStream
        complete=OAuthAnswerStream(model=args.model).complete
    elif args.fixture_model:
        async def complete(prompt,instructions):
            obj=json.loads(prompt);task=obj['conversation']['task']
            return json.dumps({'lead':'Clarify the current requirements, then explain a small testable approach.','points':['Discuss '+task['stage']+' and the supplied constraints.'],'detail':None,'assumptions':['Unprovided code, schemas and history remain unknown.'],'coverage':['current_request'],'personal_fact_ids':[]})
    host=SessionHost(complete=complete,emit=emit)
    async def output():
        while True:
            value=await queue.get()
            try:
                writer.write(value)
                await asyncio.wait_for(writer.drain(),2)
            finally: queue.task_done()
    output_task=asyncio.create_task(output());decoder=FrameDecoder()
    try:
        while True:
            # A partial header/body has a deadline; idle readiness has no timeout.
            chunk=await (asyncio.wait_for(reader.read(4096),3) if decoder.buffer or decoder.length else reader.read(4096))
            if not chunk: decoder.finish();break
            for value in decoder.feed(chunk): await host.handle(value)
            if output_task.done(): await output_task
        await host.drain()
        await asyncio.wait_for(queue.join(),2)
    except Exception:
        return 2
    finally:
        host.close();output_task.cancel()
        await asyncio.gather(output_task,return_exceptions=True)
        writer.close()
    return 0


def main():
    parser=argparse.ArgumentParser(description='Relay contextual stdio helper; no capture or network by default.')
    mode=parser.add_mutually_exclusive_group();mode.add_argument('--oauth',action='store_true');mode.add_argument('--fixture-model',action='store_true')
    parser.add_argument('--model',default='gpt-6-luna')
    return asyncio.run(run_stdio(parser.parse_args()))
if __name__=='__main__': raise SystemExit(main())
