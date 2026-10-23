# Personal and job context

Issue [#61](https://github.com/KanujVerma/relay/issues/61). Implemented code, synthetic acceptance only. The existing on-disk `BrainStore(path)` prototype remains synthetic only; real preparation uses the new native vault and an in-memory store.

## Preparation and storage boundary

`spikes/macos-profile` builds the `RelayProfile` library and `relay-profile-prep` demonstration window on macOS 14+, Swift 6. Construction and default launch do not import a file, launch a helper, access Keychain or run inference. A visible **Open protected profile** action opens/creates the vault. Only then do visible selected-file, entered-note, review, correction and revoke controls become available. The file importer opens from a real button action. This application interaction boundary is not OS attestation of a human identity and does not resist malicious code already executing as the user or in the helper.

The native vault encrypts the **whole SQLite serialized payload**, including source labels, source digests, roles, ownership, candidate text and review metadata, with CryptoKit AES-256-GCM. Its version header is authenticated additional data. A 256-bit random generic-password key lives in the macOS data-protection Keychain with WhenUnlockedThisDeviceOnly accessibility and synchronization disabled. Keychain lookup happens only during an explicit profile open/save; lookup errors, missing keys on reopen, wrong keys and authentication failures fail closed. They never trigger silent key replacement or vault recreation. The default file is `~/Library/Application Support/Relay/Profile/profile.relayvault`, under an owner-only 0700 directory with a 0600 file. Only ciphertext is written during atomic file replacement. The header, filename and payload size remain visible. No whole raw résumé/project document, source path or private content is put into logs or Git.

Python keeps SQLite in memory, exports a bounded snapshot, and receives decrypted bytes over inherited local pipes. Snapshots are limited to 8 MiB; selected input bytes to 2 MiB; selected text to 30,000 characters; 32 sources and 64 parsed claims per source. Full source files are discarded after conversion. Only exact candidate snippets, their spans/digests/locators and necessary reviewed job excerpts are retained. Job excerpts are limited to 4,000 characters and 10,000 UTF-8 bytes, with control characters rejected except newline/tab and remain role context rather than personal biography.

This protects the persisted payload, not plaintext process memory, swap, the user's original source document, a compromised user account or old filesystem backups. Revocation provides active-authority invalidation and ledger redaction. No secure erase or backup-erasure guarantee is made. Hardware/private-user Keychain and actual file-picker acceptance have not been exercised during development.

## Native integration API

The final app uses one answer helper containing one `ProfileBridge`. The standalone profile executable uses a lazy demonstration child, not a second production database.

- `ProfilePort.request(Data) async throws -> Data` exchanges one JSON command and result. `ClosureProfilePort(request:emergencyShutdown:close:)` adapts the main app's UUID-correlated profile envelope. The answer lane owns the outer envelope and replay rejection.
- `@MainActor ProfileClient(port:)` handles bounded transfers, state, snapshots and lock. `close()` returns `ProfileCloseOutcome.locked` only after the helper acknowledges `{ok:true,locked:true,ready:false}`. A shared helper port can keep conversation alive with a no-op normal closer. An in-flight request/transfer or missing acknowledgement forces the required `emergencyShutdown()` capability; the outcome is `helperStopped`, and the old client/port cannot start or use another helper. Construct a fresh helper/client/controller to recover.
- `@MainActor ProfileController(client:vault:onInvalidate:)` owns preparation state and saves each mutation before presenting its result as saved. The `onInvalidate` callback must synchronously clear current personal-answer admission before a mutation or lock. A failed save retires profile authority and clears visible evidence. A confirmed lock preserves the shared conversation helper; a missing acknowledgement stops it independently. The UI reports `helperStopped` as unavailable, not as a successful normal lock. Controller lifecycle generations fence every awaited result and vault/state commit after close or replacement. Its mutation action is explicitly `@MainActor`, preserving dictionary isolation on Swift 6.1.
- `ProfilePreparationView(controller:role:)` is the real SwiftUI selected-file, entered-note, ownership review, explicit correction and source-revocation view. Supply the app-owned canonical role to lock the preparation role to the answer engine. Add it to the existing window; no separate answer mode is required.

Native frame IO and the standalone Python harness use a four-byte big-endian length with at most 16 KiB UTF-8 JSON per frame. Snapshots/files use sequential 4096-byte base64 chunks and exact size/SHA-256 manifests, never one giant answer frame. Transfers are serialized and bounded. Incomplete or oversized loads never authorize retrieval. An active profile must be explicitly locked before another load; the final main-helper envelope must reject replayed request UUIDs. Native demo IO has a total 15-second frame deadline. Failed-child shutdown retains ownership and closes admission until an actual prelaunch termination-handler exit receipt arrives; elapsed grace only escalates TERM to KILL and is not evidence of reap. No fixed shutdown-latency bound is claimed.

## Verified retrieval API

`BrainContextProvider.retrieve(question, role, project_hint=None, budget=8)` returns an immutable `ContextBundle(facts, role, project_hint, job_context, status, missing_fields, revision)`. `ProfileBridge` implements this same provider interface and owns the actual preparation store.

Each `ContextFact` has `fact_id`, `source_id`, `actor`, `claim_key`, `text`, `evidence`, and integer `revision`. `ContextEvidence` has `source_sha256`, `snippet_sha256`, `span_start`, `span_end`, and optional `locator` (`text:line:N`, `pdf:page:N`, or `docx:paragraph:N`). Revision is the existing review revision. Source metadata and job context are covered by the opaque full-ledger bundle revision.

Retrieval ranks exact terms and project/role context in memory. It emits at most 16 facts and 8,000 total context characters. No FTS or embedding storage is added. It supports bounded résumé overviews and project-scoped follow-ups. Unknown skills stay absent, and a project rationale is available only when the reviewed source actually says it. Legacy confirmed claims without exact reviewed spans are excluded and reported as missing evidence. Self, team and teammate ownership survive retrieval; a team claim cannot authorize a first-person implementation claim.

Statuses are `ready`, `no_evidence`, `conflict` and `revoked`. `no_evidence` is not proof the user lacks experience. `conflict` marks an unresolved pending alternative under the same canonical key; this is not a semantic contradiction detector. `revoked` identifies an emptied verified profile with revocation history. Missing fields distinguish missing reviewed spans, personal facts, job context and unresolved conflicts. Rejection/revocation redacts the existing ledger and the profile metadata/locators; cross-source experience dependencies use the existing BrainStore invalidation rules.

The answer host retains the **actual issued bundle** and calls `validate_current(bundle)` immediately before publication. A copied/serialized bundle or model-supplied fact ID grants no authority. Any ledger/job mutation conservatively expires bundles; profile lock/load retires them immediately. Currentness is not a generated-claim verifier: the answer layer must separately ensure every personal claim preserves supported text and attribution.

## Source and dependency decisions

No new third-party runtime package or model is added. Native Security/CryptoKit APIs and the existing Python SQLite/conversion paths are reused. No upstream implementation was copied or vendored.

| Source inspected | Pin/license | Actual decision |
| --- | --- | --- |
| [KeychainAccess source](https://github.com/kishikawakatsumi/KeychainAccess/blob/84e546727d66f1adc5439debad16270d0fdd04e7/Lib/KeychainAccess/Keychain.swift), [generic-password/accessibility tests](https://github.com/kishikawakatsumi/KeychainAccess/blob/84e546727d66f1adc5439debad16270d0fdd04e7/Lib/KeychainAccessTests/KeychainAccessTests.swift), [license](https://github.com/kishikawakatsumi/KeychainAccess/blob/84e546727d66f1adc5439debad16270d0fdd04e7/LICENSE) | v4.2.2, `84e546727d66f1adc5439debad16270d0fdd04e7`, MIT | Reference for bounded generic-password SecItemCopyMatching/SecItemAdd behavior and explicit accessibility/synchronization. Use a narrow original native adapter, not the wrapper's broad enumeration/remove-all/update APIs. Inspected upstream tests only; they were not run because they operate on real Keychain items. |
| [swift-crypto AES-GCM source](https://github.com/apple/swift-crypto/blob/95ba0316a9b733e92bb6b071255ff46263bbe7dc/Sources/Crypto/AEADs/AES/GCM/AES-GCM.swift), [AES-GCM tests](https://github.com/apple/swift-crypto/blob/95ba0316a9b733e92bb6b071255ff46263bbe7dc/Tests/CryptoTests/Authenticated%20Encryption/AES-GCM-Runner.swift), [license](https://github.com/apple/swift-crypto/blob/95ba0316a9b733e92bb6b071255ff46263bbe7dc/LICENSE.txt) | 3.15.1, `95ba0316a9b733e92bb6b071255ff46263bbe7dc`, Apache-2.0 | Reference for random default nonces, combined representation, authenticated data and wrong-key rejection. macOS uses built-in CryptoKit directly, without SwiftCrypto/BoringSSL packages. Inspected, not executed, upstream tests. |
| [Existing converter source record](DOCUMENT_CONVERTERS.md) | Pinned optional Python converters | Keep native PDF selectable-text and simple DOCX paragraph adapters. Unsupported layouts, encrypted/scanned PDFs, unavailable dependencies or missing provenance fail closed. No OCR, network fetch or new model download. |

GRDB/SQLCipher and general memory frameworks were not adopted: whole encrypted snapshots preserve the tested ledger contract without a new migration/encryption library, and agent-fact promotion would violate explicit personal review.

## Verification and remaining acceptance

At the native checkpoint: **415 Python tests passed with 21 optional converter skips**, and **16 native tests passed**. Synthetic Swift tests inject keys and a Security client; they exercise encryption/tampering, owner-only permissions, Keychain failure behavior, lazy startup, real Python child framing, review/save/reopen/revoke, successful shared-helper close-to-lock, failed lock with approved facts, failed-save emergency retirement, and delayed open/selection/review/lookup across close/reopen. Native child tests resolve `RELAY_TEST_PYTHON` or PATH and require Python 3.11+ with SQLite serialization; they never skip the real child. No actual private imports, real Keychain reads/writes, permission dialogs, capture or model calls were exercised.

Run from the repository root:

```sh
python3 -m unittest discover -s tests -q
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-profile-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-profile-modules swift test --disable-sandbox --package-path spikes/macos-profile --scratch-path /private/tmp/relay-profile-build --cache-path /private/tmp/relay-profile-cache
```

The demo can be launched explicitly with `swift run --package-path spikes/macos-profile relay-profile-prep --repository /absolute/path/to/relay --python /absolute/path/to/python3`. The integrated app should inject its shared helper port instead. Signed-app Keychain behavior, actual native picker/review clicks with owner-approved private material, optional real PDF/DOCX conversion fidelity and the combined interview flow remain acceptance gates.


## Review round 1 correction and host adapter requirements

The independent review baseline is `d8bb0dcaf72be5db053b688d895fb5830a206a01`. Its three reproduced findings required changes: swallowed lock failures could leave an approved provider active, delayed controller responses could republish closed state, and C/R skill queries could bypass relevance after tokenization. Targeted regressions failed on the reviewed code (five native assertions and seven retrieval assertions) before correction. Currentness checks remain required in the answer layer.

The `ProfilePort` contract now requires `func emergencyShutdown() async`; there is no default no-op. The `ClosureProfilePort` initializer is:

```swift
ClosureProfilePort(
    request: @escaping @Sendable (Data) async throws -> Data,
    emergencyShutdown: @escaping @Sendable () async -> Void,
    close: @escaping @Sendable () async -> Void = {}
)
```

The app-owned emergency callback must synchronously retire native helper/session/display admission, reject and fence all pending request continuations/queued frames for the old helper, then terminate and reap that helper before returning. No old queued load/command can run afterward. It must not silently start a replacement helper; recovery uses a fresh helper/client/controller under a new lifecycle. A normal `close` callback may remain a no-op because the acknowledged Python lock already discarded the profile ledger while keeping conversation alive. `ProfileController.closeOutcome` distinguishes `.locked` and `.helperStopped` for the host and UI.

C/R are retained as meaningful single-letter terms. Every non-overview, non-project-scoped query requires positive term relevance, so an empty token set does not authorize arbitrary biography. The explicit résumé overview path and bounded project follow-ups remain available.

Local verification used Apple Swift 6.4 on arm64 and Python 3.14. Hosted Intel/Swift 6.1.2 validation is still pending; local success does not establish that older toolchain path. No private data, actual Keychain operations, capture or inference were exercised for these corrections.


## Shutdown liveness correction after integration

The root's complete native run at `eb98e41ebec670452f96313289203ebe1853afa6` compiled and then stalled for more than five minutes. The sampled cooperative executor was inside Foundation `Process.waitUntilExit`, even though no Python child remained. This supersedes the earlier local 16-test pass as sufficient shutdown verification.

[Apple's waitUntilExit documentation](https://developer.apple.com/documentation/foundation/process/waituntilexit()) describes polling the current thread's run loop. The current SDK `NSTask.h` also documents that default termination notifications target the launch thread and recommends [terminationHandler](https://developer.apple.com/documentation/foundation/process/terminationhandler) for secondary threads/queues. A Swift actor may resume on another cooperative thread. This matched the observed stack; the fix does not move the same unbounded wait to another executor or increase its timeout.

`ProfileProcessExitReceipt` is installed through `child.terminationHandler` **before** `run()`. It latches the actual termination status under a lock and resumes async waiters safely whether completion precedes or follows waiter registration. Foundation remains the sole production reaper. `PipeProfilePort` coalesces shutdown, closes inherited IO, sends TERM, allows the existing 500 ms grace asynchronously, escalates to KILL if still running, then suspends until the actual receipt. No production `waitpid`, `waitUntilExit` or blocking `Thread.sleep` is used. Pending shutdown retains the process/receipt and rejects new requests; only actual completion clears ownership. The public port API and normal shared-helper lock behavior are unchanged.

A short actual-child regression covers 16 EOF shutdowns, 16 children proven already exited before close, and four SIGTERM-ignoring children requiring escalation. Shutdown is invoked from independently scheduled cooperative tasks. Each case checks `waitpid(pid, WNOHANG) == -1` with `ECHILD` **after** completion, proving Foundation already reaped the owned child. This is a test observation, not a second production reaper. [Apple's waitpid documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/waitpid.2.html) defines those outcomes.

The regression exceeded an external 40-second deadline on the old source and passed on the correction. The complete corrected native suite passed **17 tests** in **5.962 seconds** (build 8.09 seconds), under an explicit external 50-second deadline. Python source was unchanged and its full suite was not rerun for this native-only correction. The capability-check test process also uses a prelaunch handler with a five-second failure deadline instead of a run-loop wait. Verification used local arm64 Swift 6.4; hosted Swift 6.1.2, joined-helper integration and independent delta review remain separate. No new package, copied upstream implementation or private/hardware/model action was introduced.
