# Slice 04A-0: native answer-panel prototype (offline/mock only)

**Status:** implementation proposal in a separate PR from issue #53; no production interface or real-Mac proof. The existing Swift audio capture, FluidAudio, question-turn adapter, OAuth and verified Personal Brain remain separate. This is intentionally a NORMAL, visible macOS window, not a stealth or screen-share-safe overlay.

## Run on a Mac

From the Relay root with macOS 14 or newer and Swift 6:

```sh
swift test --package-path spikes/macos-panel
swift build --package-path spikes/macos-panel
swift run --package-path spikes/macos-panel relay-panel-demo
```

The run command opens a **synthetic local demonstration**. There is no microphone permission prompt, selected-app audio tap, network connection, model request, private content import, recording, local persistence, global hotkey or SDK/model download. The test workflow compiles and runs pure state tests on hosted Mac CI without ever opening the GUI. It does not measure M2 Pro responsiveness or validate real interview correctness.

## Demo controls and state

- **New question** starts a new monotonic generation. **Correction** replaces it with a synthetic corrected question, immediately clearing any old sample answer.
- **Show sample card** displays only the fixed local illustrative SQL explanation, after an explicit mock publication event. It is labeled **unverified**: being a canonical/preapproved demonstration card does not establish technical or personal factual correctness.
- **Withhold** retracts a visible card for review. **Stop** clears all questions and answers and locks publication. **Resume** returns to idle, without resurrecting anything; only a fresh generation can start.
- Even a queued callback with matching text is rejected if turn ID/revision/generation differ or if it arrives after an interruption, stop, or replaced turn. Generations observed while stopped are retired, not made valid after resume.
- Bounded UTF-8 question/card limits and control-character rejection avoid accidental multi-megabyte UI content; all sample content lives in source files and is nonprivate. The status labels are controlled enums, not interpolated external errors.

## Integration boundary — not implemented

Future native host must first prove separate **authorized capture state**, normalized monotonic timestamps, local finalized EOU semantics, question provenance and freshness; then use the actual existing QA-active-turn publication contract. Only an explicitly approved *display card* may be delivered to this UI after completed inference + review, never arbitrary raw model prose or early ASR text. The UI must atomically check the current turn token again at main-thread commit; Swift's generation counter in this mock is **not** connected to Python's ActiveTurns or OS capture consent. No speaker identity, author permission, or model correctness is vouched for by this panel.

A real app also needs proper native package signing/bundling, consent and permission UX, Keychain, deletion controls, measured layout/accessibility on the owner's M2 Pro, and a suitable window focus/lifecycle strategy. A floating window should remain plainly user-controlled and may be visible in full-display sharing; Relay does not implement or promise undetectability. Do not connect native audio or inference to this mock executable until PRs #42/#46/#49 and #52 are reconciled and Mac source/permission validation is complete.

## Open-source references reviewed

- [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), **MIT**, approximately 2.7k stars at review: user-customizable macOS hotkey handling. Good later for an opt-in reveal shortcut; intentionally **not imported** before window behavior and native product design are validated.
- [scenee/FloatingPanel](https://github.com/scenee/FloatingPanel), **MIT**, approximately 5.8k stars: excellent state/anchor and supplemental panel prior art, but it is **iOS-specific UIKit/SwiftUI**, not a macOS NSPanel implementation. Importing it would solve the wrong platform problem.
- Prefer Apple's SwiftUI `Window` for a compile-and-run mock. Any future non-activating AppKit `NSPanel` needs separate focused keyboard/accessibility/screen-recording tests; no copied upstream code or new package dependency in this slice.

## Merge and acceptance

GitHub's isolated `panel-prototype.yml` runs `swift test` + `swift build` on public macOS CI when panel files change. Require the **actual exact-head** green result and completed Codex review before merge. No CI inference, OS consent prompt, capture, or external model download. The active 03A/03B agents currently own shared `HANDOFF.md` updates, so reconcile the global source-of-truth status only at merge, rather than overwriting concurrent agent edits.
