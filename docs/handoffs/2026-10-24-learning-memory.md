# Learning Memory continuation

Date: 2026-10-24. Project: Relay. Branch: `wip/learning-memory-app-continuation-2026-10-24`.

Latest source checkpoint: `a99082b6c66bf81bb5193382e9a93e4f10b49e25`, after the explicit app WIP `41dd14d`. This handoff is a subsequent documentation commit. The verified [PR102](https://github.com/KanujVerma/relay/pull/102) branch remains `3882c76e323e77c1bd180cb88063871a2dca4215`. Do not move that verified head or merge main merely because this WIP is published.

Read the current canonical Root handoff first. This branch imports accepted Root7302; later Notes/controller/Store/Settings work may exist on the canonical branch and must be reconciled deliberately. This is an unaccepted continuation artifact, not the canonical integration or a finished feature.

## GOAL

Finish the actual Learning Memory flow: original available suggestion, later original microphone reply and remote continuation, protected source-linked retention, later-request advice, visible why/undo and deletion/retention propagation. Current-meeting decisions/constraints/unresolved follow-ups stay bounded source data. Personal Brain remains separately confirmed.

## DONE

- Accepted foundations are preserved: matcher/continuity/derivation, checked content-free CF control receipts, protected schema3, private History factory and general/personal use provenance. Exact component refs include `5ae9d8d`, `05c2dbb` and `3882c76`; [lane evidence](../lanes/LEARNING_MEMORY.md) records their actual native/Python gates and limitations. Root independently joined the earlier foundation in its 193-case gate, 191 passed/two explicit skips. Those earlier results do not certify this WIP app.
- Root reproduced the original workspace-lock leak with three assertion failures. Published3882 removes only that original workspace's affiliated semantic data/attribution. The exact original regression passed0.003s in the later discovery gate; unrelated/future live input stays intact.
- `swift test` using the existing retained History build/cache/module roots, jobs2, external180-second owned deadline and `--filter LearningApplicationTests` completed four named original app cases in the latest run: actual reentrant disable/watchdog1.144s; three real synthetic saved conversations followed by changed later advice,12 Help and Undo3.605s; default-off isolation0.003s; hidden commit followed by real window exposure and later original microphone1.244s. The helper completion is explicitly fictional; timing/source/window/History/Model plumbing is real. The code detail remains the original executable first-or-none function.
- That command returned0/97.671s but exited after starting the fifth case without its result or an app-suite total. **It is not a six-case green.** Preserve the four completed results and the incomplete test-host lifecycle evidence separately. Local log basename: `relay-learning-actual-model-original-targets-red-fixed-harness.log`.
- Direct original cold-source replay used `xcrun xctest -XCTest RelaySessionApplicationTests.LearningApplicationTests/testOptionalLearningPreparationUsesReadyHistoryWithoutRetiringOriginalNotesSource <exact-built-app-test-bundle>`. One named case and one-case suite completed, exit1/0.655s external,0.514s test time, three expected assertion failures. Optional Learning preparation reopened ready History, retired the actual existing Notes source and changed its workspace. Local log: `relay-learning-cold-direct-original-red.log`.
- Direct original viewport replay used the same command form with `testOffViewportLeadAndPointsCannotCreditEarlierMicBeforeActualScrollExposure`. One named case/suite completed, exit1/11.573s external,10.758s test time, but timed out at the artificial document-height-greater-than-viewport-plus100 prerequisite. It did not reach its intended uptake assertions. Local log: `relay-learning-viewport-direct-original-red.log`.
- The exact compiled test bundle for those direct runs had SHA256 `9462070e29d0097938d84b1ecfc598dad5a728a7ec55e9cedc45eb940ef983ca`.
- Cheap owned-window experiments established that a Foundation loop alone leaves the window inactive/occluded. Actual AppKit event dispatch produces real visible/hidden/visible-again states. Nested `NSApplication.run` from a MainActor task failed and was rejected. The committed fixture uses bounded actual `nextEvent`/`sendEvent`/`updateWindows`, an explicit normal test-app launch, the actual RelayWindowShell/show action and foreground/policy restoration. A separate three-cycle proof passed all actual show/key/occlusion and close/restoration markers; exact foreground restoration was independently checked. No production visibility flag was weakened.
- A real helper lifetime experiment reproduced exits0/1 when a second child reused an exclusive log, and0/0 with new owned per-child files, zero model requests. The committed launcher preserves its first log and gives later actual End/new-helper launches new files.

## IN PROGRESS

The production Model is still the original discovery candidate, unchanged by the harness repairs:

| File | SHA256 |
| --- | --- |
| `spikes/macos-panel/Sources/RelayPanelSession/SessionApplicationModel.swift` | `f9c113378c97bbbd357ff18dbbda6f7f43f28fd2933f502455f2d5dbeff3f588` |
| `spikes/macos-panel/Sources/RelayPanelSession/LearningMemoryRequestBridge.swift` | `f19790068807e7cab9812003dcd1c26f2432cf63a5e08107b8ebdfe3f1222a80` |
| `spikes/macos-panel/Tests/RelaySessionApplicationTests/LearningApplicationTests.swift` | `c4594194ed1a73dbf25177a61edc14d7caa3482cf510eef6f8dbac2ad2a193e0` |

- Close the genuine cold-source red by first trying the actual private Learning restore path. Only an actual failure may select existing-only History recovery; the saving-enabled flag is a hint, never a source grant. Avoid reopening an already owned ready Notes source.
- Fix the viewport fixture before claiming its target red. Root's exact review: wait for an accepted card plus the owned window's real visible/occlusion state, not `windowVisibleAt`, so the negative never depends on the behavior it challenges. A490-character question with collapsed short code may not exceed clip height by100. Measure actual document/clip dimensions and use a deterministic real layout, such as expanding the actual optional detail while hidden and positioning the real scroll before exposure. Preserve the original four bodies and the final earlier-microphone/availability/later-reply/clean-attribution assertions. Obtain its genuine runtime negative before implementing production geometry.
- Add a real owned marker behind only the answer's lead/points, tied to the original owner/binding/card/replacement. Require its actual visible rectangle inside the attached visible window, and observe genuine scroll/layout changes. Collapsed detail cannot supply uptake tokens. Latency's coarse window-visible observation remains separate.
- Diagnose the apparent XCTest app-process lifecycle exit. Require every named case result and expected suite count; exit0 alone is insufficient. Do not hide a test-host early exit with a production visibility bypass.
- Replace the separate retired32/current32 timing pools with the retired recorder reference only while idle, cleared on fresh owner configuration. The approved total bound is32 descriptive rows.
- Audit custom owned-end paths, especially `shutdownProfile` capture-failure cleanup, for Learning session retirement/quiescence. Normal `failSession`/End already uses the shared teardown. Preserve ordinary Pause continuity and retained learning where allowed.
- Finish actual app cold restart, source deletion/expiry/reset/disable/cancel, personal presentation/current-guide and source-retirement acceptance. Earlier encrypted-ledger/CF-process tests are not an actual whole-app restart claim. Real account/model quality, device acceptance and useful-answer latency remain separate Root-owned gates.
- Root owns the Settings presentation file. Its exact two-line opt-in disclosure from e325 is imported here; Root is adding a general bounded saved-example inspector. Obtain its frozen current source rather than overwriting it. Notes owns helper Notes extensions and narrow same-History-run save/delete APIs; latency owns descriptive timing assertions. The shared Model remains one coordinated seam.

## AT RISK

- The branch intentionally contains unaccepted app/runtime work. The full six-case app gate is incomplete, viewport target still lacks its intended red, and cold-source/lifecycle/cap fixes are pending.
- Diagnostic foreground metadata, raw environment output and local logs/scripts are deliberately excluded from Git. If local logs are unavailable, use the committed commands/results as a continuation map and rerun under the shared budget; do not invent evidence.
- New standalone bundle/relocation/real GUI/account/device/quality/latency acceptance has not been completed by this lane. The older verified application predates these features.

## DECISIONS

- The owner approved automatic tentative wording/length adaptation with visible why and Undo. Do not ask again for that preference. Current explicit requests and guides override inferred presentation.
- No inference of reading, skill, technical correctness, personal biography, interviewer approval or hiring success. Lexical similarity is only possible uptake. Confirmed Personal Brain stays separate.
- Deterministic local reflection uses the existing protected History owner and existing one-answer request factory. No new provider call, framework/server, package/model/environment download or policy rewrite.
- Keep suggestions and original reply/continuation examples behind the separate Learning opt-in; ordinary History does not retain assistant suggestions.
- The availability observer is after the outer `panel.accept` return, outside the non-recursive native authority lock and after the Model publication drain. Deferred original-owner/card/binding/native-lease checks are required. Never add authority reads inside the reentrant publication callback.

## STANDING INSTRUCTIONS

- Read `AGENTS.md`, the active design/plan and `docs/LOCAL_RESOURCE_BUDGET.md`. Preserve source/tests and original red fixtures; no resets/deletions or main merge.
- One heavy job globally, Root leases it. Use only retained build/module/cache roots, at most two compiler jobs, an external180-second owned-process deadline, at least30GiB free and aggregate Relay temp plus reserve at most25GiB. Latest direct preflight sampled23.588GiB temporary allocation and36.019GiB free with1GiB reserve; this is not a peak guarantee. Do not restart because an observation handle expires.
- Default fixtures and Settings rendering must never read/write production CF receipts, History, Keychain or account data. Only explicitly injected fictional ports/domains may enable Learning in a fixture.
- Keep raw private paths, environment output, credentials, documents and transcripts out of GitHub. Only scoped fictional/source/docs were committed here. No private foreground metadata is included.
- Read canonical Root status before importing later Notes/controller/Settings work. Report accepted versus WIP refs separately. No child agents in this lane.

## NEXT STEP

Use the completed original cold-source red to repair only optional typed Learning preparation, then replay that exact one-case test under Root's lease with a named-case result and one-case suite total.

## OPEN QUESTIONS

No user preference or architecture approval is missing. Remaining questions are implementation/verification: actual viewport fixture geometry, the test-host early exit and custom lifecycle closure. Do not treat those as permission requests or completion.
