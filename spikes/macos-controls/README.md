# Relay controls

Standalone macOS 15+ library. Swift tools 6.2 or newer.

Run synthetic tests with `swift test --package-path spikes/macos-controls`. The default tests use an injected registrar and session port; they never register global shortcuts or prompt/read Accessibility.

The app retains a `ControlsController`, configures shortcuts, then explicitly enables them. Pass the real session/presentation controller as `ControlActionHandling`. Call `shutdown()` before releasing the controls owner; deallocation also unregisters owned keys. Ordinary panel hiding is not screen-sharing exclusion.

`ControlsSettingsView` records/clears bindings and reports errors. `OwnPanelControls` wraps the application's own window and current-answer callbacks. `SelectedTextService` and `SelectedTextSettingsView` provide optional, explicitly enabled read-only selected-text context. The host supplies allowed apps and real native request authority, and owns persistence of chosen shortcut bindings. All default objects remain unbound/disabled until the host/user configures them.

Integration contract and upstream review: [App controls](../../docs/APP_CONTROLS.md). Checkpoint state: [Controls lane](../../docs/lanes/CONTROLS.md).
