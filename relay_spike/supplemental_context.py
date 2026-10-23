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
from .screen_context import SupplementalScreenProvider, ScreenImageAssembler

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
    """One text frame and optional bounded image chunks precede the original EOU.

    Staging validates syntax only. The current_request callback must establish
    actual host Request identity/lease/token admission before this provider may
    ingest it into the existing screen port or issue selected-text context.
    """
    def __init__(self,*,current_request,now_ns=time.monotonic_ns,on_invalidation=lambda:None):
        self._current_request=current_request;self._now=now_ns;self._changed=on_invalidation
        self._screen=SupplementalScreenProvider(now_ns=now_ns,on_invalidation=on_invalidation)
        self._staged=None;self._native=None;self._snippet=None;self._issued=None
        self._reset_staged_images()
        self._images=ScreenImageAssembler(now_ns=now_ns);self._image_owner=self._image_size=None
    def _reset_staged_images(self):
        self._staged_images=ScreenImageAssembler(now_ns=self._now)
        self._staged_image_owner=self._staged_image_size=None
        self._staged_image_started=False
    def stage(self,payload):
        try:
            if self._staged is not None:
                self.discard_staged();return False
            value=strict_json(payload,max_bytes=16384)
            fences=_fences(value)
            if self._native is not None:
                old=_fences(self._native)
                if fences[:2]!=old[:2] or fences[2]<=old[2] or fences[3]==old[3]:return False
            staged_owner=None
            if value.get('kind')=='selected_text_context':_selected(value,self._now())
            elif value.get('kind')=='screen_context':
                # Reuse exact screen schema validation in a disposable consumer.
                # Its dict factory creates no ContextSnippet or admitted state.
                validator=SupplementalScreenProvider(now_ns=self._now,snippet_factory=lambda **fields:fields)
                if not validator.ingest(payload,value):return False
                staged_owner=validator.current_observation(value)
            else:return False
            self._reset_staged_images();self._staged_image_owner=staged_owner
            self._staged=(payload,value,self._now());return True
        except (ValueError,TypeError,KeyError,UnicodeError,OverflowError,RecursionError):return False
    def stage_image(self,payload):
        # This is bounded local data only. It grants no inference authority.
        staged=self._staged;owner=self._staged_image_owner
        if staged is None or owner is None or not 0<=self._now()-staged[2]<=2_000_000_000:
            self._staged_images.clear();return False
        try:
            value=strict_json(payload,max_bytes=16384)
            if value.get('kind')=='screen_image_begin' and self._staged_image_started:
                self._staged_images.clear();self._staged_image_owner=None;return False
            if not self._staged_images.ingest(payload,owner):
                self._staged_image_owner=self._staged_image_size=None;return False
            if value['kind']=='screen_image_begin':
                self._staged_image_started=True
                self._staged_image_size=(value['width'],value['height'])
            return True
        except (ValueError,TypeError,KeyError):
            self._staged_images.clear();self._staged_image_owner=None;return False
    def __call__(self,native):
        if not self._current_request(native):
            self.discard_staged();return None
        if self._native is native:return self._snippet if self.validate_current(self._snippet,native) else None
        staged,self._staged=self._staged,None
        images,image_size=self._staged_images,self._staged_image_size
        self._reset_staged_images()
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
            self._images.clear();self._image_owner=self._image_size=None
            self._native=native;self._snippet=snippet;self._issued=value
            if value['kind']=='screen_context':
                owner=self._screen.current_observation(native)
                if image_size is not None and images.completed(owner) is not None:
                    self._images=images;self._image_owner=owner;self._image_size=image_size
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
        self._staged_images.clear();self._reset_staged_images()
    def retire_staged(self,native):
        try:
            if self._staged is None or _fences(self._staged[1])!=_fences(native):return False
        except (ValueError,TypeError,KeyError):return False
        self.discard_staged();return True
    def retire_current(self,native):
        try:
            if self._native is None or _fences(self._native)!=_fences(native):return False
        except (ValueError,TypeError,KeyError):return False
        # Preserve any independently fenced newer staged request.
        self._native=self._snippet=self._issued=None
        self._images.clear();self._image_owner=self._image_size=None
        self._screen.invalidate(require_new_authority=False)
        return True
    def discard_images(self):
        self._images.clear();self._image_owner=self._image_size=None
        self._staged_images.clear();self._reset_staged_images()
    def image_for_request(self,native):
        if not self.owns_image_observation(self._image_owner,native):return None
        data=self._images.completed(self._image_owner)
        if data is None or self._image_size is None:return None
        return (self._image_owner,data,*self._image_size)
    def owns_image_observation(self,observation,native):
        return bool(observation is not None and observation is self._image_owner
            and self._snippet is not None and self._snippet.provenance=='local_ocr'
            and self.validate_current(self._snippet,native) and self._screen.owns_observation(observation,native))
    def release_image_bytes(self,observation,native):
        if self.owns_image_observation(observation,native):self._images.clear()
    def invalidate(self):
        self._staged=self._native=self._snippet=self._issued=None
        self.discard_staged();self.discard_images()
        self._screen.invalidate(require_new_authority=False)
    def retire_screen(self,payload,native):
        return self._screen.retire_frame(payload,native)
