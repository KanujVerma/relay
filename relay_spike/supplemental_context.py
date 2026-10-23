"""One untrusted staged context, admitted only for an actual current host request.

No capture, AX, permission, biography, image or network authority is granted by
these frames. Native checks the source again before the eventual panel commit.
"""
from __future__ import annotations
import json
import time
from .conversation_context import ContextSnippet
from .generated_answer import strict_json, CardError
from .panel_wire import exact, u64, uuid_string, WireError
from .screen_context import SupplementalScreenProvider

_FENCES=('captureSessionID','sessionEpoch','presentationGeneration','requestID')
_SELECTED=set(_FENCES)|{'schemaVersion','kind','source','consentGeneration','observationID',
    'capturedUptimeNanoseconds','provenance','text'}

def _fences(value):
    return (uuid_string(value['captureSessionID']),u64(value['sessionEpoch'],True),
        u64(value['presentationGeneration'],True),uuid_string(value['requestID']))

def _selected(value,now):
    exact(value,_SELECTED)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='selected_text_context' or value['provenance']!='selected_accessibility_text':
        raise WireError('selected_text_schema')
    _fences(value);uuid_string(value['consentGeneration']);uuid_string(value['observationID'])
    source=exact(value['source'],('bundleID','processID','launchTimeMilliseconds'))
    if not isinstance(source['bundleID'],str) or not 0<len(source['bundleID'].encode())<=120 or any(ord(c)<32 for c in source['bundleID']):raise WireError('selected_text_source')
    if not 0<u64(source['processID'],True)<=2**31-1:raise WireError('selected_text_source')
    u64(source['launchTimeMilliseconds'],True)
    captured=u64(value['capturedUptimeNanoseconds'],True)
    if not 0<=now-captured<=5_000_000_000:raise WireError('selected_text_age')
    text=value['text']
    if not isinstance(text,str) or not text.strip() or len(text.encode())>8192 or any(ord(c)<32 and c not in '\n\t' for c in text):raise WireError('selected_text_budget')

class SupplementalContextProvider:
    """Native emits at most one frame immediately before the original EOU.

    Staging validates syntax only. The current_request callback must establish
    actual host Request identity/lease/token admission before this provider may
    ingest it into the existing screen port or issue selected-text context.
    """
    def __init__(self,*,current_request,now_ns=time.monotonic_ns,on_invalidation=lambda:None):
        self._current_request=current_request;self._now=now_ns;self._changed=on_invalidation
        self._screen=SupplementalScreenProvider(now_ns=now_ns,on_invalidation=on_invalidation)
        self._staged=None;self._native=None;self._snippet=None;self._issued=None
    def stage(self,payload):
        try:
            if self._staged is not None:
                self._staged=None;return False
            value=strict_json(payload,max_bytes=16384)
            fences=_fences(value)
            if self._native is not None:
                old=_fences(self._native)
                if fences[:2]!=old[:2] or fences[2]<=old[2] or fences[3]==old[3]:return False
            if value.get('kind')=='selected_text_context':_selected(value,self._now())
            elif value.get('kind')=='screen_context':
                # Reuse exact screen schema validation in a disposable consumer.
                # Its dict factory creates no ContextSnippet or admitted state.
                validator=SupplementalScreenProvider(now_ns=self._now,snippet_factory=lambda **fields:fields)
                if not validator.ingest(payload,value):return False
            else:return False
            self._staged=(payload,value,self._now());return True
        except (ValueError,TypeError,KeyError,UnicodeError,OverflowError,RecursionError):return False
    def __call__(self,native):
        if not self._current_request(native):
            self._staged=None;return None
        if self._native is native:return self._snippet if self.validate_current(self._snippet,native) else None
        staged,self._staged=self._staged,None
        if staged is None:return None
        raw,value,staged_at=staged
        try:
            if not 0<=self._now()-staged_at<=2_000_000_000 or _fences(value)!=_fences(native):return None
            if value['kind']=='screen_context':
                self._screen=SupplementalScreenProvider(now_ns=self._now,on_invalidation=self._changed)
                if not self._screen.ingest(raw,native):return None
                snippet=self._screen(native)
            else:
                _selected(value,self._now())
                snippet=ContextSnippet(kind='screen_text',text=value['text'],source='Selected text: '+value['source']['bundleID'],
                    captured_uptime_ns=value['capturedUptimeNanoseconds'],session_id=native['captureSessionID'],
                    presentation_generation=native['presentationGeneration'],provenance='selected_accessibility_text')
            self._native=native;self._snippet=snippet;self._issued=value
            return snippet
        except (ValueError,TypeError,KeyError,UnicodeError,OverflowError):return None
    def validate_current(self,snippet,native):
        if snippet is None or snippet is not self._snippet or native is not self._native or not self._current_request(native):return False
        try:
            if _fences(self._issued)!=_fences(native):return False
            if snippet.provenance=='local_ocr':return self._screen.validate_current(snippet,native)
            return 0<=self._now()-self._issued['capturedUptimeNanoseconds']<=5_000_000_000
        except (ValueError,TypeError,KeyError):return False
    def discard_staged(self):
        self._staged=None
    def invalidate(self):
        self._staged=self._native=self._snippet=self._issued=None
        self._screen.invalidate(require_new_authority=False)
    def retire_screen(self,payload,native):
        return self._screen.retire_frame(payload,native)
