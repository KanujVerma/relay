# Personal review round 1 correction handoff

## Frozen state

- Original independent review baseline: `d8bb0dcaf72be5db053b688d895fb5830a206a01`.
- New frozen correction head: `eb98e41ebec670452f96313289203ebe1853afa6`.
- Branch: `feature/personal-context-2026-10-23`; normal push confirmed and working tree clean.
- Existing draft PR63: https://github.com/KanujVerma/relay/pull/63, targeting frozen foundation a8f8359.
- No main merge, issue closure, answer-app/global HANDOFF/BUILD_CONTRACT edits, or additional source changes after the final interruption.

## Focused delta for independent re-review

One correction commit, eb98e41, against d8bb0dc changes twelve lane-owned files. Production changes are limited to personal_context.py, profile_bridge.py, ProfileClient.swift and ProfileController.swift. The other files are synthetic regressions, portable test interpreter resolution and lane/API documentation.

1. P1 failed lock: ProfileClient.close requires `{ok:true,locked:true,ready:false}` from the actual Python lock. A rejected/missing acknowledgement, or an in-flight request/transfer, invokes required independent emergencyShutdown, returns `.helperStopped`, and permanently fences the old client/pipe. A successful normal lock returns `.locked` and can preserve the shared conversation helper. Actual-child tests start with approved facts and prove missing lock acknowledgement stops the real provider process. Failed-save coverage also starts with approved evidence and preserves the prior encrypted snapshot while retiring the old helper.
2. P2 stale async state: Client sends/transfers carry a lifecycle UUID. Controller open, mutation, lookup, close and failure paths check their own lifecycle after awaits and before persistence/publication. Open/source results commit together under that fence. Delayed results, errors and busy cleanup cannot overwrite closed/replacement state. Real-child tests delay open sources, transfer chunks, selected-source commit, review approval, mutation source refresh and existing-fact lookup across close/fresh-helper reopen. closeOutcome exposes acknowledged lock versus stopped helper; the latter is reported as unavailable/fresh helper required.
3. P2 C/R relevance: Meaningful single-letter C/R tokens survive normalization. Non-overview queries without project scope require positive term overlap even if tokenization is empty. Absent/present/lowercase C/R and bounded overview cases use real reviewed facts.
4. Hosted Swift 6.1.2 compile correction: mutate's action is explicitly `@MainActor () async throws -> [String: Any]`. Dictionary isolation is retained; no unchecked Sendable workaround was added.
5. Intel CI test compatibility: Native child tests resolve RELAY_TEST_PYTHON or PATH and validate Python>=3.11 with SQLite serialize/deserialize. No actual-child test is skipped and no hardcoded Homebrew path remains in tests.

## Verification evidence

Before production changes, three focused native baseline regressions failed five expected assertions, reproducing failed shared-helper lock, failed save with approved facts and stale open/source publication. C/R/empty-token retrieval failed seven expected subtest assertions on the reviewed source.

Completed correction checks, before the handoff interruption:
- Python unittest discovery: **415 tests, 21 optional converter skips, zero failures**.
- Native macos-profile suite: **16 tests, zero failures**, UI/demo builds. Real synthetic Python child processes, injected keys/Security only.
- EVALS/validate.py: **26 synthetic cases pass**.
- EVALS/verify_docs.py: **20 required files/local links pass**.
- git diff --check: pass.

Local toolchain: Apple Swift 6.4 arm64 and Python 3.14. Hosted Intel Swift 6.1.2 is still pending. Existing synthetic HTTP/SQLite ResourceWarnings and restricted Swift user-cache warnings remain. An expanded delay-test investigation was interrupted; its gate now has a bounded failure deadline and the final complete 16-test run passed. Completed source/tests were not rerun during final handoff-only continuation.

## Exact required shared-helper adapter

ProfilePort requires all three methods:

```swift
func request(_ data: Data) async throws -> Data
func close() async
func emergencyShutdown() async
```

ClosureProfilePort initializer:

```swift
ClosureProfilePort(
    request: @escaping @Sendable (Data) async throws -> Data,
    emergencyShutdown: @escaping @Sendable () async -> Void,
    close: @escaping @Sendable () async -> Void = {}
)
```

There is NO default emergency no-op. The shared-helper owner must implement this callback in order:
1. Synchronously retire native helper/session/display admission and clear affected visible/pending answers.
2. Fence and reject every old-helper request continuation/queued frame before awaiting teardown. No queued load/command may execute afterward.
3. Terminate and reap the actual old helper before returning. Do not silently restart it.
4. Recover using a fresh helper/port, ProfileClient and ProfileController. An emergency-retired client/pipe deliberately cannot be reused.

The normal closer may remain a no-op because an acknowledged Python profile lock already discarded its in-memory ledger while preserving conversation. ProfileClient.close returns discardable ProfileCloseOutcome.locked or .helperStopped; ProfileController.closeOutcome publishes it. The changed Python lock acknowledgement fields are in the same commit and must be imported together.

The answer owner /root/build_answers was sent this API and commit before the interruption and will receive the frozen handoff again. Root owns independent delta review, hosted verification and composed normal-lock/emergency-stop acceptance.

## Pending boundaries

Independent re-review, exact-head hosted checks and joined single-helper acceptance remain pending. Real private files, actual Keychain items, native picker/private-user acceptance, capture, inference and model downloads were not accessed. All original signed-app/hardware acceptance limitations remain unchanged. No secure erase, backup erasure or OS identity-attestation claim is added.
