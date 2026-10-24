# Saved-session AI notes: source and reuse research

2026-10-24. Design-only branch at accepted e846c00012c73762fa4a599729a5c70b87e532be; [proposed exact contract](../superpowers/specs/2026-10-24-generated-session-notes-design.md). No runtime imports, code/assets/prompts copied, SDK/dependency added, upstream application/test executed or real inference/account/capture performed. Current citations identify exactly inspected pins rather than claiming newest/default branches are equivalent.

## Competitor behavior: shipped client versus unknown service

Locally inspected REA source S07 is `dist/assets/chat-DIvku-qQ.js`, SHA256`805ede5bfe6f1ec47678f9f814534c727427f71bd9fd2a95d4eab13a0804b137`,787376bytes. The sanitized [source ledger](CLUELY_SOURCE_COORDINATES.json) and [prior report](CLUELY_DEEP_DIVE.md) distinguish static client from actual runtime.

At verified UTF-8 bytes696806..700806, session detail fetches `sessions.get`, chooses active-session or persisted transcript, and submits explicit title/summary edits through `sessions.update`. Bytes704256..707256 render editable summary and a copy action. The1476byte `use-end-session-B3brV6MJ.js` (SHA256`a20a58831162768f2d039120dc1090fa291cc76b9387c72c861e492105480b2e`) passes ready-status transcript entries to the session-end mutation before clearing local active-session state. These coordinates are from the unchanged locally inspected shipped file; source is not executed or copied into this repository. Offsets were converted from source character positions to actual UTF-8 byte counts; the first inspection used character offsets696700..700700 and704150..707150. The bytes above are the reproducible file coordinates.

That proves a client summary/transcript/edit surface and end-session submission. It does not establish which server model generated notes, exact source coverage, cancellation, citation truth, encryption, retention, cost/entitlement or durable commit semantics. Official [product page](https://cluely.com/) and [notetaker guide](https://cluely.com/blog/ai-notetaker-guide) checked2026-10-24 advertise meeting notes/action items, but do not fill those implementation gaps. Nonofficial search results were discarded. Relay's explicit text-transfer action, source-row citations, encrypted local receipt and no hidden retry are independent Relay requirements. No stealth/undetectability behavior is adopted.

## Anarlog: useful generation/persistence separation

Exact MIT source [fastrepl/anarlog48e19c9ed980bcda8dc64d63c4cdf4b96deddf4a](https://github.com/fastrepl/anarlog/tree/48e19c9ed980bcda8dc64d63c4cdf4b96deddf4a); [root license](https://github.com/fastrepl/anarlog/blob/48e19c9ed980bcda8dc64d63c4cdf4b96deddf4a/LICENSE) blobba16e1f5cd2e7bbe4ab64b6eff901c57f94ac20e. Enterprise has separate terms; none is adopted. This is a Tauri/React/Rust app with AI SDK and database/editor/cloud integrations, not a Swift/Python drop-in for Relay's existing protected account and native authority.

Primary connector reads at that pin:

| File under `apps/desktop/src/` | Blob | Relevant inspected behavior |
| --- | --- | --- |
| `session/components/note-input/enhanced/index.tsx` and `index.test.tsx` |16d8076c14b374c61c657c0edb52ad567f236a08 (source) | Generation state, completed stream awaiting stored content, actual SQLite hydration/editor transition; explicit missing-summary action and unavailable configuration. |
| `services/enhancer/index.ts` |9aef2f44a6463615ca241c2a4e64974a252fc77c | Owns session/generation jobs, eligibility, existing target state and completion; has automatic retries/resume paths. |
| `store/zustand/ai-task/task-configs/enhance-success.ts` and `enhance-success.test.ts` |0ffaa97354d1e30ff3c1a276bf7c05fe5721d0a1 /43cf54f67910538d97584c55dbd3ee0ca405ffbf | Checks abort/current target, persists against expected original content/generation; tests distinguish saved receipt, failed persistence and cancellation during database/title work. |
| `session/content-mutations.ts` and `.test.ts` |44055849bd5fc7381d1c48ae56bb27b67b7e05a6 /78134211096bc8f9fbd85795b9fb0dd3dc92a023 | Uses actual checked backend persistence result, propagates failed save and carries expected body/content-format/generation. |
| `services/enhancer/storage.test.ts` |37a2759bebef731d446e571e58b03a992a04abfc | Same-generation pending/discard, creation ordering, deleted-target and checked replacement fixtures. |
| `store/zustand/ai-task/task-configs/enhance-workflow.ts` |45d36eb7dc439a0e8f329700f43ff133bdc2476a | Combined abort propagation; model transport retry4 and early validation retry2. |

Useful concepts are original-generation/expected-content CAS, abort before persistence, missing/deleted-target checks, and distinguishing a completed stream from an actual stored document. Those reinforce Relay's existing owned-operation model. The automatic jobs, stream preview, title generation, multiple retries, cloud synchronization, provider framework, prompts and editor are not adopted: they would contradict this explicit one-generation scope or duplicate current dependencies. Their tests were read, not run, and mocked assertions are not evidence of Relay quiescence or an end-to-end upstream guarantee.

## VoiceInk: original and enhanced text are different

Exact [Beingpax/VoiceInk22e5ec5479b712797c3b338fcb875961e58800b6](https://github.com/Beingpax/VoiceInk/tree/22e5ec5479b712797c3b338fcb875961e58800b6); [LICENSE](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/LICENSE) blobedf3f3bb269575c0c3b485b51a38bbfbb76abcd2 carries a GPLv3 notice/link. No source/assets/prompts are copied or invoked.

The exact tree places code under `VoiceInk/`; initial shorthand paths without that prefix returned404 and were corrected, rather than substituted with current main. `VoiceInk/Infrastructure/Persistence/Models/Transcription.swift` blob295b937a867e1c3f10f1291a44a1f779887acb20 separates original text, enhanced text and lifecycle/model metadata. `VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift` blobfbef2b77afed06b6b18d77d4770b2bd511bf30eb explicitly routes enhancement through configured provider/prompt and has timeout/network retry paths. It also uses contextual/vocabulary/provider facilities beyond the proposed source-only notes task.

The inspected test tree includes AutoLearnAIReviewerTests plus two UI smoke files, not a session-notes deletion/late-persistence race proof. Existing [History research](https://github.com/KanujVerma/relay/pull/93) already compares its retention/export distinctions. Reuse only the conceptual original-versus-derived distinction; do not adopt SwiftData/audio storage/provider choices, retry policy or license-bearing code as a shortcut.

## Recommended actual reuse and rejected new layers

Use Relay's reviewed native request/owned helper/waiter/full-frame writer, protected account/bootstrap, HTTPX0.28.1 BSD-3-Clause transport, strict completed-only ResponseAssembler and History's accepted GRDB/protected snapshot/lease. The existing assembler admits only a completed lifecycle and8192byte final output, with512KiB finite event budget. Current response_payload supports its actual configured plan route; do not invent unsupported max_output_tokens/temperature/service-tier fields or promise model window/entitlement. Notes source bounds are application policy, not a claimed upstream limit.

History runtime is not imported here. Immutable772cec5 exposes paged selection64rows/64KiB and complete internal detail up to1024rows/256KiB; saveNotes is USER-only. Root-accepted d9d91b56185df57c03368cddcc3b38f8a30d23fb adds HistoryOwnedSnapshotStorage begin/end around actual GRDB lifetime, retained fixed owner.lock and descriptor/path checks. Later account/stop-metadata join remains under review. Notes must consume the accepted source lease and actual candidate commit rather than implement another vault, SQLite wrapper or account registry.

A separate native notes work scope is necessary because saved-document revision/citations/durable receipts are not live answer-card identity. A private notes text permit must compose source/account/configuration checks after actual `_token()` awaits and before POST; plain text completion currently has no such caller guard. Reuse the existing image-permit pattern structurally without image capability or fake source events. One exclusive worker/helper and the existing account-reap boundary are retained. The protected refresh thread may outlive cancellation of its async wrapper; scope Task.done alone cannot claim that thread stopped.

## Evidence limits and next gate

This is architectural source research, not a runtime spike. Existing unchanged contextual-scenarios baseline4tests passed0.047s in the isolated e846 clone; no notes implementation exists. No new dependency/model download is needed for the proposal. Exact wire/source/output/lifecycle and schema2 tradeoffs are submitted for root approval in the companion spec. Only after approval and accepted History/account join will implementation use fake keys/temp vaults, actual framed synthetic children and MockTransport. Actual UI, account/device/capture and model usefulness remain separate root/user gates.
