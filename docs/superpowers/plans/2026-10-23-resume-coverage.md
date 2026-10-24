# Résumé Coverage Implementation Plan

> For agentic workers: execute inline using the executing-plans workflow.
> No extra agents or shared-checkout writes are authorized in this lane.

**Goal:** Review and reuse ordinary résumé sections and entry relationships
without inferring personal skills, dates or ownership.

**Architecture:** Exact located primary claims have separately displayed entry
fields. A versioned review command approves claim and context atomically in
the existing SQLite snapshot. The original personal-context bundle and native
publication gates remain authoritative.

**Tech stack:** Existing Python/SQLite, model-free Docling native PDF,
python-docx, SwiftUI/Combine/CryptoKit and the existing framed profile client.

**Spec:** `docs/superpowers/specs/2026-10-23-resume-v2-review-contract.md`.

## Global constraints

- No new dependencies, model/account calls, real profile, Keychain or capture.
- Do not edit Model, outer app, Vault/key purpose, Package, CI or global docs.
- Primary claim stays exact, context fields retain independent spans/locators.
- 30,000 code points, 64 candidates, 16 KiB frame, 8 MiB snapshot and two
  180-byte personal points remain bounded.
- Self biography requires self-reviewed units. Visible Save/actor is the one
  context acknowledgement. Old `decide` cannot approve a v2 candidate.

## Task 1: backend review foundation

Files: new `resume_structure.py`; narrow `resume_candidates.py`,
`personal_brain.py`, `profile_preparation.py`, `profile_bridge.py` and converter
integrity adapter; new `tests/test_resume_structure.py`.

- [x] Add failing behavior tests for actual structured TXT staging, exact
  Unicode slices, rejected old decision, matching v2 approval, stale digest,
  migration/restore, re-import and long-entry association retirement.
- [x] Run the focused file and verify those behaviors are absent.
- [x] Implement bounded located DTOs/extraction and schema-3 atomic review;
  keep legacy gateway staging/decision unchanged for legacy candidates.
- [x] Run focused new cases plus existing ledger/preparation/bridge/converter
  negatives. Freeze a meaningful independently reviewable checkpoint.

Interfaces: `extract_resume_structure(text, locator)` produces immutable
unverified candidates/coverage; `ReviewCardV2` extends exact review identity;
`ProfilePreparation.decide_v2(..., card_version=2, context_sha256=...)` and
strict bridge `decide_v2` consume displayed context. No retrieval authority is
added until the matching actual confirmation event exists.

## Task 2: provider and deterministic host

Files: `personal_context.py`, dedicated pure personal rendering helper and the
existing `_personal` branch; new `tests/test_resume_personal_answers.py`.

- [x] Add failing real review→snapshot restore→provider/Host tests for education,
  Expected/completed/GPA, employment, project contribution, C++/R, actual tool
  use versus listed skills and certification issuer/status.
- [x] Implement intent-aware exact field selection with self-only biography,
  honest team labels, whole-unit budget handling and original bundle validation.
- [x] Prove unreviewed/revoked/copied contexts cannot publish, no inference is
  called for personal answers, and unrelated technical routes stay unchanged.
- [ ] Freeze backend checkpoint for independent review before UI exposure.

## Task 3: native visible review and real commands

Files: new strict review-context DTO; narrow `ProfileController`,
`ProfilePreparationView`, pure presentation helpers and native tests.

- [x] Add failing DTO Unicode-code-point/bounds/version and actual client
  command tests, using fake keys/temp vault and actual synthetic stdio helper.
- [x] Display all proposed associations before existing actor/Save; route exact
  displayed v2 digest through `decide_v2`, without a second acknowledgement.
- [x] Show truthful partial extraction and keep source/Lock/busy lifecycle.
- [ ] Run affected profile package tests and actual app build; freeze native
  checkpoint for root review, without editing outer app/Model.

## Task 4: real document acceptance and lane handoff

Files: fictional new TXT/selectable PDF/simple DOCX fixtures and generation
recipe, focused integration tests and `docs/lanes/RESUME_COVERAGE.md`.

- [ ] Generate source-identifiable fictional formats with no private material.
- [ ] Run actual pinned converters offline with zero dependency skips for the
  promised formats, then stage/review/restore/provider/Host and native API proof.
- [ ] Prove qualifier retention, old-v1 re-import authority preservation,
  conflicting replacement/redaction, unsupported layouts and long-unit gaps.
- [ ] Run scoped joined checks, inspect own diff, publish exact candidate/PR
  against frozen db768 base and report tests plus remaining layout/detail limits.
