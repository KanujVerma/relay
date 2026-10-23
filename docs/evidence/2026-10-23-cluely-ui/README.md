# Synthetic native UI exports

The first six Relay view renders use the Swift sources and pure fixture inputs frozen at15e017825dc547b4e2011174ecb6603a71266744. The seventh microphone-only export accompanies the later source-display correction below. They are not desktop screenshots or evidence of a live interview, permission, sign-in, model download, capture or inference. No competitor assets/code are included. The UI lane uses measured Cluely2.1.24 proportions with Relay branding and native SF symbols/type.

| Export | Pure input |
| --- | --- |
| [Home](home.png) | Selected synthetic app, microphone enabled, assistance permitted, AI label enabled; no model object |
| [Live](live.png) | Synthetic Python question, fixed lead/two points/code, `02:41`, fixed local-OCR label |
| [Paused](paused.png) | Paused state, no old question/answer, fresh-conversation resume message |
| [Preparing](preparing.png) | Explicit synthetic45% preparation input,225 MB label; not observed download progress |
| [Error](error.png) | Fixed unavailable/retry preparation input |
| [Pill](pill.png) | Collapsed live surface using the same fixed synthetic state |
| [Microphone only](microphone-only.png) | Explicit microphone-only source; copy explains that automatic question help requires a conversation app |
| [Context locked](context-locked.png) | Locked My Context, before any fictional open command |
| [Context memory](context-memory.png) | Two fictional saved facts with separate self/team ownership and one fictional source |
| [Context review](context-review.png) | One pending fictional claim, ownership unknown, plus the same two fictional saved facts |

Home/preparing/error are920×670. Live/paused are706×576 including the690-wide answer and outer padding. The pill's control region is350×50 within a706×66 transparent view surface; the extra width preserves the answer window's anchor. Synthetic labels are visible on the expanded surfaces. The collapsed pill is still synthetic and its elapsed time is fixed input.

## Source and method

`spikes/macos-panel/Tests/RelaySessionApplicationTests/RelayRenderFixtureTests.swift` supplies all fixed inputs. It constructs the real pure `RelayHomeView` and `LiveSessionView` components without `SessionApplicationModel`, helper, coordinator, profile store, clipboard or OS source provider. Callbacks do nothing; no live window attachment is supplied.

SwiftUI `ImageRenderer` omitted AppKit-backed scroll descendants on this host, so the test uses an `NSHostingView` inside a borderless `NSWindow` that is never ordered onto the display. It lays out the view and caches its display into a bitmap PNG. It does not use OS screen capture, read another app, unlock the Mac or request permissions. Exporting is opt-in and normal tests skip it.

```sh
RELAY_RENDER_DIRECTORY=/private/tmp/relay-cluely-ui-renders \
RELAY_TEST_PYTHON=/path/to/test-python-with-httpx \
swift test --disable-sandbox --package-path spikes/macos-panel \
  --filter 'RelayPresentationTests|RelayRenderFixtureTests|RelayContextRenderFixtureTests'
```

The test writes only to the explicitly supplied export directory. These six files were copied into this evidence directory after visual inspection; normal tests do not modify tracked evidence. Re-rendering can vary with macOS font/layout versions. Local host: macOS27/Xcode27/Swift6.4; no visible-window or hosted rendering acceptance is implied. Actual settings interactions, source ownership, account capability and capture teardown are covered by separate synthetic behavior tests or remain real-device acceptance work.

The microphone-only export uses the same never-ordered method and inert callbacks. Exact Git source blobs at export: `RelayHomeView.swift`7350d0266ef752a81afee281908f6773f329dcec and `RelayRenderFixtureTests.swift`a036afe695a0bb49d0e29cec23bff18afbf9b219. The fixed input has source admission/consent true and remote-source false; no actual audio is started.

## My Context visual fixtures

The three920×720 My Context exports use the independently accepted profile source atfe6aad710b0109a964f823af42e8f89d440be90a (complete62a1f854 +fe6aad7). `RelayContextRenderFixtureTests.swift` source blob3ca1794c96becdec409260725952c0a2b82c5fef supplies all fictional data. A fake32-byte key provider replaces Keychain. A fake command port returns the fixed Northstar source/two memory records and optional pending review card. A fictional encrypted payload is created only under a unique test temporary directory, then removed; the production profile path is never used.

The real public controller consumes these fake responses to populate view state. This is visual state setup, not actual helper/import/approval/backend acceptance. No fact is approved by the test. The controls draw their real eligibility, including disabled Save until ownership is chosen, but the never-ordered window receives no input and no button is invoked. View construction/appearance performs no IO. The pending-review view scrolls in the real UI; its export shows the top viewport rather than claiming every lower source row fits at once.

These use the same `NSHostingView`/bitmap method above. They are synthetic render evidence on a locked Mac, not an unlock bypass, desktop capture or inspection of private context.

## PNG SHA-256

```text
05fd2af2def3b5146457028e3a6cb8d075a30d9ec7f78f8c899e6036ff4c5c61  error.png
b22d5b1e139529a638a376d1939db607aa09cd4a79292a03647db703f2a172ba  home.png
6891e0c863380d5c1dbfa511b8a16a02ef38e1c5d614fb8508e4dc6caf83b0fc  live.png
f6888fa2036dee773e8a02cbde01dd3c829163d88212514327f64d53dc706061  paused.png
9255c9c1d86bd055eb5b60fd68c927bb206eb12b40ed1bb3cfc2384d9f1935c1  pill.png
f0edf3da9bc11543ef00254e8dd7001606f896ec813c2daff9b1c5f998009666  preparing.png
cb1f5a0d0a42a3ef0442b2ca9b03302a3f884dc294e54858b3d55aa98ef4dc92  microphone-only.png
0dc4541ec87a68b82334fa35ef5a2b2dda023a7c342312c2cd8741fb4dd7bd0c  context-locked.png
c2058297fe2d3f6406102e7ada65f614952fa8c066b380570157863ebc255ada  context-memory.png
cd31a32dbec09b9485ba747d930393e52ff42d3936dee125a6f7c3e09d557348  context-review.png
```
