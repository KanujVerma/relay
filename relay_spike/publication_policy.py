"""Slice 01B-B3A-2: offline answer-publication decision contract.

No OAuth, model invocation, transcription, user files, persistence or UI.
A trusted host may select a reviewed technical reference only for a *full,
unchanged and authorized* synthetic or remote-final question. Unreviewed model
text is never exposed by this contract, regardless of self-reported confidence,
source IDs, or a negative word filter. This is not a generic semantic verifier.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Literal

from .benchmark import load_cases
from .streaming_qa import ActiveTurns, TurnToken

ROOT = Path(__file__).resolve().parents[1]
EVALUATION_FIXTURES = ROOT / "EVALS" / "publication-policy-cases.jsonl"

PublicationState = Literal[
    "reviewed_reference", "model_suggestion_unverified",
    "needs_revision", "unavailable",
]
SourceChannel = Literal["user_synthetic", "remote_final", "remote_partial", "microphone", "unknown"]
QuestionStatus = Literal["final", "partial", "correction", "interrupted", "discontinuous"]
TECHNICAL_CATEGORIES = frozenset({
    "sql", "coding", "edge_case", "metrics", "visualization", "multi_part",
    "ambiguity",
})
PERSONAL_CATEGORIES = frozenset(("personal", "behavioral"))
MAX_QUESTION_CHARS = 600
MAX_INTERNAL_CANDIDATE_CHARS = 4096


@dataclass(frozen=True)
class ReviewedReference:
    reference_id: str
    question: str
    role: str
    category: str
    answer: str
    source_ref: str
    coverage: tuple[str, ...]

    def __post_init__(self) -> None:
        if not self.question or not self.answer or not self.coverage:
            raise ValueError("Reviewed references require complete local evidence.")


# This is intentionally NOT a general look-up of every EVALS fixture. The
# E09 card in B3A-0 explains search but does not WRITE the code requested by
# E09, so E09 is ineligible for direct reference publication.
_REFERENCES = (
    ReviewedReference(
        reference_id="D02-sql-where-having-v1",
        question="What is the difference between WHERE and HAVING?",
        role="analytics", category="sql",
        answer=("WHERE filters individual rows before grouping. "
                "HAVING filters aggregated groups after grouping."),
        source_ref="EVALS/interview-questions.jsonl#D02",
        coverage=("where_before_grouping", "having_after_grouping"),
    ),
)


@dataclass(frozen=True)
class PolicyInput:
    question: str
    role: str
    category: str
    source_channel: SourceChannel = "user_synthetic"
    question_status: QuestionStatus = "final"
    host_authorized: bool = True
    constraints: tuple[str, ...] = ()
    case_id_hint: str | None = None
    candidate: str | None = None
    stream_completed: bool = False
    claimed_source_ids: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.question, str) or not isinstance(self.role, str):
            raise TypeError("Question and role must be strings.")
        if not isinstance(self.category, str):
            raise TypeError("Question category must be a string.")
        if type(self.host_authorized) is not bool or type(self.stream_completed) is not bool:
            raise TypeError("Host authorization and stream completion must be booleans.")
        if (not isinstance(self.constraints, tuple)
                or any(not isinstance(c, str) or not c.strip() for c in self.constraints)):
            raise TypeError("Constraints must be a tuple of nonempty host-supplied strings.")
        if (not isinstance(self.claimed_source_ids, tuple)
                or any(not isinstance(s, str) for s in self.claimed_source_ids)):
            raise TypeError("Source references must be tuple of strings.")
        if self.candidate is not None and not isinstance(self.candidate, str):
            raise TypeError("Generated candidate must be a string or absent.")
        if self.case_id_hint is not None and not isinstance(self.case_id_hint, str):
            raise TypeError("Case hint must be a string or absent.")


@dataclass(frozen=True)
class PublicationDecision:
    state: PublicationState
    displayed_text: str | None
    reviewed_reference_id: str | None
    reason_code: str
    first_useful_verified_ms: None = None

    def __post_init__(self) -> None:
        if self.state == "reviewed_reference":
            # The decision holds only independently reviewed local copy, not
            # candidate model text, arbitrary claims, or source pointers.
            if not any(
                self.displayed_text == ref.answer
                and self.reviewed_reference_id == ref.reference_id
                for ref in _REFERENCES
            ):
                raise ValueError("Published answer must match reviewed reference.")
        elif self.displayed_text is not None or self.reviewed_reference_id is not None:
            raise ValueError("Unverified, unsafe or unavailable text cannot be displayed.")
        if self.first_useful_verified_ms is not None:
            raise ValueError("Offline fixtures cannot prove first useful latency.")

    @property
    def publishes(self) -> bool:
        return self.displayed_text is not None


def _normalize_exact_question(question: str) -> str | None:
    """Only ASCII case and whitespace differences, never meaning-changing edits."""
    if not question or len(question) > MAX_QUESTION_CHARS:
        return None
    if any(not c.isascii() or (ord(c) < 32 and c not in "\t\n\r")
           for c in question):
        return None
    normalized = " ".join(question.casefold().split())
    return normalized or None


def _result(state: PublicationState, reason: str,
            reference: ReviewedReference | None = None) -> PublicationDecision:
    if reference is not None:
        return PublicationDecision(
            state, reference.answer, reference.reference_id, reason
        )
    return PublicationDecision(state, None, None, reason)


def evaluate_publication(request: PolicyInput, *,
                         turns: ActiveTurns, token: TurnToken) -> PublicationDecision:
    """Evaluate offline. This function never requests inference or exposes a candidate.

    Only an independently approved reference for the EXACT complete question
    may publish. All model-generated candidates remain internal suggestions
    requiring a separate reviewed policy before UI publication. Passing source
    ID strings cannot authorize personal, behavioral or technical claims.
    """
    if not isinstance(request, PolicyInput):
        raise TypeError("PolicyInput required.")
    if not isinstance(turns, ActiveTurns) or not isinstance(token, TurnToken):
        raise TypeError("The trusted host must supply ActiveTurns and TurnToken.")
    if not request.host_authorized:
        return _result("unavailable", "permission_not_confirmed")
    if request.source_channel not in ("user_synthetic", "remote_final"):
        return _result("unavailable", "untrusted_or_partial_source")
    if request.question_status != "final":
        return _result("unavailable", "question_not_final")
    if not turns.is_current(token):
        return _result("unavailable", "superseded_turn")

    question = _normalize_exact_question(request.question)
    if question is None:
        return _result("unavailable", "unsupported_question_text")
    if request.category in PERSONAL_CATEGORIES:
        return _result("needs_revision", "verified_personal_attribution_missing")
    if request.category in ("correction", "interruption"):
        return _result("needs_revision", "question_context_unresolved")
    if request.category not in TECHNICAL_CATEGORIES:
        return _result("needs_revision", "category_not_reviewed")
    if request.constraints:
        return _result("needs_revision", "additional_constraints_unreviewed")

    # Model output is data, not evidence. Do NOT select a reviewed card after
    # examining/generated raw model text, even if its wording resembles a card.
    if request.candidate is not None:
        if not request.stream_completed:
            return _result("unavailable", "incomplete_model_stream")
        if not request.candidate.strip() or len(request.candidate) > MAX_INTERNAL_CANDIDATE_CHARS:
            return _result("needs_revision", "candidate_size_or_empty")
        return _result("model_suggestion_unverified", "independent_review_required")

    for reference in _REFERENCES:
        if (request.role == reference.role
                and request.category == reference.category
                and question == _normalize_exact_question(reference.question)):
            # A local reference must still agree with its frozen EVALS source.
            # A silently changed source question/role/category invalidates
            # approval rather than broadening the trusted match.
            fixture = load_cases(("D02",))[0]
            if (fixture["question"] != reference.question
                    or fixture["role"] != reference.role
                    or fixture["category"] != reference.category):
                return _result("unavailable", "reviewed_fixture_changed")
            return _result("reviewed_reference", "reviewed_full_question", reference)

    # Case ID hints are never trusted topic evidence, and are intentionally
    # not read anywhere above. A changed "not", date, JOIN or metric matters.
    return _result("unavailable", "no_complete_reviewed_reference")


def load_evaluation_fixtures(path: Path = EVALUATION_FIXTURES) -> list[dict]:
    with path.open(encoding="utf-8") as stream:
        return [json.loads(line) for line in stream if line.strip()]


def _fixture_request(row: dict) -> PolicyInput:
    data = dict(row["input"])
    fixture_id = data.pop("question_ref", None)
    question_override = data.pop("question_override", None)
    data.pop("turn_state", None)
    if fixture_id is not None:
        case = load_cases((fixture_id,))[0]
        if question_override is None:
            question = case["question"]
        else:
            question = question_override
        data.setdefault("role", case["role"])
        data.setdefault("category", case["category"])
    else:
        question = question_override
    if not isinstance(question, str):
        raise ValueError("Expected a fixture question or explicit override.")
    for key in ("constraints", "claimed_source_ids"):
        if key in data:
            if not isinstance(data[key], list):
                raise ValueError("Fixture metadata must use JSON arrays.")
            data[key] = tuple(data[key])
    return PolicyInput(question=question, **data)


def evaluate_evaluation_rows(rows: list[dict]) -> dict:
    """Aggregate fixed, author-labeled dev/eval cases with no private strings."""
    if not rows:
        raise ValueError("Nonempty publication fixtures required.")
    partitions = {
        name: {"n": 0, "reviewed_reference_published": 0,
               "model_suggestion_unverified": 0, "needs_revision": 0,
               "unavailable": 0, "unsafe_published": 0,
               "benign_withheld": 0, "manually_labeled_useful_published": 0,
               "annotation_correct": 0, "annotation_incorrect": 0,
               "coverage_complete": 0, "coverage_partial": 0,
               "state_mismatch": 0}
        for name in ("development", "evaluation")
    }
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {
            "id", "partition", "family", "input", "expected_state",
            "safe_to_publish", "annotated_useful", "annotation",
            "technical_correctness", "coverage_label"
        }:
            raise ValueError("Publication fixture missing required labels.")
        idx, partition = row["id"], row["partition"]
        if (not isinstance(idx, str) or not idx or idx in seen
                or partition not in partitions
                or not isinstance(row["family"], str) or not row["family"]
                or row["expected_state"] not in (
                    "reviewed_reference", "model_suggestion_unverified",
                    "needs_revision", "unavailable")
                or row["technical_correctness"] not in (
                    "correct", "incorrect", "uncertain", "not_applicable")
                or row["coverage_label"] not in (
                    "complete", "partial", "unknown", "not_applicable")
                or type(row["safe_to_publish"]) is not bool
                or type(row["annotated_useful"]) is not bool
                or not isinstance(row["annotation"], str)
                or not row["annotation"].strip()):
            raise ValueError("Malformed or duplicated publication case.")
        seen.add(idx)
        request = _fixture_request(row)
        turns = ActiveTurns()
        token = turns.activate("offline:"+idx, 1)
        # The held-out fixtures exercise actual generation invalidation.
        turn_state = row["input"].get("turn_state", "current")
        if turn_state == "superseded":
            turns.activate("offline:replacement", 2)
        elif turn_state == "cancelled":
            turns.cancel()
        elif turn_state != "current":
            raise ValueError("Unknown turn state.")
        # turn_state is not part of PolicyInput.
        outcome = evaluate_publication(request, turns=turns, token=token)
        bucket = partitions[partition]
        bucket["n"] += 1
        bucket[outcome.state if outcome.state != "reviewed_reference"
               else "reviewed_reference_published"] += 1
        bucket["unsafe_published"] += int(outcome.publishes and not row["safe_to_publish"])
        bucket["benign_withheld"] += int(
            row["safe_to_publish"] and not outcome.publishes
        )
        bucket["manually_labeled_useful_published"] += int(
            row["annotated_useful"] and outcome.publishes
        )
        bucket["state_mismatch"] += int(outcome.state != row["expected_state"])
        bucket["annotation_correct"] += int(row["technical_correctness"] == "correct")
        bucket["annotation_incorrect"] += int(row["technical_correctness"] == "incorrect")
        bucket["coverage_complete"] += int(row["coverage_label"] == "complete")
        bucket["coverage_partial"] += int(row["coverage_label"] == "partial")

    if not all(bucket["n"] for bucket in partitions.values()):
        raise ValueError("Both development and evaluation partitions required.")
    counts = {
        "total": sum(b["n"] for b in partitions.values()),
        "unsafe_published": sum(b["unsafe_published"] for b in partitions.values()),
        "state_mismatches": sum(b["state_mismatch"] for b in partitions.values()),
        "benign_withheld": sum(b["benign_withheld"] for b in partitions.values()),
        "manually_labeled_useful_published": sum(
            b["manually_labeled_useful_published"] for b in partitions.values()
        ),
        "model_inference_requests": 0,
        "first_useful_verified_ms": None,
        "partitioned": partitions,
        "annotation_provenance": "synthetic_author_labeled_not_blinded",
        "independent_checks": (
            "D02 SQL aggregate semantics are executable in offline unit tests; "
            "other correctness labels are author annotations, not verified code."
        ),
    }
    counts["all_guards_met"] = (
        counts["unsafe_published"] == 0 and counts["state_mismatches"] == 0
    )
    counts["limitation"] = (
        "Author-labeled synthetic policy fixtures, not blinded model accuracy, "
        "production false-accept rates, live output or measured response latency."
    )
    return counts


def main() -> int:
    report = evaluate_evaluation_rows(load_evaluation_fixtures())
    print(json.dumps(report, sort_keys=True, indent=2))
    return 0 if report["all_guards_met"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
