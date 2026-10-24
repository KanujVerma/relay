"""Bounded optional response data. Staging never authorizes a native request."""
from dataclasses import dataclass
from hashlib import sha256
import asyncio
import copy
import json
import time
import unicodedata

from .panel_wire import exact, u64, uuid_string, WireError

_OFFER=('schemaVersion','kind','captureSessionID','sessionEpoch','presentationGeneration',
        'requestID','eventSequence','memoryRevision','scope','evidenceGap','continuity','interactions','adjustments','preparation','examples','supportIDs')
_RETIRE=('schemaVersion','kind','captureSessionID','sessionEpoch','memoryRevision')


def _text(value, limit):
    try:
        valid=(isinstance(value,str) and bool(value.strip()) and len(value.encode())<=limit
               and not any(unicodedata.category(c) in ('Cc','Cf','Cs','Zl','Zp') and c not in '\n\t' for c in value))
    except UnicodeError:valid=False
    if not valid:raise WireError('learning_text')


def _interaction(value):
    exact(value,('episodeID','question','suggestion','reply','continuation','temporallyEligible','possibleUptake','distinctiveOverlap','ambiguity'))
    uuid_string(value['episodeID'])
    sources=[]
    for field in ('question','reply','continuation'):
        row=value[field];exact(row,('sourceID','text','excerpt'))
        _text(row['sourceID'],180);_text(row['text'],240)
        if type(row['excerpt']) is not bool:raise WireError('learning_excerpt')
        sources.append(row['sourceID'])
    if len(set(sources))!=3:raise WireError('learning_sources')
    suggestion=value['suggestion'];exact(suggestion,('requestID','text','availableAt','windowVisible','guideRevision','excerpt'))
    if uuid_string(suggestion['requestID'])!=uuid_string(value['episodeID']):raise WireError('learning_episode')
    _text(suggestion['text'],300);u64(suggestion['availableAt'],True)
    if suggestion['guideRevision'] is not None:uuid_string(suggestion['guideRevision'])
    if any(type(suggestion[key]) is not bool for key in ('windowVisible','excerpt')):raise WireError('learning_visibility')
    if any(type(value[key]) is not bool for key in ('temporallyEligible','possibleUptake')):raise WireError('learning_signal')
    if type(value['distinctiveOverlap']) is not int or not 0<=value['distinctiveOverlap']<=1024:raise WireError('learning_overlap')
    flags=value['ambiguity'];known=('hidden_card','speech_before_available','overlap','possible_echo','asr_confidence_unknown','asr_uncertain','late_final','remote_before_reply_final','competing_card')
    if (not isinstance(flags,list) or len(flags)>9 or not all(isinstance(flag,str) and flag in known for flag in flags)
        or len(set(flags))!=len(flags)):raise WireError('learning_ambiguity')


def decode_learning(value):
    exact(value,_OFFER)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='learning_memory':
        raise WireError('learning_schema')
    for field in ('captureSessionID','requestID','memoryRevision'):uuid_string(value[field])
    for field in ('sessionEpoch','presentationGeneration','eventSequence'):u64(value[field],True)
    if value['scope'] not in ('technical','recruiter','other'):raise WireError('learning_scope')
    if type(value['evidenceGap']) is not bool:raise WireError('learning_gap')
    adjustments=value['adjustments']
    if (not isinstance(adjustments,list) or len(adjustments)>2 or not all(isinstance(item,str) for item in adjustments) or len(set(adjustments))!=len(adjustments)
        or any(item not in ('concise_lead','stepwise','example_first') for item in adjustments)):
        raise WireError('learning_adjustment')
    for field in ('continuity','preparation','examples'):
        rows=value[field]
        if not isinstance(rows,list) or len(rows)>2:raise WireError('learning_rows')
        for row in rows:
            exact(row,('sourceID','kind','text','excerpt') if field=='continuity' else ('sourceID','text','excerpt'))
            _text(row['sourceID'],180);_text(row['text'],350 if field=='examples' else 700)
            if type(row['excerpt']) is not bool:raise WireError('learning_excerpt')
            if field=='continuity' and row['kind'] not in ('spoken_constraint','unresolved_followup','interaction'):
                raise WireError('learning_kind')
    interactions=value['interactions']
    if not isinstance(interactions,list) or len(interactions)>1:raise WireError('learning_interactions')
    for interaction in interactions:_interaction(interaction)
    supports=value['supportIDs']
    if not isinstance(supports,list) or len(supports)>8 or not all(isinstance(item,str) for item in supports) or len(set(supports))!=len(supports):raise WireError('learning_supports')
    for support in supports:uuid_string(support)
    if len(json.dumps({key:value[key] for key in ('scope','evidenceGap','continuity','interactions','adjustments','preparation','examples','supportIDs')},ensure_ascii=False,separators=(',',':')).encode())>2048:
        raise WireError('learning_budget')
    return copy.deepcopy(value)


def decode_learning_retirement(value):
    exact(value,_RETIRE)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='learning_memory_retired':
        raise WireError('learning_retirement')
    uuid_string(value['captureSessionID']);uuid_string(value['memoryRevision']);u64(value['sessionEpoch'],True)
    return dict(value)


def _scope(value):return(uuid_string(value['captureSessionID']),value['sessionEpoch'])
def _revision(value):return(*_scope(value),uuid_string(value['memoryRevision']))
def _key(value):
    return(*_scope(value),value['presentationGeneration'],uuid_string(value['requestID']),value['eventSequence'])


@dataclass(eq=False)
class _LearningUse:
    native:dict
    revision:str
    revision_key:tuple
    data:dict|None
    used:bool=False


class HostLearningMemory:
    def __init__(self,host):
        self.host=host
        self._staged={};self._ledger={};self._retired=set()
        self._timer=None;self._use=None

    def _remember(self,key,value):
        fingerprint=sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).digest()
        if key in self._ledger:
            if self._ledger[key]!=fingerprint:raise WireError('learning_reuse')
            return False
        if len(self._ledger)>=512:raise WireError('learning_budget')
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
        value=decode_learning(raw);key=_key(value)
        if not self._remember(('offer',key[3]),value):return False
        self._expire()
        if (not self.host.live or _scope(value)!=self.host.session or not self.host.permission.authorized()
            or key[3] in self.host.used_requests or self.host.user.is_retired(value)
            or _revision(value) in self._retired):return False
        if len(self._staged)>=8:raise WireError('learning_slots')
        self._staged[key]=(value,time.monotonic_ns()+2_000_000_000);self._schedule();return True

    def discard(self,native):
        self._staged.pop(_key(native),None);self._schedule()

    def claim(self,native):
        # This existing base predicate requires the actual admitted native object
        # and is independent of learning/visual/supplemental validators.
        if self._use is not None or not self.host.supplemental_request_current(native):return None
        self._expire();entry=self._staged.pop(_key(native),None);self._schedule()
        if entry is None:return None
        value,_=entry;revision=_revision(value)
        if revision in self._retired:return None
        use=_LearningUse(native,uuid_string(value['memoryRevision']),revision,
                           {key:copy.deepcopy(value[key]) for key in ('scope','evidenceGap','continuity','interactions','adjustments','preparation','examples','supportIDs')})
        self._use=use;return use

    def _owns(self,use,native):
        return (use is not None and use is self._use and use.native is native
                and use.data is not None and use.revision_key not in self._retired
                and self.host.supplemental_request_current(native))

    def current_for(self,request):
        use=self._use
        return use is None or use.native is not request.native or self._owns(use,request.native)

    def prompt_for(self,request,*,has_explicit_guide=False):
        use=self._use
        if use is None or use.native is not request.native:return None
        if not self._owns(use,request.native):raise WireError('learning_unavailable')
        use.used=True
        value=copy.deepcopy(use.data)
        if has_explicit_guide:value['adjustments']=[];value['examples']=[]
        return value

    def omitted(self,request):
        if self._use is not None and self._use.native is request.native:self._use.used=False

    def used_revision(self,request):
        use=self._use
        return use.revision if use is not None and use.used and self._owns(use,request.native) else None

    def retire(self,raw):
        value=decode_learning_retirement(raw);key=_revision(value)
        if not self._remember(('retire',key),value):return False
        self._retired.add(key)
        self._staged={identity:entry for identity,entry in self._staged.items() if _revision(entry[0])!=key}
        use=self._use
        if use is not None and use.revision_key==key:
            # Keep one data-free claimed tombstone until native replacement.
            # Absence means genuine General; a retired used claim never does.
            use.data=None
            self.host.learning_memory_changed(use.native)
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
