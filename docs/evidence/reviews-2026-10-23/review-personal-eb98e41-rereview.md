# Personal context scoped re-review

**Scope:** `d8bb0dcaf72be5db053b688d895fb5830a206a01..eb98e41ebec670452f96313289203ebe1853afa6`, limited to the three findings in `review-personal-d8bb0dc-report.md`, their regressions, the MainActor closure correction and portable mandatory child-test setup.

**Verdict: scoped correction accepted.** All three original findings are addressed in the library/helper delta. No new blocking finding was found in this scope. Integration may proceed with this exact delta; final host emergency-shutdown composition and hosted-toolchain acceptance remain separate gates.

## Original findings

### P1 failed shared-helper lock: addressed

`ProfileClient.swift:239-262` now accepts a normal lock only after the exchange has checked `ok=true` and the response additionally contains `locked=true, ready=false`. `profile_bridge.py:111-117` emits that acknowledgement only after retiring issuance, clearing transfer state and replacing the old ledger with a fresh in-memory store.

A missing acknowledgement, rejected lock, in-flight request or active transfer enters the forced path. It permanently marks the client retired before awaiting the required `ProfilePort.emergencyShutdown()` callback. Generation checks prevent an old pending response or later command from reviving that client. The protocol and `ClosureProfilePort` initializer have no default emergency no-op (`ProfileClient.swift:5-26`). The concrete demo pipe also permanently retires and stops/reaps its child (`143-146`). Normal acknowledged lock retains shared-helper operation through the normal no-op closer.

The added tests start with actual approved synthetic facts for failed-lock and failed-save cases. They assert process retirement and rejection of subsequent use. Generic `{ok:true}` does not satisfy the new acknowledgement.

### P2 late asynchronous state after close: addressed

`ProfileController.swift:97-143` captures a lifecycle generation for open and mutation operations, checks it after awaited work and before synchronous vault saves or visible publication, and commits open state/source summaries together. The mutation action is explicitly `@MainActor` at line 125. Lookup checks its generation before publishing results or errors (`179-191`). Close replaces the generation before clearing state and awaiting client closure (`201-211`); old defer/error paths cannot reset the new lifecycle's busy/error state.

The client independently fences each pending exchange and transfer (`ProfileClient.swift:172-204`). Close with pending activity forces helper retirement rather than allowing a late load/approval to execute afterward. The delayed open/selection/review/source-refresh/lookup regressions inspect closed state and the persisted snapshot after reopening a fresh helper/controller.

### P2 C/R query relevance: addressed

`personal_context.py:59-61` retains meaningful single-letter `c` and `r` tokens. The relevance guard at line 147 now rejects non-overview, non-project-scoped facts with no overlap even when the query token set is empty. The regression checks unsupported C/R and empty-token questions, supported uppercase/lowercase C/R with a budget of one, and the explicit bounded résumé overview path.

## Fresh focused verification

- Python: `test_single_letter_skills_require_matching_reviewed_evidence` passed, one test with its subcases.
- Native: `testRejectedLockStopsRealSharedHelperWithApprovedFacts`, `testDelayedOpenSourcesCannotRestoreOpenStateAfterClose` and `testSharedPortCloseLocksProfileWithoutStoppingConversationHelper` passed, three tests with zero failures. These used actual synthetic Python children and injected keys; the normal shared-helper path remained alive while the failed-lock path stopped its helper.
- The reviewed `ProfileTestEnvironment.swift` resolves `RELAY_TEST_PYTHON` or PATH, requires Python 3.11+ and SQLite serialization, and throws rather than skipping mandatory child tests. Changed native tests use that resolver instead of a hardcoded Homebrew executable.
- The builder's reported full 415-Python/16-native totals were not rerun. Broader delayed mutation/lookup and save-failure regressions were inspected as code/evidence, without expanding this re-review into a full lane audit.

## Remaining boundaries

The required final answer-host emergency callback is still a composition requirement, not something proved by the library tests. Its owner must retire native session/display admission, fence/reject pending continuations and queued old-helper frames, then terminate/reap the actual helper before returning. Recovery must use a fresh helper/client/controller. The exact Python acknowledgement and native API changes must be integrated together.

Local focused checks do not establish hosted Intel/Swift 6.1.2 acceptance. The explicit MainActor closure correction is present, but the older toolchain still needs its own build evidence. Actual Keychain/device behavior, private-file picker/review acceptance and the joined interview flow remain unverified here.

No source, index, HEAD, branch, push or GitHub modifications were made. Only this re-review report was authored; test build/cache artifacts stayed in temporary paths.
