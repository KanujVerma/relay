# Lagged ASR preprocessing with an exact native cutoff

Status: root approved this architecture on 2026-10-24 with the mandatory
optimization-backpressure fallback below. Not implemented yet. Existing
response instrumentation/compact foundation is frozen at `23bf594`; native
Model observation and account acceptance remain separate ongoing gates.

## Problem and chosen direction

The current native path waits for VAD closure, then sends the complete activity
to Parakeet in 5,120-sample pieces. Long utterances therefore pay all ASR compute
after endpointing. Reuse the existing recognizer **per source** to process a
provably safe prefix during authorized capture. At native closure send only its
unconsumed suffix and finish. Publish no partial transcript, early model request
or answer. Keep native start/end/sample/clock/lease and final EOU identity intact.

This is two existing independent VAD/ASR pairs when microphone and selected-app
audio are enabled. It is not one manager shared between sources, two new
speculative model copies, or a second final recognizer. The microphone worker
must complete independently while a remote worker is held.

## Pinned upstream evidence and alternatives

FluidAudio SDK is Apache-2.0 at
`c79c4106b954f81205113c3343e5a7e59a1089b5`; no upstream code is copied or forked.
The already verified Parakeet model weights retain their separate NVIDIA Open
Model License. Existing 320 ms mode/compiled assets and compute units remain.

Inspected [VAD streaming source](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/Sources/FluidAudio/VAD/VadManager+Streaming.swift),
[public state/config types](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/Sources/FluidAudio/VAD/VadTypes.swift),
[VAD tests](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/Tests/FluidAudioTests/VAD/VadStreamingTests.swift),
[incremental EOU manager](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift),
[EOU timing/debounce tests](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/Tests/FluidAudioTests/ASR/Parakeet/Streaming/StreamingEouAsrManagerTimestampTests.swift),
[encoder frame-count tests](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/Tests/FluidAudioTests/ASR/Parakeet/Streaming/EouChunkSizeFrameCountTests.swift)
and [license](https://github.com/FluidInference/FluidAudio/blob/c79c4106b954f81205113c3343e5a7e59a1089b5/LICENSE).

`process()` already performs encoder/decoder work incrementally, retains state,
and returns empty text; `finish()` pads only the remaining buffer and returns
accumulated text. Its EOU debounce uses processed sample counts, not elapsed
wall time. Continue ignoring early EOU hints; never truncate later constraints.
The wrapper already rejects reset underneath active accept/finish.

Rejected alternatives:

- Fixed 0.75–1 s lag alone is unsafe. A pending `tempEndSample` survives an
  arbitrarily long hysteresis-band sequence before a later low-probability
  chunk emits an end far behind current input.
- Processing all incoming audio and undoing after the final cutoff requires
  complete encoder/decoder/cache/token snapshots. The pinned public API has no
  such transactional snapshot/restore; an extra speculative manager increases
  state/memory without solving attribution automatically.
- Lowering silence, sharing one manager across sources, or moving to a new ASR
  framework changes quality/ownership without current evidence.

## Safe-prefix proof, including padding and hysteresis

Use the **same actual returned VAD state** that supplied the boundaries:
`P = processedSamples`, `C = chunkSize` (4,096), `B = speechPaddingSamples`
(1,600 at unchanged defaults), and optional `S = tempEndSample`.

While speech is active, retain one chunk and expose a safe exclusive end:

`safeEnd = min(P - C, S + B - C when S exists)`

Clamp at the original native activity start. When no active speech or the
returned event is an end, expose no prefix watermark; the end event alone
determines the final exclusive cutoff. Use checked integer arithmetic and
validate the returned processed count against the actual consumed source input.

Proof: with no pending end, any later first low chunk is processed after the
current chunk. Its candidate end is at least the current processed position
plus padding, beyond the retained prefix. When the first low chunk sets `S`,
the candidate end is exactly `S+B-C`; previous prefix submission is behind it.
Every later middle-band/low chunk keeps that cap until positive speech clears
the candidate or closure emits exactly that index. Middle-band duration cannot
advance the cap. Positive speech clears `S`, so a future candidate is later.
Never repair a backwards/invalid watermark by taking a maximum: fail closed.

Start from the actual start boundary, including its existing leading padding;
never feed an earlier source sample. Slice the original source history by its
absolute indices. Submit complete contiguous 5,120-sample pieces, preserving
the baseline adapter's exact `accept()` partition. At closure append the
remaining `[submittedEnd, finalEnd)` once and call finish. Submitted end must
never exceed final end, and acknowledged count must equal the closed span.
No sample beyond final end enters the recognizer, so rollback is unnecessary.

## Interfaces and sole owners

Keep the existing `SpeechActivityDetector.accept()` and closed
`ActivityRecognizer.recognize()` for unchanged fixtures/fallback. Add an optional
`RecognitionWatermarkDetector` protocol with one `observe(samples)` operation
returning boundaries, processed sample count and nullable safe end. The core
calls observe **instead of**, never in addition to, accept. Fluid's legacy
accept delegates to the same single state transition. The wrapper stores and
passes the unchanged explicit segmentation config used by the proof.

An optional `IncrementalActivityRecognizer` exposes serialized begin, append,
finish and abort operations on an opaque core-created activity key. The key
binds the actual original source, stream generation, native activity/start and
lease. It is not wire data or new publication authority. Each append checks key,
contiguous offset, finite samples and total count. Finish checks the original
exact cutoff/count. The Fluid adapter retains its one existing backend and
single-flight guard; legacy closed recognize is unavailable while an incremental
activity owns it. Unexpected concurrent reset/abort must reject, not reset CoreML.

One lazy serial recognition drainer per source owns that adapter exclusively:
`begin → append* → finish/reset → next begin`. It may queue the next activity
while the preceding final finishes, preserving original keys on all callbacks.
Never reset the old decoder to admit new onset. Remote and microphone drainers
have independent existing managers and no shared per-utterance actor/queue lock.

Queue bound: at most 32 commands and 16,000 queued PCM samples, plus one
in-flight 5,120-sample append per source. Existing 120 s activity/history bound
remains. Optimization-only queue saturation disables prefix work for that
original activity. It must not retire otherwise valid capture. After the actual
in-flight accept returns, discard queued prefix work for that key and reset;
at its actual closure run the original full closed-span recognizer once under
the same original key. A monotonic one-fallback latch prevents replay loops.
This is one local ASR fallback, never an external provider request or retry.
An unstarted queued activity needs no reset of the preceding owner's state.
Fallback/closure/cancel signals cannot be dropped behind a full PCM queue.
Invalid source/watermark/gaps and model errors retain the existing fail-closed
error path. Next activities preserve FIFO ownership across either finish path.
Keep the full original closed-span witness initially, so this optimization adds
only bounded queued copies, not another full history/model state. Remove that
copy only in a separately proven memory optimization if measurements justify it.
Initially the capability is explicit/default-off in source components. Normal
production activation requires the matched paced-input and resource gate below;
there is no user-facing detector/model switch or new automatic download.

## Admission, cancellation and quiescence

No preprocessing starts until the actual native `onStart` returns its original
authorized lease. Existing capture/source permission and input validation stay
unchanged. Prefix work emits no transcript or request. A newer onset can retire
the old display lease while old ASR finishes under its original activity key;
existing late-final history-only behavior remains.

Source/sequence/device/permission loss or Stop synchronously closes source
admission. The worker checks that original live source before every queued
operation and after awaited model work, rejects new commands and clears queued
PCM/control work. Cancellation cannot prove CoreML stopped mid-prediction. Retain
the original drainer and adapter until active accept/finish actually returns;
only then reset/abort. Extend real `waitForQuiescence()` to join that worker.
The existing two-second native stop deadline may report unknown, but replacement
and cleanup still wait for the actual old owner. Never let an abort reset run
under another activity's live backend call.

## Fixtures and measured gate before activation

Design fixtures first establish the cutoff invariant and retain a concrete
fixed-lag counterexample. They are source-derived metadata oracles, not execution
of the Swift adapter or an ASR accuracy/performance claim.

Runtime negative/positive gates must include:

1. Leading padding, first/last partial pieces, exact appended-byte/sample order,
   full late constraints and same final partition as closed recognition.
2. A low chunk followed by long middle-band input and later closure; no prefix
   beyond the original candidate end. Speech resumption clears only that cap.
3. Invalid/backwards/oversized watermarks, source generation/sequence gaps and
   model error with no final or stale publication. Optimization queue saturation
   instead proves the single original closed-span fallback, including a large
   watermark jump after long middle-band input and resumed speech.
4. Held accept/finish during Stop, actual reset after release, original join,
   no replacement early admission, and a later activity queued under its own key.
   Saturation while accept is held must neither reset underneath it nor emit two
   finals; disabling further prefixes cannot erase the retained original span.
5. Held remote prefix while microphone closes/finalizes independently, and the
   converse. No cross-source content/state; native event counters stay contiguous.
6. Existing native provenance/manual/typed/clock/cancellation controls unchanged.

Under a root heavy lease, reuse the verified public speech cache and fictional
WAVE input. Compare baseline closed and prefix modes on identical warmed models,
with actual paced PCM, identical final text/closed-span indices, end-event→ASR
final and submitted/remaining sample counts. Include two overlapping sources,
cold load separately, failures and process RSS. Existing historical two-source
smoke measured about 1.21 GiB max RSS, but that is not a fresh bound for this path.
There are still only two managers; record actual RSS rather than assuming weight
sharing. Investigate any increase over the matched baseline of 256 MiB before
normal activation. No new dependency, cache root, model download or account call.

Minimum write set after approval: new core observation/recognition queue types,
`SourcePipeline.swift`, `FluidSessionAdapters.swift`, focused native/capture tests
and opt-in matched offline benchmark. `NativeCaptureSession` can keep constructing
one existing adapter per source; wire, permissions, helper and answer policy do
not need changes. Root independently reviews exact source and the measured gate
before joining or claiming a response-time reduction.
