# Independent controls review

Reviewed 2026-10-23. PR #70, immutable head `006b7bdc75ac6376e9711c3733a8094fa25f9b02`, implementation head `14660e7a2a086058466bd073d24c282ad14d93c8`, frozen base `a8f8359354f44e11be39e22a55422b2cef9f6c91`.

Read all 20 changed files, 1,196 added lines, in manageable passes. Read repository AGENTS, HANDOFF, the accepted build contract, parallel plan, product requirements, APP_CONTROLS, controls lane handoff and plan, and the builder report. Inspected the actual pinned KeyboardShortcuts checkout at `772133d9dbe800fdac0473226822994c5c162c58`, including registration/status/handler cleanup, recorder binding/save order, system/menu conflicts and relevant upstream test coverage. Checked the local Apple SDK headers for selected-range representation, string-for-range and per-object messaging timeout semantics.

## Actionable finding

### [P2] Reject canceled callers before issuing a selected-text snapshot

Location: `spikes/macos-controls/Sources/RelayControls/SelectedTextService.swift:158-163`.

Trigger: cancel the Task awaiting `service.read(request:)` while the provider is suspended, or after its last cancellation checkpoint but before the service resumes. Let that provider return a successful observation while request/session/epoch/presentation generation, focus/application identity, trust, consent and time remain current.

The cancellation handler at line 160 cancels only the unstructured provider task. Swift task cancellation does not cause `task.value` to throw if that task returns successfully. The resumed service does not check its own canceled state or retire the matching observation, so it mints a snapshot at lines 168-169, and `validateCurrent` subsequently accepts that snapshot. This is possible with the production provider too: a synchronous AX message already executing cannot be interrupted, and its last attribute call can finish before the MainActor continuation observes caller cancellation. The existing test cancels through `invalidate()`, whose independent `observationID = nil` masks this missing cancellation fence.

Focused synthetic reproduction compiled the three unchanged production selection source files plus an injected provider that deliberately completes after cancellation. It performed no AX calls or prompts. Observed output:

```text
caller_cancelled=true, provider_observed_cancel=true, snapshot_accepted=true, snapshot_still_valid=true
```

Reproduction source: `/private/tmp/relay-controls-cancellation-006b7bd.swift`; executable: `/private/tmp/relay-controls-cancellation-006b7bd`. It used a fixed synthetic request, application identity, monotonic clock and selected text. The initial compile was blocked by the Observation macro server's nested sandbox; the authorized focused compiler retry succeeded with Apple Swift 6.4. No full package suite was run.

Fix: check caller cancellation on entry and immediately after awaiting the provider, before accepting or minting the snapshot. Retire only that read's matching observation when cancellation is observed, and preserve the current behavior that an older canceled read cannot retire a newer observation. Add a regression that calls `Task.cancel()` directly, keeps every other fence unchanged, lets the provider return successfully, and expects stale/cancellation with no valid snapshot.

## Spec verdict

One cancellation requirement remains incomplete. The remaining inspected implementation follows the accepted library-lane boundary: ordinary shortcuts are independent of AX; configuration is explicit and unbound by default; registration failure, rollback, leases and teardown are implemented; own-window and current-answer controls stay within the supplied host; and selected text uses the original request identity, an allowlisted bundle/PID/launch identity, consent and observation generations, actual trust checks, bounded selected ranges, post-read app/focus checks, age/time/byte limits and distinct provenance.

The synchronous MainActor host port correctly states that pause/end must retire capture/model/display admission before asynchronous teardown. Final application composition is a separate accepted task and is not reported as a defect in this library PR.

## Quality verdict and limits

Changes requested for the P2 cancellation finding. No additional actionable findings from the actual diff and focused upstream/API reads. `git diff --check` passed, and the lane checkout remained clean at the exact reviewed head after review. No source, index, HEAD or branch mutation occurred.

The focused reproduction verifies service admission behavior and compiles the production AX/AppKit selection adapters. It does not replace the builder's reported 16 synthetic tests or establish Swift 6.2/Xcode 26.2 CI results. The manifest correctly declares Swift tools 6.2 and macOS 15; the pinned dependency declares tools 6.2/macOS 10.15.

No full suite, actual global hotkey registration, AX permission prompt, real selected text, private content, pasteboard access, capture, Keychain, model or account calls were performed. Interactive shortcut delivery/menu behavior, recorder layout, actual AX grant/denial/revocation/editor behavior, display geometry, and assembled capture/ASR/model/display stop behavior remain separate acceptance gates already disclosed by the lane.
