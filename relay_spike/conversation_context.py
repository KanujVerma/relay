"""Bounded ephemeral dialogue. Transcript content never grants personal authority."""
from __future__ import annotations
from collections import deque
from dataclasses import asdict, dataclass
import json
import re


@dataclass(frozen=True)
class TaskContext:
    kind: str = 'discussion'
    known_problem: tuple[str, ...] = ()
    constraints: tuple[str, ...] = ()
    stage: str = 'clarify'
    user_attempt: tuple[str, ...] = ()
    engineer_feedback: tuple[str, ...] = ()
    unresolved_assumptions: tuple[str, ...] = ('Only explicitly supplied requirements are known.',)
    next_step: str = 'Answer the current request; clarify missing requirements.'


@dataclass(frozen=True)
class DialogueSnapshot:
    dialogue: tuple[tuple[str, str], ...]
    task: TaskContext
    def as_dict(self):
        return asdict(self)


class ConversationContext:
    def __init__(self, *, max_utterances=12, max_bytes=6000):
        if not 1 <= max_utterances <= 32 or not 512 <= max_bytes <= 12000:
            raise ValueError('Invalid context budget.')
        self._history = deque()
        self._max_count, self._max_bytes = max_utterances, max_bytes
        self._kind = 'discussion'
        self._order = 0
        self._kind_order = -1

    def clear(self):
        self._history.clear()
        self._kind = 'discussion'
        self._order = 0
        self._kind_order = -1

    def observe(self, channel: str, text: str, *, order: int | None = None):
        if channel not in ('remote', 'microphone') or not isinstance(text, str):
            raise ValueError('Invalid conversation input.')
        if not text.strip():
            return
        if len(text.encode('utf-8')) > self._max_bytes or any(ord(c) < 32 and c not in '\n\t' for c in text):
            raise ValueError('Conversation input exceeds budget.')
        self._order += 1
        order = self._order if order is None else order
        low = text.lower()
        if channel == 'remote' and order >= self._kind_order:
            if re.search(r'case study|design (?:a|an|the) (?:feature|product|app|system)', low):
                self._kind = 'case_study'
                self._kind_order = order
            elif re.search(r'implement|coding|write (?:a |the )?(?:function|code)|solve|algorithm', low):
                self._kind = 'coding'
                self._kind_order = order
        self._history.append((channel, text, order))
        self._history = deque(sorted(self._history, key=lambda row: row[2]))
        while len(self._history) > self._max_count or sum(len(t.encode()) for _, t, _ in self._history) > self._max_bytes:
            self._history.popleft()

    def snapshot(self) -> DialogueSnapshot:
        remote = tuple(text for channel, text, _ in self._history if channel == 'remote')
        user = tuple(text for channel, text, _ in self._history if channel == 'microphone')
        current = remote[-1].lower() if remote else ''
        stage = 'clarify'
        for name, pattern in (
            ('validation', r'validat|test|measure|success'), ('tradeoffs', r'tradeoff|improv|scale|optimi'),
            ('flows', r'workflow|user flow|journey'), ('requirements', r'require|constraint|capacity'),
            ('users', r'who|user|customer'), ('design', r'design|architect'), ('implementation', r'code|implement|solve|function|query'),
        ):
            if re.search(pattern, current):
                stage = name
                break
        # These are verbatim attributed observations, not inferred requirements.
        task = TaskContext(self._kind, remote[:1], tuple(t for t in remote if re.search(r'must|only|capacity|constraint|require|assume', t, re.I))[-2:], stage, user[-2:], remote[-2:], next_step='Discuss ' + stage + '; keep uncertain requirements explicit.')
        snapshot = DialogueSnapshot(tuple((channel,text) for channel,text,_ in self._history), task)
        # Fixed fields plus duplicated task observations have their own bound.
        while len(json.dumps(snapshot.as_dict(), ensure_ascii=False).encode()) > 16000 and len(self._history) > 1:
            self._history.popleft()
            return self.snapshot()
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
