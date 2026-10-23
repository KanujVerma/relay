# Personal context lane

Issue: [#61](https://github.com/KanujVerma/relay/issues/61). Branch `feature/personal-context-2026-10-23`, common base `3e0eb379fdc8a710dd9ebee51bc93b8c6004e02d`.

## Current checkpoint

Implemented the read-only `BrainContextProvider` and immutable context contract in `relay_spike/personal_context.py`. Relevant active reviewed facts preserve exact source spans/digests, actor, IDs and review revision. Missing, pending canonical-key conflicts and fully revoked profile states are distinct. Model/serialized bundle copies cannot grant publication authority; retain the host-issued bundle and check its full-ledger revision before publication. Retrieval keeps no persistent search index.

Validation: 8 new retrieval tests passed after the expected missing-module red run; combined Personal Brain/retrieval tests 27 passed and résumé review tests 22 passed. Synthetic inputs only. No real file imports, Keychain access, capture or model calls.

## Preparation checkpoint

`ProfilePreparation` now stages selected UTF-8/PDF/DOCX bytes through the existing provenance gateway, preserves text/page/paragraph locations, supports reviewed role-scoped job excerpts, and revokes/redacts source metadata. `ProfileBridge` is a composable provider and preparation service for the final single helper. Its standalone harness uses inherited BE32 JSON frames capped at 16 KiB and 4096-byte chunks; incomplete profile loads retire authority and never enable retrieval. Snapshot export/restore operates on SQLite in memory only. Native callers must own encrypted persistence; this service is not a permission credential for arbitrary code.

Validation after resumed state: **411 Python tests passed, 21 optional converter skips**. The 12 new preparation/bridge tests passed, including an actual synthetic child process, chunked reopen, exact paragraph locator, stale/incomplete loads, fake capabilities and source revocation. Existing suite emits synthetic HTTP/SQLite ResourceWarnings; no test failures. No private files, Keychain items, capture or models were used.

## Native checkpoint

The native RelayProfile library and preparation window are implemented. CryptoKit encrypts the entire payload, Keychain supplies a device-local non-synchronizing key, and all native acceptance uses injected synthetic keys. Default launch is inert until the user opens the protected profile. Ten native tests pass, including a real child plus encrypted review/save/reopen/revoke and save-failure lock. Full Python now passes 414 tests with 21 optional converter skips. The UI is built but actual file-picker clicks and real Keychain acceptance remain pending. Review cards visibly preserve the source locator and ownership hint. App composition can bind and lock its canonical interview role. Fixtures (26) and documentation/link checks (20 required files) pass. Details and exact source/test/license pins are in [PERSONAL_CONTEXT](../PERSONAL_CONTEXT.md). Existing on-disk BrainStore is still synthetic only. The plan is [personal-context](../superpowers/plans/2026-10-23-personal-context.md). Controller owns shared integration/review. The provider contract and composable bridge have been sent to the answer lane. Read the accepted BUILD_CONTRACT at published foundation a8f8359354f44e11be39e22a55422b2cef9f6c91; current ports agree with it.

## Next action

Integrate RelayProfile via the answer lane shared helper, complete independent review, and verify the joined synthetic flow. Actual private-source/Keychain acceptance remains separate.

## Publication and handoff

Draft [PR #63](https://github.com/KanujVerma/relay/pull/63) targets the frozen `build/parallel-foundation-2026-10-23` branch at a8f8359. Feature commits 8d54b67, d1f367b, 2a3e152 and 4c2faa1 are published with a normal push; the branch incorporates the controller foundation via merge 8e36809. No main merge or issue closure occurred. The answer owner has the exact integration API and native commits. Remote exact-head CI and independent review remain pending. Final lane checks also cover duplicate JSON keys, rejected active-profile reload, chunk ordering and a shared-helper profile lock that keeps the conversation process alive. The outer profile-envelope UUID duplicate/replay guard belongs to the answer owner.
