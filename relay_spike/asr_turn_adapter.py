"""03B-B0: synthetic finalized local ASR -> tentative question-turn adapter.

No FluidAudio import, microphone access, model inference, persisted transcript,
remote calls, or claim of real permission proof. Only the native host can
supply channel provenance and verified permission state in a later slice.
FluidAudio StreamingEouAsrManager does NOT produce textual partials through
process(audioBuffer:); output is finalized only after EOU/finish().
"""
from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
import re
from threading import Lock
from typing import Literal

from .correction_grammar import CORRECTION_PREFIX as _CORRECTION
from .question_turns import (
    MIN_QUESTION_CONFIDENCE,
    MAX_EVENT_CHARS,
    MAX_EVENT_INTEGER,
    QuestionTurnMachine,
    TranscriptEvent,
    TurnDecision,
)

Channel = Literal["remote", "microphone", "unknown"]
ASRStage = Literal[
    "processing", "final", "silence", "failed", "cancelled", "discontinuity"
]
Authorization = Literal["authorized", "unknown", "denied", "revoked"]
IntentLabel = Literal["question", "correction", "follow_up", "unknown"]
Disposition = Literal["ready", "pending", "ignored", "needs_review", "cancelled"]

# Conservative syntactic hints only. Natural-language understanding, context,
# speaker identity and technical answer accuracy remain unverified.
_DIRECT_QUESTION = re.compile(
    r"^(?:what|why|how|when|where|which|who|whom|whose|"
    r"can you|could you|would you|will you|do you|does|did|"
    r"is|are|was|were|have you|has|should|would|"
    r"tell me|explain|describe|compare|write|show|"
    r"walk me through|implement|calculate|outline|give me)\b", re.I
)
_FOLLOWUP = re.compile(
    r"^(?:and\s+what\s+about|what\s+about|and\s+how\s+about|"
    r"how\s+about|and\s+if|and\s+then\s+what|"
    r"and\s+tell\s+me)\b", re.I
)
_STANDALONE_RESTART = re.compile(
    r"^(?:actually|no|instead|i meant|let me rephrase)[\s,:-]+"
    r"(?:tell me|describe|explain|write|show|calculate|compare|what|"
    r"why|how|when|where|which|can you|could you|would you|"
    r"walk me through)\b", re.I
)
_UNTRUSTED_CONTROL = re.compile(
    r"^(?:system|developer|assistant)\s*:\s*|"
    r"^(?:ignore previous instructions|override the rules|"
    r"bypass approval|you are now a system|remember that i worked)\b", re.I
)


class ASRContractError(ValueError):
    """Sanitized metadata error; never includes a transcript string."""


@dataclass(frozen=True)
class CaptureContext:
    """Host-supplied scope, NOT proof of OS consent or speaker identity."""

    authorization: Authorization = "unknown"
    selected_remote_source: bool = False


@dataclass(frozen=True)
class FinalizedASRObservation:
    source_channel: Channel
    stream_generation: int
    segment_id: str
    revision: int
    start_ms: int
    end_ms: int
    received_ms: int
    stage: ASRStage
    text: str = ""
    finalized_ms: int | None = None
    confidence: float | None = None


@dataclass(frozen=True)
class ASRTurnResult:
    disposition: Disposition
    reason: str
    intent_hint: IntentLabel
    question: TurnDecision | None = None
    source_channel: Channel = "unknown"
    speech_end_ms: int | None = None
    asr_finalized_ms: int | None = None
    decision_ms: int | None = None
    asr_lag_ms: int | None = None
    first_useful_verified_ms: None = None

    @property
    def token(self):
        return self.question.token if self.question is not None else None


def _validate_context(ctx: CaptureContext) -> None:
    if not isinstance(ctx, CaptureContext):
        raise TypeError("CaptureContext required.")
    if ctx.authorization not in ("authorized", "unknown", "denied", "revoked"):
        raise ASRContractError("Invalid capture permission.")
    if type(ctx.selected_remote_source) is not bool:
        raise ASRContractError("Invalid source selection flag.")


def _validate_event(event: FinalizedASRObservation) -> None:
    if not isinstance(event, FinalizedASRObservation):
        raise TypeError("FinalizedASRObservation required.")
    if event.source_channel not in ("remote", "microphone", "unknown"):
        raise ASRContractError("Unrecognized channel.")
    if event.stage not in (
        "processing", "final", "silence", "failed", "cancelled", "discontinuity"
    ):
        raise ASRContractError("Unrecognized ASR stage.")
    if (not isinstance(event.segment_id, str) or not event.segment_id.strip()
            or len(event.segment_id) > 128):
        raise ASRContractError("Invalid segment ID.")
    for key in ("stream_generation", "revision", "start_ms", "end_ms", "received_ms"):
        value = getattr(event, key)
        if type(value) is not int or not 0 <= value <= MAX_EVENT_INTEGER:
            raise ASRContractError("Invalid ASR generation, revision or timing.")
    if not event.start_ms <= event.end_ms <= event.received_ms:
        raise ASRContractError("Invalid ASR time ordering.")
    if event.finalized_ms is not None:
        if (type(event.finalized_ms) is not int
                or not 0 <= event.finalized_ms <= MAX_EVENT_INTEGER
                or not event.end_ms <= event.finalized_ms <= event.received_ms):
            raise ASRContractError("Invalid finalization timestamp.")
    if not isinstance(event.text, str) or len(event.text) > MAX_EVENT_CHARS:
        raise ASRContractError("Invalid or oversized ASR text.")
    if "\x00" in event.text:
        raise ASRContractError("Invalid control byte in ASR text.")
    try:
        event.segment_id.encode("utf-8")
        event.text.encode("utf-8")
    except UnicodeEncodeError:
        raise ASRContractError("Invalid UTF-8 ASR text.") from None
    if event.stage == "final" and event.finalized_ms is None:
        raise ASRContractError("No EOU finalization proof.")
    if (event.stage == "final" and event.text.strip()
            and event.start_ms == event.end_ms):
        # A native uptime-to-ms conversion may collapse real submillisecond
        # audio timing. Fail closed rather than declaring stale speech safe.
        # Blank finals remain valid terminal invalidations.
        raise ASRContractError("Zero-duration final ASR text.")
    if event.stage != "final" and (event.text or event.finalized_ms is not None):
        raise ASRContractError("Non-final ASR stage cannot carry finalized text.")
    if event.confidence is not None:
        if (type(event.confidence) not in (int, float)
                or not 0 <= event.confidence <= 1):
            raise ASRContractError("Invalid ASR confidence.")


def classify_question_intent(
    utterance: str, *, has_current_question: bool
) -> IntentLabel:
    """Surface-only intent hints, not a semantic classifier or permission grant."""
    if type(has_current_question) is not bool or not isinstance(utterance, str):
        raise ASRContractError("Invalid classifier inputs.")
    text = " ".join(utterance.split()).strip()
    if not text or len(text) > MAX_EVENT_CHARS or _UNTRUSTED_CONTROL.search(text):
        return "unknown"
    if _FOLLOWUP.match(text):
        return "follow_up" if has_current_question else "unknown"
    if _CORRECTION.match(text):
        correction_tail = text[_CORRECTION.match(text).end():].strip(" \t,.:!?")
        words = correction_tail.split()
        if (has_current_question and
                (len(words) >= 2 or
                 (_CORRECTION.match(text).group(0).lower().startswith("make that")
                  and len(words) == 1))):
            return "correction"
        # A completely restarted question can stand on its own; a fragment
        # such as "No, by orders in 2025" cannot.
        return "correction" if _STANDALONE_RESTART.match(text) else "unknown"
    return "question" if _DIRECT_QUESTION.match(text) else "unknown"


class SyntheticEOUBridge:
    """Offline-only EOU bridge. The host owns authorization and source labels.

    It never generates a text partial. It also never triggers a model request.
    A ready result is only a tentative turn handoff, subject to existing QA.
    """

    def __init__(self, machine: QuestionTurnMachine, *, eligibility_strategy=None) -> None:
        if not isinstance(machine, QuestionTurnMachine):
            raise TypeError("QuestionTurnMachine required.")
        self.machine = machine
        self._eligibility_strategy = eligibility_strategy
        self._lock = Lock()
        # Blank final identity is a bounded tombstone, not a transcript.
        self._blank_finals: OrderedDict[tuple[int, str], tuple[int, int, int]] = OrderedDict()
        self._latest_generation: int | None = None
        self._retired_generation: int | None = None
        self._awaiting_host_resume = False
        # Protect old blank EOU identities after the bounded replay ledger
        # evicts them. Any older/equal source start needs review, not routing.
        self._evicted_blank_end_ms = -1

    def stop(self) -> None:
        with self._lock:
            self._awaiting_host_resume = True
            if self._latest_generation is not None:
                self._retired_generation = max(
                    self._latest_generation,
                    self._retired_generation if self._retired_generation is not None else -1,
                )
            self.machine.cancel()

    def resume_after_host_authorization(self, ctx: CaptureContext) -> None:
        _validate_context(ctx)
        if ctx.authorization != "authorized" or not ctx.selected_remote_source:
            raise ASRContractError("Explicit permitted selected source required.")
        with self._lock:
            # The host must provide an incremented ASR generation after a
            # permission-stop. Python never attests actual macOS permission.
            self.machine.resume()
            self._awaiting_host_resume = False
            self._blank_finals.clear()

    def ingest(
        self, event: FinalizedASRObservation, *,
        context: CaptureContext,
    ) -> ASRTurnResult:
        with self._lock:
            return self._ingest_locked(event, context=context)

    def _ingest_locked(
        self, event: FinalizedASRObservation, *,
        context: CaptureContext,
    ) -> ASRTurnResult:
        try:
            _validate_event(event)
            _validate_context(context)
        except (ASRContractError, TypeError):
            # A malformed selected-remote EOU/control event must not leave
            # an older answer publishable. Stop the bridge and require
            # renewed host authorization with a fresh stream generation.
            if (isinstance(event, FinalizedASRObservation)
                    and event.source_channel == "remote"):
                self._retired_generation = max(
                    self._latest_generation if self._latest_generation is not None else -1,
                    self._retired_generation if self._retired_generation is not None else -1,
                    event.stream_generation if (
                        type(event.stream_generation) is int and
                        0 <= event.stream_generation <= MAX_EVENT_INTEGER
                    ) else -1,
                )
                self.machine.cancel()
                self._awaiting_host_resume = True
            raise

        def result(
            state: Disposition, reason: str, intent: IntentLabel = "unknown",
            turn: TurnDecision | None = None,
        ) -> ASRTurnResult:
            finalized = event.finalized_ms if event.stage == "final" else None
            return ASRTurnResult(
                disposition=state, reason=reason, intent_hint=intent,
                question=turn, source_channel=event.source_channel,
                speech_end_ms=event.end_ms,
                asr_finalized_ms=finalized,
                decision_ms=event.received_ms if finalized is not None else None,
                asr_lag_ms=(finalized - event.end_ms if finalized is not None else None),
            )

        if context.authorization != "authorized":
            # Retire the *observed* stream, even if it was newer than any
            # previously trusted audio generation. Replaying that data after
            # a new permission grant must never create a question.
            self._retired_generation = max(
                event.stream_generation,
                self._latest_generation if self._latest_generation is not None else -1,
                self._retired_generation if self._retired_generation is not None else -1,
            )
            self.machine.cancel()
            self._awaiting_host_resume = True
            return result("cancelled", "capture_permission_not_established")
        if not context.selected_remote_source:
            self._retired_generation = max(
                event.stream_generation,
                self._latest_generation if self._latest_generation is not None else -1,
                self._retired_generation if self._retired_generation is not None else -1,
            )
            self.machine.cancel()
            self._awaiting_host_resume = True
            return result("cancelled", "no_explicit_remote_source")

        if event.source_channel != "remote":
            # Separate mic channels do not identify the interviewer.
            return result("ignored", "not_confirmed_remote_channel")
        if self._awaiting_host_resume:
            # Event delivery can continue after permission loss. Do not
            # update trusted generation or allow pre-resume audio to replay.
            self._retired_generation = max(
                event.stream_generation,
                self._retired_generation if self._retired_generation is not None else -1,
            )
            earlier_blank = self._blank_finals.get(
                (event.stream_generation, event.segment_id)
            )
            if (event.stage == "final" and earlier_blank is not None
                    and (bool(event.text.strip()) or
                         (event.revision, event.start_ms, event.end_ms)
                         != earlier_blank)):
                # Quarantine blocks routing, but does not turn contradictory
                # terminal evidence into an ordinary ignored replay. Keep the
                # review signal without restarting or retaining turn context.
                return result("needs_review", "final_conflicts_with_blank_eou")
            return result("ignored", "stopped_until_explicit_resume")
        if (self._retired_generation is not None
                and event.stream_generation <= self._retired_generation):
            return result("ignored", "generation_retired_after_stop")
        if (self._latest_generation is not None
                and event.stream_generation < self._latest_generation):
            return result("ignored", "stale_asr_generation")
        if (self._latest_generation is None
                or event.stream_generation > self._latest_generation):
            # Even a new generation containing only silence/unavailable
            # events must revoke the prior ActiveTurns token before the
            # event-specific early returns below. The bridge and machine
            # generation ledgers must never diverge.
            if not self.machine.accept_remote_generation(event.stream_generation):
                self.machine.cancel()
                self._awaiting_host_resume = True
                self._retired_generation = max(
                    event.stream_generation,
                    self._retired_generation
                    if self._retired_generation is not None else -1,
                )
                return result("cancelled", "remote_machine_requires_resume")
            self._latest_generation = event.stream_generation
            self._blank_finals.clear()
            self._evicted_blank_end_ms = -1

        if (event.stage in ("final", "processing")
                and self._evicted_blank_end_ms >= 0):
            # Without a trusted monotonic segment-number attestation, an
            # evicted blank terminal's revised timestamps could appear new.
            # After 128 blanks, stop routing the entire current generation;
            # require a new generation for unambiguous question detection.
            self.machine.turns.cancel()
            return result("needs_review", "blank_terminal_history_exhausted")

        if event.stage == "processing":
            # This must represent an explicit, trusted capture/VAD speech-onset
            # signal, NOT a synthesized partial from FluidAudio's empty
            # process(audioBuffer:) textual output.
            started = self.machine.remote_speech_started(
                stream_generation=event.stream_generation,
                segment_id=event.segment_id,
                start_ms=event.start_ms,
                end_ms=event.end_ms,
            )
            if started.state == "pending":
                return result("pending", "waiting_for_eou_final",
                              turn=started)
            if started.state == "needs_review":
                return result("needs_review", started.reason, turn=started)
            return result("ignored", started.reason, turn=started)
        if event.stage == "silence":
            return result("ignored", "no_speech_finalized")
        if event.stage in ("failed", "cancelled", "discontinuity"):
            self.machine.ingest(TranscriptEvent(
                source_channel="remote",
                stream_generation=event.stream_generation,
                segment_id=event.segment_id, revision=event.revision,
                start_ms=event.start_ms, end_ms=event.end_ms,
                status="discontinuity", intent="unknown", text="",
            ))
            return result("cancelled", "remote_asr_discontinuity")
        blank_key = (event.stream_generation, event.segment_id)
        earlier_blank = self._blank_finals.get(blank_key)
        if earlier_blank is not None:
            revision, start_ms, end_ms = earlier_blank
            if (event.revision == revision and not event.text.strip()
                    and event.start_ms == start_ms and event.end_ms == end_ms):
                return result("ignored", "duplicate_blank_final")
            # A blank EOU is terminal, not a missing partial. A subsequent
            # contradiction must clear the ENTIRE shared machine context,
            # not just revoke ActiveTurns: otherwise an interrupted question
            # snapshot could be reused by the next EOU final as a correction.
            # Require a new explicitly authorized host capture generation.
            self.machine.cancel()
            self._retired_generation = max(
                event.stream_generation,
                self._latest_generation if self._latest_generation is not None else -1,
                self._retired_generation if self._retired_generation is not None else -1,
            )
            self._awaiting_host_resume = True
            return result("needs_review", "final_conflicts_with_blank_eou")
        if not event.text.strip():
            self._blank_finals[blank_key] = (
                event.revision, event.start_ms, event.end_ms
            )
            self._blank_finals.move_to_end(blank_key)
            if len(self._blank_finals) > 128:
                _, (_, _, retired_end_ms) = self._blank_finals.popitem(last=False)
                self._evicted_blank_end_ms = max(
                    self._evicted_blank_end_ms, retired_end_ms
                )
            # New utterance with no recognized words may have changed the
            # question. Invalidate old answers but invent no transcript.
            terminated = self.machine.remote_unrecognized_final(
                stream_generation=event.stream_generation,
                segment_id=event.segment_id,
                start_ms=event.start_ms,
                end_ms=event.end_ms,
            )
            return result("needs_review", "empty_eou_final", turn=terminated)

        active = (self.machine.current() is not None or
                  self.machine.has_pending_question_context(event.segment_id))
        intent = classify_question_intent(
            event.text, has_current_question=active
        )

        if self._eligibility_strategy is not None:
            # Optional host policy runs only AFTER all existing source, finality,
            # replay, tombstone and lifecycle guards. It never invents confidence.
            intent = self._eligibility_strategy.assess(event, has_current_question=active)
            if intent not in ("question", "follow_up", "correction", "unknown"):
                raise ASRContractError("Invalid eligibility decision.")
            reason = "confidence_free_contextual_intent"
        elif event.confidence is None:
            # The upstream EOU API may not provide a calibrated score. Do not
            # assign a fictitious value or silently mark it trustworthy.
            intent = "unknown"
            reason = "asr_confidence_unavailable"
        elif event.confidence < MIN_QUESTION_CONFIDENCE:
            intent = "unknown"
            reason = "low_asr_confidence"
        else:
            reason = "tentative_syntactic_intent"

        # Passing "unknown" is deliberately useful: the existing turn machine
        # can quarantine an active question after unclassified remote speech.
        routed = self.machine.ingest(TranscriptEvent(
            source_channel="remote",
            stream_generation=event.stream_generation,
            segment_id=event.segment_id, revision=event.revision,
            start_ms=event.start_ms, end_ms=event.end_ms,
            status="final", intent=intent, text=event.text,
            confidence=event.confidence,
        ))
        if routed.state == "ready":
            return result("ready", "tentative_final_remote_question", intent, routed)
        if routed.state in ("cancelled", "conflict"):
            return result("cancelled", routed.reason, intent, routed)
        if routed.state == "ignored":
            if routed.reason == "no_explicit_question_intent":
                return result("needs_review", (
                    reason if reason != "tentative_syntactic_intent"
                    else "unclassified_remote_speech"
                ), "unknown", routed)
            # An older generation or a replay must not reopen a previously
            # handled question or become a new human-review request.
            return result("ignored", routed.reason, intent, routed)
        return result("needs_review", (
            (reason if reason != "tentative_syntactic_intent"
             else "unclassified_remote_speech")
            if intent == "unknown" else routed.reason
        ), intent, routed)
