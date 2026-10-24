# Personal Brain storage contract, Slice 02A-A

Status: local SQLite prototype on Python stdlib; synthetic tests only.
Implementation: [relay_spike/personal_brain.py](https://github.com/KanujVerma/relay/blob/e846c00012c73762fa4a599729a5c70b87e532be/relay_spike/personal_brain.py).
This is NOT an imported resume, a verified user profile, a secure shipping macOS
database, or an automatic AI memory engine.

## What gets reused, and what does not

| Upstream | License/status | Decision for Relay |
| --- | --- | --- |
| [SQLite](https://sqlite.org/) | Public domain, embedded transactional SQL | **Adopt now** via Python's stdlib sqlite3. Reuse foreign keys, partial unique indexes, transactions, triggers and schema migrations rather than reimplementing a database. SQLite foreign keys must be enabled on every connection. |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT, maintained Swift SQLite toolkit | **Preferred evaluation candidate for the later native macOS persistence adapter**, especially its migrations/observations. Do not add Swift/GRDB to the Python feasibility slice. Reconcile migrations/schema before adopting. |
| [Mem0](https://github.com/mem0ai/mem0) | Apache-2.0, agent long-term memory | **Reference only** for retrieval and learning signals. Its documented agent-fact promotion and ADD-only extraction are not equivalent to *user-confirmed autobiographical facts*. Copying that policy would violate Relay's provenance rule. |
| [Letta](https://github.com/letta-ai/letta) | Stateful agent platform; active code moved to letta-code | Reference only. A full agent runtime is excessive for a minimal, reviewable local fact ledger and could add latency/process overhead on the 16 GB target Mac. |
| [sqlite-vec](https://github.com/asg017/sqlite-vec) | Pre-v1 SQLite vector extension, MIT/Apache | Defer until real held-out retrieval tests show an advantage over indexed keyword and exact-ID lookups. No vector model or extension in 02A-A. |

Reviewed 2026-10-22. No third-party source code was vendored or copied in
this slice, so no new runtime dependency or upstream attribution obligation.
Earlier [research registry](REFERENCES.md) also covers ASR, audio, interview
UI, and unrelated SQL-analysis tools; those are outside this storage slice.

Official SQLite references:
- https://www.sqlite.org/foreignkeys.html
- https://www.sqlite.org/pragma.html (foreign_keys and secure_delete)
- https://www.sqlite.org/lang_createtrigger.html
- https://www.sqlite.org/fts5.html

## Primary design rule

An observed, model-generated or parsed statement is a **candidate**, not a
verified autobiographical fact. Verification is a separate, explicit
user-confirmed action. The caller must supply a UserConfirmation issued by
a future *trusted user interaction layer*. The Python dataclass itself is
not an authentication credential and cannot prove who clicked or consented.
There is deliberately NO automatic extraction-to-approval path.

Actors are separated explicitly: self, teammate, team, unknown. Unknown
attribution cannot be promoted. Team or teammate statements may be
user-confirmed as context, but only actor=self is usable when preparing
claims about **what the user personally implemented**. Do not equate the
existence of a source ID or a teammate's contribution with user experience.

## Original schema v1

- source: opaque ID, kind, optional external reference/checksum, observation
  time, consent scope, consent timestamp and revoked timestamp.
- experience: an untrusted source-backed project grouping and display label;
  it does NOT itself verify a project story or its individual's ownership.
- candidate_fact: a source/experience-linked claim with explicit actor,
  stable claim key, text, observed time and lifecycle state.
- verified_fact: only explicitly confirmed claim revisions, with a reference
  to the approval history event. A partial unique index permits only one
  **currently active** claim per key; contradictory candidates cannot both
  become active without explicit supersession.
- history_event: opaque source/fact IDs, action, confirmation ID and UTC time.
  There is no candidate text, resume snippet or private source body in audit
  events. UPDATE/DELETE triggers make decision history append-only under
  normal SQLite operations.

PR #26 adds a transactional v1-to-v2 migration and the candidate_evidence table for reviewed source spans, hashes and revision. Already-confirmed legacy facts remain readable; pending résumé facts must be restaged through the review gateway. See [RESUME_CANDIDATES.md](RESUME_CANDIDATES.md).

The original SQLite user_version=1 migration is transactional/idempotent; future database
versions fail closed. Every Python connection enables foreign_keys and
secure_delete. The current single-connection adapter uses BEGIN IMMEDIATE
transactions for state changes and rollback on conflicts.

## Consent, correction, revocation

1. Register metadata for a local source with timezone-aware observed_at.
   The initial consent scope is **none**. No raw document body is imported.
2. A trusted explicit user confirmation grants personal_brain scope.
   Candidate claims/experience labels can then be added. Model suggestions,
   transcript snippets and resume extractions remain candidates.
3. A different, fresh user confirmation can promote a pending candidate
   with known actor to verified. Retrieval shows only active confirmed
   claims whose own source and any experience source remain consented.
4. Another candidate for the same claim key cannot be simultaneously
   promoted. An explicit replacement points to the exact current verified
   fact. The prior fact is invalidated and the replacement is confirmed in
   **one transaction**, with separate immutable history events.
5. Rejection and fact revocation redact that candidate's text and key.
   Source revocation invalidates all dependent active verified facts,
   including facts from other sources that depend on its experience grouping.
   It redacts the revoked source's external ref/checksum, **all dependent
   candidate text/keys (even claims from a different source that reference its
   experience grouping)**, dependent experience labels, and historical
   verified claim keys, while retaining opaque audit tombstones.
6. A revoked source never silently regains consent. Later user-supplied
   evidence must enter as a **new** source with new permission/approval.

No service or model can promote a verified fact merely because a response
looks plausible or an SQL query succeeds.

## Retrieval and future QA boundary

BrainStore.verified_claims(actor="self") returns user-confirmed source-scoped
individual claims only, and verified_by_fact_id returns an active record or
None. A VerifiedClaim contains fact ID, claim key/text, actor, source ID,
optional experience ID and confirmation time.

These values are *not* suitable for passing directly as proof that a
generated model answer is supported. The existing QA contract treats
verified_source_ids as pointers. A later independent attribution step must
compare the **specific generated claim** against live verified entries and
source ownership, then reject unsupported elaborations. A verified fact
with actor=teammate must never authorize a first-person user claim.

This slice does not add a prompt importer, chat memory, embedding retrieval,
an AI classifier, Drive/GitHub sync, or production claim-to-answer matcher.
Those require separate benchmarks and source-level trust boundaries.

## Privacy constraints

- SQLite in :memory: mode is the default. Explicit on-disk paths are used
  only in synthetic tests for migration/reopen. The prototype **does not
  encrypt local data at rest** or control full-device backups.
- PRAGMA secure_delete=ON helps overwrite deleted content in ordinary
  SQLite pages but **does not guarantee deletion of WAL/journal history,
  filesystem snapshots, backups or future FTS shadow tables**. No FTS
  index or vector shadow tables are created here.
- The source metadata can contain external references; the consented local
  user controls them and revocation clears them. Never commit a real
  resume, claim, source URL, user identifier, recording or SQLite DB to
  the public GitHub repository. Tests use fabricated content exclusively.
- The trusted UI and local encrypted storage/retention UX are **not
  implemented**. Do not point real private documents at this spike yet.

## Acceptance and next boundary

Offline tests in [tests/test_personal_brain.py](https://github.com/KanujVerma/relay/blob/e846c00012c73762fa4a599729a5c70b87e532be/tests/test_personal_brain.py)
exercise migrations, foreign keys, source consent, actor ownership,
unverified candidate isolation, conflicting facts and atomic correction,
approval-reference reuse, cross-source experience invalidation, no content
in the immutable event log, and revocation/redaction.

[PR #26](https://github.com/KanujVerma/relay/pull/26) implements
[issue #21](https://github.com/KanujVerma/relay/issues/21), the synthetic
résumé candidate/approval-boundary step. After its merge,
[issue #29](https://github.com/KanujVerma/relay/issues/29) is the separately
scoped synthetic selected-file converter evaluation. Real user source
imports, trusted approval UI and local data encryption remain future work.
Do not bundle it with app audio, an interview overlay, API calls or
continuous-learning personalization.
