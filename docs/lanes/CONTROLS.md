# Controls lane handoff

Issue #65. Branch `feature/app-controls-2026-10-23`, frozen foundation `a8f8359354f44e11be39e22a55422b2cef9f6c91`.

## Verified checkpoint 1

The new macOS 15+ `RelayControls` library implements `ControlsController`, `ControlActionHandling`, a pinned production `KeyboardShortcutsRegistrar`, shortcut validation, per-action callback leases, registration rollback and explicit shutdown. No default shortcuts are assigned. Constructing a registrar does not register keys or ask for Accessibility permission.

`swift test --package-path spikes/macos-controls` passed 5 synthetic tests on 2026-10-23. The initial test-first run failed for absent production types. Tests do not register real global shortcuts. A baseline panel test attempt was blocked by the default sandbox's Swift module-cache write; the controls tests ran with the approved Swift test escalation.

Public integration API: `ControlsController(registrar:actionPort:)`; `configure(_:for:) throws`; `setEnabled(_:) throws`; `dispatch(_:)`; `shutdown()`. `ControlActionHandling.perform(_:) throws` runs synchronously on MainActor. The host owns real capture/ASR/model admission and display retirement on pause/end. A synthetic host demonstrates this seam; actual integrated session stop remains assembly acceptance.

## Verified checkpoint 2

The library now includes `ControlsSettingsView`, `OwnPanelControls`, `WorkspaceFrontmostApplication`, `SelectedTextService`, `SelectedTextSettingsView` and the real `AccessibilitySelectedTextProvider`. The complete production library compiled and `swift test --package-path spikes/macos-controls` passed **16 tests in 3 suites** at 2026-10-23 12:36 CDT with no warnings. `git diff --check` passed. No private context, actual AX selection/trust prompt, global binding, capture, pasteboard operation or inference was exercised.

New tests cover automatic hotkey teardown, current-answer-only copy/expand/scroll, bounded multi-display geometry, explicit enable/allowlist/trust boundaries, secure/unsupported/empty/oversized selections, native identity preservation, focus/trust/consent/request/PID changes, timeout/age, concurrent reads and cancellation. A test-first failure found that controller deallocation left registrations behind; isolated teardown now clears them. Another test-first failure showed restored trust could revive a previously invalidated snapshot; failed validation now retires only that observation permanently, leaving newer reads untouched.

Selected-text live API: `SelectedTextService(currentRequest:)`; `enable(allowedBundleIDs:requestPermission:) throws`; `read(request:) async throws -> SelectedTextSnapshot`; `validateCurrent(_:) -> Bool`; `invalidate()`; `revoke()`. `SelectionRequestIdentity` retains native session UUID, session epoch, presentation generation and request UUID. Snapshot adds application bundle/PID/launch identity, exact selected text, uptime, consent UUID and `selected_accessibility_text`. Its constructor is not public.

The host issues the native request before reading, validates immediately before attaching the snapshot to `ContextSnippet`, and invalidates on pause/end/supersession/context-source change. Actual pause/capture/ASR/model stops remain host composition acceptance. See `docs/APP_CONTROLS.md` for exact adapters and limits.

Pending interactive acceptance: real keyboard delivery/menu conflicts and recorder layout, AX grant/denial/revocation/editor support, window behavior across real displays, and the assembled app's actual pause/resume/end effects. Upstream tests were inspected, not run: they deliberately register keys and alter standard UserDefaults. They are not part of Relay's synthetic default suite.

Next action: controller reviews/integrates the draft lane PR and connects these ports to the actual session/presentation lease owner. Do not merge to main without owner approval. The root owns the global HANDOFF and shared contracts; this lane changed neither.
