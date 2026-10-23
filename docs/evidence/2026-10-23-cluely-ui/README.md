# Synthetic native UI exports

These are Relay view renders from the Swift sources and pure fixture inputs in this commit. They are not desktop screenshots or evidence of a live interview, permission, sign-in, model download, capture or inference. No competitor assets/code are included. The UI lane uses measured Cluely2.1.24 proportions with Relay branding and native SF symbols/type.

| Export | Pure input |
| --- | --- |
| [Home](home.png) | Selected synthetic app, microphone enabled, assistance permitted, AI label enabled; no model object |
| [Live](live.png) | Synthetic Python question, fixed lead/two points/code, `02:41`, fixed local-OCR label |
| [Paused](paused.png) | Paused state, no old question/answer, fresh-conversation resume message |
| [Preparing](preparing.png) | Explicit synthetic45% preparation input,225 MB label; not observed download progress |
| [Error](error.png) | Fixed unavailable/retry preparation input |
| [Pill](pill.png) | Collapsed live surface using the same fixed synthetic state |

Home/preparing/error are920×670. Live/paused are706×576 including the690-wide answer and outer padding. The pill's control region is350×50 within a706×66 transparent view surface; the extra width preserves the answer window's anchor. Synthetic labels are visible on the expanded surfaces. The collapsed pill is still synthetic and its elapsed time is fixed input.

## Source and method

`spikes/macos-panel/Tests/RelaySessionApplicationTests/RelayRenderFixtureTests.swift` supplies all fixed inputs. It constructs the real pure `RelayHomeView` and `LiveSessionView` components without `SessionApplicationModel`, helper, coordinator, profile store, clipboard or OS source provider. Callbacks do nothing; no live window attachment is supplied.

SwiftUI `ImageRenderer` omitted AppKit-backed scroll descendants on this host, so the test uses an `NSHostingView` inside a borderless `NSWindow` that is never ordered onto the display. It lays out the view and caches its display into a bitmap PNG. It does not use OS screen capture, read another app, unlock the Mac or request permissions. Exporting is opt-in and normal tests skip it.

```sh
RELAY_RENDER_DIRECTORY=/private/tmp/relay-cluely-ui-renders \
RELAY_TEST_PYTHON=/path/to/test-python-with-httpx \
swift test --disable-sandbox --package-path spikes/macos-panel \
  --filter 'RelayPresentationTests|RelayRenderFixtureTests'
```

The test writes only to the explicitly supplied export directory. These six files were copied into this evidence directory after visual inspection; normal tests do not modify tracked evidence. Re-rendering can vary with macOS font/layout versions. Local host: macOS27/Xcode27/Swift6.4; no visible-window or hosted rendering acceptance is implied. Actual settings interactions, source ownership, account capability and capture teardown are covered by separate synthetic behavior tests or remain real-device acceptance work.

## PNG SHA-256

```text
05fd2af2def3b5146457028e3a6cb8d075a30d9ec7f78f8c899e6036ff4c5c61  error.png
b22d5b1e139529a638a376d1939db607aa09cd4a79292a03647db703f2a172ba  home.png
6891e0c863380d5c1dbfa511b8a16a02ef38e1c5d614fb8508e4dc6caf83b0fc  live.png
f6888fa2036dee773e8a02cbde01dd3c829163d88212514327f64d53dc706061  paused.png
9255c9c1d86bd055eb5b60fd68c927bb206eb12b40ed1bb3cfc2384d9f1935c1  pill.png
f0edf3da9bc11543ef00254e8dd7001606f896ec813c2daff9b1c5f998009666  preparing.png
```
