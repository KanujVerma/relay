# Idle terminal answer presentation

Owner `/root/review_composition`, GPT-6.1 Sol xhigh. Isolated branch `fix/idle-terminal-presentation-2026-10-23`, base `cd77aa930d97771607f090602000b33d9c76cfaa`.

Root's actual idle no-inference window retained its question and displayed Thinking after the request had finished. `SessionPanelController` already records the correct terminal status. The view previously chose its large message from question presence. `RelayEmptyAnswerPresentation`, consumed directly by `LiveSessionView`, now shows Thinking only for the reducer's Thinking status and otherwise preserves the actual nonempty terminal message. Paused/closing messages take priority; ordinary Ready/Listening still use the existing idle or listening text. Detail text, actions, authorities, Model, transport and helper behavior are unchanged.

Regression evidence uses the real panel reducer and original lease: pending to error/AI-off/abstention/clarification, rejected late pending, real deadline expiry, and clear with cancellation/withheld text. Both audio-running and assistant-only presentation are covered. A separate actual normal no-inference Model/child test issues an idle typed question, reaches AI requests are off, and checks the same large-message projection without audio, recording consent, private context or model calls.

The message extraction initially retained the original ternary unchanged. The final four-test red run then failed29assertions in1.259s, including the actual child test's Thinking-versus-AI-off assertion. The narrow status change passes those same four cases. Combined affected verification collected97cases:81panel collected/80pass/one explicit actual-bundle gate skip in8.122s, plus16app/presentation cases pass in1.412s. Existing local NSWorkspace notification diagnostics appear without XCTest failures. No assertion or skip was weakened. The filter also matched the panel test module, so all81panel cases ran once; no further full suite was requested.

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-idle-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-idle-module-cache RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python swift test --disable-sandbox --skip-update --scratch-path /private/tmp/relay-idle-terminal-panel-build --cache-path /private/tmp/relay-idle-spm-cache --filter 'LiveEmptyAnswerPresentationTests|RelayPresentationTests|SessionPanelTests|TypedApplicationTests'
```

Run from `spikes/macos-panel`. Logs `/private/tmp/relay-idle-terminal-presentation-final-red.log` and `/private/tmp/relay-idle-terminal-presentation-green.log`. Tests and dependency/build caches are isolated from root/peer builds. `git diff --check` passes. No new upstream dependency, framework, assets or source reuse is introduced by this presentation-only correction.

The separate startup investigation remains unconfirmed: ten actual no-inference child open/close schedules using the production3.14.9 interpreter completed ready/closed/exit0 in132–219ms, with no stderr. These repeat launches do not prove an uncached cold-start bound. No freshness widening or startup behavior change is included. An initial diagnostic with macOS system Python's process-relative clock was discarded and rerun using the shared monotonic clock; it was not product failure evidence.

No actual window inspection, capture/permissions, audio/ASR/model load, private files, Keychain/account, network inference, packaged-app rebuild/signature/relocation or hosted CI was performed for this correction. Root owns actual window and joined artifact acceptance. Next action: independently review this narrow source delta, then join and repeat the terminal idle window observation.
