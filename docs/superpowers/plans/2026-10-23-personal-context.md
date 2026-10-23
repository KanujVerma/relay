# Personal context implementation plan

**Goal:** Selected résumé, project notes and job preparation flow into reviewed, source-backed context in the automatic answer experience.

**Architecture:** Keep the existing BrainStore/ReviewGateway lifecycle. A native macOS host owns actual selection and approval callbacks and AES-GCM encrypted full-ledger persistence; Python operates in memory over inherited pipes. Retrieval returns bounded immutable host-issued context and validates freshness before publication.

**Tech stack:** Python stdlib SQLite and framed JSON; Swift 6, SwiftUI, CryptoKit, Security. Existing optional PDF/DOCX adapters remain optional and fail closed.

**Spec:** Controller-approved lane brief for issue #61; PRODUCT.md; PERSONAL_BRAIN_STORAGE.md; RESUME_CANDIDATES.md; DOCUMENT_CONVERTERS.md. Controller owns integration and review; no subagents in this lane.

## Constraints

- No private user files, Keychain items, inference, capture, or model downloads during development. Synthetic tests and injected keys only.
- No plaintext ledger or metadata on disk. Key loss/corruption fails closed, without replacing the vault. No secure-erase or backup-erasure claim.
- Preserve exact spans/digests, ownership, atomic supersession and cross-source revocation. No automatic biographical approval.
- No caller-provided boolean proves selection or identity. Native callbacks and owned child pipes are an application boundary, not OS attestation against malicious same-user code.
- Write scope: personal_context/profile_preparation/profile_bridge, their tests, macos-profile package, narrow BrainStore snapshot seam, PERSONAL_CONTEXT.md, this plan, lanes/PERSONAL.md.

## Coherent checkpoints

- [x] Retrieval contract: write failing synthetic tests for relevance, bounded facts, ownership, conflict/missing/revoked states, and stale/counterfeit bundles. Implement provider and run the tests plus existing provenance tests. Commit and send the API and fixtures to the answer lane.
- [x] Preparation and snapshots: test selected text/document preparation, reviewed job context, exact locators, direct approval rejection, snapshot restoration, and redaction. Implement a bounded in-memory service and inherited-pipe helper. Never put raw documents into snapshots. Commit after targeted tests pass.
- [x] Protected native host: inspect pinned upstream source/tests/license. Test AES-GCM authenticated roundtrip/tampering, key-provider failures, atomic persistence, startup without import and real helper lifecycle with synthetic input. Implement Keychain adapter, native picker/review UI and protected persistence. Build/test without launching real-input actions. Commit.
- [ ] Verify integration: run full Python checks, macOS-profile tests/build, synthetic helper reopen/revocation checks and document current limitations. Update lane record and report. Push scoped branch and draft PR against the controller foundation once available; no merge.

## Source decisions

KeychainAccess v4.2.2 at 84e546727d66f1adc5439debad16270d0fdd04e7 (MIT) and Apple swift-crypto 3.15.1 at 95ba0316a9b733e92bb6b071255ff46263bbe7dc (Apache-2.0) are source/test references. Use native Security/CryptoKit APIs directly rather than vendoring either wrapper or adding a runtime package. Exact inspected files and validation belong in PERSONAL_CONTEXT.md.

## Lane handoff

Lane implementation and local verification are complete in draft PR #63. Joined interview acceptance, independent controller review and real private-user/Keychain acceptance remain separate. See docs/lanes/PERSONAL.md for exact published state and next action.
