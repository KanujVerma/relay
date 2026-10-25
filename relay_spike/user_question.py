"""Explicit user actions and deny-only fences, never audio observations."""
from collections import OrderedDict
from dataclasses import dataclass
from hashlib import sha256
import asyncio
import json
import time
import uuid
from .panel_wire import exact, u64, uuid_string, WireError
from .generated_answer import bounded_text, CardError

_IDENTITY=('captureSessionID','sessionEpoch','presentationGeneration','requestID')
_MAX_SEMANTIC_BYTES=6000  # Same bounded text domain as the existing dialogue ring.

def _common(value, fields, kind):
    exact(value, fields)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!=kind:
        raise WireError('user_schema')
    for key in ('captureSessionID','requestID'):uuid_string(value[key])
    for key in ('sessionEpoch','presentationGeneration'):u64(value[key],True)

def decode_user_question(value):
    _common(value,('schemaVersion','kind',*_IDENTITY,'anchorEventSequence','emittedUptimeNanoseconds',
        'intent','question','baseRequestID'),'user_question_request')
    u64(value['anchorEventSequence'],True);u64(value['emittedUptimeNanoseconds'])
    basis=value['baseRequestID']
    if basis is not None:uuid_string(basis)
    if value['intent']=='ask':
        try:bounded_text(value['question'],500)
        except (CardError,TypeError,UnicodeError):raise WireError('user_question') from None
    elif value['intent']=='help_current':
        if value['question'] is not None or basis is None:raise WireError('user_basis')
    else:raise WireError('user_intent')
    return {**value,'eventSequence':value['anchorEventSequence']}

def decode_retirement(value):
    _common(value,('schemaVersion','kind',*_IDENTITY,'reasonCode'),'answer_request_retired')
    if value['reasonCode']!='request_retired':raise WireError('user_retirement')
    return dict(value)

def decode_cancel(value):
    _common(value,('schemaVersion','kind',*_IDENTITY,'targetRequestID','anchorEventSequence',
        'emittedUptimeNanoseconds'),'answer_cancel_request')
    uuid_string(value['targetRequestID']);u64(value['anchorEventSequence'],True);u64(value['emittedUptimeNanoseconds'])
    return dict(value)

@dataclass(frozen=True)
class _Basis:
    session: tuple
    display_question: str
    semantic_question: str
    semantic_context: tuple[str, ...]
    projection: object

class UserQuestionCoordinator:
    """Bounded host-owned context, replay and actual target-task receipts."""
    def __init__(self,host):
        self.host=host;self.bases=OrderedDict();self.seen={};self.replies=OrderedDict()
        self.retired={};self.cancel_tasks=set();self._retired_current=None

    @staticmethod
    def key(value):return (value['captureSessionID'].lower(),value['sessionEpoch'],value['presentationGeneration'],value['requestID'].lower())

    def close(self):
        self.bases.clear();self.seen.clear();self.replies.clear();self.retired.clear()
        self.invalidate_retired_help()

    def invalidate_retired_help(self):self._retired_current=None

    def note_request(self,request,projection,*,semantic_context=None):
        self.invalidate_retired_help()
        context=(request.question,) if semantic_context is None else semantic_context
        self.bases[request.native['requestID'].lower()]=_Basis(self.host.session,request.display_question,request.question,context,projection.fork())
        while len(self.bases)>8:self.bases.popitem(last=False)

    def note_result(self,value):
        identity=value['requestID'].lower()
        if identity not in self.seen:return
        self.replies[identity]=dict(value);self.replies.move_to_end(identity)
        while len(self.replies)>8:self.replies.popitem(last=False)

    def _replay(self,value):
        identity=value['requestID'].lower()
        fingerprint=sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).digest()
        if identity in self.seen:
            if self.seen[identity]!=fingerprint:
                self.host.close();raise WireError('user_request_reuse')
            if identity in self.replies:self.host.emit(dict(self.replies[identity]))
            return True
        return False

    def _help_after_retirement(self,n):
        h=self.host;retired=self._retired_current;current=h.machine.turns.current()
        if retired is None or h.active is not None or current is None:return False
        key,semantic_generation=retired
        return (key[:2]==h.session and key[3]==n['baseRequestID'].lower()
            and key[2]==h.presentation and n['presentationGeneration']==key[2]+1
            and current.generation==semantic_generation and h.permission.authorized())

    def _admit(self,value):
        h=self.host
        return (h.live and (value['captureSessionID'].lower(),value['sessionEpoch'])==h.session
            and value['anchorEventSequence']==h.sequence and value['presentationGeneration']>h.presentation
            and 0<=time.monotonic_ns()-value['emittedUptimeNanoseconds']<=2_000_000_000)

    def _spend(self,value):
        h=self.host;identity=value['requestID'].lower()
        if identity in h.used_requests or len(h.used_requests)>=512:
            h.close();raise WireError('request_ledger_budget')
        h.used_requests.add(identity)
        self.seen[identity]=sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).digest()
        self.invalidate_retired_help()

    async def question(self,raw,*,received_ns=None):
        from .answer_timing import HelperRequestTiming
        timing=HelperRequestTiming(time.monotonic_ns() if received_ns is None else received_ns)
        try:n=decode_user_question(raw)
        except Exception:self.host.close();raise WireError('invalid_user_request') from None
        if self._replay(n):return False
        if not self._admit(n):return False
        h=self.host;previous=h.active
        basis=self.bases.get((n['baseRequestID'] or '').lower())
        valid=basis is not None and basis.session==h.session
        if n['intent']=='help_current':
            live_current=(previous is not None and previous.native['requestID'].lower()==n['baseRequestID'].lower()
                and h.machine.turns.is_current(previous.token) and h.permission.authorized())
            valid=valid and (live_current or self._help_after_retirement(n))
        self._spend(n);h.presentation=n['presentationGeneration'];h._invalidate()
        if self.key(n) in self.retired:return False
        if n['baseRequestID'] is not None and not valid:
            h._withhold_native(n,'user_request_context_unavailable',timing=timing);return False
        text=n['question'] if n['intent']=='ask' else basis.display_question
        if n['intent']=='help_current':
            semantic,semantic_context=basis.semantic_question,basis.semantic_context
        else:
            # Preserve original supplied questions, never recursively embed an
            # earlier rendered semantic wrapper or silently lose a personal
            # ancestor. The existing unavailable-basis result recovers drafts.
            semantic_context=(*(basis.semantic_context if valid else ()),text)
            semantic=text if not valid else ('Current user question (verbatim): '+text
                +'\nChosen earlier questions (context only):\n'+'\n'.join(semantic_context[:-1]))
        if len(semantic.encode())>_MAX_SEMANTIC_BYTES:
            h._withhold_native(n,'user_request_context_unavailable',timing=timing);return False
        projection=(h.context.project_user_request(text,basis=basis.projection if valid else None)
            if n['intent']=='ask' else basis.projection.fork())
        token=h.machine.begin_explicit_request(n['requestID'])
        if token is None:return False
        try:bundle=h.provider.retrieve(semantic,h.role) if h.provider else None
        except ValueError:bundle=None
        from .session_host import Request
        req=Request(n,token,uuid.uuid4().hex,semantic,text,bundle,time.monotonic(),'explicit_user',projection,timing=timing)
        h.active=req;self.note_request(req,projection,semantic_context=semantic_context);h._route(req);return True

    def retire(self,raw):
        n=decode_retirement(raw);h=self.host
        if not h.live or (n['captureSessionID'].lower(),n['sessionEpoch'])!=h.session:return
        key=self.key(n)
        if key in self.retired:return
        if len(self.retired)>=512:h.close();raise WireError('retirement_budget')
        owner=h._worker if h._worker_request is not None and self.key(h._worker_request.native)==key else None
        self.retired[key]=owner
        h.response_preferences.retire_native(n)
        h.learning_memory.retire_native(n)
        if h.active is not None and self.key(h.active.native)==key:
            original=h.active.native
            token=h.active.token
            eligible=h.machine.turns.is_current(token) and h.permission.authorized()
            h._invalidate()
            retire_current=getattr(h.supplemental_provider,'retire_current',None)
            if callable(retire_current):retire_current(original)
            # Only the exact formerly-current request may bridge deny-first
            # Help. Keep a generation fence, never an old publication token.
            if eligible and h.machine.turns.is_current(token) and h.permission.authorized():
                self._retired_current=(key,token.generation)
        elif owner is not None and not owner.done() and not owner.cancelling():owner.cancel()
        staged=getattr(h.supplemental_provider,'retire_staged',None)
        if callable(staged):staged(n)

    def cancel(self,raw):
        n=decode_cancel(raw)
        if self._replay(n) or not self._admit(n):return False
        h=self.host;target=n['targetRequestID'].lower()
        keys=[key for key in self.retired if key[3]==target]
        active=h.active
        current_target=active is not None and active.native['requestID'].lower()==target
        target_generation=active.native['presentationGeneration'] if current_target else (keys[-1][2] if keys else None)
        # The original denied frame may expire before admission, leaving this
        # helper behind its actual native target. A fresh cancellation can
        # acknowledge that known target, but never cross a newer presentation.
        if (target_generation is None or target_generation<h.presentation
            or n['presentationGeneration']!=target_generation+1):return False
        if current_target:
            self.retire({**{k:active.native[k] for k in _IDENTITY},'schemaVersion':1,
                'kind':'answer_request_retired','reasonCode':'request_retired'})
            keys=[self.key(active.native)]
        if not keys:return False
        self._spend(n);h.presentation=n['presentationGeneration']
        owner=self.retired[keys[-1]]
        pending=owner is not None and not owner.done()
        session=h.session
        async def finish():
            if owner is not None:await asyncio.gather(asyncio.shield(owner),return_exceptions=True)
            # A receipt acknowledges the captured task, not answer permission.
            # Scope close still owes it before that scope can actually drain.
            if h.session!=session:return
            reply={k:n[k] for k in ('captureSessionID','sessionEpoch','presentationGeneration','requestID','targetRequestID')}
            reply.update(schemaVersion=1,kind='answer_cancel_response',resultRevision=2,
                reasonCode='request_cancelled' if pending else 'already_finished',quiesced=True)
            self.note_result(reply);h.emit(reply)
        task=asyncio.create_task(finish());self.cancel_tasks.add(task)
        task.add_done_callback(self.cancel_tasks.discard)
        return True

    def is_retired(self,native):return self.key(native) in self.retired

    async def drain(self):
        while self.cancel_tasks:await asyncio.gather(*tuple(self.cancel_tasks),return_exceptions=True)
