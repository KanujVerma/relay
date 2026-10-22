"""Slice 01B-B2: one authorized synthetic text case through real SSE and offline QA.

The API call uses the CLI's already validated ChatGPT-plan access token; this
module never reads an API key, imports a résumé, prompts with actual interview
content, makes a second inference request or publishes provisional text.
"""
from __future__ import annotations

from contextlib import AbstractContextManager
from dataclasses import dataclass
import re
import time
from typing import Callable, Iterable

from .benchmark import load_cases, instructions_for
from .stream import StreamError, response_sse_lines, validated_reasoning_effort
from .streaming_qa import (
    ActiveTurns, ModelPolicy, Presentation, StreamAssessment, SyntheticContext,
    TurnToken, assess_synthetic_stream, publish_assessment,
)

# Only reviewed synthetic technical whole responses may clear the guard.
# A real interview requires independent trusted grounding and turn checks.
# Additional conservative risk label. Never used to authorize display.
WORK_HISTORY_TERMS = re.compile(
    r"\b(?:built|implemented|developed|designed|created|led|owned|"
    r"managed|shipped|delivered|interned|internship|graduated|"
    r"employer|employed|worked|responsible|contributed|coworker|"
    r"teammate|cofounder|co-founder|portfolio|resume|résumé|"
    r"career|previous|professional|experience|production|"
    r"improved|increased|reduced|achieved|launched|optimized|"
    r"engineer|developer|analyst|consultant|job|role)\b",
    re.IGNORECASE,
)


# Whole-answer smoke matches only. Model-generated text is untrusted and an
# absence of flagged regex words never certifies an absence of personal claims.
APPROVED_SMOKE_ANSWERS: dict[str, frozenset[str]] = {
    "D02": frozenset({
        "WHERE filters input rows before grouping, while HAVING filters aggregated groups after grouping.",
        "WHERE filters rows before grouping, while HAVING filters groups after aggregation.",
    }),
    "E09": frozenset({
        "Binary search halves the sorted search range with each comparison, using logarithmic time and constant auxiliary space.",
    }),
}
APPROVED_SMOKE_CATEGORIES = {"D02": "sql", "E09": "coding"}


def synthetic_nonpersonal_classification(answer: str, category: str, *, case_id: str) -> str:
    """Positive, exact synthetic technical phrase allowlist, NOT semantic QA.

    A different generated phrase remains uncertain, no matter what words are
    missing from our optional risk regex. Model text cannot certify its own
    absence of invented personal history.
    """
    if not isinstance(answer, str) or category != APPROVED_SMOKE_CATEGORIES.get(case_id):
        return "uncertain"
    normalized = " ".join(answer.split())
    if normalized in APPROVED_SMOKE_ANSWERS.get(case_id, frozenset()):
        return "absent"
    if WORK_HISTORY_TERMS.search(normalized):
        return "present"
    return "uncertain"

def validate_live_case(case_id: str, model: str, effort: str) -> dict:
    """Validate all public CLI parameters BEFORE authentication or inference."""
    case = load_cases((case_id,))[0]
    if (case_id not in APPROVED_SMOKE_ANSWERS or
            case["category"] != APPROVED_SMOKE_CATEGORIES[case_id]):
        raise StreamError(
            "Live QA supports only the reviewed D02/E09 technical smoke cases. "
            "Other questions await trusted attribution and answer review."
        )
    if model not in ("gpt-6-luna", "gpt-6.1-sol"):
        raise StreamError("Live QA only supports the reviewed Luna/Sol models.")
    if effort not in ("default", "low", "medium"):
        raise StreamError("Live QA supports only default, low or medium effort.")
    validated_reasoning_effort(model, effort)
    return case


@dataclass(frozen=True)
class LiveCaseResult:
    model: str
    requested_effort: str
    assessment: StreamAssessment
    presentation: Presentation


def run_live_synthetic_case(
    access_token: str, *,
    case_id: str,
    model: str,
    effort: str = "default",
    on_present: Callable[[Presentation], None],
    turns: ActiveTurns | None = None,
    token: TurnToken | None = None,
    response_stream: Callable[..., AbstractContextManager[Iterable[bytes | str]]] = response_sse_lines,
    clock: Callable[[], float] = time.monotonic,
) -> LiveCaseResult:
    """Make exactly one OAuth-backed request; publish only completed QA PASS.

    Caller MUST obtain access_token from auth.active_access_token, and enforce
    an explicit opt-in and the currently visible account model first. The
    optional transport injection exists solely for offline negative tests.
    """
    case = validate_live_case(case_id, model, effort)
    if not isinstance(access_token, str) or not access_token.strip():
        raise StreamError("No authorized ChatGPT-plan token available.")
    if not callable(on_present):
        raise TypeError("A synchronous presentation callback is required.")
    if (turns is None) != (token is None):
        raise TypeError("Turns and token must be supplied together.")
    if turns is None:
        turns = ActiveTurns()
        token = turns.activate("synthetic:" + case_id, 1)
    assert token is not None
    if not turns.is_current(token):
        raise StreamError("Turn superseded before the inference request.")

    started = clock()  # Network connection, generation, QA and publish included.
    with response_stream(
        access_token, model, case["question"],
        instructions=instructions_for(case["role"]),
        effort=validated_reasoning_effort(model, effort),
    ) as byte_lines:
        assessed = assess_synthetic_stream(
            byte_lines,
            turns=turns, token=token, context=SyntheticContext(case_id),
            clock=clock, started_at=started,
            attribution_classifier=lambda answer, category: synthetic_nonpersonal_classification(
                answer, category, case_id=case_id
            ),
        )
    presentation = publish_assessment(
        assessed, turns=turns, on_present=on_present,
        policy=ModelPolicy(preferred_model=model), clock=clock,
    )
    return LiveCaseResult(model, effort, assessed, presentation)
