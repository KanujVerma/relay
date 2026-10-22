# Relay résumé review contract, Slice 02A-B0

Status: **synthetic selected-text prototype**, not a real résumé importer, native UI, or production-secure confirmation screen. Implementation uses the existing [Personal Brain SQLite ledger](PERSONAL_BRAIN_STORAGE.md), not another memory datastore.

## What to reuse, and when

| Upstream | Reuse decision |
| --- | --- |
| [Docling](https://github.com/docling-project/docling), MIT | Rich PDF/DOCX structure and page layout, a strong **later** choice if simple converters lose page/text provenance. Benchmark on the M2 Pro first; verify any model-weights licenses. |
| [Microsoft MarkItDown](https://github.com/microsoft/markitdown), MIT | Good lightweight **later** candidate for local-only selected PDF/DOCX to Markdown. Use its narrow local or stream converter rather than URI-enabled conversion for untrusted content. |
| [Unstructured](https://github.com/Unstructured-IO/unstructured) | Its element metadata and page coordinates are useful design references. Assess dependency burden and licensing before use. |
| [GRDB.swift](https://github.com/groue/GRDB.swift), MIT | Preferred native Swift persistence candidate when macOS app work begins. Reuse the existing SQLite schema and migration contract. |
| [Mem0](https://github.com/mem0ai/mem0), Apache-2.0 | Useful long-term memory inspiration, but agent-derived personal facts must **not** be automatically marked verified in Relay. |

No upstream source code was copied, vendored or added as a runtime dependency. Converting a selected file and verifying whose work it describes are separate problems. For this narrow step, building an extra PDF parser is unnecessary when established converters can be reused in the later real-file slice.

## Synthetic source and review lifecycle

1. A trusted host **simulation** selects a string and creates a consented résumé source with SHA-256 revision. No filesystem or remote source is read, and no document body is stored.
2. A deterministic line parser records verbatim candidate text, exact Unicode character start/end offsets and an owner hint. Neutral résumé bullets are marked **unknown**, not implicitly personal. Explicit first person, team and teammate language produce only unverified hints. Prompt-like instructions inside imported text are skipped, never executed.
3. The transactional SQLite **v2 migration** adds a candidate_evidence record with source SHA-256, snippet SHA-256, span offsets and review revision. It preserves all v1 records on upgrade, never stores complete résumé text, and rejects duplicate source spans.
4. Review cards are reconstructed from live DB content. The host must visibly present the original sentence, its evidence location, owner hint and revision. It must collect a separate decision, approved owner and canonical claim key. The parser and model cannot approve candidates.
5. A host capability object (identity comparison, not a user-entered string) is required to select and review. A separate one-per-store ledger review guard is bound at startup: direct calls to confirm a résumé-derived candidate, even with a forged UserConfirmation and correct text hash, are rejected unless they come through that registered gateway. The review gateway generates an opaque random confirmation ID for the existing ledger. Stale cards and mismatched source revisions fail closed, and rejected candidates are redacted.
6. Conflicting claims cannot both be active under one canonical key. A replacement must explicitly name the current verified fact and is committed atomically with the correction. Only actor=self confirmed facts are eligible for a user's own technical contribution retrieval.
7. Source or fact revocation removes dependent candidate text and candidate-evidence metadata, including prior approved source spans, while retaining text-free history action IDs. A trusted document must not be inferred from the existence of an ID alone.
8. The existing deterministic QA gate **does not** treat approved source references as proof that a generated first-person sentence is true. A future independent claim-to-evidence verifier is still needed.

## Security boundary, explicitly limited

An in-process opaque host capability cannot demonstrate that a real person clicked a button or resist malicious code already running within the trusted Python process. The underlying UserConfirmation object is also only a software contract, not authentication or OS UI provenance. In this slice all host actions are **simulated in synthetic offline tests**. Before using a real résumé, a native event boundary must restrict writes, establish actual user selection/confirmation and protect encrypted local storage. No real personal file, résumé text, OAuth token, recording or account-linked data should be committed to the public repository or CI.

The source SHA-256 can be susceptible to guessing attacks; on-disk SQLite is **not encrypted** here. secure_delete does not guarantee removal from journals, backups or OS snapshots. This slice guarantees state invalidation and row-level redaction only, not forensic deletion.

## Tests and next integration

The synthetic tests cover source offsets, UTF-8/Unicode, first-person vs shared/teammate/unknown ownership, unconfirmed tool experience (Power BI), prompt injection as data, stale/forged review cards, missing or counterfeit host capability, confirmation bypass attempts, duplicate source spans, conflicts and explicit supersession, revocation and SQLite v1-to-v2 migrations.

Next 02A-B1 should adapt a *user-selected* local file converter (initially evaluate MarkItDown; use Docling if fidelity requires it), preserve page/paragraph offsets, implement the actual native review screen and protect private storage. No automatic promotion, external connectors, audio, mock interviewing or paid inference should enter this step.

Run the existing offline fixture/document validations and unittest suite before merging; require exact-head green CI and completed Codex review.