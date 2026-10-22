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

# Restrict this bridge to non-personal, already-reviewed synthetic question types.
# A genuine interview will need a separate permission/grounding/turn classifier.
TECHNICAL_CATEGORIES = frozenset({
    "sql", "coding", "edge_case", "ambiguity", "multi_part", "correction",
    "metrics", "visualization",
})
FIRST_PERSON_TERMS = re.compile(
    r"\b(?:i|me|my|mine|myself|we|us|our|ours|ourselves)\b", re.IGNORECASE
)
# Implicit-subject résumé claims need a conservative veto even without
# a literal "I" or "we". False negatives are possible: NOT a trust classifier
# suitable for real interview or Personal Brain text.
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


def synthetic_nonpersonal_classification(answer: str, category: str) -> str:
    """Narrow negative screen, NOT a general proof of facts or attribution.

    A non-personal *synthetic technical* fixture has no user biography in its
    input. Any first-person wording, including quoted or code text, makes the
    output uncertain. This does NOT validate technical answer correctness.
    """
    if category not in TECHNICAL_CATEGORIES or not isinstance(answer, str) or not answer.strip():
        return "uncertain"
    # Suspected biography, including implicit/third-person work claims, is
    # treated as personal and abstains without verified personal source IDs.
    if WORK_HISTORY_TERMS.search(answer):
        return "present"
    if FIRST_PERSON_TERMS.search(answer):
        return "uncertain"
    return "absent"


def validate_live_case(case_id: str, model: str, effort: str) -> dict:
    """Validate all public CLI parameters BEFORE authentication or inference."""
    case = load_cases((case_id,))[0]
    if case["category"] not in TECHNICAL_CATEGORIES:
        raise StreamError(
            "Live QA is restricted to synthetic technical cases; "
            "personal, behavioral and interruption cases are deferred."
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
            attribution_classifier=synthetic_nonpersonal_classification,
        )
    presentation = publish_assessment(
        assessed, turns=turns, on_present=on_present,
        policy=ModelPolicy(preferred_model=model), clock=clock,
    )
    return LiveCaseResult(model, effort, assessed, presentation)
