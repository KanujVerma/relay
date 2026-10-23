# Screen context and controls: lessons from a shipped client

Reviewed 2026-10-23. Static research on Cluely 2.1.24 informs these proposals. No competitor code, prompts, assets or service implementation is copied. No dependency is adopted by this document. This does not change Relay's accepted build contract or imply a delivered screen feature.

## What the client establishes

Cluely's observed client path captures a screenshot for a specific answer request, uploads it under that request's message ID, adds newly available transcript text and optional partial audio, and can display a screenshot preview. It uses separate microphone/system audio channels. A new submit while busy queues a replacement and stops the client response. These are useful product patterns for Relay's technical, coding and case-study conversations.

The inspected screenshot path selects the display containing Cluely's own panel and can fall back to the first display. It does not establish selected-app capture, continuous OCR, backend image understanding or stale-screen protection. The observed submit path requests explicit help; automatic question detection, server model selection, retrieval and upstream cancellation remain unknown.

The onboarding accessibility label mentions global shortcuts and app-aware controls. The inspected code requests AX trust, registers Electron global shortcuts, and controls its own windows. Selected-module review found no external-app AX reader or actuator. This bounded search does not establish the purpose of every native component. Relay should request permissions for demonstrated capabilities.

Pause UI changes a paused flag and elapsed-time bookkeeping, while inspected capture/transcription paths check session presence. No runtime pause behavior was tested. Relay's pause acceptance must verify actual capture/ASR admission and late-result invalidation.

## Proposed Relay shape

| Area | Proposed behavior | Ownership and acceptance |
| --- | --- | --- |
| Screen context | Explicitly select a window/app/display; capture on request or an agreed question boundary; show source and capture age. | Conversation/native capture seam. Revocation, selection change, closed source and superseded questions invalidate old context. Never silently fall back to unrelated content. |
| Extraction | Start with bounded local text recognition. Preserve code line breaks and uncertain recognition. | Answer context seam. OCR alone does not establish diagram relationships or reliably recover every code symbol. Ask for missing context when needed. |
| Transport | Keep image payloads outside the existing 16 KiB JSON wire. | Controller-owned contract change if future image transport is required. Do not send images until the authorized model route and capability are verified. |
| Grounding | Bind screen observations to native request/session/presentation identity, source/consent revision, capture uptime and digest. | Answer publication checks current source authority. Session screen material never becomes confirmed résumé experience. |
| Controls | Configurable show/hide, request context, pause/resume, expand/copy and response scroll. | Panel seam. Handle conflicts/rebinding visibly; avoid taking an unmodified global Tab key. |
| Conversation | Retain whole-conversation stage, assumptions, latest attempt, corrections and personal evidence separately. | Existing conversation, answer and Personal Brain ports. Do not replace native source ordering with wall-clock transcript watermarks. |

Public implementation candidates are Apple's [SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker) and [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager), both documented for macOS 14+, plus local [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), documented for macOS 10.15+. These are legitimate equivalents, not claims about Cluely's internals.

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts/tree/772133d9dbe800fdac0473226822994c5c162c58), MIT, is a concrete native hotkey candidate. Its source uses Carbon RegisterEventHotKey and its README reports no permission dialogs. No AX request should be added solely for these ordinary hotkeys. Pin, inspect tests and preserve notices before adoption. Relay should keep its existing selected-app audio/local ASR path instead of adding the competitor's separate Electron/CDN pipeline.

## Evidence and limits

Target `app.asar`: 28,442,561 bytes; SHA-256 `5ed201e85fc9de452b338887bffadca2a5dd1eef1f12fd101db81be02b0b28a0`, unchanged after read-only analysis. REA `6.7.0` ran successfully on seven JavaScript sources and package metadata using Node `24.22.1`. Evidence ID: `ev_9a3c93b1c705cc08b8c4c76de07107012303c7bb258165e26ce5d18783ff9403`. Selected-source and semantic retention limits make coverage partial. Two unpacked native protocol members contradicted declared ASAR hashes; REA retained them as observed-untrusted. Their cause and behavior were not determined.

Supporting direct source coordinates use UTF-8 byte ranges, end-exclusive:

- Permissions: `dist-electron/main.js` 536408..537885, lines 16690-16742. Shortcuts: 522691..525514, lines 16159-16275. Screen capture/IPC: 537885..541869, lines 16743-16857.
- Audio: main 519464..522033, lines 16025-16123; `dist/assets/transcription-D8utNpim.js` 420300..423250.
- Request context/stop: `dist/assets/chat-DIvku-qQ.js` 276714..279164, 751864..753014 and 754814..759214. Pause: 763214..764064. Preview: 291214..292984.

Full evidence, file hashes and manual provenance remain outside Git in the local research workspace. No Cluely runtime, account data or private service was accessed. No latency, accuracy, backend retention or complete-product claim is supported by this investigation.
