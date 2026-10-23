# Relay controls

Standalone macOS 15+ library. Swift tools 6.2 or newer.

Run synthetic tests with `swift test --package-path spikes/macos-controls`. The default tests use an injected registrar and session port; they never register global shortcuts or prompt/read Accessibility.

The app retains a `ControlsController`, configures shortcuts, then explicitly enables them. Pass the real session/presentation controller as `ControlActionHandling`. Call `shutdown()` before releasing the controls owner. Ordinary panel hiding is not screen-sharing exclusion.

Integration contract and upstream review: [App controls](../../docs/APP_CONTROLS.md). Checkpoint state: [Controls lane](../../docs/lanes/CONTROLS.md).
