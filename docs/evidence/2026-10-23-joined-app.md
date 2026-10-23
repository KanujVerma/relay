# Joined app verification, 2026-10-23

Source checkpoint: `657aee1fc30299dd15cb1d2fe7f9932616c1277a`, controller draft PR71. It joins accepted composition e45549a, answer b33292f and visual-service ad9f587 with the accepted conversation/profile/screen/control dependencies. This record covers synthetic behavior; it does not establish actual interview accuracy, permissions, hardware capture, private-profile imports, model/account availability or latency.

## Controller tests and packaging

- `/private/tmp/relay-answers-venv/bin/python -m unittest discover -s tests -q`:524 tests,21 optional document-converter skips, zero failures. HTTPX0.28.1 was installed; local socket tests ran. Expected negative CLI diagnostics and existing ResourceWarnings were observed.
- `swift test --package-path spikes/macos-session`:32 passed.
- `swift test --package-path spikes/macos-composition`:12 Swift Testing tests passed. The separate empty XCTest harness reports zero tests; that is not the package total.
- `swift test --package-path spikes/macos-panel`:37 passed, comprising22 transport/reducer,4 actual app-model/helper and11 legacy panel tests.
- Each native package ran with an external180-second process-group deadline; none timed out. No timed-out/stalled run is counted as passing.
- `spikes/macos-panel/scripts/build-session-app.sh`, ad hoc signature verification and Info.plist lint exited0.
- EVALS validation:26 synthetic questions; documentation/link validation:20 required files; diff whitespace check passed.

Unchanged profile17, screen28 and controls18 are earlier exact-source controller evidence, not fresh reruns in this check. Hosted checks and their precise heads remain in BUILD_STATUS.

## Visible coding fixture

The compiled app was copied to a temporary fixture bundle with a distinct local bundle ID/name and re-signed. Its executable was unchanged. This isolates it from other Relay windows; the temporary metadata is not a source/product change. Launch arguments selected `--fixture-suite coding`, this repository and the existing test Python runtime. No OAuth mode or source/model folder was supplied. Native UI automation inspected only this fixture window.

Observed in the actual window:

1. The automatically delivered question asks for a Python function returning the first item or None for an empty list. The fixture is visibly labeled OFFLINE FIXTURE and states synthetic audio/injected answers.
2. Talking points appear, and expanding Code and detail shows the multiline `first_or_none` function with preserved whitespace.
3. Pause clears question/card, shows Stopped and Resume, disables Help/Copy, and discloses that resume starts a fresh conversation.
4. Resume produces the fresh synthetic question/answer with collapsed detail.
5. Explicit Help reruns the currently accepted question and leaves a valid card.
6. End clears question/card, returns Start session and disables Help/Copy.
7. The owned fixture quits cleanly, process exit0.

The visible card layout was also inspected. No global shortcut was enabled; no screen/AX source was selected, no real permission prompt was approved, and no clipboard action was used.

## Case-study fixture and remaining work

The same executable launched with `--fixture-suite case` visibly receives the nurse-handoff feature-design question, displays a prose card and ends cleanly (exit0). This proves the visible case-study transport path only. The old injected fixture text reused coding-oriented input-contract/invariant/empty-input wording. That is a demo-content mismatch, not evidence of actual model quality. The helper owner subsequently corrected this fixture to discuss users/workflow, information needs, the smallest useful flow and success measures with a focused real-helper regression.

At that earlier checkpoint, the two visual consumer branches still needed frozen-head review and joined tests. Those source gates are now accepted below; visible inert setup-state verification remains blocked. The accepted service alone does not send real screen images from this app checkpoint. Actual capture/account tests remain explicit external acceptance work, and main merges remain separately approved.

## Follow-up helper/routing checkpoint

At controller source1f1d75a70a602edf07629281c528f1eeab227b71, accepted visual backend1c2d8ef and prospective routing a5827dc are joined. Full Python:558 tests/21 optional converter skips, zero failures. Eight existing native app/helper tests pass against the new Python host. Native source/tests remain exactly e45549a, while the image UI/producer is a separate unfinished branch. The case-study fixture mismatch above is corrected with a focused actual-helper test. Its attempted final visible recheck was blocked because the Mac locked; the owned synthetic fixture was stopped (exit143). This is not recorded as a passing visual check. Earlier coding/case End results remain as observed above.

Hosted native/Python run40014242743 on exact5bde19b succeeded with524 Python tests/21 optional skips, all144 native tests and app compilation. Contract run40014242744 also succeeded. Later-source local results and future hosted results are separate.

## Native visual core and prospective case helper

Controller code checkpoint6fcf2c2c0af1e0ef2cfe2d7468b44c03ce9194ef assembles reviewed native core e896 plus queued retirement correctione01 and first-write I/O correctiona227. Native source/test comparison against a227 is empty; no producer/UI code is included. `swift test --package-path spikes/macos-panel` passes50 tests (35 transport/reducer,4 app-model/helper,11 legacy), zero failures. Complete earlier Python558/21 optional skips remains unchanged-source evidence. Hosted exactb66cf2d also passed native/Python40016463296 and contract40016463067:558 Python/21 optional skips,144 native and app compilation, before this core extension.

While macOS remained locked, a manual headless run started the real `python -m relay_spike.session_host --fixture-model`, sent BE32 start/onset/closed-end/EOU frames for Case study: design a workflow for a clinic intake team. What would you build?, awaited the terminal frame with a5-second external read bound, and checked exactly one answer, identical question, users/workflow lead and null code detail. It produced Start with the users, workflow, and problem that needs to improve., then closed stdin and exited0 within5 seconds. No OAuth mode, account/model network or real capture was used. This confirms the corrected CLI/helper composition, not the final native visual walkthrough.

## Final accepted producer/settings assembly

At source5ed2b5005b8d415ee8b43a5451d992c0d7c12794, all native source/tests and the test-only mocked backend launcher exactly match independently acceptedc707ef86a47a067f00ad818a6a50ad7b50d346e7. Selected Python backend files exactly match accepted1c2d8ef; the separate reviewed prospective-routing correction remains joined. The final [scoped independent re-review](reviews-2026-10-23/review-visual-app-c707ef8-rereview.md) closes the b880 P1. Its14 focused methods and original frame/backend proof establish retirement-before-EOU ordering, preserved probe-response ownership, zero stale image POSTs after retirement, an unchanged positive image path and OCR-only Disable fallback.

Root fresh checks on the assembled source:

- `RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python` with writable temporary module caches; `swift test` for changed macos-composition and macos-panel under external180-second per-package process-group deadlines:17 composition and64 panel/app tests, zero failures. Panel counts are39 transport/state,14 actual app/model/helper and11 legacy tests. Logs: /private/tmp/relay-final-macos-composition-tests.log and /private/tmp/relay-final-macos-panel-tests.log.
- `/private/tmp/relay-answers-venv/bin/python -m unittest discover -s tests -q`:558 tests,21 optional converter skips, zero failures. Log: /private/tmp/relay-final-python-tests.log.
- `swift build --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-panel --product relay-panel-session`, with writable temporary module caches:exit0. Then copy the built product and committed plist into the existing ignored app bundle, ad-hoc sign, `codesign --verify --deep --strict` and `plutil -lint`:all exit0. Initial plain packaging script attempt failed on a restricted default module-cache path; the supported cache/SwiftPM invocation corrected the environment without source changes. Log: /private/tmp/relay-final-app-build-retry.log.
- `git diff --check` and exact source comparisons:exit0. Unchanged native session/profile/screen/controls use earlier exact-source hosted proof; this is not a new complete local rerun of all six packages.

Hosted exacte9e89cd passed [native/Python40019222418](https://github.com/KanujVerma/relay/actions/runs/40019222418) and [contract40019222481](https://github.com/KanujVerma/relay/actions/runs/40019222481):558 Python/21 optional skips,157 native tests and app compilation on Swift6.2.3. It precedes final producer/UI; observe final published-head CI separately.

After final source assembly, CUA inventory again reported that the Mac is locked and automatic unlock failed. No unlock bypass or further native launch was attempted. The final case/settings walkthrough remains unperformed. All image/catalog/token/SSE/backend inputs in the new app regressions were synthetic via HTTPX MockTransport, with actual local owned-child pipes. No real account, Keychain, model request, permission, screen/AX/global-key capture or private content was used. App packaging remains a local checkout/Python prototype, not a standalone distribution.

## Full final hosted integration

Exact published7685572cb862bf399f35b3ed3a494c0bd8dc6be5 passed [macOS/Python40027128942](https://github.com/KanujVerma/relay/actions/runs/40027128942) and [contracts/docs40027128884](https://github.com/KanujVerma/relay/actions/runs/40027128884). Root downloaded completed job120666020515 logs and checked the individual package totals:session32,profile17,screen28,controls18,composition17,panel/app64, totaling176 native tests with zero failures. All seven actual app/owned-child/accepted-backend visual regressions pass. Python ran558 tests with21 optional skips, zero failures; final app compilation passed. Hosted compiler is Swift6.2.3. These hosted checks supersede the earlier unchanged-package proof for this exact assembled runtime. The documentation mirror6b77ce5 also passed contract/docs40027270800.

Separate feature-branch CI on nativec707 used an older setup without the mocked helper's HTTPX dependency. Its seven visual cases failed before verification/capture; the configured integration above already installs pinnedHTTPX0.28.1 and passes them. The original owner reproduced missing-dependency startup failure versus successful synthetic verification with the established interpreter. The narrow environment/interpreter portability correction babb979 was subsequently accepted and assembled as951b062. The product runtime and accepted regression assertions/timeouts are unchanged; later setup-only source and checks are attributed separately.

Root reviewed the complete [setup-only correction](reviews-2026-10-23/review-visual-test-setup-babb979.md), confirmed no product/runtime/fixture or root-workflow changes, and passed all seven affected actual-app tests at951b062 in3.012s. The new feature hosted run40028985057 was still running when recorded. No repeated full runtime suite was needed after the completed exact7685572 hosted proof.
