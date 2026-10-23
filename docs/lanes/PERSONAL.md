# Personal context lane

Issue: [#61](https://github.com/KanujVerma/relay/issues/61). Branch `feature/personal-context-2026-10-23`, common base `3e0eb379fdc8a710dd9ebee51bc93b8c6004e02d`.

## Current checkpoint

Implemented the read-only `BrainContextProvider` and immutable context contract in `relay_spike/personal_context.py`. Relevant active reviewed facts preserve exact source spans/digests, actor, IDs and review revision. Missing, pending canonical-key conflicts and fully revoked profile states are distinct. Model/serialized bundle copies cannot grant publication authority; retain the host-issued bundle and check its full-ledger revision before publication. Retrieval keeps no persistent search index.

Validation: 8 new retrieval tests passed after the expected missing-module red run; combined Personal Brain/retrieval tests 27 passed and résumé review tests 22 passed. Synthetic inputs only. No real file imports, Keychain access, capture or model calls.

## Preparation checkpoint

`ProfilePreparation` now stages selected UTF-8/PDF/DOCX bytes through the existing provenance gateway, preserves text/page/paragraph locations, supports reviewed role-scoped job excerpts, and revokes/redacts source metadata. `ProfileBridge` is a composable provider and preparation service for the final single helper. Its standalone harness uses inherited BE32 JSON frames capped at 16 KiB and 4096-byte chunks; incomplete profile loads retire authority and never enable retrieval. Snapshot export/restore operates on SQLite in memory only. Native callers must own encrypted persistence; this service is not a permission credential for arbitrary code.

Validation after resumed state: **411 Python tests passed, 21 optional converter skips**. The 12 new preparation/bridge tests passed, including an actual synthetic child process, chunked reopen, exact paragraph locator, stale/incomplete loads, fake capabilities and source revocation. Existing suite emits synthetic HTTP/SQLite ResourceWarnings; no test failures. No private files, Keychain items, capture or models were used.

## In progress

Native encrypted vault code/tests are in progress and not part of this Python checkpoint. Existing on-disk BrainStore is still synthetic only. The plan is [personal-context](../superpowers/plans/2026-10-23-personal-context.md). Controller owns shared integration/review. The provider contract and composable bridge have been sent to the answer lane. Read the accepted BUILD_CONTRACT at published foundation a8f8359354f44e11be39e22a55422b2cef9f6c91; current ports agree with it.

## Next action

Finish the native encrypted-storage and selected-file/review UI boundary, then verify synthetic whole-path persistence without accessing private inputs or Keychain.
