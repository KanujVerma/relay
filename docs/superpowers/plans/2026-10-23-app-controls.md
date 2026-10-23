# App controls implementation plan

> For agentic workers: execute inline with superpowers:executing-plans. The controller assigned this isolated lane and approved implementation; no further delegation.

**Goal:** User-configurable ordinary global shortcuts, own-panel actions, and explicit read-only selected-text context.

**Architecture:** A MainActor controller owns registration, validation, callback leases and teardown. Session and answer operations go through a synchronous host action port so the assembled app keeps real capture/model/display authority. A separate selected-text service binds one explicit read to a session/request and allowed frontmost application, and rejects stale results.

**Tech stack:** Swift 6.2, macOS 15+, SwiftUI/AppKit/ApplicationServices, MIT KeyboardShortcuts 3.1.0 pinned to 772133d9dbe800fdac0473226822994c5c162c58.

**Spec:** `docs/BUILD_CONTRACT.md`, issue #65, controller assignment, and `docs/APP_CONTROLS.md` describe the approved lane and integration boundary.

## Constraints

- Only `spikes/macos-controls`, this plan, `docs/APP_CONTROLS.md` and `docs/lanes/CONTROLS.md` belong to this lane.
- No real hotkey registration, AX prompts/reads, capture or account use in default tests.
- No AX solely for hotkeys, global text logging, external app control, stealth or proprietary copying.
- Preserve native request/session/epoch/presentation identity and `selected_accessibility_text` provenance. Selection does not become verified personal evidence.

## Task 1: Hotkey lifecycle and host actions

Files: package manifest, `Sources/RelayControls/ControlsController.swift`, `ControlAction.swift`, `KeyboardShortcutsRegistrar.swift`, `Tests/RelayControlsTests/ControlsControllerTests.swift`.

Interface: `ControlsController(registrar: HotkeyRegistering, actionPort: ControlActionHandling)`; `configure(_:for:)`, `setEnabled(_:)`, `dispatch(_:)`, `shutdown()`. `ControlActionHandling.perform(_:) throws` is synchronous and MainActor. The host must synchronously retire display/model admission on pause/end before starting asynchronous teardown.

- [x] Write tests for duplicate/unsafe bindings, registration failure, successful rebind, old callback after rebind/disable/shutdown and action-port failure.
- [x] Run `swift test --package-path spikes/macos-controls` and observe missing implementation failures.
- [x] Implement validation, registration leases, rollback and cleanup. Adopt the pinned upstream registrar, using its registration status rather than claiming success unconditionally.
- [x] Run package tests; commit and push the passing scope (13b68db).

## Task 2: Settings and own-panel adapter

Files: `ControlsSettingsView.swift`, `OwnPanelControls.swift`, tests and README/notices.

Interface: SwiftUI settings consumes `ControlsController`; upstream recorder uses a binding so recording alone never registers. `OwnPanelControls` receives the application's NSWindow and answer scroll/copy/expand closures; it operates only that window.

- [x] Add failing tests for host session action ordering and actual panel geometry boundaries using synthetic geometry.
- [x] Implement settings enable/disable, recorder/clear rows and visible conflicts/errors; implement ordinary show/focus/hide, bounded move and answer callbacks.
- [x] Compile public production adapters and run tests without real registration.

## Task 3: Explicit selected text

Files: `SelectedTextService.swift`, `AccessibilitySelectedTextProvider.swift`, `FrontmostApplication.swift`, synthetic tests.

Interface: `SelectedTextService.enable(allowedBundleIDs:requestPermission:)`, `read(request:) async throws -> SelectedTextSnapshot`, `revoke()`, `invalidate()`. Snapshot retains the native request identity, app identity, uptime and consent generation. The host revalidates via `validateCurrent(_:)` immediately before attaching context and invalidates when request/session authority changes.

- [x] Write failing tests for no trust/allowlist, secure/unsupported/empty/oversized selection, focus changes, trust revocation, request supersession, concurrent reads and timeout.
- [x] Implement real public AX focused-element read on a bounded worker, explicit prompt only, no clipboard/full-text fallback, per-call messaging timeout, original PID checks and post-read freshness checks.
- [x] Compile and run the synthetic suite; record untested permission and hardware acceptance honestly.
- [ ] Update lane handoff and integration guide with exact API, evidence and next assembly action. Commit/push; create and attach draft PR against the frozen foundation.
