# Local Session History Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. No additional agents are assigned. Each checkpoint includes its own failing tests, actual green verification and immutable review head.

**Goal:** Working opt-in encrypted local audio-session history with manual notes, real delete/export, and exact lifecycle/currentness.

**Architecture:** GRDB private in-memory queues use a capped serialization bridge and encrypted whole snapshots. A native coordinator owns bounded queued observations and real write/close receipts. The existing transcript validator issues observations before ring eviction; Model binds them to explicit retained-session ownership before capture.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, MIT GRDB exact `b83108d10f42680d78f23fe4d4d80fc88dab3212`, system SQLite3, existing CryptoKit/fixed-purpose Keychain abstraction.

**Spec:** [Accepted design](../specs/2026-10-23-local-session-history-design.md), with its approval amendment recorded there. Baseline `ac70eb3b8526331b074cd5a9e24f0d775ecad4f9`.

## Global constraints

- Default saving off; constructor and workspace appearance inert. Tests only temporary files, fictional text and injected keys/preferences, never actual Keychain/capture/account/inference.
- History service `com.relay.history.v1`, account `local-history-aes256`, `Application Support/Relay/History/history.relayvault`, authenticated `RELAYHISTORY1\n`. Preserve profile/chatGPTCredentials exact namespaces and ProfileVault API/format.
- 30-day expiry on access; 100 records/8 MiB snapshot, 7 MiB soft admission, 1,024 finals/256 KiB per record, 8 KiB note, 120-byte title, 128 pending events/256 KiB. Whole observations only, reserved lifecycle slots and real joins.
- Native original source/epoch/event sequence/generation/timing preserved. No restamping or fake audio, no history as personal evidence. Actual capture permission and retention are separate.
- Lock, Stop saving, source/record deletion and End have the distinct approved fences/joins. No success on timeout or old-operation cleanup of replacement state.
- Manual notes only in this slice. Generated notes have a separate future exact inference contract; no enabled stub.

### Checkpoint 1: protected snapshot compatibility and namespace

Files: factor `spikes/macos-profile/Sources/RelayProfile/ProfileVault.swift`; add `ProtectedSnapshotVault.swift`; add `Tests/RelayProfileTests/ProtectedSnapshotTests.swift`.

Interface: `ProtectedSnapshotStorage: Sendable` has synchronous throwing `exists() -> Bool`, `load() -> Data`, `save(_:createKey:)`. `ProtectedSnapshotVault(directory:purpose:keys:)` accepts fixed `.profile`/`.history` formats. `ProfileVault` preserves initializer, maximum and method signatures and delegates the same profile bytes. `KeychainKeyPurpose` adds accepted `.profile/.chatGPTCredentials` and approved `.history`; existing client/random labels remain compatible.

- [ ] Add tests for exact three fixed namespaces, inert construction, authenticated cross-domain rejection, ciphertext-only real-file roundtrip, missing existing-only load with no key creation, wrong-key/corrupt preservation, shared owned-parent/symlink/mode/hard-link checks.
- [ ] Run focused test; absent purpose/primitive APIs are the expected red.
- [ ] Factor the existing implementation without changing profile defaults. History creates/checks only owned Relay then History directories, nonrecursively and without permission healing.
- [ ] Run all profile tests and focused compatibility negatives. Commit/push exact own checkpoint, declaring the accepted account enum compatibility import.

### Checkpoint 2: GRDB ledger and original observation DTO

Files: panel package exact GRDB dependency/pin/notice; new `RelaySessionPanel/HistoryModels.swift`, `HistorySnapshotCodec.swift`, `HistoryStore.swift`; new `HistoryStoreTests.swift`; narrow `SessionTranscriptStore.swift` observation hook and tests.

Interfaces: producer-issued `ValidatedTranscriptObservation` (no public constructor) carries original native final/row or original lifecycle control. Immutable stored record/segment/final/note DTOs encode unsigned counters as canonical decimal strings. `HistoryStore` owns one canonical and at most one candidate `DatabaseQueue`; all queries/mutations are serialized. Every mutation saves encrypted candidate before publishing revision; delete/expiry rebuild only kept rows. `HistoryExport` emits bounded Markdown/JSON from a revision-bound immutable detail.

- [ ] First failing store test: create/open with real fake-key ciphertext, record/final/title/note, restart fidelity and lossless UInt64 values; absent APIs are red.
- [ ] Implement exact schema/version/allowlist/bounds/integrity checks, memory settings and capped SQLite ownership bridge using the already measured release APIs.
- [ ] Add failing negative schedules: failed save keeps old canonical/ciphertext, malformed/future/symlink snapshots, cap rollback, 30-day purge before reads, exact source deletion and dependent content, pagination/CAS and export escaping.
- [ ] Add hook test with more than 64 actual validated synthetic finals; observer sees each original once, rejects invalid/stale events, preserves Pause/end/source behavior. Implement the nil-default hook only after red.
- [ ] Run focused ledger/transcript tests and package build. Commit/push with source/license/adoption record and exact pin.

### Checkpoint 3: bounded coordinator and real owned cleanup

Files: `RelaySessionPanel/SessionHistoryCoordinator.swift`, `HistoryPreferences.swift`, coordinator tests using an actual encrypted temporary vault behind a held storage port.

Interfaces: inert `SessionHistoryCoordinator(storage:preferences:clock:)`, observed snapshot, explicit `enable/openExisting/stopSaving/lock/waitForQuiescence`, privately issued `HistorySessionPermit`, `beginSession/observe/retire/finish`, revision-bound browse/edit/delete/export. Public fences are synchronous; storage work uses one retained serialized owner. Snapshot failure messages are fixed.

- [ ] First red: default/appearance zero work; explicit Enable persists only encrypted store; existing-only remembered Start missing vault fails without create.
- [ ] Implement explicit enable/open and private permit issuance; one FIFO bounded observation buffer; reserve terminal/partial status outside row capacity.
- [ ] Red held-write cases: Stop saving drops unstarted work but joins started commit; Lock hides immediately and joins; late completion/cancel cannot reopen; delete after actual started write cannot be undone; ready observer sees actual busy admission.
- [ ] Implement operation UUID/generation fencing and actual queue joins. Exercise actual file persistence in positive controls rather than asserting only mock calls.
- [ ] Run focused held schedules plus store/transcript cases; commit/push independently reviewable core.

### Checkpoint 4: actual Model and Home/Settings/History workspace

Files: Model constructor/history factory/preferences, source/Start/retirement hooks; new History workspace/view adapter; Home navigation and live state; Settings retention controls; package/product notice wiring; `HistoryApplicationTests.swift`.

Interfaces: Model owns one lazy coordinator, injectable storage/preferences factory; `start()` remains existing speech/source/context flow and additionally awaits enabled existing-history restore before any actual capture/helper fixture issuance; same-intent guard repeats after awaits. Actual `session_started` binds original capture identity; validated observation hook appends under the original permit. End/Pause synchronously retire admission and finish after native/event/helper joins. Resume uses a new capture segment under retained logical record. Idle assistant requests do not invent transcript history.

- [ ] Add failing actual Model fake-key/stdin fixture Save/End/fresh Model Open test; include more-than-ring observations, manual note, exact source label and restart.
- [ ] Add Model failure/late Lock/source-choice replacement/cancel tests proving zero capture-start and no missing-vault creation. Preserve idle assistant and résumé fixture behavior.
- [ ] Implement actual History list/detail/open/enable/Lock/title/note/delete/export controls. Export uses explicit save panel only, injected destination for tests. Show Off/Saving/Partial/Unavailable and no Generate/Resume stub.
- [ ] Add actual action-routing and source/expiry/delete/held-write Model cases. Run affected app/presentation/core tests plus product compile. No assertion/timeouts/skips weakening.
- [ ] Update lane evidence, freeze own head/draft PR against immutable foundation, request controller independent review. Product signature/GUI/hardware/private account acceptance remains separately attributed.

### Approved follow-up: cross-process owner lease

Controller approval2026-10-24 follows an actual two-independent-store lost-update reproduction. Add only a History-specific `HistoryOwnedSnapshotStorage` port and `HistoryVaultStorage` wrapper. Shared194 and peer053 files remain untouched. `beginAccess(create:)` holds a nonblocking exclusive Darwin flock on zero-content0600 `owner.lock` under owned0700 Relay/History before any load/create; `endAccess()` releases only after actual database/storage cleanup. No truncation, overwrite or permission healing; no existing-only missing directory/vault/key/lock creation. Validate retained descriptor/device/inode/owner/link/mode/path identity before storage calls. Constructor/default appearance remains inert. File lock is cooperating-process consistency, not same-user hostile-process isolation.

- [x] Red desired API and actual two-owner/synthetic subprocess contention, stale cached writer rejection and actual release/reopen.
- [x] Red inode/path replacement, symlink/hardlink/nonzero lock/wrong owner-mode/no healing and existing-only zero-create.
- [x] Red held actual `endAccess` plus repeated Lock, proving second owner cannot acquire before cleanup.
- [x] Implement wrapper/port and minimal HistoryStore/Model default factory; temporary tests use injected fake keys and actual wrapper.
- [x] Run focused store/coordinator and actual Model history cases, publish frozen narrow checkpoint/report.

### Approved follow-up: root account/idle integration

After narrow timing/lease checkpoints freeze, merge accepted canonical `e846c00012c73762fa4a599729a5c70b87e532be` into this isolated lane. Preserve194 ProfileVault compatibility/history purpose, accepted account domains, one ConversationOwnerBox/max4native profile flights, and account preparation outside the capture Start task. History logical records remain independent of helper/account lifetimes; idle account changes cannot create an audio history record. Root owns review, not a later serial manual Model join. First-launch160 shared Settings selection is a separately reviewed peer dependency; no unreviewed preference imports.

Actual capture metadata is currently start-only. Record completion indicates the logical retention workflow, not a measured capture segment duration. Capture end receipt or explicit unknown-end/gap remains required before claiming complete segment timing; do not derive it from logical record endedAt or an elapsed UI timer. A later separate checkpoint will use only original native stop evidence/actual joins, retaining unknown when the native source has no qualifying end receipt.

### Resource-limited source successor (2026-10-24)

- [x] Preserve accepted account e846, first-launch160 and preferences b270 in one actual Model/Settings composition; no new purpose namespace.
- [x] Prepare original-stop/unknown-end DTO/store/terminal-slot/export/UI source and synthetic tests; no invented capture duration.
- [x] Prepare current private paused-permit/account refresh and End escalation changes with actual protected helper tests.
- [x] Fence default fixture production History storage without relying only on disabled UI.
- [ ] Execute new tests once the globally shared heavy slot is granted. No compile/pass claim from source preparation.
- [ ] Reproduce the root's Combine subscriber deletion hypothesis before any publication correction.
- [ ] Run affected gates using the two retained shared build roots only, <=2compiler jobs and the canonical resource floors. No automatic restart of removed lane caches.
