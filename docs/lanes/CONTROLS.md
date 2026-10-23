# Controls lane handoff

Issue #65. Branch `feature/app-controls-2026-10-23`, frozen foundation `a8f8359354f44e11be39e22a55422b2cef9f6c91`.

## Verified checkpoint 1

The new macOS 15+ `RelayControls` library implements `ControlsController`, `ControlActionHandling`, a pinned production `KeyboardShortcutsRegistrar`, shortcut validation, per-action callback leases, registration rollback and explicit shutdown. No default shortcuts are assigned. Constructing a registrar does not register keys or ask for Accessibility permission.

`swift test --package-path spikes/macos-controls` passed 5 synthetic tests on 2026-10-23. The initial test-first run failed for absent production types. Tests do not register real global shortcuts. A baseline panel test attempt was blocked by the default sandbox's Swift module-cache write; the controls tests ran with the approved Swift test escalation.

Public integration API: `ControlsController(registrar:actionPort:)`; `configure(_:for:) throws`; `setEnabled(_:) throws`; `dispatch(_:)`; `shutdown()`. `ControlActionHandling.perform(_:) throws` runs synchronously on MainActor. The host owns real capture/ASR/model admission and display retirement on pause/end. A synthetic host demonstrates this seam; actual integrated session stop remains assembly acceptance.

Next: settings/own-panel adapter, explicit selected-text service, production AX adapter, synthetic stale/focus/trust/size/timeout tests, final draft PR and controller report.
