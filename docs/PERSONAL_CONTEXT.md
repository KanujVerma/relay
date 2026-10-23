# Personal and job context

Issue [#61](https://github.com/KanujVerma/relay/issues/61). Implemented code, synthetic acceptance only. The existing on-disk `BrainStore(path)` prototype remains synthetic only; real preparation uses the new native vault and an in-memory store.

## Preparation and storage boundary

`spikes/macos-profile` builds the `RelayProfile` library and `relay-profile-prep` demonstration window on macOS 14+, Swift 6. Construction and default launch do not import a file, launch a helper, access Keychain or run inference. A visible **Open protected profile** action opens/creates the vault. Only then do visible selected-file, entered-note, review, correction and revoke controls become available. The file importer opens from a real button action. This application interaction boundary is not OS attestation of a human identity and does not resist malicious code already executing as the user or in the helper.

The native vault encrypts the **whole SQLite serialized payload**, including source labels, source digests, roles, ownership, candidate text and review metadata, with CryptoKit AES-256-GCM. Its version header is authenticated additional data. A 256-bit random generic-password key lives in the macOS data-protection Keychain with WhenUnlockedThisDeviceOnly accessibility and synchronization disabled. Keychain lookup happens only during an explicit profile open/save; lookup errors, missing keys on reopen, wrong keys and authentication failures fail closed. They never trigger silent key replacement or vault recreation. The default file is `~/Library/Application Support/Relay/Profile/profile.relayvault`, under an owner-only 0700 directory with a 0600 file. Only ciphertext is written during atomic file replacement. The header, filename and payload size remain visible. No whole raw résumé/project document, source path or private content is put into logs or Git.

Python keeps SQLite in memory, exports a bounded snapshot, and receives decrypted bytes over inherited local pipes. Snapshots are limited to 8 MiB; selected input bytes to 2 MiB; selected text to 30,000 characters; 32 sources and 64 parsed claims per source. Full source files are discarded after conversion. Only exact candidate snippets, their spans/digests/locators and necessary reviewed job excerpts are retained. Job excerpts are limited to 4,000 characters and remain role context rather than personal biography.

This protects the persisted payload, not plaintext process memory, swap, the user's original source document, a compromised user account or old filesystem backups. Revocation provides active-authority invalidation and ledger redaction. No secure erase or backup-erasure guarantee is made. Hardware/private-user Keychain and actual file-picker acceptance have not been exercised during development.

## Native integration API

The final app uses one answer helper containing one `ProfileBridge`. The standalone profile executable uses a lazy demonstration child, not a second production database.

- `ProfilePort.request(Data) async throws -> Data` exchanges one JSON command and result. `ClosureProfilePort(request:close:)` adapts the main app's UUID-correlated profile envelope. The answer lane owns the outer envelope and replay rejection.
- `@MainActor ProfileClient(port:)` handles bounded transfers, state, snapshots and lock. `close()` sends a profile lock before closing its port. A shared helper port can keep the conversation transport alive in its close closure.
- `@MainActor ProfileController(client:vault:onInvalidate:)` owns preparation state and saves each mutation before presenting its result as saved. The `onInvalidate` callback must synchronously clear current personal-answer admission before a mutation or lock. A failed save locks the profile, closes the preparation port and clears its visible evidence rather than leaving an unsaved approval active.
- `ProfilePreparationView(controller:)` is the real SwiftUI selected-file, entered-note, ownership review, explicit correction and source-revocation view. Add it to the existing window; no separate answer mode is required.

Native frame IO and the standalone Python harness use a four-byte big-endian length with at most 16 KiB UTF-8 JSON per frame. Snapshots/files use sequential 4096-byte base64 chunks and exact size/SHA-256 manifests, never one giant answer frame. Transfers are serialized and bounded. Incomplete or oversized loads never authorize retrieval. An active profile must be explicitly locked before another load; the final main-helper envelope must reject replayed request UUIDs. Native demo IO has a total 15-second frame deadline and reaps a failed child.

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

At the native checkpoint: **413 Python tests passed with 21 optional converter skips**, and **9 native tests passed**. Synthetic Swift tests inject keys and a Security client; they exercise encryption/tampering, owner-only permissions, Keychain failure behavior, lazy startup, real Python child framing, review/save/reopen/revoke and failed-save admission retirement. No actual private imports, real Keychain reads/writes, permission dialogs, capture or model calls were exercised.

Run from the repository root:

```sh
python3 -m unittest discover -s tests -q
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-profile-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-profile-modules swift test --disable-sandbox --package-path spikes/macos-profile --scratch-path /private/tmp/relay-profile-build --cache-path /private/tmp/relay-profile-cache
```

The demo can be launched explicitly with `swift run --package-path spikes/macos-profile relay-profile-prep --repository /absolute/path/to/relay --python /absolute/path/to/python3`. The integrated app should inject its shared helper port instead. Signed-app Keychain behavior, actual native picker/review clicks with owner-approved private material, optional real PDF/DOCX conversion fidelity and the combined interview flow remain acceptance gates.
