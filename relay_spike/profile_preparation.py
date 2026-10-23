"""Preparation service for the native selected-file/review host.

This module never opens a path, writes a database, reads a Keychain item, or
automatically approves a claim. Production callers must be the native owner
of the encrypted vault and inherited helper pipes. Capabilities here prevent
accidental misuse, not malicious code already executing in the helper.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import sqlite3

from .document_conversion import MAX_INPUT_BYTES, convert_document, stage_converted, _validate_for_staging
from .personal_brain import BrainError, BrainStore, MissingEvidence, _observed, _required
from .personal_context import BrainContextProvider
from .resume_candidates import ReviewCard, ReviewGateway, MAX_SELECTED_CHARS

MAX_SNAPSHOT_BYTES = 8 * 1024 * 1024
MAX_SOURCES = 32
MAX_JOB_CHARS = 4_000

_SCHEMA = """
CREATE TABLE IF NOT EXISTS profile_source (
    source_id TEXT PRIMARY KEY REFERENCES source(id), purpose TEXT NOT NULL,
    label TEXT, role TEXT, project_hint TEXT
);
CREATE TABLE IF NOT EXISTS profile_locator (
    fact_id TEXT PRIMARY KEY REFERENCES candidate_fact(id), locator TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS profile_job_context (
    source_id TEXT PRIMARY KEY REFERENCES source(id), text TEXT,
    fingerprint TEXT, confirmed_at TEXT
);
CREATE TRIGGER IF NOT EXISTS profile_redact_source AFTER UPDATE OF revoked_at ON source
WHEN NEW.revoked_at IS NOT NULL BEGIN
    UPDATE profile_source SET label=NULL,role=NULL,project_hint=NULL WHERE source_id=NEW.id;
    UPDATE profile_job_context SET text=NULL,fingerprint=NULL WHERE source_id=NEW.id;
END;
CREATE TRIGGER IF NOT EXISTS profile_redact_locator AFTER UPDATE OF claim_text ON candidate_fact
WHEN NEW.claim_text IS NULL BEGIN
    DELETE FROM profile_locator WHERE fact_id=NEW.id;
END;
"""


@dataclass(frozen=True)
class JobReview:
    text: str
    source_sha256: str
    fingerprint: str


@dataclass(frozen=True)
class PreparedSource:
    source_id: str
    purpose: str
    cards: tuple[ReviewCard, ...]
    job_review: JobReview | None = None


def export_memory_snapshot(store: BrainStore) -> bytes:
    if store.db.execute("PRAGMA database_list").fetchone()[2] != "":
        raise BrainError("Only an in-memory profile may cross the vault boundary.")
    if store.db.in_transaction:
        raise BrainError("Profile mutation has not committed.")
    snapshot = store.db.serialize()
    if not snapshot or len(snapshot) > MAX_SNAPSHOT_BYTES:
        raise BrainError("Profile snapshot exceeds its bound.")
    return snapshot


def restore_memory_snapshot(snapshot: bytes) -> BrainStore:
    if (type(snapshot) is not bytes or not 0 < len(snapshot) <= MAX_SNAPSHOT_BYTES
            or not snapshot.startswith(b"SQLite format 3\x00")):
        raise BrainError("Invalid profile snapshot.")
    store = BrainStore()
    try:
        store.db.deserialize(snapshot)
        store.db.execute("PRAGMA foreign_keys=ON")
        store.db.execute("PRAGMA secure_delete=ON")
        store.db.execute("PRAGMA temp_store=MEMORY")
        if store.db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise BrainError("Profile integrity check failed.")
        store._migrate()
        return store
    except (sqlite3.Error, BrainError):
        store.close()
        raise BrainError("Profile snapshot could not be opened.") from None


class ProfilePreparation:
    def __init__(self, store: BrainStore, *, host_capability: object) -> None:
        if store.db.execute("PRAGMA database_list").fetchone()[2] != "":
            raise BrainError("Private preparation requires an in-memory ledger.")
        self.store = store
        self.__capability = host_capability
        self.gateway = ReviewGateway(store, host_capability=host_capability)
        store.db.executescript(_SCHEMA)
        self.provider = BrainContextProvider(store)

    def _host(self, capability: object) -> None:
        if capability is not self.__capability:
            raise MissingEvidence("Native preparation action required.")

    def select_bytes(self, data: bytes, *, file_type: str, purpose: str,
                     label: str, role: str, observed_at: str, capability: object,
                     project_hint: str | None = None) -> PreparedSource:
        self._host(capability)
        if purpose not in ("resume", "project", "job"):
            raise BrainError("Unsupported preparation purpose.")
        label = _required(label, "source label", limit=160)
        role = _required(role, "role", limit=160)
        stamp = _observed(observed_at)
        if project_hint is not None:
            project_hint = _required(project_hint, "project", limit=200)
        if type(data) is not bytes or not 0 < len(data) <= MAX_INPUT_BYTES:
            raise BrainError("Selected file exceeds its bound or is empty.")
        if file_type not in ("txt", "pdf", "docx"):
            raise BrainError("Unsupported selected file type.")
        if self.store.db.execute("SELECT COUNT(*) FROM source").fetchone()[0] >= MAX_SOURCES:
            raise BrainError("Profile source limit reached.")
        conversion = None
        if file_type == "txt":
            try:
                text = data.decode("utf-8-sig", errors="strict")
            except UnicodeDecodeError:
                raise BrainError("Selected text must be UTF-8.") from None
        else:
            conversion = convert_document(data, file_type=file_type, backend="native")
            if conversion.status != "converted":
                raise BrainError("Selected document cannot be converted with source locations.")
            _validate_for_staging(conversion)
            text = conversion.text
        if not text.strip() or len(text) > MAX_SELECTED_CHARS or "\x00" in text:
            raise BrainError("Selected text is empty, invalid or too large.")
        if purpose == "job" and (len(text) > MAX_JOB_CHARS or len(text.encode()) > 10_000 or
                any(ord(char) < 32 and char not in "\n\r\t" for char in text)):
            raise BrainError("Select a bounded plain-text job excerpt.")
        with self.store._transaction():
            if purpose == "job" or conversion is None:
                source_id = self.gateway.select_source(text, observed_at=stamp,
                        capability=capability, raw_document_sha256=sha256(data).hexdigest())
                cards = () if purpose == "job" else self.gateway.stage(source_id, text, observed_at=stamp)
            else:
                source_id, cards = stage_converted(conversion, self.gateway,
                        observed_at=stamp, capability=capability)
            self.store.db.execute(
                "INSERT INTO profile_source VALUES (?,?,?,?,?)",
                (source_id, purpose, label, role, project_hint))
            for card in cards:
                locator = "text:line:" + str(text.count("\n", 0, card.span_start) + 1)
                if conversion is not None:
                    matching = [s for s in conversion.segments
                                if s.start <= card.span_start < card.span_end <= s.end]
                    if len(matching) != 1:
                        raise MissingEvidence("Candidate source location is ambiguous.")
                    segment = matching[0]
                    locator = ("pdf:page:" + str(segment.page) if segment.page is not None
                               else "docx:paragraph:" + str(segment.paragraph))
                self.store.db.execute("INSERT INTO profile_locator VALUES (?,?)", (card.fact_id, locator))
            job_review = None
            if purpose == "job":
                source_sha = sha256(text.encode()).hexdigest()
                fingerprint = sha256((source_id + "|" + role + "|" + source_sha).encode()).hexdigest()
                self.store.db.execute("INSERT INTO profile_job_context VALUES (?,?,?,NULL)",
                                      (source_id, text, fingerprint))
                job_review = JobReview(text, source_sha, fingerprint)
        return PreparedSource(source_id, purpose, cards, job_review)

    def pending_cards(self) -> tuple[ReviewCard, ...]:
        return tuple(self.gateway.preview(row[0]) for row in self.store.db.execute(
            "SELECT c.id FROM candidate_fact c JOIN candidate_evidence e ON e.fact_id=c.id "
            "WHERE c.state='candidate' ORDER BY c.rowid"))

    def decide(self, fact_id: str, fingerprint: str, *, decision: str,
               capability: object, actor: str | None = None, claim_key: str | None = None,
               replaces_fact_id: str | None = None) -> None:
        self._host(capability)
        card = self.gateway.preview(fact_id)
        if card.card_fingerprint != fingerprint:
            raise MissingEvidence("Displayed review card is stale.")
        self.gateway.decide(card, decision=decision, capability=capability,
                            approved_actor=actor, claim_key=claim_key,
                            replaces_fact_id=replaces_fact_id)

    def approve_job(self, source_id: str, fingerprint: str, *, capability: object) -> None:
        self._host(capability)
        with self.store._transaction():
            self.store._source_usable(source_id)
            row = self.store.db.execute(
                "SELECT fingerprint,confirmed_at FROM profile_job_context WHERE source_id=?", (source_id,)
            ).fetchone()
            if row is None or row[0] != fingerprint or row[1] is not None:
                raise MissingEvidence("Displayed job context is stale.")
            from datetime import datetime, timezone
            self.store.db.execute("UPDATE profile_job_context SET confirmed_at=? WHERE source_id=?",
                                  (datetime.now(timezone.utc).isoformat(), source_id))

    def revoke(self, source_id: str, *, capability: object) -> None:
        self._host(capability)
        self.gateway.revoke_selected_source(source_id, capability=capability)
