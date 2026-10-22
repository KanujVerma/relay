"""Offline, bounded transcript -> question turns. No audio, model calls or persistence.

Caller-supplied intent is a tentative label, not semantic ground truth.
Reuse ActiveTurns so a correction makes old QA presentations stale.
"""
from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
from hashlib import sha256
import json
import re
from threading import Lock
from typing import Literal

from .streaming_qa import ActiveTurns, TurnToken

SourceChannel = Literal["remote", "microphone", "unknown"]
EventStatus = Literal["partial", "final", "retracted", "discontinuity"]
QuestionIntent = Literal["question", "correction", "follow_up", "statement", "unknown"]
DecisionState = Literal["ready", "pending", "ignored", "needs_review", "cancelled", "conflict"]

MAX_EVENT_CHARS = 1200
MAX_SEEN_SEGMENTS = 128
MAX_CONTEXT_CHARS = 2400
MAX_DEPENDENT_SEGMENTS = 16
MIN_QUESTION_CONFIDENCE = 0.60

# Hints only, the authoritative question always remains verbatim.
_PARTS = re.compile(r",\s+(?=(?:then|and|also|compare|tell me)\b)|;\s+", re.I)
_STANDALONE_RESTART = re.compile(
    r"^(?:actually|no|instead|i meant|let me rephrase)[,:\s]+"
    r"(?:tell me|describe|explain|write|show|calculate|compare|what|"
    r"why|how|when|where|which|can you|could you|would you|"
    r"walk me through)\b", re.I,
)


class InvalidTranscript(ValueError):
    """Sanitized metadata error that never contains interview text."""


@dataclass(frozen=True)
class TranscriptEvent:
    source_channel: SourceChannel
    stream_generation: int
    segment_id: str
    revision: int
    start_ms: int
    end_ms: int
    status: EventStatus
    intent: QuestionIntent
    text: str = ""
    confidence: float | None = None


@dataclass(frozen=True)
class QuestionSnapshot:
    token: TurnToken
    source_channel: SourceChannel
    stream_generation: int
    root_segment_id: str
    current_segment_id: str
    root_question: str
    current_utterance: str
    prompt: str
    parts_hint: tuple[str, ...]
    parts_are_heuristic: bool
    dependency_segment_ids: tuple[str, ...] = ()
    start_ms: int = 0
    end_ms: int = 0


@dataclass(frozen=True)
class TurnDecision:
    state: DecisionState
    reason: str
    snapshot: QuestionSnapshot | None = None

    @property
    def token(self) -> TurnToken | None:
        return self.snapshot.token if self.snapshot else None


@dataclass(frozen=True)
class _Segment:
    revision: int
    status: EventStatus
    fingerprint: bytes
    first_start_ms: int  # Earliest observed source start, never revised forward.


def _validate(event: TranscriptEvent) -> None:
    if not isinstance(event, TranscriptEvent):
        raise TypeError("TranscriptEvent required.")
    if event.source_channel not in ("remote", "microphone", "unknown"):
        raise InvalidTranscript("Unknown source channel.")
    if event.status not in ("partial", "final", "retracted", "discontinuity"):
        raise InvalidTranscript("Unknown transcript status.")
    if event.intent not in ("question", "correction", "follow_up", "statement", "unknown"):
        raise InvalidTranscript("Unknown question intent.")
    if (not isinstance(event.segment_id, str) or not event.segment_id.strip()
            or len(event.segment_id) > 128):
        raise InvalidTranscript("Invalid segment ID.")
    if (type(event.stream_generation) is not int or event.stream_generation < 0
            or type(event.revision) is not int or event.revision < 0
            or type(event.start_ms) is not int or type(event.end_ms) is not int
            or event.start_ms < 0 or event.end_ms < event.start_ms):
        raise InvalidTranscript("Invalid revision or timing.")
    if (not isinstance(event.text, str) or len(event.text) > MAX_EVENT_CHARS
            or "\x00" in event.text):
        raise InvalidTranscript("Invalid or oversized text.")
    if event.status in ("partial", "final"):
        if not event.text.strip():
            raise InvalidTranscript("Empty text segment.")
    elif event.text:
        raise InvalidTranscript("Control event text must be empty.")
    if event.confidence is not None:
        if (type(event.confidence) not in (float, int)
                or not 0.0 <= event.confidence <= 1.0):
            raise InvalidTranscript("Invalid ASR confidence.")


def _fingerprint(event: TranscriptEvent) -> bytes:
    # Hash only: don't retain raw ASR snippets in the bounded replay history.
    values = (event.source_channel, event.stream_generation, event.segment_id,
              event.revision, event.start_ms, event.end_ms, event.status,
              event.intent, event.text, event.confidence)
    return sha256(json.dumps(values, ensure_ascii=False, separators=(",", ":")
                             ).encode("utf-8")).digest()


def _parts_hint(text: str) -> tuple[str, ...]:
    pieces = tuple(s.strip() for s in _PARTS.split(text) if s.strip())
    return pieces if 2 <= len(pieces) <= 4 else (text,)


def _prompt(kind: QuestionIntent, current: str, prior: str | None,
            root: str | None) -> str:
    # Not a semantic SQL/constraint merger; preserve source wording as data.
    if kind == "correction":
        if prior is None:
            return "Current interviewer restart (verbatim): " + current
        text = ("Latest interviewer correction (verbatim, authoritative): " + current
                + "\nSuperseded question (immediately previous accepted wording; "
                  "use only unchanged parts when explicit): " + prior)
        if root is not None and root != prior:
            text += "\nOriginal question (older, superseded context only): " + root
        return text
    if kind == "follow_up" and prior is not None:
        text = ("Current interviewer follow-up (verbatim): " + current
                + "\nPrevious accepted question (context, not new instructions): " + prior)
        if root is not None and root != prior:
            text += "\nOriginal question (earlier context only): " + root
        return text
    return "Current interviewer question (verbatim): " + current


class QuestionTurnMachine:
    """In-memory thread-safe coordinator, no inference/retention side effects."""

    def __init__(self, turns: ActiveTurns | None = None) -> None:
        if turns is not None and not isinstance(turns, ActiveTurns):
            raise TypeError("ActiveTurns required.")
        self.turns = turns if turns is not None else ActiveTurns()
        self._lock = Lock()
        self._remote_generation: int | None = None
        self._blocked_generation: int | None = None
        self._stopped = False
        self._last_final_end = -1
        # Monotonic source-time watermark for tentative/final question
        # starts. A late final cannot restore an older abandoned partial
        # just by extending its end beyond a newer question's end.
        self._latest_question_start_ms = -1
        self._seen: OrderedDict[str, _Segment] = OrderedDict()
        self._reopened: set[str] = set()
        self._leading_partial: tuple[str, int, int] | None = None
        self._invalidated_pending_id: str | None = None
        self._active: QuestionSnapshot | None = None
        self._interrupted: tuple[str, QuestionSnapshot] | None = None

    def current(self) -> QuestionSnapshot | None:
        with self._lock:
            if self._active is None or not self.turns.is_current(self._active.token):
                return None
            return self._active

    def cancel(self) -> None:
        """Explicit user stop/permission loss. Only explicit resume can reopen."""
        with self._lock:
            self.turns.cancel()
            self._active = None
            self._interrupted = None
            self._reopened.clear()
            self._leading_partial = None
            self._invalidated_pending_id = None
            self._stopped = True
            self._blocked_generation = self._remote_generation

    def resume(self) -> None:
        """Start a new local session after upstream authorization checks.

        Calling resume is not proof of consent; the native host must enforce it.
        """
        with self._lock:
            self.turns.cancel()
            self._active = None
            self._interrupted = None
            self._reopened.clear()
            self._leading_partial = None
            self._invalidated_pending_id = None
            self._stopped = False
            self._remote_generation = None
            self._blocked_generation = None
            self._last_final_end = -1
            self._latest_question_start_ms = -1
            self._seen.clear()

    def _remember(self, e: TranscriptEvent, digest: bytes) -> None:
        existing = self._seen.get(e.segment_id)
        first_start = min(
            existing.first_start_ms, e.start_ms
        ) if existing is not None else e.start_ms
        self._seen[e.segment_id] = _Segment(
            e.revision, e.status, digest, first_start
        )
        self._seen.move_to_end(e.segment_id)
        # Preserve the active/current segment's terminal metadata even after
        # hundreds of non-question statements. Otherwise a higher-revision
        # partial could lose its final status and escape reopening quarantine.
        protected = set(self._reopened)
        if self._active is not None:
            protected.update(self._active.dependency_segment_ids)
        if self._leading_partial is not None:
            protected.add(self._leading_partial[0])
        if self._interrupted is not None:
            protected.add(self._interrupted[0])
            protected.update(self._interrupted[1].dependency_segment_ids)
        while len(self._seen) > MAX_SEEN_SEGMENTS:
            evicted = next((
                sid for sid in self._seen if sid not in protected
            ), None)
            if evicted is None:
                # Too many simultaneously protected pieces cannot be safely
                # represented in bounded memory; never relax the limit.
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                self._blocked_generation = self._remote_generation
                self._seen.clear()
                self._reopened.clear()
                self._leading_partial = None
                raise InvalidTranscript("Active ASR segment capacity exceeded.")
            del self._seen[evicted]

    def ingest(self, event: TranscriptEvent) -> TurnDecision:
        """Ready means a tentative, complete remote question can be routed.

        It does not establish speaker identity, actual authorization,
        correctness, or permission to skip later deterministic answer QA.
        """
        _validate(event)
        if event.source_channel != "remote":
            return TurnDecision("ignored", "not_confirmed_remote_source")
        with self._lock:
            if self._stopped:
                return TurnDecision("ignored", "stopped_until_explicit_resume")
            if (self._remote_generation is not None
                    and event.stream_generation < self._remote_generation):
                return TurnDecision("ignored", "stale_stream_generation")
            if (self._remote_generation is None
                    or event.stream_generation > self._remote_generation):
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                self._seen.clear()
                self._reopened.clear()
                self._leading_partial = None
                self._invalidated_pending_id = None
                self._last_final_end = -1
                self._latest_question_start_ms = -1
                self._remote_generation = event.stream_generation
                self._blocked_generation = None
            if self._blocked_generation == event.stream_generation:
                return TurnDecision("ignored", "stream_generation_stopped")
            if event.status == "discontinuity":
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                self._seen.clear()
                self._reopened.clear()
                self._leading_partial = None
                self._invalidated_pending_id = None
                self._blocked_generation = event.stream_generation
                return TurnDecision("cancelled", "asr_discontinuity")

            # An unfinished correction whose original support was retracted
            # cannot be promoted by a later final of that pending segment.
            if self._invalidated_pending_id == event.segment_id:
                if event.status == "final":
                    # Retain the disqualified segment ID so replaying this
                    # same final cannot resurrect its revoked context.
                    self._last_final_end = max(self._last_final_end, event.end_ms)
                    return TurnDecision("needs_review", "pending_context_retracted")
                if event.status in ("partial", "retracted"):
                    return TurnDecision("ignored", "pending_context_retracted")
            interrupted_dep = (
                self._interrupted is not None and event.status == "retracted"
                and event.segment_id in
                self._interrupted[1].dependency_segment_ids
            )
            # An unclassified final inside the active question's source-time
            # interval cannot be dismissed as an old harmless finalized
            # segment just because its end precedes the question end.
            if (event.status == "final" and event.intent == "unknown"
                    and self._active is not None
                    and event.segment_id != self._active.current_segment_id
                    and event.start_ms < self._active.end_ms
                    and event.end_ms > self._active.start_ms):
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                return TurnDecision("needs_review", "unclassified_overlapping_remote_utterance")
            # Until the newest tentative question finishes, an older
            # finalized segment must not regain authority merely because no
            # other *final* advanced the timestamp watermark yet.
            if (self._leading_partial is not None
                    and event.segment_id != self._leading_partial[0]
                    and event.status in ("final", "retracted")
                    and not interrupted_dep):
                leader = self._leading_partial
                if event.status == "final" and event.start_ms >= leader[2]:
                    # A complete, independently newer utterance can replace
                    # an unfinished tentative one without waiting forever.
                    self._leading_partial = None
                    self._interrupted = None
                elif event.status == "final" and event.start_ms > leader[1]:
                    # Distinct voices/segments may overlap in one remote
                    # channel; require confirmation instead of guessing.
                    self.turns.cancel()
                    self._active = None
                    self._interrupted = None
                    return TurnDecision("needs_review", "overlapping_pending_utterances")
                else:
                    return TurnDecision("ignored", "superseded_by_newer_partial")
            # Transcript finals can arrive out of order. Even if an
            # abandoned partial A's eventual final extends beyond the end
            # time of the newer accepted B, A's *start* still predates B.
            # Exempt the currently active, leading or reopened segment
            # because its ASR may revise its original timestamps.
            remembered_start = self._seen.get(event.segment_id)
            effective_start_ms = (
                min(event.start_ms, remembered_start.first_start_ms)
                if remembered_start is not None else event.start_ms
            )
            if (event.status == "final"
                    and effective_start_ms < self._latest_question_start_ms
                    and event.segment_id not in self._reopened
                    and (self._leading_partial is None
                         or self._leading_partial[0] != event.segment_id)
                    and (self._active is None
                         or self._active.current_segment_id != event.segment_id)):
                remembered = self._seen.get(event.segment_id)
                if remembered is not None and remembered.status == "final":
                    return TurnDecision("ignored", "superseded_segment_revision")
                if event.end_ms <= self._last_final_end:
                    return TurnDecision("ignored", "late_final_after_newer_utterance")
                return TurnDecision("ignored", "superseded_source_start")
            digest = _fingerprint(event)
            prior = self._seen.get(event.segment_id)
            if prior is not None:
                if event.revision < prior.revision:
                    return TurnDecision("ignored", "older_segment_revision")
                if event.revision == prior.revision:
                    if prior.fingerprint == digest:
                        return TurnDecision("ignored", "duplicate_segment")
                    if not (prior.status == "partial" and event.status == "final"):
                        self.turns.cancel()
                        self._active = None
                        self._interrupted = None
                        self._reopened.clear()
                        self._leading_partial = None
                        self._blocked_generation = event.stream_generation
                        return TurnDecision("conflict", "conflicting_segment_revision")
                if prior.status == "final" and event.status == "partial":
                    if (self._active is None or
                            self._active.current_segment_id != event.segment_id):
                        return TurnDecision("ignored", "superseded_segment_revision")
                    # A higher revision reopening a finalized segment is
                    # tentative but makes the prior completed answer unsafe.
                    self.turns.cancel()
                    self._active = None
                    self._interrupted = None
                    self._remember(event, digest)
                    self._reopened.add(event.segment_id)
                    return TurnDecision("pending", "final_reopened_as_partial")
            if event.status == "retracted":
                # An unrelated old segment must never erase a current
                # revision's quarantine, including when _active is None
                # while a finalized segment is being reopened.
                current_dependency = (
                    self._active is not None and event.segment_id in
                    self._active.dependency_segment_ids
                )
                leading_dependency = (
                    self._leading_partial is not None and
                    event.segment_id == self._leading_partial[0]
                )
                if not (current_dependency or interrupted_dep
                        or leading_dependency or
                        event.segment_id in self._reopened):
                    return TurnDecision("ignored", "superseded_segment_retraction")
                if interrupted_dep and self._leading_partial is not None:
                    self._invalidated_pending_id = self._leading_partial[0]
                self._remember(event, digest)
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                self._reopened.clear()
                self._leading_partial = None
                # A segment retraction is NOT an ASR stream discontinuity:
                # new unrelated questions in the same generation remain valid.
                return TurnDecision("cancelled", "transcript_retracted")
            if event.status == "partial":
                # Ignore a delayed update to an older partial after a newer
                # tentative remote question has taken priority.
                if (self._leading_partial is not None
                        and event.segment_id != self._leading_partial[0]
                        and event.start_ms < self._leading_partial[1]):
                    return TurnDecision("ignored", "superseded_partial_revision")
                self._remember(event, digest)
                # A new tentative question/correction invalidates in-flight
                # answers immediately, before any of its partial text is used.
                if event.intent in ("question", "correction", "follow_up"):
                    if (self._leading_partial is not None
                            and self._leading_partial[0] != event.segment_id
                            and self._interrupted is not None
                            and event.intent in ("correction", "follow_up")):
                        self._interrupted = (event.segment_id, self._interrupted[1])
                    # Timestamp revisions cannot advance a segment's
                    # original leading time. Preserve the first observed end
                    # too, so an older corrected partial cannot suppress a
                    # clearly newer complete question after its initial end.
                    old_cursor = self._leading_partial
                    seen = self._seen[event.segment_id]
                    first_start = seen.first_start_ms
                    first_end = (
                        old_cursor[2] if old_cursor is not None and
                        old_cursor[0] == event.segment_id else event.end_ms
                    )
                    self._leading_partial = (
                        event.segment_id, first_start, first_end
                    )
                    self._latest_question_start_ms = max(
                        self._latest_question_start_ms, first_start
                    )
                    if event.intent == "question":
                        self._interrupted = None
                    if self._active is not None:
                        self._interrupted = (
                            (event.segment_id, self._active)
                            if event.intent in ("correction", "follow_up")
                            else None
                        )
                        self.turns.cancel()
                        self._active = None
                return TurnDecision("pending", "partial_text_not_authoritative")
            if (self._leading_partial is not None
                    and event.segment_id == self._leading_partial[0]):
                self._leading_partial = None
            # Partial events also have a ledger entry: a later-arriving final
            # from that older partial must not become current after newer
            # accepted questions. The replay hash alone is not ordering.
            if (event.end_ms <= self._last_final_end
                    and event.segment_id not in self._reopened
                    and (prior is None or prior.status != "final")):
                self._reopened.discard(event.segment_id)
                return TurnDecision("ignored", "late_final_after_newer_utterance")
            if event.segment_id in self._reopened:
                self._reopened.discard(event.segment_id)
                self._remember(event, digest)
                self._last_final_end = max(self._last_final_end, event.end_ms)
                if self._active is not None:
                    return TurnDecision("ignored", "superseded_segment_revision")
                # A previously finalized transcript was reopened. Don't
                # silently re-authorize it on new words or guessed intent.
                return TurnDecision("needs_review", "final_transcript_revised")
            # Two different remote speakers can overlap in the same output
            # channel. A new question/follow-up whose source time overlaps
            # the prior finalized utterance is not safely ordered. Corrections
            # are allowed to interrupt explicitly, but unqualified questions
            # require review rather than silently changing the active turn.
            if (event.start_ms < self._last_final_end
                    and event.intent in ("question", "follow_up")
                    and (prior is None or prior.status != "final")):
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                self._remember(event, digest)
                self._last_final_end = max(self._last_final_end, event.end_ms)
                return TurnDecision("needs_review", "overlapping_remote_utterances")
            if prior is not None and prior.status == "final":
                if (self._active is None or
                        self._active.current_segment_id != event.segment_id):
                    return TurnDecision("ignored", "superseded_segment_revision")
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                self._remember(event, digest)
                self._last_final_end = max(self._last_final_end, event.end_ms)
                return TurnDecision("needs_review", "final_transcript_revised")

            self._remember(event, digest)
            self._last_final_end = max(self._last_final_end, event.end_ms)
            if event.intent not in ("question", "correction", "follow_up"):
                self._interrupted = None
                if event.intent == "unknown" and self._active is not None:
                    # An unclassified completed remote utterance may alter
                    # the previous question; keep it out of live display
                    # rather than allow an unreviewed stale answer to win.
                    self.turns.cancel()
                    self._active = None
                    return TurnDecision("needs_review", "unclassified_remote_utterance")
                return TurnDecision("ignored", "no_explicit_question_intent")
            if (event.confidence is not None
                    and event.confidence < MIN_QUESTION_CONFIDENCE):
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                return TurnDecision("needs_review", "low_asr_confidence")
            previous = self._active if (
                self._active is not None and self.turns.is_current(self._active.token)
            ) else None
            if (previous is None and self._interrupted is not None
                    and self._interrupted[0] == event.segment_id
                    and event.intent in ("correction", "follow_up")):
                previous = self._interrupted[1]
            self._interrupted = None
            if event.intent == "follow_up" and previous is None:
                return TurnDecision("needs_review", "orphan_follow_up")
            if event.intent == "correction" and previous is None:
                if not _STANDALONE_RESTART.search(event.text.strip()):
                    return TurnDecision("needs_review", "orphan_correction_fragment")

            if event.intent == "question" or previous is None:
                logical_id = "remote:{}:{}".format(event.stream_generation, event.segment_id)
                next_version = 1
                root_text = event.text.strip()
                root_segment = event.segment_id
                reference = None
            else:
                logical_id = previous.token.turn_id
                next_version = previous.token.version + 1
                root_text = previous.root_question
                root_segment = previous.root_segment_id
                reference = previous.current_utterance
            current_text = event.text.strip()
            root_context = root_text if reference is not None else None
            prompt = _prompt(event.intent, current_text, reference, root_context)
            if len(prompt) > MAX_CONTEXT_CHARS:
                self.turns.cancel()
                self._active = None
                return TurnDecision("needs_review", "turn_context_too_long")
            dependencies = (
                tuple(dict.fromkeys((*previous.dependency_segment_ids,
                                     event.segment_id)))
                if (previous is not None and
                    event.intent in ("correction", "follow_up"))
                else (event.segment_id,)
            )
            if len(dependencies) > MAX_DEPENDENT_SEGMENTS:
                self.turns.cancel()
                self._active = None
                self._interrupted = None
                return TurnDecision("needs_review", "correction_chain_too_long")
            token = self.turns.activate(logical_id, next_version)
            snapshot = QuestionSnapshot(
                token=token, source_channel="remote",
                stream_generation=event.stream_generation,
                root_segment_id=root_segment, current_segment_id=event.segment_id,
                root_question=root_text, current_utterance=current_text,
                prompt=prompt, parts_hint=_parts_hint(current_text),
                parts_are_heuristic=True,
                dependency_segment_ids=dependencies,
                start_ms=event.start_ms, end_ms=event.end_ms,
            )
            self._active = snapshot
            self._latest_question_start_ms = max(
                self._latest_question_start_ms, event.start_ms
            )
            return TurnDecision("ready", "final_remote_question", snapshot)
