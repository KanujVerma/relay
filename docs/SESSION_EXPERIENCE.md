# Session experience, memory and latency

2026-10-24. This records the intended normal experience and current implementation limits, following the owner's workflow/memory questions. It is not a claim of real account/device acceptance or a finished release. [BUILD_STATUS](BUILD_STATUS.md) and [HANDOFF](../HANDOFF.md) own exact source/gates.

## Normal workflow

1. Set up once: connect the supported account, allow the selected audio sources, optionally enable screen context and choose one window. Add selected résumé/job context and confirm personal facts. Speech models/detection are prepared automatically; normal use has no technical model/folder picker.
2. Start a session. Relay listens to the enabled microphone and selected meeting-app audio while that session is active. The normal panel stays compact. Audio-source labels do not prove biometric speaker identity.
3. A detected interviewer question/follow-up automatically requests concise advice using the current conversation, relevant confirmed background and current allowed screen context. No question-confirmation button is required. Help reruns an existing current question; it cannot initiate a request from a screen alone. A new typed Ask can start a screen-only request.
4. The user answers naturally. Their microphone text becomes conversation context for the next request. The intended learned-style loop additionally links an actually available suggestion to subsequent original speech and continuation; that comparison loop is not built yet.
5. New questions/corrections retire affected prior suggestions. Pause/Resume control listening; Stop response cancels answer work; End finishes the session. These are different actions. The current implementation starts a fresh capture/conversation owner on Resume and resets recent dialogue/task context; preserving full semantic continuity across Pause remains unfinished.
6. Saved History is optional and off by default. Its current feature candidate retains final audio-session text/manual notes locally, not raw audio, screenshots, typed chats or assistant suggestions. AI notes and Learning Memory have separate unfinished delivery contracts. Enabling transcript saving does not silently authorize every new learning input or background model call.

## Screen behavior

Current screen context is selected-window and request-driven: capture/OCR at a question or Help request, with a bounded recheck before showing a dependent answer. It is not a continuous video stream or automatic frontmost-app/window following. The source must remain the selected window. Switching to another window can require choosing it again. Image use is optional and separately verified; diagrams cannot be understood from OCR labels alone.

The target is automatic relevant context once enabled, with truthful source status and minimal interaction. Screen-change monitoring/app-following beyond this first source-bound path remains a separate design/performance choice. Basic shortcut support is distinct from optional Accessibility-based selected-text controls.

## Four memory jobs

| Memory | Inputs | Intended effect |
| --- | --- | --- |
| Current meeting | Original question, actual user response, clarification, decisions and unresolved constraints | Continue the discussion coherently and avoid repeating already-covered material. Current bounded-context foundation is implemented; complete long-meeting semantic continuity is not. |
| Confirmed background | Explicitly selected/reviewed résumé and personal sources | Give accurate personal examples. Implemented foundation, tested with fictional inputs; real private-user acceptance remains separate. |
| Speaking style | Repeated clean examples of how the user phrases/restructures advice, plus explicit preferences | Match word choice, length and explanation order by situation. Automatic observation-driven adaptation is pending. |
| Interaction/preparation | Source-linked suggestion/response/follow-up episodes and explicit corrections | Anticipate relevant follow-ups and prepare recurring gaps. Persistent learning and measured improvement are pending. |

Store compact, bounded text/provenance and selected examples under explicit learning retention, with review/reset/source-deletion behavior. Keep inference-heavy consolidation outside the live response path. Do not infer that an answer was correct, read or well received merely because it was displayed or followed by another question. [Research](research/LEARNING_MEMORY_DESIGN_INPUT.md) compares exact LangMem/Graphiti source/tests/licenses and rejected behaviors; no framework is installed or adopted by that report.

## Response time evidence

[MODEL_STRATEGY](MODEL_STRATEGY.md) records owner-run exploratory tests from 2026-10-22. Across nine matched default-effort samples per model:

| Model | Median first nonempty text | Median complete response |
| --- | ---: | ---: |
| Luna | 3.265 s | 6.371 s |
| Sol 6.1 | 4.258 s | 8.761 s |

These are older user-reported model-only observations, not independently repeated current-app benchmarks. They exclude audio/VAD/ASR, screen extraction, retrieval, final checks and display. First nonempty text is not necessarily useful advice. Sample counts do not support a reliable p95. The current native answer card waits for a complete validated response; first-token performance cannot be advertised as card latency.

The 2–4 second first-useful-answer figure remains a target, not an achieved current-app result. Complex coding may take longer; no guaranteed range is established. The next permitted live gate measures question speech-end → actual readable card, with component timestamps, cold/warm setup, screen/memory on/off, real account configuration and representative technical/personal/case/follow-up cases. Compare learning on/off on held-out whole sessions for usefulness, grounding, stale outputs and latency; retain failures rather than reporting only successful fast samples.

Cluely's current public page describes continuous meeting context and an Assist shortcut; its 300 ms figure appears under live transcription. That marketing figure is not an independently verified end-to-end answer benchmark. The existing REA report covers selected 2.1.24 client/UI paths, not its private server-side memory, exact automatic trigger policy or measured speed. [REA evidence](research/CLUELY_DEEP_DIVE.md), [current primary website](https://cluely.com/).
