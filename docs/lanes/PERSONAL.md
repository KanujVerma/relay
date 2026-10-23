# Personal context lane

Issue: [#61](https://github.com/KanujVerma/relay/issues/61). Branch `feature/personal-context-2026-10-23`, common base `3e0eb379fdc8a710dd9ebee51bc93b8c6004e02d`.

## Current checkpoint

Implemented the read-only `BrainContextProvider` and immutable context contract in `relay_spike/personal_context.py`. Relevant active reviewed facts preserve exact source spans/digests, actor, IDs and review revision. Missing, pending canonical-key conflicts and fully revoked profile states are distinct. Model/serialized bundle copies cannot grant publication authority; retain the host-issued bundle and check its full-ledger revision before publication. Retrieval keeps no persistent search index.

Validation: 8 new retrieval tests passed after the expected missing-module red run; combined Personal Brain/retrieval tests 27 passed and résumé review tests 22 passed. Synthetic inputs only. No real file imports, Keychain access, capture or model calls.

## In progress

Protected persistence/native preparation are not implemented at this checkpoint. Existing on-disk BrainStore is still synthetic only. The plan is [personal-context](../superpowers/plans/2026-10-23-personal-context.md). Controller owns shared integration/review. The provider contract has been sent to the answer lane.

## Next action

Implement and verify in-memory snapshot/preparation service and the native encrypted-storage/UI boundary before enabling real input.
