# App controls

Issue #65 adds a separate native `RelayControls` library for integration by the app controller. It does not change the main panel or session files in another lane.

Ordinary global shortcuts use [KeyboardShortcuts 3.1.0](https://github.com/sindresorhus/KeyboardShortcuts/tree/772133d9dbe800fdac0473226822994c5c162c58), MIT, exact revision `772133d9dbe800fdac0473226822994c5c162c58`. Source review covered `Package.swift`, `license`, `HotKey.swift`, registration/enable/handler cleanup in `KeyboardShortcuts.swift`, `Shortcut.swift`, recorder binding/validation and upstream lifecycle/conflict tests. Upstream requires Swift tools 6.2 and macOS 10.15; Relay's controls package uses macOS 15. No fork or copied registrar is introduced.

The upstream README [states that it causes no permission dialogs](https://github.com/sindresorhus/KeyboardShortcuts/blob/772133d9dbe800fdac0473226822994c5c162c58/readme.md). Source uses Carbon `RegisterEventHotKey`. Relay requests no Accessibility permission for ordinary shortcuts. A broad keyboard monitor and a fresh Carbon implementation were rejected because the pinned package already implements registration, menu handling, cleanup and a configurable recorder.

All shortcuts start unbound and disabled. A binding must include Command or Control. Duplicate Relay bindings fail before registration; macOS conflicts and unavailable registration report errors. The settings recorder checks this app's main-menu conflicts. Other applications' menu shortcuts cannot be exhaustively discovered and may still conflict, so users can rebind or clear every action. Registration success is checked through upstream `isEnabled(for:)`; enabling is atomic, and failed rebind attempts restore the original binding or disable the controller if restoration fails.

The host implements `@MainActor ControlActionHandling.perform(_:) throws`. Pause/end must synchronously retire capture/model admission and current presentation authority, clear the answer and then finish asynchronous teardown. The library cannot prove those host effects by changing a UI flag. Its callback leases prevent already queued callbacks after rebind, disable and shutdown from reaching the host.

Show/focus/hide controls affect only Relay's ordinary window. Hiding a window does not promise screen-sharing exclusion. No external app click/typing/actuation, stealth behavior or proprietary competitor source is used.

## Native integration

Add a local Swift package dependency on `spikes/macos-controls` and the `RelayControls` product to the composed app. Retain one controls owner and one `KeyboardShortcutsRegistrar` per namespace. `ControlsSettingsView(controller:)` provides the enable toggle, upstream binding-based recorder, duplicate/unsafe-key validation, clear buttons and visible registration failures. Recording alone does not register anything. The host owns persistence of chosen bindings; the default initializer starts unbound and disabled each launch.

`OwnPanelControls(window:sessionActions:answerText:expandAnswer:scrollAnswer:)` composes ordinary own-window controls with the real session port. `answerText` must return only the currently leased answer, or nil after retirement. Copy explicitly writes that current answer to the pasteboard; it never reads clipboard context. Expand/scroll are invoked only when a current answer exists. Window movement stays in that window's current display visible frame.

`WorkspaceFrontmostApplication.current()` returns public NSWorkspace bundle ID, process ID and launch date without AX. It can label the chosen context app. No app content is read by this metadata query.

## Optional selected-text context

`SelectedTextService(currentRequest:)` is the live adapter. The supplied MainActor closure returns the current native `SelectionRequestIdentity(sessionID:sessionEpoch:presentationGeneration:requestID:)`, or nil when no request has authority. Neither construction nor a normal hotkey requests AX trust. `SelectedTextSettingsView(service:allowedBundleIDs:)` calls `enable(allowedBundleIDs:requestPermission:)` only after the user enables the option or presses the permission button. Changing the displayed allowlist revokes the old capability. An untrusted enable remains pending; read checks actual OS trust every time.

For an explicit Help action, the host first issues the native request identity, then calls `read(request:)`. A successful `SelectedTextSnapshot` contains the original identity, allowlisted application identity, text, monotonic capture time, consent generation and `selected_accessibility_text` provenance. It has no public constructor. The host checks `validateCurrent(snapshot)` immediately before attaching context, and preserves the same original request fences in its `ContextSnippet`. Map the text to problem/screen context, never to verified personal history. Source metadata should identify the selected bundle/PID; do not silently relabel the text as OCR or verified résumé evidence.

Call `invalidate()` synchronously on pause/end, request supersession or context-source change; call `revoke()` when consent is withdrawn. Invalidation cancels pending work and retires issued snapshots. Late results cannot acquire a new session/request identity. The live service observes every NSWorkspace activation, including an away-and-back switch. A failed validation permanently retires the matching snapshot; restoring trust cannot revive it. An older snapshot cannot invalidate a newer read.

The production AX adapter reads only the focused element of the original PID, rejects secure/password role identifiers, permits only text area/text field/static text roles, and requests the bounded selected range through [AXStringForRange](https://developer.apple.com/documentation/applicationservices/kaxstringforrangeparameterizedattribute). [AXSelectedTextRange](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute) is checked again after reading; focus-object and trust changes reject the observation. Unsupported apps receive no full-value, whole-app or clipboard fallback. Each public AX message uses a [50 ms messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout), work runs off MainActor, cancellation is checked between calls, and results taking over 750 ms are rejected. A message already executing cannot be forcibly canceled.

Selection is at most 8,192 UTF-8 bytes with code LF/tab preserved, one in-flight read per service, and a maximum five-second observation age when attaching. Validation establishes current permission/request/focus authority; it does not prove the source content stayed unchanged after observation. Application AX implementations can omit or misreport semantics; unsupported content is unavailable. No actual user's selected text is read by development tests.

## Verification and remaining acceptance

Synthetic package tests exercise the controller/host seam, stale callback leases, atomic registration failure, rebind restoration, teardown, current-answer-only actions, display-bound movement, explicit permission boundaries, secure/unsupported/size selection rejection, native identity preservation, concurrent reads, timeout, trust/focus/request/consent changes and cancellation. The production AX, NSWorkspace, AppKit and SwiftUI adapters compile in the same package.

Real keyboard delivery across macOS/app menus, interactive recorder layout, AX grant/denial/revocation, supported editor selection behavior, multi-display window movement and the assembled app's actual capture/ASR/model pause/resume/end remain manual acceptance. No private selection, permission prompt, real global binding, capture, Keychain or inference ran in the default tests. Passing an injected host test proves the port contract; it does not prove the assembled app has connected every session effect.

## Research boundary

Static Cluely 2.1.24 research established AX trust requests, Electron global shortcuts and own-window controls in selected modules. It did not establish an external-app AX reader/actuator, backend behavior or runtime pause bug. See the controller's canonical research note for evidence limits. Relay's controls are independently implemented from public APIs and licensed upstream source.
