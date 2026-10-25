# Cluely parity implementation contract

2026-10-23. The owner explicitly requested Cluely-style desktop functionality/UI, automatic speech setup, résumé ingestion and personal memory, and directed implementation. This contract makes that authorized direction concrete. Frozen runtime foundation: `build/cluely-parity-foundation-2026-10-23`,1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7. Preserve [accepted engine boundaries](BUILD_CONTRACT.md); this phase replaces developer-facing setup, not request authority.

## First joined deliverable

A clean Home and guided initial preparation, a compact live control/answer surface, a separate My Context workspace and Settings. One normal Start automatically provisions the reviewed pinned speech set (225,301,695bytes/21files) if missing and uses its verified cache thereafter. No ASR/VAD folder picker or model-license checkbox in normal Home/session UI. User audio-source/recording permission remains explicit. Existing automatic answers, Help, copy/detail and real Pause/End work. A first interface-only branch must declare automatic-setup dependency rather than claim downloads already work.

Measured Cluely2.1.24 proportions inform the visual target: a separate small control surface,690-wide chat/answer panel and920×670 Settings. Root prefers these familiar proportions over an unrelated dashboard design. Adapt control sizing for accessible current actions; use Relay branding/SF symbols and original assets. Deep REA renderer/theme findings can refine spacing/colors without changing authority. Ordinary own-window behavior stays intact. No stub chat box, fake transcript/history/mode state or fake progress.

## Fixed automatic-setup seam

In `RelaySessionCapture`, public Sendable/Equatable `SpeechSetupSnapshot` exposes `stage`, optional UInt64 `completedBytes`/`totalBytes`, optional Double `progressFraction`, `userMessage`, `recovery` and `isBusy`. Stages are notPrepared/checking/downloading/validating/ready/unavailable/cancelled. Recovery is none/retry/openSettings.

```swift
@MainActor public final class SpeechSetupCoordinator: ObservableObject {
    @Published public private(set) var snapshot: SpeechSetupSnapshot
    public func prepare() async throws -> PreparedSpeechAssets
    public func cancel()
    public func waitForQuiescence() async
}
```

`PreparedSpeechAssets` is an immutable owned result with readable manifestID/asrModelRoot/vadCompiledModel and internal construction. It establishes asset integrity and reviewed dependency policy only. It cannot grant audio/screen/account permission. The managed capture initializer consumes this result; arbitrary advanced roots retain their separate explicit policy. No file-existence-to-license-approval shortcut.

The app model owns `let speechSetup` with inert injectable construction. Existing `start() async` prepares then starts only for the same current uncancelled intent. It adds `cancelPreparation()` and `retryPreparation() async`; Retry cannot revive an old cancelled Start. `canStartSession`/Resume remain blocked through actual preparation/capture/helper joins. Init/fixture performs no downloads/model loads/OS requests. UI observes coordinator state and calls real model actions. Readiness never impersonates microphone/process-tap permission or actual recognizer startup.

## Disjoint ownership

- Native UI owner: new isolated work/relay-cluely-ui, branch feature/cluely-ui-2026-10-23. Own `RelayPanelSessionApp.swift`, `SessionSettingsView.swift`, `SessionWindowControls.swift`, new Home/live/toolbar/card/context/theme/settings/window-shell/presentation SwiftUI files under the same target, presentation/command-routing tests and lane handoff. Do not edit SessionApplicationModel, capture/transport/profile cores or shared package/dependency manifests. Only the live surface binds existing window actions.
- Automatic speech owner: new isolated work/relay-cluely-automatic-speech, branch feature/automatic-speech-setup-2026-10-23. Own new SpeechAssetManifest/Store/Downloader/SpeechSetupCoordinator files and focused tests in macos-session, narrow managed initializer in NativeCaptureConfiguration, and SessionApplicationModel init/start/cancel/retirement/canStart integration. Own new model notices and its lane handoff. No view/Settings, Python, event/lease/controller, image/profile or accepted capture teardown edits beyond this setup join.
- Controller: current integration/global contracts/docs, root-owned ProfilePreparationView/pure profile presentation, bounded read-only approved-memory bridge/controller/browser for usable My Context review and correction, typed-query/transcript/history/account gap sequencing, independent reviews and assembly. No other owner writes these concurrently.
- REA owner: deepen local package/renderer/behavior coverage and sanitized parity research; no runtime edits until assigned a later feature slice.

The automatic owner sends an immutable API foundation commit to UI early; UI may import it as a declared dependency. Root reviews each own delta separately and joins only accepted final source. Old PR79 and previous review branches remain frozen. All workers remain GPT-6.1 Sol extra-high; four active slots include controller.

## Remaining parity sequence

After the first joined UI/setup deliverable, implement real typed chat/quick actions, bounded transcript/current activity and modes, then persistent session/history and account onboarding using explicit contracts. Keep the full REA parity inventory current and do not treat first-slice UI polish as complete Cluely parity. Root's My Context improvement removes fingerprint/span/key complexity from the default view while preserving explicit source/ownership approval and revoke/correction behavior. No transcript or model answer becomes a verified personal fact automatically.

## Acceptance

Automatic setup must pass empty/warm/offline/corrupt cache, strict manifest/path/hash/byte bounds, bounded downloads/retries, pre-cancel and cancellation-during-validation, single-flight and actual cleanup-before-restart tests. Exact ASR/VAD pin/license/notice identity remains in the design and manifest. No default CI weight fetch or model load.

Native UI must pass actual command routing/state eligibility, no normal model/detector controls, honest progress/error/ready presentation, readable current question/lead/two points/code, preserved copy/detail behavior, and correct own-window targeting. Use inert synthetic render fixtures for visual review where possible. Mac lock is not permission to bypass OS access; final visible/real account/capture/quality/resource acceptance waits for appropriate access.

## My Context browser refinement

Source inspection found that hiding the old manually typed claim key without a saved-memory browser would make later correction difficult. Controller therefore owns a bounded read-only `memories` command in ProfileBridge plus native DTO/paging/controller state and My Context browser. The command reads only existing active user-confirmed fully consented claims, does not approve/promote/change provider authority, and is available only after protected profile open. Return at most8 facts and14KiB encoded response per page, with exact source/fact identity, source label, claim key/text, ownership, total count and opaque last-fact cursor. No truncation of claims. Reject malformed paging inputs, including boolean limits. Lock/revoke/correction and lifecycle changes invalidate visible/paged state; loaded data cannot reopen a closed profile.

The user selects a remembered fact for correction through the UI; internal claim keys remain in the controller. Actual existing-fact lookup and explicit replacement confirmation still gate review. Root owns ProfileController, ProfilePreparationView, new presentation/DTO files, profile_bridge.py and associated tests for this addition. No other lane edits these. Native vault, review authority, fingerprint/source validation and helper close/reaping semantics remain unchanged.
