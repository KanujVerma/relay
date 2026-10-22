# Relay 03B-A: question and turn state

Status: **offline synthetic transcript contract only**, tracked in [issue #41](https://github.com/KanujVerma/relay/issues/41) and [PR #42](https://github.com/KanujVerma/relay/pull/42). This is not an audio-to-answer pipeline, a turn-detection model, or an application that automatically listens to real interviews.

Implementation: [question_turns.py](../relay_spike/question_turns.py) and [test_question_turns.py](../tests/test_question_turns.py).

## Reuse decisions

| Existing code/upstream | Decision |
| --- | --- |
| Relay [ActiveTurns](../relay_spike/streaming_qa.py) from PR #16 | **Reuse the exact existing object**. It already has thread-safe ID, version, generation, cancellation and atomic final-publication checks. Another turn-token system would create mismatched stale-answer behavior. |
| [Pipecat](https://github.com/pipecat-ai/pipecat), BSD-2-Clause | Useful real-time event pipeline and interruption architecture reference. **Do not install the full Python voice-agent framework** for the narrow local transcript state contract. |
| [LiveKit Agents](https://github.com/livekit/agents), Apache-2.0 for framework | Reference for semantic end-of-turn design. Its optional separate turn-detection models have their own licensing and performance considerations, and its framework is oriented toward server-side real-time participants. Defer model selection and Mac RAM/latency benchmarks. |
| [XState](https://github.com/statelyai/xstate), MIT | Reference for explicit transitions, guard conditions and event-driven machines. A JS runtime and statechart interpreter are unnecessary for this small standalone Python adapter. |

No external code was copied or vendored and no runtime dependency was added. Actual authenticated audio ownership and on-device speech recognition remain in the separate [audio issue #33](https://github.com/KanujVerma/relay/issues/33) under parent [#22](https://github.com/KanujVerma/relay/issues/22).

## Event input contract

`TranscriptEvent` contains the audio **source channel** (`remote`, `microphone`, `unknown`), stream generation, segment ID, revision, monotonic start/end milliseconds, partial/final/retracted/discontinuity status, verbatim text and optional ASR confidence. The caller may supply a **tentative intent** (`question`, `correction`, `follow_up`, `statement`, `unknown`).

The supplied intent is not semantic proof. The module neither infers a complete interviewer identity from remote audio nor treats spoken instructions as application instructions. A remote channel may mix multiple interviewers. Low confidence (when a numeric value is actually supplied) blocks question routing; the 0.60 threshold is a provisional guardrail, not a calibrated probability. Missing confidence does not establish high accuracy.

Only final, sufficiently unambiguous remote question events may produce a `TurnDecision(state="ready")` with a `QuestionSnapshot` and the *shared* `TurnToken`. Partial text never starts inference. Unknown or microphone-channel utterances do not create remote interview questions. Intent labels and transcript text are untrusted inputs; in later slices a separately evaluated classifier must decide when to label them.

## State, timing and privacy semantics

- Each active logical question has one ID and version. A genuine new question gets a new ID and version one. A correction or follow-up increments the existing logical version and, through `ActiveTurns.activate`, replaces its generation. Old answers become stale **before** they can publish.
- A remote partial explicitly labeled question/correction/follow-up invalidates a previously active answer immediately. For matching eventual correction/follow-up finals, only the previous accepted verbatim context is held provisionally. The partial **cannot** become an answer, and a discarded project question in E11 cannot be treated as authoritative.
- D12 preserves the literal corrected request about **distinct orders in 2025** as authoritative. Earlier question wording is included in a separately labeled superseded/context-only field, never silently merged into a newly fabricated SQL predicate, ranking metric, tie policy or database dialect.
- E04/D07 multi-part splitting is a reversible **verbatim heuristic hint**, never a semantic parts-coverage or answer-correctness certificate. The complete user-provided transcript stays available as one current utterance.
- Exact same-segment revision replays are ignored using SHA-256 fingerprints. Conflicting same-revision finals, post-final ASR revisions, retractions and stream discontinuities invalidate any old active answer. Old remote stream generations, late finalizations of previously seen partials, and revisions to an already superseded segment cannot regain control. A newly finalized unclassified remote utterance invalidates the previous answer, and overlapping remote question timestamps require review rather than assuming one speaker.
- Replay bookkeeping holds at most 128 opaque segment summaries, not complete transcript history. Active/current context is bounded; nothing is written to a file or sent to a model.
- Explicit stop/permission removal blocks **every** subsequent generation until `resume()` is invoked by the native host. Calling `resume()` in Python does **not** prove actual OS permission or user consent. A stream discontinuity blocks the affected generation until a new generation arrives.
- `ready` means the calling adapter may consider routing to a separately authorized QA/inference step, not that the speaker was identified, the question semantically understood, or the AI answer verified.
- [publish_assessment](../relay_spike/streaming_qa.py) still checks the token **at the synchronous publication boundary**. A stale completed model response never displays after a correction, interruption or stop.

## Scope and next integration

The [synthetic regression suite](../tests/test_question_turns.py) covers E11 discarded partial questions, D12 corrected SQL metric/date, E04/D07 multi-part wording, follow-ups, partial-to-final replacement, interrupted in-flight QA publication, low-confidence uncertainty, mic/remote overlaps, duplicate/stale events, stream-generation resets, stops/retractions and sanitized error handling.

B0 does **not** wire into FluidAudio, capture Zoom, recognize actual questions from arbitrary natural language, import Private Brain facts, invoke ChatGPT OAuth or measure first-useful-answer latency. After real, permission-checked Mac audio/ASR evidence exists, a separate bounded integration slice may adapt finalized transcript event metadata, test an independent intent classifier, and connect this machine to the existing safe `live-qa` publisher. Keep the M2 Pro 16 GB CPU/RAM budget and permission constraints explicit. Never present a purported useful talking point before independent validation.