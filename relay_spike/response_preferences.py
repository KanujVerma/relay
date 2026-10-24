"""Bounded optional response data. Staging never authorizes a native request."""
from dataclasses import dataclass
from hashlib import sha256
import asyncio
import json
import time
import unicodedata

from .panel_wire import exact, u64, uuid_string, WireError

_OFFER=('schemaVersion','kind','captureSessionID','sessionEpoch','presentationGeneration',
        'requestID','eventSequence','preferencesRevision','focus','guidance')
_RETIRE=('schemaVersion','kind','captureSessionID','sessionEpoch','preferencesRevision')


def decode_preferences(value):
    exact(value,_OFFER)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='response_preferences':
        raise WireError('preferences_schema')
    for field in ('captureSessionID','requestID','preferencesRevision'):uuid_string(value[field])
    for field in ('sessionEpoch','presentationGeneration','eventSequence'):u64(value[field],True)
    if value['focus'] not in ('automatic','coding','feature'):raise WireError('preferences_focus')
    text=value['guidance']
    try:
        valid=(isinstance(text,str) and bool(text.strip()) and len(text.encode())<=2048
               and not any(unicodedata.category(c) in ('Cc','Cf','Cs','Zl','Zp') and c not in '\n\t' for c in text))
    except UnicodeError:valid=False
    if not valid:raise WireError('preferences_guidance')
    return dict(value)


def decode_preferences_retirement(value):
    exact(value,_RETIRE)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='response_preferences_retired':
        raise WireError('preferences_retirement')
    uuid_string(value['captureSessionID']);uuid_string(value['preferencesRevision']);u64(value['sessionEpoch'],True)
    return dict(value)


def _scope(value):return(uuid_string(value['captureSessionID']),value['sessionEpoch'])
def _revision(value):return(*_scope(value),uuid_string(value['preferencesRevision']))
def _key(value):
    return(*_scope(value),value['presentationGeneration'],uuid_string(value['requestID']),value['eventSequence'])


@dataclass(eq=False)
class _PreferenceUse:
    native:dict
    revision:str
    revision_key:tuple
    data:dict|None
    used:bool=False


class HostResponsePreferences:
    def __init__(self,host):
        self.host=host
        self._staged={};self._ledger={};self._retired=set()
        self._timer=None;self._use=None

    def _remember(self,key,value):
        fingerprint=sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).digest()
        if key in self._ledger:
            if self._ledger[key]!=fingerprint:raise WireError('preferences_reuse')
            return False
        if len(self._ledger)>=512:raise WireError('preferences_budget')
        self._ledger[key]=fingerprint;return True

    def _schedule(self):
        if self._timer is not None:self._timer.cancel();self._timer=None
        if self._staged:
            delay=max(0,min(deadline for _,deadline in self._staged.values())-time.monotonic_ns())/1e9
            self._timer=asyncio.get_running_loop().call_later(delay,self._expire)

    def _expire(self):
        now=time.monotonic_ns()
        self._staged={key:entry for key,entry in self._staged.items() if entry[1]>now}
        self._schedule()

    def stage(self,raw):
        value=decode_preferences(raw);key=_key(value)
        if not self._remember(('offer',key[3]),value):return False
        self._expire()
        if (not self.host.live or _scope(value)!=self.host.session or not self.host.permission.authorized()
            or key[3] in self.host.used_requests or self.host.user.is_retired(value)
            or _revision(value) in self._retired):return False
        if len(self._staged)>=8:raise WireError('preferences_slots')
        self._staged[key]=(value,time.monotonic_ns()+2_000_000_000);self._schedule();return True

    def discard(self,native):
        self._staged.pop(_key(native),None);self._schedule()

    def claim(self,native):
        # This existing base predicate requires the actual admitted native object
        # and is independent of preference/visual/supplemental validators.
        if self._use is not None or not self.host.supplemental_request_current(native):return None
        self._expire();entry=self._staged.pop(_key(native),None);self._schedule()
        if entry is None:return None
        value,_=entry;revision=_revision(value)
        if revision in self._retired:return None
        use=_PreferenceUse(native,uuid_string(value['preferencesRevision']),revision,
                           {'focus':value['focus'],'guidance':value['guidance']})
        self._use=use;return use

    def _owns(self,use,native):
        return (use is not None and use is self._use and use.native is native
                and use.data is not None and use.revision_key not in self._retired
                and self.host.supplemental_request_current(native))

    def current_for(self,request):
        use=self._use
        return use is None or use.native is not request.native or self._owns(use,request.native)

    def prompt_for(self,request):
        use=self._use
        if use is None or use.native is not request.native:return None
        if not self._owns(use,request.native):raise WireError('preferences_unavailable')
        use.used=True;return dict(use.data)

    def used_revision(self,request):
        use=self._use
        return use.revision if use is not None and use.used and self._owns(use,request.native) else None

    def retire(self,raw):
        value=decode_preferences_retirement(raw);key=_revision(value)
        if not self._remember(('retire',key),value):return False
        self._retired.add(key)
        self._staged={identity:entry for identity,entry in self._staged.items() if _revision(entry[0])!=key}
        use=self._use
        if use is not None and use.revision_key==key:
            # Keep one data-free claimed tombstone until native replacement.
            # Absence means genuine General; a retired used claim never does.
            use.data=None
            self.host.response_preferences_changed(use.native)
        self._schedule();return True

    def retire_native(self,native):
        # The existing native denial owns this exact request, not every future
        # request using the same selected guide revision.
        original=(*_scope(native),native['presentationGeneration'],uuid_string(native['requestID']))
        self._staged={key:entry for key,entry in self._staged.items() if key[:4]!=original}
        if self._use is not None and _key(self._use.native)[:4]==original:self._use.data=None
        self._schedule()

    def retire_request(self):
        if self._use is not None:self._use.data=None
        self._use=None
        self._staged={key:entry for key,entry in self._staged.items()
                      if key[:2]==self.host.session and key[2]>=self.host.presentation}
        self._schedule()

    def close(self):
        if self._use is not None:self._use.data=None
        self._use=None;self._staged.clear()
        if self._timer is not None:self._timer.cancel();self._timer=None
