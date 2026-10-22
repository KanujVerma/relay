"""Slice 01B-B1: synthetic SSE-to-QA integration with safe publish semantics.

There is NO model call, OAuth, audio, UI, retention, or online source import here.
Only a complete response can produce a final, *not fact-certified*, answer.
Potentially scannable partial text is timed but NEVER exposed to a callback.
"""
from __future__ import annotations

from dataclasses import dataclass
import re
from threading import Lock
import time
from typing import Callable, Iterable, Literal

from .benchmark import load_cases
from .qa import CoverageIndicator, QAInput, QAResult, FIRST_PERSON_WORK_CLAIM, assess
from .stream import StreamError, consume_stream

# These are synthetic fixture-specific hints, not universal semantic rubrics.
_CASE_RISKS: dict[str, tuple[str, ...]] = {
    "D01": ("join_fanout",),
    "D13": ("ranking_ties",),
    "E09": ("sorted_input",),
    "E04": ("hash_collision",),
    "D07": ("optimizer_variance",),
    "E11": ("interrupted_question",),
    "D12": ("interrupted_question",),
}
_CASE_COVERAGE: dict[str, tuple[CoverageIndicator, ...]] = {
    "E04": (
        CoverageIndicator("hash_table", ("hash table", "hash map", "hashmap")),
        CoverageIndicator("collisions", ("collision", "collisions", "chaining", "probing")),
        CoverageIndicator("worst_case", ("worst-case", "worst case", "O(n)")),
    ),
    "D07": (
        CoverageIndicator("CTE", ("CTE", "common table expression")),
        CoverageIndicator("subquery", ("subquery", "nested query")),
        CoverageIndicator("performance", ("performance", "optimizer", "execution plan", "speed")),
    ),
}
ALLOWED_MODELS = ("gpt-6-luna", "gpt-6.1-sol")


@dataclass(frozen=True)
class TurnToken:
    turn_id: str
    version: int
    generation: int


class ActiveTurns:
    """Thread-safe active identity; generation prevents ID/version reuse (ABA).

    A publication callback must commit its synchronous UI change directly; it
    must not re-enter the coordinator or defer publication to a separate queue.
    Queued UI updates must independently compare the attached TurnToken.
    """

    def __init__(self) -> None:
        self._lock = Lock()
        self._generation = 0
        self._current: TurnToken | None = None

    def activate(self, turn_id: str, version: int) -> TurnToken:
        if not isinstance(turn_id, str) or not turn_id.strip():
            raise ValueError("Nonempty turn ID required.")
        if type(version) is not int or version < 0:
            raise ValueError("Nonnegative integer turn version required.")
        with self._lock:
            self._generation += 1
            self._current = TurnToken(turn_id, version, self._generation)
            return self._current

    def current(self) -> TurnToken | None:
        with self._lock:
            return self._current

    def is_current(self, token: TurnToken) -> bool:
        with self._lock:
            return self._current == token

    def _publish_if_current(self, token: TurnToken,
                            callback: Callable[[], None]) -> bool:
        # Atomic with respect to activate(). Keep callbacks synchronous/cheap.
        with self._lock:
            if self._current != token:
                return False
            callback()
            return True


@dataclass(frozen=True)
class SyntheticContext:
    """Caller-supplied synthetic evaluation metadata.

    The attribution classification MUST come from a trusted independent
    process, never blindly from model output or a prompt. Default uncertain
    fails the QA gate. This slice does NOT implement that trusted classifier.
    """

    case_id: str
    attribution: Literal["absent", "present", "uncertain"] = "uncertain"
    verified_source_ids: tuple[str, ...] = ()


@dataclass(frozen=True)
class ModelPolicy:
    """Editable *development* preference, NOT automatic model inference."""

    preferred_model: str = "gpt-6-luna"
    review_candidate: str = "gpt-6.1-sol"
    requested_effort: str = "default"  # Omitted from wire, Medium observed locally.

    def __post_init__(self) -> None:
        if (self.preferred_model not in ALLOWED_MODELS or
                self.review_candidate not in ALLOWED_MODELS or
                self.requested_effort not in ("default", "low", "medium")):
            raise ValueError("Only tested development model/effort choices are allowed.")

    def choose(self, override: str | None = None) -> str:
        chosen = override if override is not None else self.preferred_model
        if chosen not in ALLOWED_MODELS:
            raise ValueError("Unverified development model.")
        return chosen

    def review_suggestion(self, result: QAResult | None) -> str | None:
        # Signal only: never triggers another model request.
        return self.review_candidate if (
            result is not None and result.second_review_recommended
        ) else None


@dataclass(frozen=True)
class StreamAssessment:
    token: TurnToken
    case_id: str
    answer: str | None
    completed: bool
    qa: QAResult | None
    first_text_ms: int | None
    first_scannable_candidate_ms: int | None
    completed_ms: int | None
    qa_decided_ms: int | None
    started: float
    error_code: Literal["stream_error", "superseded_turn"] | None = None

    # Genuine answer usefulness is not objectively determined in this slice.
    # First scannable is a *heuristic* timestamp, never a quality certificate.


@dataclass(frozen=True)
class Presentation:
    token: TurnToken
    case_id: str
    state: Literal["final_unverified", "needs_revision", "unavailable", "suppressed"]
    text: str | None
    reasons: tuple[str, ...]
    presented_ms: int | None
    first_text_ms: int | None
    first_scannable_candidate_ms: int | None
    first_useful_verified_ms: None  # Requires human/independent correctness review.
    stream_completed: bool
    review_candidate: str | None
    review_executed: bool = False


def _ms(now: float, started: float) -> int:
    return max(0, round(1000 * (now - started)))


def _scannable_prefix(buffer: str, *, category: str, attribution: str) -> bool:
    """Weak presentation heuristic. It never publishes text or proves utility.

    Suppress provisional timestamps entirely for personal/behavioral,
    interrupted or unclassified output. An early code fence or a table also
    isn't a direct talking point.
    """
    if attribution != "absent" or category in ("personal", "behavioral", "interruption"):
        return False
    trimmed = buffer.lstrip()
    if not trimmed or trimmed.startswith(chr(96) * 3):
        return False
    if FIRST_PERSON_WORK_CLAIM.search(trimmed):
        return False
    first_line = trimmed.splitlines()[0].strip()
    if not first_line or "|" in first_line:
        return False
    # Only a finished, reasonably short lead sentence counts as a candidate.
    match = re.match(r"^(.+?[.!?])(?:\s|$)", first_line)
    if not match:
        return False
    lead = match.group(1)
    words = len(re.findall(r"\b[\w'-]+\b", lead))
    return 8 <= words <= 75


def _fixture_spec(case_id: str) -> dict:
    # Only known, reviewed synthetic EVALS fixtures, never a supplied prompt.
    return load_cases((case_id,))[0]


def assess_synthetic_stream(
    byte_lines: Iterable[bytes | str], *,
    turns: ActiveTurns,
    token: TurnToken,
    context: SyntheticContext,
    clock: Callable[[], float] = time.monotonic,
) -> StreamAssessment:
    """Collect a mock/authorized-caller-provided SSE iterator and apply B0 QA.

    No previews or responses are displayed here. No network request is made.
    """
    if not isinstance(turns, ActiveTurns) or not isinstance(token, TurnToken):
        raise TypeError("A managed active turn token is required.")
    if not isinstance(context, SyntheticContext):
        raise TypeError("SyntheticContext is required.")
    spec = _fixture_spec(context.case_id)
    started = clock()
    if not turns.is_current(token):
        return StreamAssessment(token, context.case_id, None, False, None,
                                None, None, None, None, started, "superseded_turn")

    fragments: list[str] = []
    first_text_ms = None
    first_candidate_ms = None
    stream_metrics = None
    error: Literal["stream_error", "superseded_turn"] | None = None

    def on_delta(delta: str) -> None:
        nonlocal first_text_ms, first_candidate_ms
        if not turns.is_current(token):
            raise StreamError("Stream was superseded.")
        if first_text_ms is None:
            first_text_ms = _ms(clock(), started)
        fragments.append(delta)
        if first_candidate_ms is None and _scannable_prefix(
            "".join(fragments), category=spec["category"],
            attribution=context.attribution,
        ):
            first_candidate_ms = _ms(clock(), started)

    try:
        stream_metrics = consume_stream(
            byte_lines, started=started, clock=clock, on_delta=on_delta,
            should_continue=lambda: turns.is_current(token),
        )
    except (StreamError, UnicodeError, ValueError):
        # No text or exception details are sent to the presenter on failure.
        error = "superseded_turn" if not turns.is_current(token) else "stream_error"

    if not turns.is_current(token):
        return StreamAssessment(token, context.case_id, None, False, None,
                                first_text_ms, first_candidate_ms, None, None,
                                started, "superseded_turn")

    completed = stream_metrics is not None and bool(stream_metrics.get("completed"))
    answer = "".join(fragments) if completed else ""
    # An incomplete stream must never be scored/published as a successful answer.
    qa = assess(QAInput(
        case_id=context.case_id, role=spec["role"], category=spec["category"],
        answer=answer, completed=completed,
        turn_id=token.turn_id, active_turn_id=turns.current().turn_id,
        turn_version=token.version, active_turn_version=turns.current().version,
        personal_claim_classification=context.attribution,
        verified_source_ids=context.verified_source_ids,
        coverage_indicators=_CASE_COVERAGE.get(context.case_id, ()),
        risk_flags=_CASE_RISKS.get(context.case_id, ()),
    ))
    qa_time = _ms(clock(), started)
    return StreamAssessment(
        token=token, case_id=context.case_id, answer=answer if completed else None,
        completed=completed, qa=qa, first_text_ms=first_text_ms,
        first_scannable_candidate_ms=first_candidate_ms,
        completed_ms=stream_metrics["total_ms"] if completed else None,
        qa_decided_ms=qa_time, started=started, error_code=error,
    )


def publish_assessment(
    assessed: StreamAssessment, *,
    turns: ActiveTurns,
    on_present: Callable[[Presentation], None],
    policy: ModelPolicy | None = None,
    clock: Callable[[], float] = time.monotonic,
) -> Presentation:
    """Recheck turn freshness *at the synchronous presentation boundary*.

    The callback receives only status for failed, ungrounded or unsafe answers.
    When a new question supersedes an answer before presentation, the callback
    is never invoked. A queued UI renderer must check token freshness again.
    """
    if not callable(on_present):
        raise TypeError("A synchronous presentation callback is required.")
    policy = policy if policy is not None else ModelPolicy()
    if not isinstance(policy, ModelPolicy):
        raise TypeError("Expected ModelPolicy.")

    def envelope(state: str, text: str | None, presented: int | None) -> Presentation:
        qa = assessed.qa
        return Presentation(
            token=assessed.token, case_id=assessed.case_id,
            state=state, text=text,
            reasons=(qa.reasons if qa else (assessed.error_code or "not_assessed",)),
            presented_ms=presented, first_text_ms=assessed.first_text_ms,
            first_scannable_candidate_ms=assessed.first_scannable_candidate_ms,
            first_useful_verified_ms=None, stream_completed=assessed.completed,
            review_candidate=policy.review_suggestion(qa),
        )

    outcome: Presentation | None = None

    def commit() -> None:
        nonlocal outcome
        if not assessed.completed or assessed.qa is None:
            outcome = envelope("unavailable", None, _ms(clock(), assessed.started))
        elif assessed.qa.status == "abstain":
            outcome = envelope("unavailable", None, _ms(clock(), assessed.started))
        elif assessed.qa.status == "needs_revision":
            outcome = envelope("needs_revision", None, _ms(clock(), assessed.started))
        else:
            outcome = envelope("final_unverified", assessed.answer,
                               _ms(clock(), assessed.started))
        on_present(outcome)

    if not turns._publish_if_current(assessed.token, commit):
        # Important: no presentation callback or stale answer emitted.
        return envelope("suppressed", None, None)
    assert outcome is not None
    return outcome
