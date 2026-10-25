# Relay native UX redesign: inventory and implementation proposal

2026-10-23. Read-only design phase by native UI owner, GPT-6.1 Sol xhigh. Baseline: clean controller checkout `work/relay-build-integration`, exact `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`. PR79 remains frozen at `babb9798f50615a0db083006e6b8b92ac51c494a`; no runtime, root checkout, global doc or old branch was modified. The Mac is locked: these are source/research findings and proposed values, not a claim of current visible UI inspection or measured visual parity.

## Decision

Build a familiar meeting-copilot experience with three distinct surfaces: Home/setup and activity, a compact live session bar with expandable answer, and a dedicated Memory workspace. Settings is separate. Keep SwiftUI/AppKit and the existing session/profile/context/control owners. The live surface should say what Relay hears and offer useful talking points, not teach the user how to configure ASR/VAD or expose internal helper authority.

This is a structural UX correction, not a recolor. Automatic suggestions stay automatic. Personal memory and résumé ingestion are Relay's addition to the familiar copilot flow. First implementation must be honest about missing capabilities; no decorative chat box, fake history, nonfunctional mode picker or invented dynamic action.

## Exact current problems

Sources: `spikes/macos-panel/Sources/RelayPanelSession/RelayPanelSessionApp.swift`, `SessionSettingsView.swift`, `SessionApplicationModel.swift`, `SessionWindowControls.swift`; `spikes/macos-profile/Sources/RelayProfile/ProfilePreparationView.swift` and `ProfileController.swift`; `RelaySessionPanel/SessionPanelController.swift`.

1. The only ordinary window defaults to570×620 with minimum480×430. Its idle content includes an AI toggle/account limitation paragraph, interview-app picker, microphone toggle, two model-folder pickers, permitted-conversation checkbox and model-license checkbox before the answer. `setup` starts expanded. The Start action cannot work without manually supplied ASR/VAD paths. Moving two buttons into a disclosure would preserve the underlying setup burden.
2. Status, question, answer, context source, raw error and empty-state instructions share one vertical hierarchy. A long question competes with the lead answer; generic Ready/Thinking/Talking points text is presented alongside large session status. There is no compact livebar versus reading state.
3. Pause/End/Start/Help/Copy/Settings and Prepare background occupy two footer rows. Their hierarchy is nearly equal. The useful current-question Help action is not typed chat. Copy/detail affordances belong to the answer card rather than the global session row.
4. Settings currently has only Screen context, Selected text and Shortcuts tabs. Account, audio, model setup and appearance are scattered or absent. It repeats snapshot/source-age/preview/OCR text that `ScreenContextSettingsView` already renders, and includes multiple paragraphs of helper/receipt/provenance explanation in the normal path.
5. Memory opens as Prepare background in a620-wide sheet, while its embedded `ProfilePreparationView` requires minimum740×620. The form mixes source import, role/purpose/label/project fields, entered notes, review, ownership, topic lookup/replacement, source fingerprints/spans, revocation and lock controls. The underlying approved-fact safeguards are important, but the first task should be Add résumé, then review, not a technical source form.
6. The current app has only the latest `SessionPanelSnapshot`. No public native transcript list, durable session history, modes UI, typed-question submission port or functional dynamic actions exist. `ProfileController` exposes sources/pending cards but not a complete approved-memory browser. Source count is not approved-fact count.
7. Window actions are already real and reusable: show/hide, move, expand, scroll, copy, Pause/Resume/End/Help. Only the live window should bind `attachWindow`; attaching a future Home/Settings window to that same weak window would misroute current controls.

## Research and reuse boundaries

- The REA research owner reports exact shipped Cluely2.1.24 has a separate163×50 control window; chat is690 wide,104 collapsed and500 expanded,760 in dashboard mode; Settings is920×670, min760 wide. Source: `main.js` lines15368,15425–15728, SHA256 `e4f94c34baf217795b4c961bbf3d919ae4b698a78796740f045a1c84708460e3`. This supports separate compact/expanded/workspace surfaces. It is not permission to copy proprietary code/assets, its invisibility behavior, or its pause implementation. Deeper module/flow mapping is owned by `/root/research_visual_inputs`.
- Official [Cluely guide index](https://docs.cluely.com/llms.txt) exposes Live Insights, Settings, meeting notes and knowledge/mode material. The public guide is dated relative to shipped2.1.24 and the research owner is checking differences. Full target includes live input/transcript/actions plus workspace history/context; public docs are product references, not proof Relay already implements them.
- [Clicky](https://github.com/farzaa/clicky/tree/a80fa80721a8aebe51a170a7780705024ebc6e46), immutable main pin `a80fa80721a8aebe51a170a7780705024ebc6e46`, MIT copyright2026 Farza. Read `LICENSE`, `MenuBarPanelManager.swift` and `CompanionPanelView.swift`. Its native panel separates window lifecycle from SwiftUI content; the source uses320-wide menu content and16-point padding. Reuse the architectural lesson, not its teacher/cursor overlay, global mouse monitor, automatic permission requests or remote paid-provider pipeline. No code copied and no package adopted. The published source is an older open version, not its current proprietary product.
- [MenuBarExtraAccess1.3.1](https://github.com/orchetect/MenuBarExtraAccess/tree/e93e3a5b814714bf4d4cea67bf63a6b6a8323968), pin `e93e3a5b814714bf4d4cea67bf63a6b6a8323968`, MIT copyright2023 Steffan Andrews. Read license, package and scene/observer source. It provides presentation binding/status-item/window introspection; the Swift6.2 manifest has no external package dependency, and scene API is macOS13+. Current Relay is macOS15.2+/Swift6.2, so compatible in principle. Prefer native `MenuBarExtra` plus Relay's existing own-window attachment first; add this package only if a concrete native presentation limitation remains. No dependency added during this design.
- [Aski](https://github.com/jxmnhm/aski) was inspected as a comparable compact/expanded native assistant. Its README explicitly says no open-source license is selected, so do not adopt its code. Its clipboard fallback/external insertion/provider auth also differ from Relay's boundary.
- Apple's [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) supports access to common actions while the app is inactive. A menu entry is an optional launcher/status affordance; it does not require removing Relay from Dock/app switching. Use ordinary application/window behavior. No screen-exclusion, detection-evasion or external typing change belongs here.

Exact Relay dimensions/colors below are design choices informed by native precedents and measured surface separation. They are not claimed Cluely pixel values.

## Proposed hierarchy and original visual tokens

### Home and first run

Ordinary window, default880×640, minimum760×560. Header: Relay identity, compact account/setup state, Settings. Main emphasis: “Ready for your next conversation” and one Start session button. A small source row chooses the authorized conversation app and microphone state. Memory is a distinct navigation destination with Add résumé/Manage memory, not a form embedded above the answer. Activity appears only when backed by real data.

First-run setup is a short task flow: explain local speech preparation/download and required rights once; audio permission and permitted-use consent; choose the conversation source; optional résumé import and optional selected-window context. Account setup is a separate real task. If the existing account is unavailable, explain it and offer supported local-reference operation; do not fabricate a sign-in button until an auth port exists.

After initial consent, Start handles automatic preparation via the setup coordinator and then starts only if that intent is still current. Show Checking, Preparing speech with actual fractional progress when supplied (225MB is the manifest download size), Validating, Ready, or a fixed recovery message/Retry. Display completed bytes only if the coordinator actually supplies them; the public downloader currently exposes fraction/phase, so never derive invented exact byte progress. Cancellation, loss of permission or changed source prevents automatic start. Normal UI never asks for speech-model or detector folders. Advanced overrides belong Settings.

### Live session bar and expandable answer

Initial proposed bar480×56; expanded answer600×460, minimum440×240, clamped to the active display's visible frame. These are one presentation owner, not two competing session models. Bar: drag region/logo, Listening/Paused/Preparing status, real elapsed time, audio source indicator, screen-context indicator, Pause/Resume, End and ordinary Hide/Minimize. End stays immediately available. Screen/audio controls use real current source state, never ASR readiness as a substitute for capture state.

Expanded content: small current verbatim question (up to two visible lines with expand), prominent answer lead, at most two supporting points, optional code/detail. Copy and More detail sit with that card. Context provenance is a small source chip with popover preview/age. Keep toolbar/footer anchored while content scrolls. On accepted replacement, reset detail expansion as today. Do not append stale answers to the active card.

Full target adds an ordinary typed question/follow-up composer and action chips; this requires a separately specified typed-request route. First slice shows the real current-question Help, Copy and More detail actions only. Do not simulate ASR, EOU or fake transcript to make a text box work. Automatically received questions continue to launch suggestions without a manual confirmation step.

Window activation: explicit user Show/input may focus Relay. Automatic answer presentation should preserve source focus, especially for selected AX context, using the existing ordinary `orderFront` semantics and currentness gates. A visible pin-on-top preference can be offered as own-window behavior; there is no invisibility promise. Hidden/minimized sessions keep a visible menu/status state and usable real Pause/End controls.

### Memory, activity and settings

Memory workspace: Sources, Pending review, Approved memory (when its read port exists). Add résumé / Add project notes / Add job context are concrete tasks. Keep ownership confirmation, conflict/replacement and source revocation; put fingerprint/span/revision behind “Source details.” No auto-approval. Lock remains a clear workspace action. Root owns deeper profile-flow research and must assign view/core ownership before changes.

Activity target: real sessions, current/past questions, transcript and answer history with explicit save/retention choices. Existing audit history is not a meeting transcript store. A bounded in-memory current-session activity view can ship when it has a real accepted-event DTO; durable history requires a separate encrypted/consent/retention contract. Do not render fake session rows or make old answers current again.

Settings categories: General; Audio & speech; Screen & selected text; Account & AI; Shortcuts; Advanced. Audio & speech has friendly device/source status and automatic setup, with paths/version/debug choices under Advanced. Screen settings has one preview renderer, explicit selected-window access, AX allowlist/consent and visual test controls. Explain required user decisions plainly; helper generations, receipt/bearer details and raw parser failures live in Advanced/Help. Keep accurate image expiry/refresh limitations available without paragraphs filling the live surface.

Tokens: spacing4/8/12/16/24; outer content padding16, workspace24; outer radius16, inner card12; toolbar56, standard controls32 high; SF system typography chrome12–13, question13, lead17 semibold, supporting text14 with comfortable leading, SF Mono13 for code only. Dark base `#101315`, raised `#191D20`; light base `#F6F7F8`, raised white; adaptive label/secondary-label colors and system accent. Thin separator at8% label opacity. Status uses text plus icon, not color alone. No heavy gradient, dashboard tiles or repeated bordered groups around every sentence. Respect reduced motion, keyboard focus and accessible labels; use a short120–160ms expansion transition only when reduced motion is off.

## Full gap matrix and sequencing

| Capability | Current truth | Required implementation / first-slice behavior |
|---|---|---|
| Automatic listening/suggestions | Real native pipeline and contextual automatic routing exist, but manual assets required | Setup owner supplies validated automatic assets; one Start with real progress. Preserve explicit source/consent. |
| Compact bar/live answers | Current single large setup/answer window | UI lane separates Home/live layout, card controls and own-window presentation; same real session model/ports. |
| Résumé ingest/review/revoke | Real protected ProfileController and source review flow | Memory entry point works in first slice; dedicated task UI can wrap existing controller. Approved-memory browser/count requires a read DTO. |
| Typed chat/follow-ups | No typed question port; Help repeats accepted current question | Root assigns new native/helper semantic request contract. No fake composer in first slice. |
| Quick/dynamic actions | Real Help/copy/expand/scroll; no new semantic action requests | Ship real actions only; Simplify/Explain/Code/etc require typed intent and authority before UI exposure. |
| Live transcript | Native final events exist, no published transcript-view model | Bounded readonly final-turn DTO with source/status; no implied human verification or biography promotion. |
| Activity/history | Latest card only; protected personal audit is a different store | Current-session bounded event DTO first; durable sessions need explicit persistence/retention/consent contract. No fake Activity nav. |
| Modes/custom context | Fixed role from launch; no idle mode mutation UI | Root defines idle-only mode/context configuration, helper retirement/recovery and presets; UI cannot wire a decorative picker to a constant. |
| Account onboarding | Existing external sign-in; no in-window setup | Functional account port needed. Keep a truthful unavailable state and local-reference option until assigned. |
| Screen/image context | Real selected-window/OCR/image gates and explicit visual check | Compact status/source popover; preserve all consent, currentness, expiry and pre-EOU retirement rules. |

## Shippable first slice and file ownership request

First slice: one-click automatic setup/start, a clean Home state, actual compact live bar/answer view, functional Memory entry, separate Settings and existing working actions. It is a coherent replacement for the current prototype UI, not the full target's typed chat/history/modes. Root should sequence those next from the gap matrix so the final product meets the owner's full direction.

Proposed UI-owned new files under `spikes/macos-panel/Sources/RelayPanelSession`: `RelayHomeView.swift`, `LiveSessionView.swift`, `SessionToolbar.swift`, `AnswerCardView.swift`, `ContextStatusView.swift`, `RelayTheme.swift`, `RelaySettingsView.swift`, `SessionWindowShell.swift`. UI owns the app entry/view split and `SessionWindowControls.swift` attachment adaptation after assignment. Leave transport, reducer, capture/context core and profile controller unchanged. Root/profile owner assigns `MemoryWorkspaceView` or a wrapper around current preparation UI separately.

Shared `SessionApplicationModel.swift` must have exactly one seam owner during this phase. Setup owner owns asset coordinator integration and real Start/Resume admission changes. UI requests a readonly UI adapter/snapshot plus commands; do not concurrently edit that model. Existing `performWindowAction`, `setAIEnabled`, screen/selection controls and profile getter remain the current command ports. Root may integrate the small view-adapter patch once setup freezes.

Requested setup UI snapshot: stage `notPrepared/checking/downloading/validating/ready/unavailable/cancelled`, optional progressFraction and completed/total byte counts, fixed user message and recovery action `retry/openSettings/none`. Commands: prepare-and-start, cancel, retry, then existing real stop controls. Validated ASR/VAD URLs remain internal. Setup owner reports selected compiled ASR+vocabulary224,238,270 bytes plus VAD1,063,425 bytes, total225,301,695 bytes across21 files; final policy/licenses are still its authority. Audio readiness (app source/mic permission/availability) remains a separate state from model readiness. The process-tap has no public TCC preflight: choose the source and request actual OS access only after Start. Silence is not permission-ready, and there is no auto-switch to global/unrelated audio.

Later typed input, transcript/activity and mode contracts should be separate real ports, not UI-derived authority. Existing accepted native UUID/sequence/lease, semantic token, source consent, profile revision, bounded queue, final publication and actual quiescence boundaries remain mandatory.

## Testable acceptance

1. Normal launch has no model/VAD/folder controls or raw helper/lease prose. One primary Start; first-run consent/download work is a visible task, then normal readiness is quiet.
2. Injected checking/download/validation/offline/cancel states render truthful progress and one valid recovery action. No fake percentage, network or model/account action in previews/tests. Canceled/obsolete preparation cannot start capture.
3. Main session renders Listening/Thinking/answer/Paused/Stopping/unavailable states from real owner state. Pause/End retire admission exactly as accepted, including held-image retirement; Start/Resume remain blocked until actual joins finish.
4. Latest question, answer lead and up to two points have clear hierarchy; code preserves indentation. Copy/detail act only on current accepted answer. Replacement resets expansion; old cards never revive.
5. Memory import/review/revoke remains usable and source-owned; viewing a workspace does not read arbitrary files or approve facts. UI reports source versus approved-fact counts accurately.
6. Own-window controls target the live surface, clamp frames and preserve focus-sensitive AX validation. Closing/hiding does not masquerade as stopping. No screen-sharing exclusion, external typing, permission bypass or stealth feature.
7. No enabled UI action is a stub. Typed input/history/modes/transcript appear only with their working contract. Functional gaps are explicit in delivery evidence.
8. Test pure presentation mapping and actual command routing with injected ports; build the real SwiftUI app. Capture fixed synthetic Home/live/paused/setup/error states for visual review after implementation, with no OS/account/private actions. Final visible verification waits for the manually unlocked Mac; no current screenshot inspection is claimed.

## Next coordination action

Root freezes the first-slice hierarchy, automatic-setup/model seam and disjoint file ownership, then supplies a fresh isolated clone/branch from the current phase baseline. UI implementation starts only afterward. REA owner supplies the full official/client flow and measured design findings; append any necessary corrections to this proposal before contract freeze rather than silently expanding shared runtime scope.
