# Synthetic local History exports

These two PNGs are local offscreen exports of Relay's actual History workspace. They are not desktop screenshots or a visible-window/hardware acceptance result. No competitor assets are used.

Source: `spikes/macos-panel/Tests/RelaySessionApplicationTests/HistoryApplicationTests.swift`, `testOptInSyntheticHistoryRendersNeverOrderAWindowOnScreen`; actual view `RelayHistoryWorkspace.swift`. `history-locked` uses the unopened/default-off coordinator. `history-saved` uses the real encrypted GRDB ledger with an injected temporary fake key and actual fixture native audio packets → existing validated-final hook → History → actual helper session End; its fictional title/manual note are explicitly saved through the coordinator.

Rendering creates a borderless NSWindow with `isReleasedWhenClosed=false`, installs NSHostingView, lays it out and uses its own `cacheDisplay` bitmap. It never calls `orderFront`, `makeKeyAndOrderFront`, screen capture, system Keychain, a profile/account, OS audio capture or model inference. The window is detached/closed after export. This is an owned synthetic view artifact, not a lock-screen bypass.

Normal tests do not write tracked artifacts. Opt in with `RELAY_HISTORY_RENDER_DIRECTORY` pointing at an owned temporary directory, and `RELAY_TEST_PYTHON` at the selected test interpreter. The author inspected the outputs and copied these two exports into this evidence folder. Local source build is Swift6.4/arm64/macOS27; older supported runtime, Intel and actual visible app interactions are separate checks. Logs: `/private/tmp/relay-history-render-green.log` and `/private/tmp/relay-history-app-affected.log`.

The visible sources are labelled Selected app audio/Microphone without assigning a person's identity. User notes are not approved personal facts. Saving is optional; Lock/Stop saving/Delete/export have distinct behavior. Generated notes, cloud/calendar/share and replay of a saved session are not implemented in this slice.
