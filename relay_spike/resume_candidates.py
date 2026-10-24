"""Slice 02A-B0: selected-text résumé candidates and explicit review contract.

No file access, remote calls, LLM calls, credential access or automatic approval.
Only caller-supplied *synthetic* text may be used in tests for this slice.
A future real macOS host must provide a genuine UI event and encrypted local
storage before real private documents can enter this flow.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, replace
from hashlib import sha256
import re
import secrets

from .personal_brain import (
    ACTORS, BrainError, BrainStore, InvalidState, MissingEvidence,
    UserConfirmation, _observed, _required,
)
from .resume_structure import ResumeContext, decode_context, digest as context_digest

MAX_SELECTED_CHARS = 30_000
MAX_CANDIDATES = 64
MAX_LINE_CHARS = 600

_HEADING = re.compile(r"(?i)^(?:#+\s+)?(?:experience|education|projects|skills|"
                      r"technologies|technical skills|summary|achievements|"
                      r"certifications|relevant coursework|work history):?$")
_BULLET = re.compile(r"^\s*(?:[-*•]\s+|\d+[.)]\s+)")
_ACTION = re.compile(
    r"(?i)^(?:I(?:'ve| have)?\s+|we\s+|our team\s+|my teammate\s+|"
    r"teammate\s+|my cofounder\s+|cofounder\s+|"
    r"built\b|implemented\b|developed\b|designed\b|created\b|"
    r"shipped\b|led\b|managed\b|wrote\b|worked\b|used\b|"
    r"optimized\b|deployed\b|analyzed\b|automated\b|"
    r"proficient\b|familiar\b)"
)
_INSTRUCTION = re.compile(
    r"(?i)(?:ignore (?:all |the |your )?(?:previous |prior )?instructions|"
    r"(?:system|developer|assistant)\s*:\s*|"
    r"mark (?:every|all) (?:claim|fact|record)s? (?:as )?(?:approved|verified)|"
    r"bypass (?:the )?(?:consent|review|approval|verification))"
)


@dataclass(frozen=True)
class ExtractedCandidate:
    """Exact source substring, never a normalized biographical assertion."""

    snippet: str
    span_start: int
    span_end: int
    line_number: int
    actor_hint: str
    needs_manual_review: bool


@dataclass(frozen=True)
class ReviewCard:
    fact_id: str
    source_id: str
    source_sha256: str
    snippet: str
    snippet_sha256: str
    span_start: int
    span_end: int
    review_revision: int
    actor_hint: str
    card_fingerprint: str


@dataclass(frozen=True)
class ReviewCardV2(ReviewCard):
    schema_version: int
    claim_kind: str
    review_context: ResumeContext
    context_sha256: str
    locator: str


def _digest(text: str) -> str:
    return sha256(text.encode("utf-8")).hexdigest()


def extract_synthetic_candidates(text: str) -> tuple[ExtractedCandidate, ...]:
    """Deterministic, conservative line parser with actual character offsets.

    Unattributed verbs like "built" are intentionally UNKNOWN, even in a
    résumé: the project may be a team outcome. We do not infer a user's
    experience from vocabulary, tools, metrics or section headings.
    """
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_SELECTED_CHARS:
        raise BrainError("Invalid or oversized selected text.")
    rows: list[ExtractedCandidate] = []
    offset = 0
    for line_number, raw in enumerate(text.splitlines(keepends=True), 1):
        line = raw.rstrip("\r\n")
        leading = len(line) - len(line.lstrip())
        segment = line[leading:].rstrip()
        m = _BULLET.match(segment)
        if m:
            leading += m.end()
            segment = segment[m.end():].rstrip()
        else:
            segment = segment.rstrip()
        if (not segment or len(segment) > MAX_LINE_CHARS or
                _HEADING.fullmatch(segment) or _INSTRUCTION.search(segment)):
            offset += len(raw)
            continue
        # Do not pull arbitrary paragraphs or quoted tool instructions into
        # a candidate; only explicitly work-like lines or list bullets.
        if not m and not _ACTION.match(segment):
            offset += len(raw)
            continue
        if not _ACTION.match(segment):
            offset += len(raw)
            continue
        start = offset + leading
        end = start + len(segment)
        if text[start:end] != segment:
            raise BrainError("Candidate source offsets are inconsistent.")
        actor = "unknown"
        lower = segment.casefold()
        if re.match(r"^(?:my teammate|teammate|my cofounder|cofounder)\b", lower):
            actor = "teammate"
        elif re.match(r"^(?:we\b|our team\b)", lower):
            actor = "team"
        elif re.match(r"^(?:i\b|i've\b|i have\b)", lower):
            actor = "self"
        # Even explicit actor hints are NOT user-verified. The reviewer must
        # confirm and can correct ownership with an explicit local action.
        rows.append(ExtractedCandidate(segment, start, end, line_number,
                                       actor, True))
        if len(rows) > MAX_CANDIDATES:
            raise BrainError("Too many candidate lines in selected text.")
        offset += len(raw)
    return tuple(rows)


class ReviewGateway:
    """An in-process boundary wired to a future trusted local UI callback.

    The opaque capability must be held only by the host, never by the parser,
    model input or imported document. Identity comparison blocks arbitrary
    strings and forged review receipts at this *process* boundary. It does
    NOT prove physical user presence or protect against malicious Python
    executing inside the same process. No native UI is built in B0.
    """

    def __init__(self, store: BrainStore, *, host_capability: object) -> None:
        if not isinstance(store, BrainStore):
            raise TypeError("BrainStore is required.")
        if (host_capability is None or
                isinstance(host_capability, (str, bytes, int, float, bool))):
            raise BrainError("Use an opaque trusted host capability object.")
        # Register one gateway per store lifetime. Model/parser code must never
        # be handed either the host capability or this ledger authorization.
        ledger_guard = object()
        store._bind_resume_review_gate(ledger_guard)
        self.__ledger_guard = ledger_guard
        self._store = store
        self.__host_capability = host_capability

    def _require_host(self, capability: object) -> None:
        if capability is not self.__host_capability:
            raise MissingEvidence("Explicit host review action required.")

    def select_source(self, synthetic_text: str, *, observed_at: str,
                      capability: object,
                      raw_document_sha256: str | None = None) -> str:
        """Trusted-host simulation of selecting a single résumé text source.

        This deliberately takes a string, not a filename/URL: no real import
        or file-permission path is implemented.
        """
        self._require_host(capability)
        extract_synthetic_candidates(synthetic_text)  # Validate size early.
        external_ref = None
        if raw_document_sha256 is not None:
            if (not isinstance(raw_document_sha256, str) or
                    re.fullmatch(r"[0-9a-f]{64}", raw_document_sha256) is None):
                raise BrainError("Invalid original document digest.")
            external_ref = "document-sha256:" + raw_document_sha256
        timestamp = _observed(observed_at)
        source_id = self._store.register_source(
            kind="resume", observed_at=timestamp, external_ref=external_ref,
            checksum=_digest(synthetic_text)
        )
        self._store.grant_consent(source_id, confirmation=UserConfirmation(
            "review-source:" + secrets.token_urlsafe(24)
        ))
        return source_id

    def stage(self, source_id: str, synthetic_text: str, *,
              observed_at: str) -> tuple[ReviewCard, ...]:
        """Only makes UNVERIFIED candidates. Re-select if content changes."""
        items = extract_synthetic_candidates(synthetic_text)
        stamp = _observed(observed_at)
        source_sha = _digest(synthetic_text)
        # Source checks, every insert and every preview share one commit.
        # A later duplicate or failed preview must leave no hidden candidates.
        with self._store._transaction():
            source = self._store._get("source", source_id)
            self._store._source_usable(source_id)
            if source["kind"] != "resume" or source["checksum"] != source_sha:
                raise MissingEvidence("Selected document revision does not match.")
            cards: list[ReviewCard] = []
            for item in items:
                new_id = self._store.stage_resume_candidate(
                    source_id=source_id, claim_key="resume.pending." + source_id +
                    "." + str(item.span_start),
                    claim_text=item.snippet, actor=item.actor_hint,
                    observed_at=stamp, document_sha256=source_sha,
                    span_start=item.span_start, span_end=item.span_end,
                )
                cards.append(self.preview(new_id))
        return tuple(cards)

    def preview(self, fact_id: str) -> ReviewCard:
        """Read a still-pending source-bound snapshot from SQLite v2."""
        fact_id = _required(fact_id, "candidate ID", limit=80)
        row = self._store.db.execute(
            "SELECT c.id, c.source_id, c.claim_text, c.actor, c.state, "
            "e.source_sha256, e.snippet_sha256, e.span_start, e.span_end,"
            "e.review_revision FROM candidate_fact c"
            " JOIN candidate_evidence e ON e.fact_id=c.id WHERE c.id=?",
            (fact_id,),
        ).fetchone()
        if row is None or row["state"] != "candidate":
            raise InvalidState("Review candidate is no longer pending.")
        self._store._source_usable(row["source_id"])
        source = self._store._get("source", row["source_id"])
        if source["checksum"] != row["source_sha256"]:
            raise MissingEvidence("Review source revision is stale.")
        if row["claim_text"] is None or _digest(row["claim_text"]) != row["snippet_sha256"]:
            raise MissingEvidence("Candidate text no longer matches evidence.")
        identity = "|".join((
            row["id"], row["source_id"], row["source_sha256"],
            row["snippet_sha256"], str(row["span_start"]),
            str(row["span_end"]), str(row["review_revision"]), row["actor"],
        ))
        card = ReviewCard(
            fact_id=row["id"], source_id=row["source_id"],
            source_sha256=row["source_sha256"], snippet=row["claim_text"],
            snippet_sha256=row["snippet_sha256"],
            span_start=row["span_start"], span_end=row["span_end"],
            review_revision=row["review_revision"],
            actor_hint=row["actor"], card_fingerprint=_digest(identity),
        )
        structured = self._store.db.execute(
            'SELECT * FROM candidate_resume_context WHERE fact_id=?', (fact_id,)).fetchone()
        if structured is None: return card
        context = decode_context(structured['context_json'])
        if context_digest(asdict(context)) != structured['context_sha256']:
            raise MissingEvidence('Résumé context no longer matches review evidence.')
        location = self._store.db.execute('SELECT locator FROM profile_locator WHERE fact_id=?', (fact_id,)).fetchone()
        if location is None: raise MissingEvidence('Résumé claim location is missing.')
        from .resume_structure import _text
        _text(card.snippet, 600, 2400)
        if (not 0 <= card.span_start < card.span_end <= MAX_SELECTED_CHARS or
                card.span_end-card.span_start != len(card.snippet) or
                re.fullmatch(r'(?:text:line|pdf:page|docx:paragraph):[1-9][0-9]*', location[0]) is None or
                len(location[0]) > 80):
            raise MissingEvidence('Résumé claim source bounds are invalid.')
        result = ReviewCardV2(**asdict(card), schema_version=2, claim_kind=structured['claim_kind'],
            review_context=context, context_sha256=structured['context_sha256'], locator=location[0])
        payload = asdict(result); del payload['card_fingerprint']
        result = replace(result, card_fingerprint=context_digest(payload))
        from .resume_structure import canonical
        if len(canonical(asdict(result)).encode()) > 12*1024:
            raise BrainError('Résumé review card exceeds its frame budget.')
        return result

    def decide(self, card: ReviewCard, *, decision: str,
               capability: object, approved_actor: str | None = None,
               claim_key: str | None = None,
               replaces_fact_id: str | None = None) -> None:
        """Must be called from a synchronous host-controlled review action.

        Each call generates a fresh one-use confirmation ID. A stale card,
        forged capability, changed source or previous approval fails closed.
        """
        if isinstance(card, ReviewCardV2):
            raise MissingEvidence('Use the context-aware review action for this card.')
        self._decide(card, decision=decision, capability=capability, approved_actor=approved_actor,
            claim_key=claim_key, replaces_fact_id=replaces_fact_id)

    def decide_v2(self, card: ReviewCardV2, *, decision: str, capability: object,
                  context_sha256: str, approved_actor: str | None = None,
                  claim_key: str | None = None, replaces_fact_id: str | None = None) -> None:
        if not isinstance(card, ReviewCardV2) or context_sha256 != card.context_sha256:
            raise MissingEvidence('Displayed résumé context is stale.')
        self._decide(card, decision=decision, capability=capability, approved_actor=approved_actor,
            claim_key=claim_key, replaces_fact_id=replaces_fact_id, expected_context_sha256=context_sha256)

    def _decide(self, card, *, decision, capability, approved_actor=None, claim_key=None,
                replaces_fact_id=None, expected_context_sha256=None):
        self._require_host(capability)
        if not isinstance(card, ReviewCard) or self.preview(card.fact_id) != card:
            raise MissingEvidence("Reviewed card is stale or invalid.")
        receipt = UserConfirmation("review-decision:" + secrets.token_urlsafe(24))
        if decision == "reject":
            if approved_actor is not None or claim_key is not None or replaces_fact_id is not None:
                raise BrainError("Rejection must not include approval details.")
            self._store.reject_candidate(card.fact_id, confirmation=receipt)
        elif decision == "approve":
            if approved_actor not in ("self", "team", "teammate"):
                raise MissingEvidence("Reviewer must explicitly select attribution.")
            if card.actor_hint != "unknown" and approved_actor != card.actor_hint:
                # A reviewed team or teammate sentence cannot be rewritten
                # as the user's own individual work by changing only metadata.
                # Reject/replace the source statement and require new evidence.
                raise MissingEvidence("Reviewer attribution conflicts with source text.")
            if claim_key is None:
                raise MissingEvidence("Reviewer must select canonical claim key.")
            self._store.confirm_fact(
                card.fact_id, confirmation=receipt,
                reviewed_actor=approved_actor, reviewed_claim_key=claim_key,
                expected_snippet_sha256=card.snippet_sha256,
                expected_context_sha256=expected_context_sha256,
                replaces_fact_id=replaces_fact_id,
                reviewer_token=self.__ledger_guard,
            )
        else:
            raise BrainError("Unknown review decision.")

    def revoke_selected_source(self, source_id: str, *,
                               capability: object) -> None:
        self._require_host(capability)
        self._store.revoke_source(
            source_id, confirmation=UserConfirmation(
                "review-revoke:" + secrets.token_urlsafe(24)
            )
        )
