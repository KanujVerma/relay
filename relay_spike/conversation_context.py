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

    def clear(self):
        self._history.clear()
        self._kind = 'discussion'

    def observe(self, channel: str, text: str):
        if channel not in ('remote', 'microphone') or not isinstance(text, str):
            raise ValueError('Invalid conversation input.')
        if not text.strip():
            return
        if len(text.encode('utf-8')) > self._max_bytes or any(ord(c) < 32 and c not in '\n\t' for c in text):
            raise ValueError('Conversation input exceeds budget.')
        low = text.lower()
        if channel == 'remote':
            if re.search(r'case study|design (?:a|an|the) (?:feature|product|app|system)', low):
                self._kind = 'case_study'
            elif re.search(r'implement|coding|write (?:a |the )?(?:function|code)|solve|algorithm', low):
                self._kind = 'coding'
        self._history.append((channel, text))
        while len(self._history) > self._max_count or sum(len(t.encode()) for _, t in self._history) > self._max_bytes:
            self._history.popleft()

    def snapshot(self) -> DialogueSnapshot:
        remote = tuple(text for channel, text in self._history if channel == 'remote')
        user = tuple(text for channel, text in self._history if channel == 'microphone')
        current = remote[-1].lower() if remote else ''
        stage = 'clarify'
        for name, pattern in (
            ('validation', r'validat|test|measure|success'), ('tradeoffs', r'tradeoff|improv|scale|optimi'),
            ('flows', r'workflow|user flow|journey'), ('requirements', r'require|constraint|capacity'),
            ('users', r'who|user|customer'), ('design', r'design|architect'), ('implementation', r'code|implement|solve'),
        ):
            if re.search(pattern, current):
                stage = name
                break
        # These are verbatim attributed observations, not inferred requirements.
        task = TaskContext(self._kind, remote[:1], tuple(t for t in remote if re.search(r'must|only|capacity|constraint|require|assume', t, re.I))[-2:], stage, user[-2:], remote[-2:], next_step='Discuss ' + stage + '; keep uncertain requirements explicit.')
        snapshot = DialogueSnapshot(tuple(self._history), task)
        # Fixed fields plus duplicated task observations have their own bound.
        while len(json.dumps(snapshot.as_dict(), ensure_ascii=False).encode()) > 16000 and len(self._history) > 1:
            self._history.popleft()
            return self.snapshot()
        return snapshot
