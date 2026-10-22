"""Relay Personal Brain 02A-A: local, evidence-scoped fact lifecycle.

No model calls, network, résumé import, logging or user-account integrations.
This is a synthetic-only persistence contract. A future trusted UI must issue
UserConfirmation after a real user action; constructing this Python value is
NOT proof of human identity or consent.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
from hashlib import sha256
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
from typing import Iterator
from uuid import uuid4


class BrainError(ValueError):
    """Safe, non-content-bearing Personal Brain validation error."""


class MissingEvidence(BrainError):
    """Required permission, provenance or approval is missing."""


class FactConflict(BrainError):
    """Another active verified fact already owns this claim key."""


class InvalidState(BrainError):
    """A candidate or source is not in the requested lifecycle state."""


ACTORS = frozenset(("self", "teammate", "team", "unknown"))
SOURCES = frozenset(("user_statement", "resume", "github", "drive",
                     "model_suggestion", "transcript"))
SCHEMA_VERSION = 2

SCHEMA = """
CREATE TABLE source (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK (kind IN
        ('user_statement','resume','github','drive','model_suggestion','transcript')),
    external_ref TEXT,
    checksum TEXT,
    observed_at TEXT NOT NULL,
    consent_scope TEXT NOT NULL DEFAULT 'none'
        CHECK (consent_scope IN ('none','personal_brain')),
    consented_at TEXT,
    revoked_at TEXT
);
CREATE TABLE experience (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES source(id),
    label TEXT,
    created_at TEXT NOT NULL,
    revoked_at TEXT
);
CREATE TABLE candidate_fact (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES source(id),
    experience_id TEXT REFERENCES experience(id),
    claim_key TEXT,
    claim_text TEXT,
    actor TEXT NOT NULL CHECK (actor IN ('self','teammate','team','unknown')),
    state TEXT NOT NULL DEFAULT 'candidate'
        CHECK (state IN ('candidate','confirmed','rejected','superseded','revoked')),
    observed_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE history_event (
    id TEXT PRIMARY KEY,
    source_id TEXT REFERENCES source(id),
    fact_id TEXT REFERENCES candidate_fact(id),
    action TEXT NOT NULL CHECK (action IN
       ('consent_granted','fact_confirmed','fact_rejected','fact_superseded',
        'fact_revoked','source_revoked','source_invalidated')),
    confirmation_id TEXT UNIQUE,
    recorded_at TEXT NOT NULL,
    CHECK (source_id IS NOT NULL OR fact_id IS NOT NULL)
);
CREATE TABLE verified_fact (
    fact_id TEXT PRIMARY KEY REFERENCES candidate_fact(id),
    claim_key TEXT,
    confirmation_event_id TEXT NOT NULL UNIQUE REFERENCES history_event(id),
    confirmed_at TEXT NOT NULL,
    invalidated_at TEXT,
    invalidation_reason TEXT
);
CREATE UNIQUE INDEX one_active_verified_claim_per_key
    ON verified_fact(claim_key) WHERE invalidated_at IS NULL;
CREATE INDEX candidate_source_idx ON candidate_fact(source_id);
CREATE INDEX candidate_experience_idx ON candidate_fact(experience_id);
CREATE INDEX history_fact_idx ON history_event(fact_id);
CREATE TRIGGER immutable_history_update BEFORE UPDATE ON history_event
BEGIN SELECT RAISE(ABORT, 'history events are immutable'); END;
CREATE TRIGGER immutable_history_delete BEFORE DELETE ON history_event
BEGIN SELECT RAISE(ABORT, 'history events are immutable'); END;
"""

# Provenance metadata only. Claim text is stored in candidate_fact and is
# purged by existing rejection/revocation lifecycle. This table never stores
# a full selected document body, model response, or real file pathname.
EVIDENCE_SCHEMA = """
CREATE TABLE candidate_evidence (
    fact_id TEXT PRIMARY KEY REFERENCES candidate_fact(id),
    source_id TEXT NOT NULL REFERENCES source(id),
    source_sha256 TEXT NOT NULL CHECK(length(source_sha256)=64),
    snippet_sha256 TEXT NOT NULL CHECK(length(snippet_sha256)=64),
    span_start INTEGER NOT NULL CHECK(span_start>=0),
    span_end INTEGER NOT NULL CHECK(span_end>span_start),
    review_revision INTEGER NOT NULL DEFAULT 1 CHECK(review_revision>=1)
);
CREATE INDEX candidate_evidence_source_idx ON candidate_evidence(source_id);
CREATE UNIQUE INDEX candidate_evidence_one_span_per_source ON candidate_evidence(source_id,span_start,span_end);
"""


@dataclass(frozen=True)
class UserConfirmation:
    """Opaque reference minted ONLY by a future trusted user-action boundary."""

    event_id: str


@dataclass(frozen=True)
class VerifiedClaim:
    fact_id: str
    claim_key: str
    claim_text: str
    actor: str
    source_id: str
    experience_id: str | None
    confirmed_at: str


@dataclass(frozen=True)
class HistoryEntry:
    id: str
    source_id: str | None
    fact_id: str | None
    action: str
    recorded_at: str
    confirmation_id: str | None


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _required(value: str, field: str, *, limit: int = 2048) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise BrainError("Invalid " + field + ".")
    return value.strip()


def _observed(value: str) -> str:
    _required(value, "observation time", limit=64)
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise BrainError("Observation time must be ISO-8601.") from None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise BrainError("Observation time must include a timezone.")
    return parsed.isoformat()


class BrainStore:
    """Explicitly local SQLite store, single-connection writer.

    In-memory by default. Passing a disk path is an explicit storage choice,
    NOT proof of encryption or permission to import real personal documents.
    Every write below is an atomic SQLite transaction.
    """

    def __init__(self, path: str | Path = ":memory:") -> None:
        # A future trusted host binds at most one in-process review gateway.
        # This protects accidental direct v2 confirmation, not malicious
        # Python with arbitrary access to this store or the OS user session.
        self.__resume_review_gate: object | None = None
        self.db = sqlite3.connect(str(path), isolation_level=None)
        try:
            self.db.row_factory = sqlite3.Row
            self.db.execute("PRAGMA foreign_keys=ON")
            if self.db.execute("PRAGMA foreign_keys").fetchone()[0] != 1:
                raise BrainError("SQLite foreign-key enforcement unavailable.")
            self.db.execute("PRAGMA secure_delete=ON")
            self.db.execute("PRAGMA busy_timeout=1500")
            self._migrate()
        except BaseException:
            self.db.close()
            raise

    def __enter__(self) -> "BrainStore":
        return self

    def __exit__(self, *unused: object) -> None:
        self.close()

    def close(self) -> None:
        self.db.close()

    def _migrate(self) -> None:
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version > SCHEMA_VERSION or version < 0:
            raise BrainError("Unsupported Personal Brain schema version.")
        if version == 0:
            # Keep pre-existing v1 on-disk databases compatible. Each step is
            # transactional; v2 never claims to be installed if its DDL fails.
            try:
                self.db.executescript("BEGIN IMMEDIATE;\n" + SCHEMA +
                                      "\nPRAGMA user_version=1;\nCOMMIT;")
            except sqlite3.Error:
                if self.db.in_transaction:
                    self.db.execute("ROLLBACK")
                raise BrainError("Personal Brain migration failed.") from None
            version = 1
        if version == 1:
            try:
                self.db.executescript("BEGIN IMMEDIATE;\n" + EVIDENCE_SCHEMA +
                                      "\nPRAGMA user_version=2;\nCOMMIT;")
            except sqlite3.Error:
                if self.db.in_transaction:
                    self.db.execute("ROLLBACK")
                raise BrainError("Personal Brain migration failed.") from None
        if self.db.execute("PRAGMA foreign_key_check").fetchone() is not None:
            raise BrainError("Personal Brain foreign-key integrity check failed.")

    @contextmanager
    def _transaction(self) -> Iterator[None]:
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
            self.db.execute("COMMIT")
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def _get(self, table: str, row_id: str) -> sqlite3.Row:
        # Internal allowlist prevents caller-controlled identifier interpolation.
        if table not in ("source", "experience", "candidate_fact", "verified_fact"):
            raise BrainError("Invalid table.")
        row = self.db.execute(
            "SELECT * FROM " + table + " WHERE " +
            ("fact_id" if table == "verified_fact" else "id") + "=?", (row_id,),
        ).fetchone()
        if row is None:
            raise MissingEvidence("Requested record is unavailable.")
        return row

    def _source_usable(self, source_id: str) -> None:
        source = self._get("source", source_id)
        if source["revoked_at"] is not None or source["consent_scope"] != "personal_brain":
            raise MissingEvidence("Source lacks active Personal Brain consent.")

    def _confirmation(self, confirmation: UserConfirmation) -> str:
        if not isinstance(confirmation, UserConfirmation):
            raise MissingEvidence("Explicit trusted user confirmation required.")
        event_id = _required(confirmation.event_id, "confirmation ID", limit=128)
        used = self.db.execute(
            "SELECT 1 FROM history_event WHERE confirmation_id=?", (event_id,)
        ).fetchone()
        if used is not None:
            raise InvalidState("Confirmation reference already used.")
        return event_id

    def _event(self, action: str, *, source_id: str | None = None,
               fact_id: str | None = None, confirmation_id: str | None = None) -> str:
        event_id = uuid4().hex
        self.db.execute(
            "INSERT INTO history_event "
            "(id,source_id,fact_id,action,confirmation_id,recorded_at) "
            "VALUES (?,?,?,?,?,?)",
            (event_id, source_id, fact_id, action, confirmation_id, _now()),
        )
        return event_id

    def register_source(self, *, kind: str, observed_at: str,
                        external_ref: str | None = None,
                        checksum: str | None = None) -> str:
        if kind not in SOURCES:
            raise BrainError("Unknown source kind.")
        observed_at = _observed(observed_at)
        if external_ref is not None:
            external_ref = _required(external_ref, "source reference")
        if checksum is not None:
            checksum = _required(checksum, "checksum", limit=128)
        source_id = uuid4().hex
        with self._transaction():
            self.db.execute(
                "INSERT INTO source(id,kind,external_ref,checksum,observed_at)"
                " VALUES (?,?,?,?,?)",
                (source_id, kind, external_ref, checksum, observed_at),
            )
        return source_id

    def grant_consent(self, source_id: str, *, confirmation: UserConfirmation) -> None:
        with self._transaction():
            ref = self._confirmation(confirmation)
            source = self._get("source", source_id)
            if source["revoked_at"] is not None or source["consent_scope"] != "none":
                raise InvalidState("Source cannot receive consent in this state.")
            self.db.execute(
                "UPDATE source SET consent_scope='personal_brain', consented_at=? WHERE id=?",
                (_now(), source_id),
            )
            self._event("consent_granted", source_id=source_id, confirmation_id=ref)

    def add_experience(self, *, source_id: str, label: str) -> str:
        label = _required(label, "experience label", limit=200)
        experience_id = uuid4().hex
        with self._transaction():
            self._source_usable(source_id)
            self.db.execute(
                "INSERT INTO experience(id,source_id,label,created_at)"
                " VALUES (?,?,?,?)",
                (experience_id, source_id, label, _now()),
            )
        return experience_id

    def add_candidate(self, *, source_id: str, claim_key: str, claim_text: str,
                      actor: str, observed_at: str,
                      experience_id: str | None = None) -> str:
        claim_key = _required(claim_key, "claim key", limit=160)
        claim_text = _required(claim_text, "candidate claim", limit=2000)
        observed_at = _observed(observed_at)
        if actor not in ACTORS:
            raise BrainError("Unknown actor attribution.")
        fact_id = uuid4().hex
        with self._transaction():
            self._source_usable(source_id)
            if experience_id is not None:
                experience = self._get("experience", experience_id)
                if experience["revoked_at"] is not None:
                    raise MissingEvidence("Experience is no longer available.")
                self._source_usable(experience["source_id"])
            self.db.execute(
                "INSERT INTO candidate_fact"
                " (id,source_id,experience_id,claim_key,claim_text,actor,"
                "  observed_at,created_at) VALUES (?,?,?,?,?,?,?,?)",
                (fact_id, source_id, experience_id, claim_key,
                 claim_text, actor, observed_at, _now()),
            )
        return fact_id

    def _bind_resume_review_gate(self, gate: object) -> None:
        """Register exactly one trusted-host adapter for this store lifetime."""
        if gate is None or self.__resume_review_gate is not None:
            raise InvalidState("Résumé review boundary is already bound or invalid.")
        self.__resume_review_gate = gate

    def stage_resume_candidate(self, *, source_id: str, claim_key: str,
                               claim_text: str, actor: str, observed_at: str,
                               document_sha256: str, span_start: int,
                               span_end: int) -> str:
        """Atomically stage a selected *synthetic-text* résumé snippet only.

        This is not an approval. The external caller must verify the exact
        selected document digest and offsets before supplying these values.
        """
        claim_key = _required(claim_key, "candidate key", limit=160)
        claim_text = _required(claim_text, "candidate text", limit=2000)
        observed_at = _observed(observed_at)
        if actor not in ACTORS:
            raise BrainError("Invalid attribution.")
        if (type(span_start) is not int or type(span_end) is not int or
                span_start < 0 or span_end <= span_start or
                span_end - span_start != len(claim_text)):
            raise BrainError("Invalid candidate source span.")
        if (not isinstance(document_sha256, str) or
                len(document_sha256) != 64 or
                any(char not in "0123456789abcdef" for char in document_sha256)):
            raise BrainError("Invalid selected-source checksum.")
        with self._transaction():
            self._source_usable(source_id)
            source = self._get("source", source_id)
            if source["kind"] != "resume" or source["checksum"] != document_sha256:
                raise MissingEvidence("Source content/revision does not match.")
            fact_id = uuid4().hex
            self.db.execute(
                "INSERT INTO candidate_fact "
                "(id,source_id,claim_key,claim_text,actor,observed_at,created_at)"
                " VALUES (?,?,?,?,?,?,?)",
                (fact_id, source_id, claim_key, claim_text, actor, observed_at, _now()),
            )
            try:
                self.db.execute(
                    "INSERT INTO candidate_evidence "
                    "(fact_id,source_id,source_sha256,snippet_sha256,span_start,span_end)"
                    " VALUES (?,?,?,?,?,?)",
                    (fact_id, source_id, document_sha256,
                     sha256(claim_text.encode("utf-8")).hexdigest(),
                     span_start, span_end),
                )
            except sqlite3.IntegrityError:
                raise InvalidState("Source span has already been staged.") from None
        return fact_id

    def confirm_fact(self, fact_id: str, *, confirmation: UserConfirmation,
                     replaces_fact_id: str | None = None,
                     reviewed_actor: str | None = None,
                     reviewed_claim_key: str | None = None,
                     expected_snippet_sha256: str | None = None,
                     reviewer_token: object | None = None) -> None:
        """Confirm explicitly, optionally superseding exactly one trusted claim.

        Contradictory candidates for an existing key must use replaces_fact_id.
        Both the invalidation and new verified claim commit atomically.
        """
        with self._transaction():
            ref = self._confirmation(confirmation)
            candidate = self._get("candidate_fact", fact_id)
            if candidate["state"] != "candidate":
                raise InvalidState("Only pending candidate facts can be confirmed.")
            has_resume_evidence = self.db.execute(
                "SELECT 1 FROM candidate_evidence WHERE fact_id=?", (fact_id,)
            ).fetchone() is not None
            if has_resume_evidence and (
                    self.__resume_review_gate is None or
                    reviewer_token is not self.__resume_review_gate):
                raise MissingEvidence("Use the registered host review boundary.")
            if not has_resume_evidence and reviewer_token is not None:
                raise BrainError("Review authorization cannot apply to legacy facts.")
            if any(value is not None for value in
                   (reviewed_actor, reviewed_claim_key, expected_snippet_sha256)):
                if not all(value is not None for value in
                           (reviewed_actor, reviewed_claim_key, expected_snippet_sha256)):
                    raise BrainError("Incomplete reviewed approval evidence.")
                if reviewed_actor not in ("self", "team", "teammate"):
                    raise MissingEvidence("Reviewer must resolve attribution.")
                reviewed_claim_key = _required(reviewed_claim_key, "approved claim key",
                                               limit=160)
                row = self.db.execute(
                    "SELECT snippet_sha256,source_sha256 FROM candidate_evidence "
                    "WHERE fact_id=?", (fact_id,),
                ).fetchone()
                if (row is None or row["snippet_sha256"] != expected_snippet_sha256
                        or row["snippet_sha256"] !=
                        sha256(candidate["claim_text"].encode("utf-8")).hexdigest()):
                    raise MissingEvidence("Reviewed snapshot is stale or invalid.")
                source = self._get("source", candidate["source_id"])
                if source["checksum"] != row["source_sha256"]:
                    raise MissingEvidence("Selected source revision changed.")
                self.db.execute(
                    "UPDATE candidate_fact SET actor=?,claim_key=? WHERE id=?",
                    (reviewed_actor, reviewed_claim_key, fact_id),
                )
                candidate = self._get("candidate_fact", fact_id)
            elif self.db.execute(
                "SELECT 1 FROM candidate_evidence WHERE fact_id=?", (fact_id,)
            ).fetchone() is not None:
                # Resume-derived candidates can never use the legacy confirmation
                # shortcut; they require an explicit reviewed actor + digest.
                raise MissingEvidence("Résumé candidate needs a reviewed snapshot.")
            if candidate["actor"] == "unknown":
                raise MissingEvidence("Attribution must be explicitly resolved.")
            self._source_usable(candidate["source_id"])
            if candidate["experience_id"] is not None:
                exp = self._get("experience", candidate["experience_id"])
                if exp["revoked_at"] is not None:
                    raise MissingEvidence("Experience is revoked.")
                self._source_usable(exp["source_id"])
            active = self.db.execute(
                "SELECT fact_id FROM verified_fact WHERE claim_key=?"
                " AND invalidated_at IS NULL",
                (candidate["claim_key"],),
            ).fetchone()
            if active is None and replaces_fact_id is not None:
                raise FactConflict("No active fact exists to supersede.")
            if active is not None:
                if active["fact_id"] != replaces_fact_id:
                    raise FactConflict("Conflicting active verified claim.")
                self.db.execute(
                    "UPDATE verified_fact SET invalidated_at=?,"
                    " invalidation_reason='superseded' WHERE fact_id=?",
                    (_now(), replaces_fact_id),
                )
                self.db.execute(
                    "UPDATE candidate_fact SET state='superseded' WHERE id=?",
                    (replaces_fact_id,),
                )
                self._event("fact_superseded", fact_id=replaces_fact_id)
            event_id = self._event(
                "fact_confirmed", fact_id=fact_id, confirmation_id=ref
            )
            self.db.execute(
                "INSERT INTO verified_fact"
                "(fact_id,claim_key,confirmation_event_id,confirmed_at)"
                " VALUES (?,?,?,?)",
                (fact_id, candidate["claim_key"], event_id, _now()),
            )
            self.db.execute(
                "UPDATE candidate_fact SET state='confirmed' WHERE id=?",
                (fact_id,),
            )

    def reject_candidate(self, fact_id: str, *, confirmation: UserConfirmation) -> None:
        with self._transaction():
            ref = self._confirmation(confirmation)
            fact = self._get("candidate_fact", fact_id)
            if fact["state"] != "candidate":
                raise InvalidState("Only pending candidates can be rejected.")
            self.db.execute(
                "UPDATE candidate_fact SET state='rejected',claim_text=NULL,"
                "claim_key=NULL WHERE id=?",
                (fact_id,),
            )
            self.db.execute("DELETE FROM candidate_evidence WHERE fact_id=?", (fact_id,))
            self._event("fact_rejected", fact_id=fact_id, confirmation_id=ref)

    def revoke_fact(self, fact_id: str, *, confirmation: UserConfirmation) -> None:
        with self._transaction():
            ref = self._confirmation(confirmation)
            fact = self._get("candidate_fact", fact_id)
            approved = self.db.execute(
                "SELECT 1 FROM verified_fact WHERE fact_id=? AND invalidated_at IS NULL",
                (fact_id,),
            ).fetchone()
            if fact["state"] != "confirmed" or approved is None:
                raise InvalidState("Only active verified facts can be revoked.")
            self.db.execute(
                "UPDATE verified_fact SET invalidated_at=?,invalidation_reason='user_revoked',"
                "claim_key=NULL WHERE fact_id=?", (_now(), fact_id),
            )
            self.db.execute(
                "UPDATE candidate_fact SET state='revoked',claim_key=NULL,"
                "claim_text=NULL WHERE id=?", (fact_id,),
            )
            self.db.execute("DELETE FROM candidate_evidence WHERE fact_id=?", (fact_id,))
            self._event("fact_revoked", fact_id=fact_id, confirmation_id=ref)

    def revoke_source(self, source_id: str, *, confirmation: UserConfirmation) -> None:
        """Revoke consent, invalidate all dependent evidence and redact content.

        Retains only opaque IDs and non-content audit markers, never old claim
        text or a source external reference. Does not delete SQLite backups.
        """
        with self._transaction():
            ref = self._confirmation(confirmation)
            source = self._get("source", source_id)
            if source["revoked_at"] is not None:
                raise InvalidState("Source is already revoked.")
            targets = self.db.execute(
                "SELECT c.id FROM candidate_fact c WHERE c.source_id=? OR"
                " c.experience_id IN (SELECT id FROM experience WHERE source_id=?)",
                (source_id, source_id),
            ).fetchall()
            for row in targets:
                fact_id = row["id"]
                active = self.db.execute(
                    "SELECT 1 FROM verified_fact WHERE fact_id=? AND invalidated_at IS NULL",
                    (fact_id,),
                ).fetchone()
                if active is not None:
                    self.db.execute(
                        "UPDATE verified_fact SET invalidated_at=?,"
                        " invalidation_reason='source_revoked' WHERE fact_id=?",
                        (_now(), fact_id),
                    )
                # Redact every dependency, not just direct-source candidates:
                # the experience source might be revoked while the claim
                # came from a different, still-consented source.
                self.db.execute(
                    "UPDATE verified_fact SET claim_key=NULL WHERE fact_id=?",
                    (fact_id,),
                )
                self.db.execute(
                    "UPDATE candidate_fact SET state='revoked',"
                    "claim_text=NULL,claim_key=NULL WHERE id=?",
                    (fact_id,),
                )
                self.db.execute(
                    "DELETE FROM candidate_evidence WHERE fact_id=?", (fact_id,),
                )
                self._event("source_invalidated", fact_id=fact_id)
            self.db.execute(
                "UPDATE experience SET label=NULL,revoked_at=? WHERE source_id=?",
                (_now(), source_id),
            )
            self.db.execute(
                "UPDATE source SET consent_scope='none',revoked_at=?,"
                " external_ref=NULL,checksum=NULL WHERE id=?",
                (_now(), source_id),
            )
            self._event("source_revoked", source_id=source_id, confirmation_id=ref)

    def verified_claims(self, *, actor: str | None = None,
                        claim_key: str | None = None) -> tuple[VerifiedClaim, ...]:
        """Return only active, user-confirmed, fully consented claims.

        This is the future QA retrieval contract. The returned source IDs are
        provenance pointers, NOT automatic proof that a generated sentence is
        faithful to these records.
        """
        if actor is not None and actor not in ACTORS:
            raise BrainError("Unknown actor filter.")
        conditions = [
            "v.invalidated_at IS NULL", "c.state='confirmed'",
            "s.consent_scope='personal_brain'", "s.revoked_at IS NULL",
            "c.claim_text IS NOT NULL", "c.claim_key IS NOT NULL",
            "(e.id IS NULL OR (e.revoked_at IS NULL AND"
            " es.consent_scope='personal_brain' AND es.revoked_at IS NULL))",
        ]
        args: list[str] = []
        if actor is not None:
            conditions.append("c.actor=?")
            args.append(actor)
        if claim_key is not None:
            conditions.append("c.claim_key=?")
            args.append(_required(claim_key, "claim key", limit=160))
        sql = (
            "SELECT c.id,c.claim_key,c.claim_text,c.actor,c.source_id,"
            " c.experience_id,v.confirmed_at FROM verified_fact v"
            " JOIN candidate_fact c ON c.id=v.fact_id"
            " JOIN source s ON s.id=c.source_id"
            " LEFT JOIN experience e ON e.id=c.experience_id"
            " LEFT JOIN source es ON es.id=e.source_id"
            " WHERE " + " AND ".join(conditions) +
            " ORDER BY c.claim_key,c.id"
        )
        return tuple(VerifiedClaim(
            fact_id=row["id"], claim_key=row["claim_key"],
            claim_text=row["claim_text"], actor=row["actor"],
            source_id=row["source_id"], experience_id=row["experience_id"],
            confirmed_at=row["confirmed_at"],
        ) for row in self.db.execute(sql, args))

    def verified_by_fact_id(self, fact_id: str) -> VerifiedClaim | None:
        _required(fact_id, "fact ID", limit=64)
        return next((fact for fact in self.verified_claims()
                     if fact.fact_id == fact_id), None)

    def history(self) -> tuple[HistoryEntry, ...]:
        """IDs/timestamps/action labels only; never raw candidate text."""
        rows = self.db.execute(
            "SELECT id,source_id,fact_id,action,recorded_at,confirmation_id"
            " FROM history_event ORDER BY rowid"
        )
        return tuple(HistoryEntry(**dict(row)) for row in rows)
