"""B3A-0 offline technical candidate evaluation, NOT general semantic verification.

Untrusted model prose is NEVER displayed. A candidate can only select a
separately reviewed fixed technical card after passing a narrow, closed
vocabulary and proposition check for two synthetic question families.
No network, tokens, inference, personal memory, or runtime publication here.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re

FIXTURES = Path(__file__).resolve().parents[1] / "EVALS" / "technical-answer-gate.jsonl"
MAX_CANDIDATE_CHARS = 560
MIN_CANDIDATE_WORDS = 9
MAX_CANDIDATE_WORDS = 95

# An unknown word is NEVER evidence that the model is safe. It means withhold.
# These are tightly scoped technical words, not a comprehensive English lexicon.
_COMMON = frozenset("""
a about additional after also an and another are as at be because before
between both by can clause clauses compares comparison compared condition
conditions constant contains data difference different during each element else
every first for from group grouped grouping groups if in individual input is it
its later less limited limits more must of on once only or over per
pre prior process processing records requires restrict restricts restricting
result results row rows second selects selection so space stage step
than that the their then there these this time to use used uses using
versus vs when whereas which while with within works
""".split())
_D02_WORDS = frozenset("""
aggregate aggregated aggregates aggregating aggregation apply applies applied
avg count filter filtered filtering filters having raw sql sum where
beforehand afterwards afterward predicate predicates earlier subsequent
""".split())
_E09_WORDS = frozenset("""
algorithm array arrays auxiliary binary check checks checked checking comparisons
complexity discard discards divide divided dividing divides extra half halves halve
halving iterative iteratively iteration iterations log logarithmic loop middle
midpoint n o ordered order search searching searches sorted sort target worst
case memory range remaining reduces reduce reduced split splits stack
implementation implements left right size repeatedly 1
""".split())

_SAFE_RENDER: dict[str, str] = {
    "D02": ("WHERE filters individual rows before grouping. "
            "HAVING filters aggregated groups after grouping."),
    "E09": ("Binary search requires sorted input and halves the search range. "
            "Its iterative implementation takes O(log n) time and O(1) auxiliary space."),
}
_ALLOWED_PUNCTUATION = frozenset(" ,.;:!?()-/")
_WORD = re.compile(r"[a-z]+|[0-9]+")
_FILTER = frozenset(("filters", "restricts", "selects", "limits"))
_ROWS = frozenset(("row", "rows", "records"))
_GROUPS = frozenset(("group", "groups", "grouped", "aggregate", "aggregated", "aggregation", "aggregates"))
_BEFORE = frozenset(("before", "prior", "earlier", "pre"))
_AFTER = frozenset(("after", "later", "subsequent", "afterward", "afterwards"))


@dataclass(frozen=True)
class TechnicalVerdict:
    case_id: str
    publishable: bool
    rendered_text: str | None
    reason: str

    def __post_init__(self) -> None:
        # There is no candidate text in the public verdict.
        if self.publishable:
            if self.rendered_text is None or self.rendered_text != _SAFE_RENDER.get(self.case_id):
                raise ValueError("Published technical text must be an approved local card.")
        elif self.rendered_text is not None:
            raise ValueError("Withheld candidates cannot carry visible output.")


def _review_d02(text: str, words: tuple[str, ...]) -> bool:
    """Accept fully scoped WHERE/row and HAVING/group propositions only."""
    clauses = [segment.strip() for segment in re.split(r"[.;!?]+", text) if segment.strip()]
    if not 1 <= len(clauses) <= 2:
        return False
    if len(clauses) == 2:
        # Two statements must each concern exactly one required SQL clause.
        # A free-floating conclusion can contradict the recognized answer.
        mentioned = [
            set(re.findall(r"\b(?:where|having)\b", segment))
            for segment in clauses
        ]
        if mentioned != [{"where"}, {"having"}] and mentioned != [{"having"}, {"where"}]:
            return False
    if words.count("where") != 1 or words.count("having") != 1:
        return False
    wpos, hpos = words.index("where"), words.index("having")
    if wpos < hpos:
        where, having = words[wpos + 1:hpos], words[hpos + 1:]
    else:
        having, where = words[hpos + 1:wpos], words[wpos + 1:]
    w, h = set(where), set(having)
    if not (w & _FILTER and w & _ROWS):
        return False
    if not (h & _FILTER and h & _GROUPS):
        return False
    if w & _AFTER or h & _BEFORE:
        return False
    if w & _GROUPS and not w & _BEFORE:
        return False
    if h & _ROWS:
        return False
    return True


def _review_e09(text: str, words: tuple[str, ...]) -> bool:
    """Require sorted precondition, halving, log time and iterative constant space."""
    vocabulary = set(words)
    # Reject every unreviewed asymptotic expression, even when the answer
    # ALSO includes the expected O(log n) and O(1) somewhere else.
    formulas = re.findall(r"\bo\s*\([^)]*\)", text)
    if any(not re.fullmatch(r"o\s*\(\s*(?:log\s*n|1)\s*\)", x)
           for x in formulas):
        return False
    without_formulas = re.sub(r"\bo\s*\(\s*(?:log\s*n|1)\s*\)", " ", text)
    if re.search(r"\b(?:n|1)\b", without_formulas):
        return False
    if "binary" not in vocabulary or "search" not in vocabulary:
        return False
    if not re.search(
        r"\b(?:sorted|ordered)\b.{0,35}\b(?:input|array|arrays|data)\b"
        r"|\b(?:input|array|arrays|data)\b.{0,35}\b(?:sorted|ordered)\b", text
    ):
        return False
    if not vocabulary.intersection({
        "halves", "halve", "halving", "half", "midpoint", "middle", "divide",
        "dividing", "discard", "discards", "split", "splits"
    }):
        return False
    if not re.search(r"\bo\s*\(\s*log\s*n\s*\)|\blogarithmic\b", text):
        return False
    if not (
        re.search(r"\bo\s*\(\s*1\s*\)", text)
        or re.search(r"\bconstant\b.{0,40}\b(?:space|memory)\b", text)
    ):
        return False
    # Bind the complexity to the relevant quantity, not just words nearby.
    # A reversed O(1)-time/O(log n)-space claim is not an acceptable answer.
    if re.search(
        r"\bo\s*\(\s*1\s*\)\s*(?:time|complexity)\b"
        r"|\btime(?:\s+complexity)?\s+(?:is|of|:)\s*o\s*\(\s*1\s*\)",
        text,
    ):
        return False
    if re.search(
        r"\bo\s*\(\s*log\s*n\s*\)\s*(?:auxiliary|extra)?\s*(?:space|memory)\b"
        r"|\b(?:space|memory)(?:\s+complexity)?\s+(?:is|of|:)\s*o\s*\(\s*log\s*n\s*\)",
        text,
    ):
        return False
    if "time" not in vocabulary or not vocabulary.intersection({"space", "auxiliary"}):
        return False
    if not vocabulary.intersection({"iterative", "iteratively", "loop"}):
        return False
    return True


def review_technical_candidate(case_id: str, candidate: str) -> TechnicalVerdict:
    """Bounded, deterministic candidate-to-canonical technical reference gate.

    Every failure withholds ALL candidate text. An accepted verdict contains
    only a constant reviewed card. This cannot verify arbitrary coding/SQL.
    """
    def withhold(reason: str) -> TechnicalVerdict:
        return TechnicalVerdict(str(case_id), False, None, reason)

    if not isinstance(case_id, str) or case_id not in _SAFE_RENDER:
        return withhold("unsupported_technical_case")
    if not isinstance(candidate, str):
        return withhold("invalid_candidate_type")
    if not candidate or len(candidate) > MAX_CANDIDATE_CHARS:
        return withhold("candidate_size_out_of_bounds")
    if any(not ch.isascii() for ch in candidate):
        return withhold("unsupported_character")
    if any(not (ch.isalnum() or ch.isspace() or ch in _ALLOWED_PUNCTUATION)
           for ch in candidate):
        return withhold("unsafe_format")
    if candidate.count("\n") > 2:
        return withhold("unsupported_layout")
    text = " ".join(candidate.lower().split())
    words = tuple(_WORD.findall(text))
    if not MIN_CANDIDATE_WORDS <= len(words) <= MAX_CANDIDATE_WORDS:
        return withhold("candidate_word_count")
    allowed = _COMMON | (_D02_WORDS if case_id == "D02" else _E09_WORDS)
    if any(word not in allowed for word in words):
        return withhold("outside_reviewed_vocabulary")
    valid = _review_d02(text, words) if case_id == "D02" else _review_e09(text, words)
    if not valid:
        return withhold("technical_propositions_not_verified")
    return TechnicalVerdict(case_id, True, _SAFE_RENDER[case_id], "reviewed_synthetic_card")


def load_fixture_rows(path: Path = FIXTURES) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def evaluate_fixture_rows(rows: list[dict]) -> dict:
    """Synthetic expected-label counts, never raw model answer logging."""
    if not rows:
        raise ValueError("Nonempty fixtures required.")
    seen: set[str] = set()
    positive = negative = published = unsafe_published = 0
    for row in rows:
        if (not isinstance(row, dict)
                or not {"id", "case_id", "candidate", "expected"} <= row.keys()
                or not isinstance(row["id"], str) or not row["id"]
                or row["id"] in seen or row["case_id"] not in _SAFE_RENDER
                or row["expected"] not in ("publish", "withhold")
                or not isinstance(row["candidate"], str)):
            raise ValueError("Malformed or duplicated technical fixture.")
        seen.add(row["id"])
        outcome = review_technical_candidate(row["case_id"], row["candidate"])
        if row["expected"] == "publish":
            positive += 1
            published += int(outcome.publishable)
        else:
            negative += 1
            unsafe_published += int(outcome.publishable)
    if not positive or not negative:
        raise ValueError("Both publish and withhold fixtures are required.")
    return {
        "total": len(rows), "expected_publish": positive,
        "published_of_expected": published, "expected_withhold": negative,
        "unsafe_published": unsafe_published,
        "withheld_of_expected": negative - unsafe_published,
        "all_guards_met": unsafe_published == 0 and published == positive,
        "note": "Hand-reviewed fixed synthetic fixtures only, no generic correctness proof.",
    }


def main() -> int:
    report = evaluate_fixture_rows(load_fixture_rows())
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["all_guards_met"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
