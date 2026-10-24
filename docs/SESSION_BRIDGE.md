# Proposed native session and answer bridge

Status 2026-10-23: accepted implementation direction. Exact current fields and ownership are frozen in [BUILD_CONTRACT](BUILD_CONTRACT.md); this document preserves rationale. Implementations are in progress and not yet accepted as a joined product. [PARALLEL_PLAN](PARALLEL_PLAN.md) owns write scope; this file is the single proposed interface definition.

## Ownership and framing

Swift owns source/consent lifecycle, native speech observation and the display admission gate. One Python coordinator owns the existing QuestionTurnMachine, shared ActiveTurns, composite eligibility strategy, router and terminal-request ledger. Network work posts immutable results to that coordinator and cannot publish directly.

Use dedicated inherited binary pipes with a 4-byte big-endian length and strict UTF-8 JSON. Proposed limits: 16 KiB per frame, 32 queued frames and 256 KiB per direction. Enforce bounds before allocation, exact keys, duplicate-key rejection, bounded depth/text and lossless UInt64 parsing. No listener or raw PCM IPC. Diagnostics stay off the protocol and contain fixed local reason codes. A partial-frame stall, blocked writer, overflow, malformed response or EOF retires native admission; controls cannot be silently dropped.

## Native input envelope

Keep the existing inner EOU v1 decoder and all 13 exact keys unchanged. Proposed outer fields are `schemaVersion`, `captureSessionID`, `sessionEpoch`, `eventSequence`, `presentationGeneration`, `kind`, `sourceCode`, `streamGeneration`, `emittedUptimeNanoseconds`, and discriminated `payload`. IDs/counters originate in native state before asynchronous delivery. They are not permission assertions supplied by a transcript.

Proposed kinds: session_started, speech_started, eou, source_unavailable, discontinuity, stopping, stopped. Session controls may have null source/generation; source events require the explicitly selected source. Source 2 means selected-app output, not a person's identity. Source stream generation is distinct from native presentation generation and Python token generation.

- A speech-start payload carries a source-local activity ID, actual start host ticks, detection uptime and the existing explicit native timebase calibration. It has no text, intent or fabricated confidence.
- An EOU payload wraps the exact inner event plus proven activity/input-range association. Preserve stable final identity across revisions. Missing or ambiguous association withholds routing.
- Final association must establish that the candidate covers the complete closed speech activity, including later same-activity constraints; first/last packet overlap alone is insufficient. Native-owned activity closure and last-speech-input sequence, or equivalent lifecycle evidence, need an agreed tested representation before serialization is frozen.
- Unavailable/discontinuity/stop controls carry bounded local enums, never raw errors. Stop closes admission before waiting for driver shutdown. Timeout does not establish producer quiescence or permit early queue reclamation.

Current ASR segment IDs are allocated at finalization and packet times do not prove decoded sample coverage. Do not match VAD activities and ASR segments by equal counters or callback arrival order. The native adapter needs a small explicit consumed-range/identity seam after PR49 repairs; until then fake fixtures are not hardware proof.

## One eligibility policy and one router

Inject one composite strategy into the existing ASR bridge. Common source/finality/activity/freshness checks precede route-specific decisions. A complete reviewed match selects the reviewed route; an otherwise eligible general technical request selects the generated route under [GENERATED_ANSWERS](GENERATED_ANSWERS.md). A reviewed-only strategy must not classify every miss unknown and starve the generated engine.

Use PR46's existing `remote_speech_started` and interrupted context. Add only the proven activity-aware association seam if needed; no fabricated partial text or second question machine. Preserve null ASR confidence. Route reason and evaluated policy version are separate from a confidence score. Unknown/blank/gap inputs invalidate affected pending context.

## Shared answer decision

Every result echoes the original native request ID, session ID/epoch, presentation generation and originating input sequence. It carries full Python turn identity plus an opaque native display ID; Python token IDs contain colons that current Swift TurnKey rejects, so map one-to-one without truncation or parsing.

Proposed `resultRevision`: optional pending 1, exactly one immutable terminal 2. Terminal disposition is answer, clarify, abstain or error. Only answer has an answer kind, card and host-controlled provenance. Other states expose fixed local reason codes and no arbitrary model prose. Terminal requests reject later success, even if a worker supplies a larger revision. Errors for an older request cannot clear a newer one.

Answer kinds are reviewed_reference and generated_suggestion. The reviewed catalog owns canonical content and its approved full match contract. A model cannot supply reviewed status, reference IDs, approval records or personal evidence. Generated provenance records actual completion/checks and explicit lack of independent review.

Proposed card bounds: lead <=280 UTF-8 bytes, 0-2 points <=180 bytes each, optional detail `{kind:prose|code, language:null|python|sql, text}` <=4096 bytes. Reviewed entries require 1-2 points. Code detail permits LF/tab and preserves whitespace; other controls and overflow reject. Never truncate. The existing 500-byte native question bound remains separate from the larger transcript/context bounds; overflow clears with a fixed status instead of rewriting the semantic question.

## Display and cancellation contract

Native-observed onset, stop, source/permission loss or invalid provenance retires local presentation authority before helper delivery. Queued MainActor commit checks that same authority synchronously with the reducer update. A delayed callback cannot acquire the newest native epoch by being delivered later.

Python retains real ReferenceCard objects and runs publish_reference/render_queued_card on its side before serialization; a copied JSON card is not that same object. This check is pre-send authorization, not native actual paint. Swift separately accepts only the current bound request, fences, live lifecycle and validated immutable card/provenance.

Initial v1 has one final card and no autonomous post-publication critic, upgrade or revocation. Model failure/timeout is a terminal pending-request decision, sealed before delivery. Native also enforces a deadline and terminal latch. If a later feature revokes an already displayed answer from Python, add an explicit answer-bound revoke and native clear acknowledgement before calling distributed revocation complete.

The guarantee starts at native-observed invalidation. It cannot prevent a state commit that preceded that observation, detect physical speech before VAD, or promise simultaneous pixel clearing across processes. Real visible draw/clear delay remains a measured Mac acceptance item.

## Required offline integration cases

Use golden messages in both languages and a real local child helper with fake source/model fixtures. Start from an already visible card and independently delay native admission, Python routing/network result, pipe output and MainActor commit. Verify no stale resurrection after onset, correction, blank final, stop/resume, source loss, replay, overflow, malformed input, child exit/hang or ID reuse. Test blocked/partial pipes and shutdown ownership with deterministic readiness handshakes. No model download, account call, microphone prompt or private content is part of this offline gate.
