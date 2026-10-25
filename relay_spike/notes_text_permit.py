"""Privately issued, one-send notes text authority. Never serialize or log it."""
import asyncio
from hashlib import sha256
import weakref

class NotesPermitError(ValueError):pass
_ISSUER=object()
_ISSUED=weakref.WeakSet()

def _digest(value):return sha256(value.encode('utf-8')).digest()

def is_issued_notes_permit(value):return type(value) is NotesTextPermit and value in _ISSUED

class NotesTextPermit:
    __slots__=('_owner','_request','_stream','_provider','_config','_source','_prompt','_instructions',
               '_bearer','_used','_retired','_completed','__weakref__')
    def __init__(self,*,_issuer=None,owner=None,request=None,stream=None,prompt=None,instructions=None):
        if _issuer is not _ISSUER:raise NotesPermitError('notes_permit_unverified')
        self._owner=weakref.ref(owner);self._request=weakref.ref(request);self._stream=weakref.ref(stream)
        self._provider=stream._token_provider;self._config=(stream.model,stream.effort,stream._endpoint)
        self._source=request.source;self._prompt=_digest(prompt);self._instructions=_digest(instructions)
        self._bearer=None;self._used=False;self._retired=False;self._completed=False;_ISSUED.add(self)
    def __repr__(self):return 'NotesTextPermit(<private>)'
    def __reduce__(self):raise TypeError('notes_permit_private')
    def retire(self):
        self._retired=True;self._source=None;self._bearer=None;self._provider=None
    def _check(self,*,token,model,effort,endpoint):
        if self not in _ISSUED:raise NotesPermitError('notes_permit_unverified')
        owner,request,stream=self._owner(),self._request(),self._stream()
        if (self not in _ISSUED or self._retired or owner is None or request is None or stream is None
            or not owner._current(request) or request.source is not self._source
            or owner.host._worker_request is not request or owner.host._worker is not asyncio.current_task()
            or getattr(owner.host.complete,'__self__',None) is not stream
            or (model,effort,endpoint)!=self._config or (stream.model,stream.effort,stream._endpoint)!=self._config
            or stream._token_provider is not self._provider or stream._closed):
            raise NotesPermitError('notes_permit_retired')
        fingerprint=sha256(b'relay.notes.bearer.v1\n'+token.encode()).digest()
        if self._bearer is not None and fingerprint!=self._bearer:raise NotesPermitError('notes_grant_changed')
        return fingerprint
    def _begin_send(self,*,token,model,effort,endpoint,question,instructions):
        if self._used:raise NotesPermitError('notes_permit_spent')
        if (type(question) is not str or type(instructions) is not str or _digest(question)!=self._prompt
            or _digest(instructions)!=self._instructions):raise NotesPermitError('notes_input_changed')
        self._bearer=self._check(token=token,model=model,effort=effort,endpoint=endpoint);self._used=True
    def _mark_completed(self,*,token,model,effort,endpoint):
        self._check(token=token,model=model,effort=effort,endpoint=endpoint)
        if not self._used:raise NotesPermitError('notes_permit_unspent')
        self._completed=True

def issue_notes_text_permit(owner,request,stream,prompt,instructions):
    # Issuance is available only inside the actual request task created by the
    # admitted source/scope coordinator. Parsed DATA/UUIDs cannot recreate it.
    from .session_notes_host import HostNotesCoordinator,_Request,model_prompt,INSTRUCTIONS
    from .oauth_answer_stream import OAuthAnswerStream
    if (type(owner) is not HostNotesCoordinator or type(request) is not _Request
        or not isinstance(stream,OAuthAnswerStream) or not callable(stream._token_provider)
        or owner._request is not request or not owner._current(request) or request.source is None
        or owner.host._worker_request is not request or owner.host._worker is not asyncio.current_task()
        or getattr(owner.host.complete,'__self__',None) is not stream
        or prompt!=model_prompt(request.source) or instructions!=INSTRUCTIONS):
        raise NotesPermitError('notes_permit_unverified')
    return NotesTextPermit(_issuer=_ISSUER,owner=owner,request=request,stream=stream,prompt=prompt,instructions=instructions)
