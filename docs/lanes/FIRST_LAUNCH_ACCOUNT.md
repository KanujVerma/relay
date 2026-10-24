# First-launch ChatGPT entry

Owner `/root/research_visual_inputs`, GPT-6.1 Sol xhigh. Isolated branch `feature/firstlaunch-account-2026-10-23`; immutable foundation `build/firstlaunch-account-foundation-2026-10-23` at `15d6f6df50c8906faba3363807f8b04fdc1cb0b1`. Root explicitly approved this bounded implementation after the account/idle300c source join. The previous account and account/idle candidates/artifacts remain frozen.

When plan use is off, normal Home presents a prominent Connect ChatGPT entry above Ask Relay and explains the limited local-reference alternative. It keeps the existing Home dimensions and preserves Start/audio/reference actions. Synthetic fixture mode does not display the setup entry. Actual lifecycle headings retain priority. The actual AI-off terminal also offers the same recovery route; missing personal context, unavailable answers, Pause and closing do not acquire that action.

`.connectChatGPT` is navigation only. Both actual Home/live adapters call `SessionApplicationModel.showAISettings(openWindow:)`, which sets the shared `settingsSection` to `.ai` synchronously before raising `relay-settings`. The same already-open Settings view reads that shared state, so a previous General or Screen tab cannot hide the destination. Generic Settings navigation retains the selected tab. The existing AI settings Continue with ChatGPT remains the only login action; no readiness, key, account request, browser, helper or model work is added to navigation. AI-off is not treated as evidence that no account is saved. This route neither enables plan use nor resends a question.

The Model delta consists only of the published settings selection and its synchronous navigation method. Account mutation guards, original request/owner/currentness, encrypted credentials, saved-context choice, draft/basis, capture, helper and provider behavior are unchanged. The actual Settings view may be opened during a session while its existing account mutation guard still rejects Connect.

## Evidence

The first test run failed compilation on the missing route, shared selection and recovery APIs. After implementation, the final focused run collected20 cases, all passed in2.839s: four new actual Model/router cases, eleven existing presentation cases, four existing real terminal cases and one optional offscreen-render case. The new tests cover selection in the same existing view BEFORE the window-open callback, zero key/account/browser/helper effects on pure navigation, real idle reviewed-card/draft/original-basis/session preservation, actual synthetic audio guard rejection, and actual no-inference idle helper terminal recovery with no extra helper or account work. Wrong terminal reasons and paused state have no recovery action. Logs are `/private/tmp/relay-firstlaunch-route-red.log` and `/private/tmp/relay-firstlaunch-route-render-final2.log`.

```sh
RELAY_TEST_PYTHON=/private/tmp/relay-product-runtime-build/venv/bin/python \
RELAY_RENDER_DIRECTORY=/private/tmp/relay-firstlaunch-account-renders \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-firstlaunch-module-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-firstlaunch-clang-cache \
swift test --disable-sandbox --disable-automatic-resolution --skip-update --jobs 4 \
  --package-path spikes/macos-panel \
  --scratch-path /private/tmp/relay-firstlaunch-panel-build-20261023 \
  --filter 'FirstLaunchAccountTests|RelayPresentationTests|LiveEmptyAnswerPresentationTests|RelayRenderFixtureTests'
```

Existing local NSWorkspace notification diagnostics appear without XCTest failures. No assertion, timeout or optional-skip rule changed. The final source compiles through the actual app test target. [Synthetic renders and hashes](../evidence/2026-10-24-first-launch-account/README.md) confirm the existing dimensions and visible controls. They are offscreen view evidence, not actual-window/account/device acceptance. Root owns independent review and actual GUI verification; fresh bundle and exact-head hosted checks remain separate gates.

## Reuse and integration

No new upstream source, dependency, asset or parser is adopted. This reuses the accepted Relay command router, Home/live views, primary button, account settings and actual no-inference/fixture helper paths from the exact foundation. Existing [Cluely research](../research/CLUELY_DEEP_DIVE.md) informed the already-approved simple setup direction; no proprietary source/assets are included. The patch changes only presentation/navigation and its tests/docs, with no auth/transport/profile/capture edits.

History and Responses workers remain isolated. Their future settings cases must be reconciled into `RelaySettingsSection` and retain the single Model selection; they must not restore per-view local selection or replace the navigation route with an account operation. Next action: independently review this exact patch and exercise Home → AI Settings and already-open General → AI in the actual joined app.
