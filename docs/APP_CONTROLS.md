# App controls

Issue #65 adds a separate native `RelayControls` library for integration by the app controller. It does not change the main panel or session files in another lane.

Ordinary global shortcuts use [KeyboardShortcuts 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/tree/772133d9dbe800fdac0473226822994c5c162c58), MIT, exact revision `772133d9dbe800fdac0473226822994c5c162c58`. Source review covered `Package.swift`, `license`, `HotKey.swift`, registration/enable/handler cleanup in `KeyboardShortcuts.swift`, `Shortcut.swift`, recorder binding/validation and upstream lifecycle/conflict tests. Upstream requires Swift tools 6.2 and macOS 10.15; Relay's controls package uses macOS 15. No fork or copied registrar is introduced.

The upstream README [states that it causes no permission dialogs](https://github.com/sindresorhus/KeyboardShortcuts/blob/772133d9dbe800fdac0473226822994c5c162c58/readme.md). Source uses Carbon `RegisterEventHotKey`. Relay requests no Accessibility permission for ordinary shortcuts. A broad keyboard monitor and a fresh Carbon implementation were rejected because the pinned package already implements registration, menu handling, cleanup and a configurable recorder.

All shortcuts start unbound and disabled. A binding must include Command or Control. Duplicate Relay bindings fail before registration; macOS conflicts and unavailable registration report errors. The settings recorder checks this app's main-menu conflicts. Other applications' menu shortcuts cannot be exhaustively discovered and may still conflict, so users can rebind or clear every action. Registration success is checked through upstream `isEnabled(for:)`; enabling is atomic, and failed rebind attempts restore the original binding or disable the controller if restoration fails.

The host implements `@MainActor ControlActionHandling.perform(_:) throws`. Pause/end must synchronously retire capture/model admission and current presentation authority, clear the answer and then finish asynchronous teardown. The library cannot prove those host effects by changing a UI flag. Its callback leases prevent already queued callbacks after rebind, disable and shutdown from reaching the host.

Show/focus/hide controls affect only Relay's ordinary window. Hiding a window does not promise screen-sharing exclusion. No external app click/typing/actuation, stealth behavior or proprietary competitor source is used.

## Research boundary

Static Cluely 2.1.24 research established AX trust requests, Electron global shortcuts and own-window controls in selected modules. It did not establish an external-app AX reader/actuator, backend behavior or runtime pause bug. See the controller's canonical research note for evidence limits. Relay's controls are independently implemented from public APIs and licensed upstream source.
