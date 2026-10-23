"""Bounded ephemeral dialogue. Transcript content never grants personal authority."""
from __future__ import annotations
from collections import deque
from dataclasses import asdict, dataclass
import json
import re
import copy
from .correction_grammar import CORRECTION_PREFIX


@dataclass(frozen=True)
class TaskContext:
    kind: str = 'discussion'
    known_problem: tuple[str, ...] = ()
    constraints: tuple[str, ...] = ()
    stage: str = 'clarify'
    user_attempt: tuple[str, ...] = ()
    engineer_feedback: tuple[str, ...] = ()
    unresolved_assumptions: tuple[str, ...] = ('Only explicitly supplied requirements are known.',)
    context_gaps: tuple[str, ...] = ()
    state: str = 'ready'
    next_step: str = 'Answer the current request; clarify missing requirements.'


@dataclass(frozen=True)
class DialogueSnapshot:
    dialogue: tuple[tuple[str, str], ...]
    task: TaskContext
    def as_dict(self):
        return asdict(self)


class ConversationContext:
    """Raw dialogue ring plus independently bounded, source-backed task state.

    Only explicit field statements replace current constraints. This is a small
    mechanical update grammar, not a semantic requirements extractor. Unknown
    corrections and overflow require a restatement instead of losing authority.
    """
    _NEW=re.compile(r'^(?:new|next|different) (?:task|problem|case(?: study)?)[,: ]+',re.I)
    _CORRECTION=CORRECTION_PREFIX
    _FIELD=re.compile(r'\b(capacity|keys?|values?|inputs?|latency|users?|concurrency|throughput|budget|privacy|availability|language|storage|requirements?)\b',re.I)
    def __init__(self, *, max_utterances=12, max_bytes=6000):
        if not 1 <= max_utterances <= 32 or not 512 <= max_bytes <= 12000:
            raise ValueError('Invalid context budget.')
        self._max_count,self._max_bytes=max_utterances,max_bytes
        self.clear()

    def clear(self):
        self._history=deque();self._kind='discussion';self._order=0;self._task_order=-1
        self._gaps=();self._problem=();self._constraints={};self._task_state='ready';self._task_started=False
        self._unresolved_fields=set();self._unresolved_bare=False;self._unresolved_value=None;self._problem_restatement=False

    def mark_gap(self,reason):
        if reason not in ('microphone_unavailable','microphone_discontinuity'): raise ValueError('Invalid context gap.')
        self._gaps=tuple(dict.fromkeys((*self._gaps,reason)))

    def fork(self):
        """Private bounded task state; no source, permission or memory authority."""
        return copy.deepcopy(self)

    def project_user_request(self,text,*,basis=None):
        if not isinstance(text,str) or not text.strip() or len(text.encode())>500:
            raise ValueError('Invalid explicit task text.')
        projected=basis.fork() if basis is not None else ConversationContext(max_utterances=self._max_count,max_bytes=self._max_bytes)
        # Preserve typed basis context and current actual audio as labelled data.
        prior=[row for row in projected._history if row[0]=='user_text']
        projected._history=deque([*self._history,*prior])
        order=max((row[2] for row in projected._history),default=0)
        order=max(order,projected._task_order)+1
        projected._update_task(text,order)
        projected._history.append(('user_text',text,order));projected._explicit_current=text
        while len(projected._history)>projected._max_count or sum(len(row[1].encode()) for row in projected._history)>projected._max_bytes:
            projected._history.popleft()
        return projected

    @staticmethod
    def _kind_of(text):
        if re.search(r'case study|design (?:a|an|the) (?:feature|product|app|system)',text,re.I): return 'case_study'
        if re.search(r'implement|coding|write (?:a |the )?(?:function|code)|solve|algorithm',text,re.I): return 'coding'
        return 'discussion'

    @staticmethod
    def _field_name(name):
        name=name.lower()
        return {'key':'keys','value':'values','inputs':'input','user':'users','requirement':'requirements'}.get(name,name)

    def _constraint(self,part):
        stripped=self._CORRECTION.sub('',part).strip()
        if stripped.endswith('?'): return None
        field=self._FIELD.search(stripped)
        if field is None or not re.search(r'\b(?:must|shall|is|are|only|require|requires|assume|no)\b|=',stripped,re.I): return None
        name=self._field_name(field.group(1))
        return name,stripped

    def _replacement_hint(self,text):
        tail=self._CORRECTION.sub('',text).strip(' \t,.:!?')
        tail=re.sub(r'^make (?:it|that)\s+','',tail,flags=re.I)
        words=tuple(re.findall(r"\w+",tail.casefold()))
        if not 1<=len(words)<=4 or len(tail.encode())>128: return None
        if any(w in ('make','it','that','please','actually','no','instead','rather','sorry','reverse') for w in words): return None
        return words

    def _update_task(self,text,order):
        if order<self._task_order: return
        self._task_order=order
        kind=self._kind_of(text);explicit_new=bool(self._NEW.match(text) or re.match(r'^case study:',text,re.I))
        if self._task_started and self._task_state=='overflow' and not explicit_new: return
        begin=not self._task_started or explicit_new or (kind=='case_study' and re.match(r'^case study',text,re.I)) or self._kind=='discussion' and kind!='discussion'
        parts=tuple(p.strip() for p in re.split(r'(?<=[.!?;])\s+',text) if p.strip())
        if begin:
            self._task_started=True
            self._kind=kind;self._constraints={};self._task_state='ready'
            self._unresolved_fields.clear();self._unresolved_bare=False;self._unresolved_value=None;self._problem_restatement=False
            problem=tuple(part for index,part in enumerate(parts) if index==0 or self._constraint(part) is None)
            if sum(len(p.encode()) for p in problem)>4096:
                self._problem=();self._task_state='overflow';return
            self._problem=problem
        correction=bool(self._CORRECTION.match(text))
        updates=[(part,self._constraint(part)) for part in parts]
        if correction and not any(parsed is not None for _,parsed in updates):
            fields={self._field_name(name) for name in self._FIELD.findall(text)}
            self._unresolved_fields.update(fields)
            if not fields:
                self._unresolved_bare=True;self._unresolved_value=self._replacement_hint(text)
            self._task_state='needs_clarification';return
        for part,parsed in updates:
            if parsed is None: continue
            key,value=parsed
            candidate={**self._constraints,key:value}
            size=sum(len(p.encode()) for p in self._problem)+sum(len(v.encode()) for v in candidate.values())
            if len(candidate)>8 or size>8192:
                self._task_state='overflow';return
            # An embedded original value cannot be safely rewritten mechanically.
            # A full explicit task restatement is required in that case.
            if correction and key in self._constraints and any(self._constraint(p) and self._constraint(p)[0]==key for p in self._problem):
                self._problem_restatement=True;self._unresolved_fields.add(key)
                self._task_state='needs_clarification';return
            changed=self._constraints.get(key)!=value
            self._constraints=candidate
            # Resolve a named target only with that field. A bare replacement
            # also needs a changed explicit statement carrying its bounded
            # replacement hint; unrelated/unchanged requirements cannot clear it.
            if self._problem_restatement and key in self._unresolved_fields and not correction:
                self._problem_restatement=False
            self._unresolved_fields.discard(key)
            if self._unresolved_bare and changed and self._unresolved_value is not None and set(self._unresolved_value).issubset(re.findall(r"\w+",value.casefold())):
                self._unresolved_bare=False;self._unresolved_value=None
        if self._task_state=='needs_clarification' and not self._unresolved_fields and not self._unresolved_bare and not self._problem_restatement:
            self._task_state='ready'

    def observe(self,channel,text,*,order=None):
        if channel not in ('remote','microphone') or not isinstance(text,str): raise ValueError('Invalid conversation input.')
        if not text.strip(): return
        if len(text.encode())>self._max_bytes or any(ord(c)<32 and c not in '\n\t' for c in text): raise ValueError('Conversation input exceeds budget.')
        self._order+=1;order=self._order if order is None else order
        if channel=='remote': self._update_task(text,order)
        self._history.append((channel,text,order));self._history=deque(sorted(self._history,key=lambda row:row[2]))
        while len(self._history)>self._max_count or sum(len(t.encode()) for _,t,_ in self._history)>self._max_bytes: self._history.popleft()

    def snapshot(self):
        remote=tuple(t for c,t,_ in self._history if c=='remote');user=tuple(t for c,t,_ in self._history if c=='microphone')
        current=getattr(self,'_explicit_current',remote[-1] if remote else '').lower();stage='clarify'
        for name,pattern in (('validation',r'validat|test|measure|success'),('tradeoffs',r'tradeoff|improv|scale|optimi'),('flows',r'workflow|user flow|journey'),('requirements',r'require|constraint|capacity'),('users',r'who|user|customer'),('design',r'design|architect'),('implementation',r'code|implement|solve|function|query')):
            if re.search(pattern,current): stage=name;break
        assumptions=('Only explicitly supplied requirements are known.',)
        if self._task_state!='ready':
            assumptions+=('Restate the full task or affected constraint before relying on it.',)
            if self._unresolved_fields: assumptions+=('Unresolved fields: '+', '.join(sorted(self._unresolved_fields)),)
            elif self._unresolved_bare:
                assumptions+=('The correction target is not yet explicit.',)
                if self._unresolved_value: assumptions+=('Unresolved replacement: '+' '.join(self._unresolved_value),)
        task=TaskContext(kind=self._kind,known_problem=self._problem,constraints=tuple(self._constraints.values()),stage=stage,user_attempt=user[-2:],engineer_feedback=remote[-2:],unresolved_assumptions=assumptions,context_gaps=self._gaps,state=self._task_state,next_step='Discuss '+stage+'; keep uncertain requirements explicit.')
        snapshot=DialogueSnapshot(tuple((c,t) for c,t,_ in self._history),task)
        if len(json.dumps(snapshot.as_dict(),ensure_ascii=False).encode())>24576 and len(self._history)>1:
            self._history.popleft();return self.snapshot()
        return snapshot

@dataclass(frozen=True)
class ContextSnippet:
    """Reserved injected screen/paste port. No capture, AX or biography authority.

    The provider owns source selection and provenance. Host freshness/session
    checks are mandatory before including this untrusted task input in a prompt.
    """
    kind: str
    text: str
    source: str
    captured_uptime_ns: int
    session_id: str
    presentation_generation: int
    provenance: str

    def __post_init__(self):
        if self.kind not in ('screen_text','pasted_problem') or self.provenance not in ('local_ocr','selected_accessibility_text','user_paste'):
            raise ValueError('Invalid supplemental context kind.')
        if not isinstance(self.text,str) or not 0<len(self.text.encode())<=8192 or any(ord(c)<32 and c not in '\n\t' for c in self.text):
            raise ValueError('Invalid supplemental context budget.')
        if not isinstance(self.source,str) or not 0<len(self.source.encode())<=160 or not isinstance(self.session_id,str):
            raise ValueError('Invalid supplemental context provenance.')
        if type(self.captured_uptime_ns) is not int or self.captured_uptime_ns<0 or type(self.presentation_generation) is not int or self.presentation_generation<1:
            raise ValueError('Invalid supplemental context time.')

    def current(self,*,session_id,presentation_generation,now_ns):
        return self.session_id==session_id and self.presentation_generation==presentation_generation and 0<=now_ns-self.captured_uptime_ns<=10_000_000_000
