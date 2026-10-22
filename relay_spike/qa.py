"""Offline-only, conservative Relay answer-quality decision contract (Slice 01B-B0).

A PASS here means that deterministic presentation and context guards passed.
It is NOT a factual correctness certificate, a verified personal attribution,
a completed second-model review, or permission to display a stale turn.
This module performs no authentication, I/O, networking, or model inference.
"""
from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Literal

from .benchmark import format_metrics

QAStatus = Literal["pass", "needs_revision", "abstain"]

KNOWN_CATEGORIES = frozenset({
    "sql", "coding", "edge_case", "ambiguity", "multi_part", "correction",
    "personal", "behavioral", "metrics", "visualization", "interruption",
})
PERSONAL_CATEGORIES = frozenset({"personal", "behavioral"})
REVIEW_CATEGORIES = frozenset({
    "coding", "edge_case", "ambiguity", "multi_part", "correction",
    "personal", "behavioral",
})

# A deliberately conservative trigger for autobiographical work-attribution language
# in otherwise technical answers. This is only a heuristic, not a semantic proof.
FIRST_PERSON_WORK_CLAIM = re.compile(
    r"\b(?:(?:I|I've|I have)\s+(?:built|implemented|developed|created|led|"
    r"owned|shipped|managed|designed|delivered|wrote|written|"
    r"contributed\s+to|was\s+responsible\s+for|"
    r"worked\s+(?:on|as|at|with)|helped\s+(?:build|ship|deliver))|"
    r"(?:I|I've)\s+have\s+\d+\s+years?|"
    r"in\s+my\s+(?:role|job|experience)|"
    r"my\s+(?:team|employer|project|professional\s+experience))\b",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class CoverageIndicator:
    """Explicit, weak keyword signal for a question subpart, never proof of coverage."""

    label: str
    any_of: tuple[str, ...]


@dataclass(frozen=True)
class QAInput:
    case_id: str
    role: str
    category: str
    answer: str
    completed: bool
    turn_id: str
    active_turn_id: str
    turn_version: int
    active_turn_version: int
    # Only a trusted non-model-derived classifier may assert "absent";
    # uncertain is intentionally fail-closed for real user-generated answers.
    personal_claim_classification: Literal["absent", "present", "uncertain"] = "uncertain"
    verified_source_ids: tuple[str, ...] = ()
    coverage_indicators: tuple[CoverageIndicator, ...] = ()
    risk_flags: tuple[str, ...] = ()


@dataclass(frozen=True)
class QAResult:
    status: QAStatus
    reasons: tuple[str, ...]
    warnings: tuple[str, ...]
    second_review_recommended: bool
    case_id: str
    turn_id: str
    active_turn_id: str
    turn_version: int
    verified_source_ids: tuple[str, ...]
    missing_coverage_indicators: tuple[str, ...]
    words: int


def _validate(data: QAInput) -> None:
    if not isinstance(data, QAInput):
        raise TypeError("QAInput required.")
    for value in (data.case_id, data.role, data.category, data.turn_id, data.active_turn_id):
        if not isinstance(value, str) or not value.strip():
            raise ValueError("Nonempty case, role, category, and turn identifiers required.")
    if not isinstance(data.answer, str):
        raise TypeError("Answer must be text.")
    if type(data.completed) is not bool:
        raise TypeError("Completed must be a boolean.")
    if type(data.turn_version) is not int or type(data.active_turn_version) is not int:
        raise TypeError("Turn versions must be integers.")
    if data.turn_version < 0 or data.active_turn_version < 0:
        raise ValueError("Turn versions must be nonnegative.")
    if data.personal_claim_classification not in ("absent", "present", "uncertain"):
        raise ValueError("Personal claim classification must be absent, present or uncertain.")
    if not isinstance(data.verified_source_ids, tuple) or not isinstance(data.risk_flags, tuple):
        raise TypeError("Source IDs and risk flags must be tuples.")
    if not isinstance(data.coverage_indicators, tuple):
        raise TypeError("Coverage indicators must be a tuple.")
    for values in (data.verified_source_ids, data.risk_flags):
        if any(not isinstance(value, str) or not value.strip() for value in values):
            raise ValueError("Empty or malformed evidence/risk identifier.")
    if len(data.verified_source_ids) != len(set(data.verified_source_ids)):
        raise ValueError("Duplicate verified source IDs.")
    names = []
    for item in data.coverage_indicators:
        if not isinstance(item, CoverageIndicator):
            raise TypeError("Coverage indicators must be CoverageIndicator records.")
        if (not isinstance(item.label, str) or not item.label.strip() or
                not isinstance(item.any_of, tuple) or not item.any_of or
                any(not isinstance(word, str) or not word.strip() for word in item.any_of)):
            raise ValueError("Coverage indicators require a name and nonempty literal alternatives.")
        names.append(item.label)
    if len(names) != len(set(names)):
        raise ValueError("Duplicate coverage indicator labels.")


def _has_indicator(text: str, literal: str) -> bool:
    """Match a literal token/phrase rather than inside another word."""
    return re.search(r"(?<!\w)" + re.escape(literal) + r"(?!\w)",
                     text, flags=re.IGNORECASE) is not None


def assess(data: QAInput) -> QAResult:
    """Return a *deterministic gate*, not an answer correctness judgment.

    The calling UI must re-check active turn version immediately before display:
    the active turn can change *after* this function returns.
    """
    _validate(data)
    reasons: list[str] = []
    warnings: list[str] = []
    missing: list[str] = []
    words = 0

    def result(status: QAStatus, recommend: bool = False) -> QAResult:
        return QAResult(
            status=status, reasons=tuple(reasons), warnings=tuple(warnings),
            second_review_recommended=recommend, case_id=data.case_id,
            turn_id=data.turn_id, active_turn_id=data.active_turn_id,
            turn_version=data.turn_version,
            verified_source_ids=data.verified_source_ids,
            missing_coverage_indicators=tuple(missing), words=words,
        )

    if (data.turn_id != data.active_turn_id or
            data.turn_version != data.active_turn_version):
        reasons.append("superseded_turn")
        return result("abstain")
    if not data.completed:
        reasons.append("incomplete_stream")
        return result("abstain")
    if data.category not in KNOWN_CATEGORIES:
        reasons.append("unknown_question_category")
        return result("abstain")
    if not data.answer.strip():
        reasons.append("empty_answer")
        return result("abstain")

    metrics = format_metrics(data.answer, data.category)
    words = metrics["words"]
    if words < 4:
        reasons.append("insufficient_answer_text")
    if not metrics["under_word_ceiling"]:
        reasons.append("over_word_ceiling")
    if metrics["contains_markdown_table"]:
        reasons.append("markdown_table_not_scannable")
    if data.answer.lstrip().startswith("```"):
        warnings.append("code_first_answer_may_be_hard_to_scan")

    # Evidence IDs are pointers, NOT evidence that any claim is supported.
    inferred_personal_attribution = bool(FIRST_PERSON_WORK_CLAIM.search(data.answer))
    if inferred_personal_attribution:
        warnings.append("possible_first_person_work_claim_heuristic")
    personal = (data.category in PERSONAL_CATEGORIES or
                "personal_claim" in data.risk_flags or
                data.personal_claim_classification == "present" or
                inferred_personal_attribution)
    if personal and not data.verified_source_ids:
        reasons.append("missing_verified_personal_context")
        return result("abstain")
    if personal:
        reasons.append("personal_claims_need_actual_source_review")
    elif data.personal_claim_classification == "uncertain":
        # Without trusted classification, do not claim a clean technical
        # answer contains no made-up first-person contribution.
        reasons.append("personal_attribution_not_classified")

    # A literal keyword can indicate a missing subpart, not verify correctness.
    if data.coverage_indicators:
        for indicator in data.coverage_indicators:
            if not any(_has_indicator(data.answer, needle) for needle in indicator.any_of):
                missing.append(indicator.label)
        warnings.append("keyword_coverage_is_not_semantic_verification")
        if missing:
            reasons.append("possible_missing_question_subparts")

    # The offline text spike has no turn-state machine. Don't claim an
    # interrupted/restarted question is authoritative without one.
    if data.category == "interruption":
        reasons.append("turn_interruption_needs_state_confirmation")

    status: QAStatus = "needs_revision" if reasons else "pass"
    high_risk = data.category in REVIEW_CATEGORIES or bool(data.risk_flags)
    # Abstentions above never incur automatic second-model usage.
    return result(status, recommend=high_risk)
