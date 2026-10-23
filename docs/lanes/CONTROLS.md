# Controls lane handoff

Issue #65. Branch `feature/app-controls-2026-10-23`, frozen foundation `a8f8359354f44e11be39e22a55422b2cef9f6c91`.

Date: 2026-10-23. Verified code head: `14660e7a2a086058466bd073d24c282ad14d93c8`. [Draft PR #70](https://github.com/KanujVerma/relay/pull/70) targets the frozen foundation. This lane is ready for independent controller review and assembly.

Toolchain minimum: the actual pinned upstream KeyboardShortcuts 3.1.0 `Package.swift` declares **Swift tools 6.2**, macOS 10.15 and no external dependencies. RelayControls requires tools 6.2/macOS 15. Swift 6.1 cannot resolve this manifest; hosted native checks must select a toolchain providing Swift 6.2 or newer. Local verification used Apple Swift 6.4 with the macOS 27 SDK and a macOS 15 deployment target.

## Goal

Configurable ordinary global controls, useful own-window actions and optional explicit selected-text context, preserving the real host's session and display authority.

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

## In progress and at risk

No uncommitted implementation or unpublished code remains at this handoff. The final documentation/report publication records the PR. Integration and interactive acceptance are pending as described above; this is a library lane, not a claim that the assembled app already runs these controls.

## Decisions and standing instructions

Use the pinned MIT package rather than copying Carbon code. Keep ordinary hotkeys independent of AX. Keep selected-text reads allowlisted, explicit, bounded and read-only; no proprietary source/assets/prompts, broad key logging, full-text/clipboard context fallback or external app actuation. Preserve the native request identity and selected-text provenance. The host owns shortcut persistence, actual session effects and context publication checks. No subagents, force push or main merge are authorized for this lane. Scoped commits/pushes and the draft PR were explicitly authorized by the controller/owner.

## Open questions

No blocking API question. The controller chooses how to persist shortcut choices, which setup-selected apps enter the selection allowlist, and how an explicit Help action issues its native request before attaching selected text. Do not infer these policies from AX trust alone.
