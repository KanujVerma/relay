# Session history storage and notes reuse research

Research date: 2026-10-23. Proposal baseline: `5575b184a081450308b88b622ec5fcb5eb81318a`. This is a read-only source comparison plus an isolated, fictional-data storage probe. No production dependency, history schema, capture observer, credential or storage policy has been adopted. [Proposed design and approval seams](../superpowers/specs/2026-10-23-local-session-history-design.md).

Implementation update after controller approval: the separate `feature/local-session-history-2026-10-23` lane at baseac70 now actually invokes the exact GRDB pin for its new in-memory ledger, unmodified `DatabaseQueue`/`DatabaseReader.backup`, owned read/write transactions, throwing `Row.decode` and real close. Its own capped serialization adapter and inherited CryptoKit snapshot primitive are used. The native bundle/full MIT notice are retained by product assembly. The earlier "no adoption" statement describes frozen designe242; no VoiceInk/Anarlog/competitor code, assets or tests are copied. Complete app/coordinator exposure remains a later reviewed checkpoint.

## Recommended reusable component: GRDB

Pin [GRDB.swift v7.11.1](https://github.com/groue/GRDB.swift/tree/b83108d10f42680d78f23fe4d4d80fc88dab3212), commit `b83108d10f42680d78f23fe4d4d80fc88dab3212`. The release was published June 18, 2026; the exact commit, not a mutable branch or range, is the proposed adoption identity. [MIT license](https://github.com/groue/GRDB.swift/blob/b83108d10f42680d78f23fe4d4d80fc88dab3212/LICENSE), license blob `550890c8912ca08ff000249777b9eeb46411f189`.

Source and tests read at that release:

- `Package.swift`: Swift tools 6.1, Swift 6 mode, macOS 10.15 minimum; standard SPM target uses system `GRDBSQLite`. No ordinary remote dependency. The documentation-only SPI builder and optional commented SQLCipher configuration are not the proposed build. Relay's current panel already requires Swift 6.2 and macOS 15.2, so this package does not raise the app's declared toolchain/platform floor.
- `GRDB/Core/DatabaseQueue.swift`: unnamed in-memory initializer uses private `:memory:`, serialized access and explicit close through its writer. Close waits on the actual queue. Named shared memory and disk pools are unnecessary here.
- `GRDB/Core/DatabaseReader.swift:470` and `Database.swift:1892`: queue-to-queue backup executes through owned read/write closures; its unfinished error path finishes the backup and preserves the previous destination. Destination schema caches are cleared after a completed backup.
- `GRDB/Core/Database.swift` connection/close sections and `Database+Schema.swift:79`: the raw SQLite connection is scoped to the database queue; close clears it; `clearSchemaCache()` clears both schema and statement caches. A serializer bridge must use only that queue, never escape the pointer, and restore only a new queue.
- `Tests/GRDBTests/Core/DatabaseQueue/DatabaseQueueInMemoryTests.swift`: separate unnamed queues and deliberately shared named memory.
- `Tests/GRDBTests/Core/BackupTestCase.swift`: whole copy, aborted multi-page progress preserving old destination, successful copy and dropped-table behavior.
- `Tests/GRDBTests/Core/DatabaseQueue/DatabaseQueueConcurrencyTests.swift`: selected transaction/concurrency cases with real SQLite busy outcomes. Relay's own tests should use bounded held-operation schedules rather than copy indefinite test waits.

The queue/reader/package/license and three listed test files have identical Git blob identities at the initially inspected master `0d8cf958b4b66a0473ec6e6986eb9da462171da9` and the pinned release. The release's `Database+Schema.swift` was checked separately because the whole file differs. No claim is made that master and the release are otherwise interchangeable.

GRDB would actually be invoked for in-memory queue confinement, compiled/bound SQL, transaction rollback, backup and close. A small Relay-owned adapter would provide capped `sqlite3_serialize`/`sqlite3_deserialize` and encrypted snapshot publication. Standard GRDB does not encrypt a disk database. Its MIT notice must accompany an adoption. No upstream source or tests are copied into Relay by this research.

## Direct SQLite3 comparison and measured boundary

Direct native SQLite is viable, rather than unsuitable merely because it is lower-level. The SDK declares serialization APIs available since macOS 10.14. A local `import SQLite3` probe reports system SQLite `3.54.0` and `SQLITE_OMIT_DESERIALIZE=0`. The [SQLite serialization contract](https://sqlite.org/c3ref/serialize.html) gives the caller ownership of a normal serialized copy. The [deserialization contract](https://sqlite.org/c3ref/deserialize.html) specifies transferred buffer ownership, extra padding, read/backup conflicts and WAL limitations. [In-memory documentation](https://sqlite.org/inmemorydb.html) distinguishes exact private `:memory:` from temporary databases that may spill.

The owned [probe and reproduction instructions](../evidence/2026-10-23-history-storage/README.md) compiled and ran GRDB's pinned release plus the direct C API against the same fictional fixture. Results:

| Boundary | Observed result |
| --- | --- |
| Direct C serialization/restore | Exact 8,192-byte snapshot round-trips and passes integrity check; memory temp policy verified. |
| C memory-file cap | Oversized insert returns SQLite FULL and preserves the previous row. |
| GRDB backup rollback | Throwing before multi-page completion preserves destination's prior content. Successful backup then matches source. |
| GRDB narrow serializer bridge | A new queue restores the snapshot, clears caches, passes integrity/memory-policy checks and accepts a later transaction. Oversized insert fails with FULL and rolls back. |
| Actual close ownership | Close remains unfinished while a real writer is held, completes after release, and a read after close rejects. |
| Owned filesystem containment | Working directory and TMPDIR contain no database, WAL, journal or temp file after the run. |

This was local arm64, Swift 6.4/Xcode SDK macOS 27, with a macOS 14 deployment target. It proves current installed source/symbol compatibility and the exercised local behavior. It does not prove execution on an older OS, Intel Swift 6.2, maximum-size latency, whole History encryption or global absence of OS swap/caches. Future implementation needs a supported-runtime capability test, fixed failure if serialization is unavailable, resource-containment tests around all paths and product dependency/signature review. Never fall back to plaintext disk.

Choosing direct C would still require Relay to implement and maintain query/statement binding, rollback, queue preconditions, backup/close/cancel ownership and row conversion. GRDB has suitable reviewed APIs/tests for those responsibilities. The recommendation is therefore GRDB plus the narrow bridge, not a blanket runtime rewrite or a rejection of mature reuse to save a dependency.

## Existing Relay primitives

At the proposal base, `ProfileVault` and `ProfileVaultTests` were read: whole AES-GCM authenticated payloads, 8 MiB bound, owned directory/file checks, ciphertext-only atomic writes, explicit existing-only load, fake key/file ports, corruption/wrong-key/invalid-size/symlink negatives and inert key-provider construction. `profile_preparation.restore_memory_snapshot` reapplies memory/foreign-key policies and validates SQLite integrity. These are reusable techniques, not permission to share the Personal Brain key, schema or authorizing provider with unverified history.

The proposed factoring must preserve those exact profile defaults and first establish a separate fixed History purpose. No live Keychain item, private directory, profile or account was opened. No encryption tests were rerun or newly claimed by this design-only change; existing source/tests are dependencies. New History encryption/publication needs actual fake-key tests.

## Other source comparisons, not dependencies

### Anarlog, formerly Hyprnote

Pinned source: [fastrepl/anarlog](https://github.com/fastrepl/anarlog/tree/48e19c9ed980bcda8dc64d63c4cdf4b96deddf4a), `48e19c9ed980bcda8dc64d63c4cdf4b96deddf4a`. Root [LICENSE](https://github.com/fastrepl/anarlog/blob/48e19c9ed980bcda8dc64d63c4cdf4b96deddf4a/LICENSE) is MIT; enterprise has its own license and was not treated as covered or adopted. This is a Tauri/React/Rust application with workspace editor/database/plugins and many provider/cloud integrations, not a drop-in native Swift storage layer.

Read `apps/desktop/src/chat/store/pending-persists.ts` and its test, `session/pending-soft-deletes.ts`, complete `session/hooks/useDeleteSession.ts` and selected matching tests, plus complete `session/components/note-input/enhanced/index.tsx` and matching generation/hydration tests. The useful patterns are separating optimistic visibility from actual committed deletion, retaining pending operations by record identity, preserving late failure information, and distinguishing streamed notes from persisted notes. A complete stream is not yet durable SQLite content. Tests explicitly hold a never-resolving deletion, roll back optimistic failure and prevent failed writes from finalizing; summary tests wait for stored content/hydration.

Relay should reuse those concepts through its own existing owned-operation contracts. It should not copy the web shell, cloud-share revocation, soft-delete/undo policy or provider framework. The inspected pending-chat helper has a finite-round waiter; that is not evidence of actual Relay quiescence and must not replace a real owner join. No Anarlog source/assets/prompts are adopted; no upstream tests/application were run. This is bounded conceptual review, not an audit of that product.

### VoiceInk

Pinned source: [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk/tree/22e5ec5479b712797c3b338fcb875961e58800b6), `22e5ec5479b712797c3b338fcb875961e58800b6`. Its [LICENSE](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/LICENSE) has a GPLv3 notice/link. No code or asset adoption is proposed.

Read `Infrastructure/Persistence/Models/Transcription.swift`, `Infrastructure/Persistence/Cleanup/TranscriptionAutoCleanupService.swift`, `Features/History/Views/HistorySettingsPanel.swift`, `Features/History/Export/VoiceInkCSVExportService.swift`, and available UI smoke-test inventory. These show separate raw/enhanced text and status, explicit transcript/audio cleanup choices, actual background-model deletion and explicit export. They also retain audio paths/request/model data beyond Relay's proposed scope. The selected test inventory did not provide proof of history deletion races; do not confuse a UI launch test with retention correctness.

Useful Relay distinctions are original versus derived text, explicit retention controls and real delete/export actions. SwiftData, audio-file storage, AI prompt persistence and that license-bearing implementation are not adopted. No VoiceInk runtime/test was run.

## Handoff

Read the proposal first, especially the action table. Approve/adjust the dependency, key-purpose factoring, remembered saving/Lock behavior, bounded retention/deletion policy and issued-observation/Model seams before code. Then create a separate implementation checkpoint for store/coordinator and another for actual Model/UI composition. Generated notes require a distinct accepted noncapture inference contract. This research delivers no recording, saved history, generated notes, visible UI acceptance or inference/account result.

## Approved native History owner lease

The History-only wrapper now invokes the installed Darwin `open/openat`, `mkdir/mkdirat`, `fstat/fstatat/lstat`, `flock` and `close` APIs; no new runtime framework or package is added. Reviewed primary references: [Apple flock(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html), [open(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html) and [close(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/close.2.html), plus the actual macOS27 SDK `sys/fcntl.h` definitions for exclusive/nonblocking locks, directory/no-follow/close-on-exec flags and descriptor calls. These are invoked system APIs, not copied competitor/source code. The archived manual documents cooperating-process advisory semantics; the actual owned-temp-file/subprocess tests prove the behavior on this local macOS runtime. No older supported runtime/Intel result is inferred from that.

`HistoryVaultStorage` owns a zero-content regular0600 `owner.lock` inside owned0700 Relay/History. It never truncates, overwrites or unlinks that lock and writes no PID, application timestamp, private title/index or credential to it. The ciphertext inode cannot serve as the lifetime lock because the protected atomic save replaces it. The separate lock fd remains held before load/create until actual GRDB/storage close; descriptors are close-on-exec so a helper cannot retain the app's lease. Before storage access, fd/device/inode/owner/mode/link/zero-size and retained directory/path identity are checked. Directory replacement, symlink/hard-link/permission-invalid or nonzero entries fail without healing/truncation. A failed close is not blindly retried against a possibly reused fd.

Existing-only missing vault/directory creates no lock/key/directory/vault. An earlier candidate vault with no owner.lock needs explicit idle Enable to establish the empty lock; its ciphertext/header/key are preserved. The production Model factory uses this wrapper. Explicit injected storage ports keep their own stated test/IO ownership contract; the primitive ProfileVault/shared194 source is unchanged. No same-user hostile-process isolation, secure erase or authority based on an arbitrary PID is claimed.

Ten lease cases and actual Model tests use temporary owned paths and fake keys. Real Python `fcntl.flock` probes independently contend/release the kernel lock, held begin/close ports prove cancellation and real joins, and two actual Model/helper lifecycles prove no key/read/native start by the competing app and no helper-inherited fd after History Lock. The fixed contention message reflects actual EWOULDBLOCK only. The warm snapshot validation and original-evidence validation remain separate defenses; neither is a replacement for this lease.
