# Personal context independent review

Reviewed head `d8bb0dcaf72be5db053b688d895fb5830a206a01` against `a8f8359354f44e11be39e22a55422b2cef9f6c91`, PR #63.

**Spec verdict: changes required.** The core reviewed-source, encrypted-persistence and provider design follows the requested direction, but lock failure handling and asynchronous controller state are incomplete, and retrieval can return unrelated evidence for unsupported C/R questions.

**Task-quality verdict: substantial, well-scoped implementation with useful synthetic coverage, requiring focused corrections before acceptance.** No critical findings. Three important findings below. Reported suite totals were inspected as implementation evidence, not independently rerun or treated as proof.

## Important findings

### 1. [P1] A failed shared-helper lock silently leaves the profile active

**Location:** `spikes/macos-profile/Sources/RelayProfile/ProfileClient.swift:204-208`; callers at `ProfileController.swift:81-85` and `171-174`.

`close()` discards every error from the `lock` request, then invokes the port closer. The documented shared-helper adapter deliberately has a no-op closer, so a transport failure or rejected lock can return as if closure completed while `ProfileBridge` remains ready with its existing approved ledger. This also weakens the promised failed-save lock: the controller hides the profile and says it is locked without knowing that helper authority was retired. The native invalidation callback retires existing answer admission, but this library does not disable the still-ready provider for subsequent retrieval.

**Focused reproduction:** Loaded the unchanged `ProfileClient.swift` into an inline Swift harness with an actual synthetic Python child. An injected `ProfilePort` forwarded all commands except `lock`, which threw `ProfileError.transport`; its close action was empty, as for the shared port. After `await client.close()` returned, a subsequent real `state` command reported `ready=true`. No Keychain or private source was accessed.

**Suggested correction:** Require and propagate a successful lock acknowledgement. On a missing acknowledgement, fail closed for subsequent personal retrieval through an independently enforceable helper/admission shutdown or helper restart. Do not display a successful lock or save-failure lock until retirement is established. Preserve the conversation helper on the successful path. Add a shared-port lock-failure regression test, including a failed-save path with previously approved evidence.

### 2. [P2] An in-flight open can restore open UI state after close completes

**Location:** `spikes/macos-profile/Sources/RelayProfile/ProfileController.swift:87-100`, especially `99-100`, and `171-174`.

The controller is reentrant at its awaited port calls. `close()` clears state but does not retire an operation generation or cancel an outstanding `openProfile()`. If an open is awaiting `refreshSources()`, a host-triggered close can complete, and the delayed sources response then repopulates `sources` and executes `opened = true`. The native UI consequently reports an open profile after locking and can show source labels again; normal reopening is also blocked because `openProfile()` now sees `opened=true` while the helper can be locked. The view's busy disabling does not protect a public host close used for dismissal or lifecycle cleanup.

**Focused reproduction:** Ran the unchanged controller/client code with an in-memory vault stub and an injected asynchronous port. Held the `sources` response during `openProfile()`, awaited `controller.close()`, then released the response. Result: `opened=true, helperLocked=true`. No persisted profile or Keychain item was created.

**Suggested correction:** Give controller operations a lifecycle generation and discard results after close or replacement. Coordinate close with in-flight client transfers and make it impossible for an old operation to republish state after closure. Add delayed-response tests for open, selection/review and lookup against close/reopen.

### 3. [P2] Single-letter skill queries retrieve unrelated approved biography

**Location:** `relay_spike/personal_context.py:59-61` and `146-148`.

The tokenizer removes all one-character terms, including the meaningful language names `C` and `R`. When the rest of the question consists of stop words, `question_terms` becomes empty and the relevance filter is bypassed. Unsupported skill questions therefore return `ready` with arbitrary approved facts, contrary to bounded relevant retrieval and the stated unknown-skill behavior.

**Focused reproduction:** Created one synthetic reviewed fact, `I implemented Atlas SQL tests.`, through `ProfileBridge`'s normal selection/review commands. Both `Have you used R?` and `Have you used C?` returned `ready` with that SQL fact. The control `Have you used Tableau?` returned `no_evidence` with no facts.

**Suggested correction:** Retain meaningful single-letter tokens and require positive relevance for non-overview questions when no project hint supplies context. Keep the explicit résumé overview path. Test absent and present C/R evidence with a bounded budget.

## Strengths and inspected boundaries

- Selection only stages candidates; explicit native review uses source-bound fingerprints and the existing ReviewGateway/BrainStore lifecycle. Actor distinctions, exact spans/digests, atomic replacement checks and revocation remain represented.
- Provider bundles are immutable, issued by object identity and checked against a full-ledger digest. Job/profile mutations are included in freshness rather than relying on model or wire booleans.
- The actual vault source seals the whole serialized ledger with CryptoKit AES-GCM and uses a narrow Keychain adapter. Python preparation uses an in-memory store. Transfers are bounded to 4096 raw bytes per chunk within 16 KiB frames.
- The frozen diff was read once; output cutoff was resolved by reading changed files separately. Baseline reads were limited to `resume_candidates.py` and relevant `personal_brain.py` functions to evaluate candidate bounds, attribution, canonical correction and active-source checks. This was not a full system security review.
- No source, index, branch, commit, push or GitHub changes were made. The checkout was clean at the reviewed head before the focused checks.

## Cannot verify here

- Joined single-answer-helper integration, outer request UUID replay rejection, final personal-answer currentness/claim checking and native answer-card invalidation belong to the composition boundary and were not established from this lane diff.
- Actual file-picker/review clicks, signed-app device Keychain behavior, optional real PDF/DOCX fidelity and private-user acceptance remain pending. Synthetic injection does not prove these gates.
- The reported 414 Python tests, 10 native tests, 26 fixtures and 20 documentation checks were not rerun. Only the three focused reproductions above were executed; the Swift interpreter required a permitted temporary compiler cache, and no repository test files were added.
