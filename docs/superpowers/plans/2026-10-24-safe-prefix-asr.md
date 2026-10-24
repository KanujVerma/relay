# Safe-prefix ASR Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. The controller
> explicitly forbids child agents for this lane; root owns review and the shared
> heavy-job lease. Complete each independently testable task with red/green proof.

**Goal:** Move safe local ASR work before native speech closure while preserving
the exact final span, source ownership and one actual final.

**Architecture:** One bounded serial recognition lane per existing source uses
its existing recognizer. Actual VAD state supplies safe prefixes; native closure
supplies the sole final cutoff. Queue saturation disables speculation and reuses
the retained original closed-span path once after joining/resetting old work.

**Tech Stack:** Swift 6.2, existing Foundation/Dispatch/CoreML and pinned FluidAudio
`c79c4106b954f81205113c3343e5a7e59a1089b5`, existing offline Python fixtures.

**Spec:** [approved design](../specs/2026-10-24-lagged-asr-preprocessing-design.md).

## Global constraints

- Existing two independent managers remain one per enabled source; no new model,
  dependency, framework, archive, environment or cache root.
- Preserve existing VAD silence/padding, 13-key EOU, original source/generation,
  native clock/lease, late-history-only behavior and true quiescence ownership.
- Source components default to closed-span processing until matched paced WAVE,
  final text/cutoff and two-source resource gates pass and root reviews activation.
- Existing maximum activity is 1,920,000 samples. Prefix queue is at most 32
  commands / 16,000 queued samples plus one 5,120-sample in-flight append/source.
- Optimization queue pressure invokes one local fallback, not capture failure or
  provider retry. Invalid source/watermark/gap/model state remains fail closed.
- Heavy work requires root lease, existing retained cache, jobs=2, 180 s deadline,
  fresh at least 30 GiB free and aggregate Relay temporary allocation <=25 GiB.

## Task 1: Optional contracts and bounded original-activity feed

**Files:** new `spikes/macos-session/Sources/RelayNativeSession/ActivityPreprocessing.swift`;
new `spikes/macos-session/Tests/RelayNativeSessionTests/ActivityPreprocessingTests.swift`.

**Interfaces:** `SpeechActivityObservation(boundaries,processedSamples,safePrefixEnd)`;
`RecognitionWatermarkDetector.observe(_:)`; opaque core-issued recognition key;
`IncrementalActivityRecognizer.begin/append/finish/abort`; an internal per-source
lane with `begin`, `offer`, `close`, `cancel`, `waitForQuiescence` and a bounded
fixed diagnostics value for synthetic test observations.

- [x] Write fake-actor cases proving original key, contiguous 5,120-piece order,
  exact final suffix and one finish. Example assertion:
  `XCTAssertEqual(await backend.consumed, originalClosedSpan)`.
- [x] Write held accept + queue saturation case: before release assert zero reset
  and zero final; after original closure/release assert one full legacy call,
  exactly one final and no second prefix restart for that key.
- [x] Obtain root lease and run `swift test --package-path spikes/macos-session
  --filter ActivityPreprocessingTests` with the required existing-cache driver;
  retain expected missing-API output, then release the lease.
- [x] Implement bounded owned feeds with independently deliverable close/cancel
  state, one fallback latch and one serial worker. Never await model work under
  its queue lock. Preserve original ClosedActivity until completion.
- [x] Obtain the next lease; run the same cases plus existing session-pipeline
  cancellation/clock/late-source controls. Inert core had four-case green; the
  later full conditional-source gate passed all 47 native cases and 36/38
  capture cases (two explicit download/model skips), still no normal activation.

## Task 2: Actual pinned VAD watermark and original single backend

**Files:** `spikes/macos-session/Sources/RelaySessionCapture/FluidSessionAdapters.swift`;
new `spikes/macos-session/Tests/RelaySessionCaptureTests/PrefixFluidAdapterTests.swift`.

**Consumes:** Task 1 optional contracts. **Produces:** Fluid observation uses the
same state transition once and `min(P-C,S+B-C)` cap; Fluid recognizer implements
serialized prefix operations using its existing backend, with original key/count.

- [x] Add leading-padding, long middle-band/pending-end, resumed-speech and
  original cutoff cases from `tests/fixtures/asr-prefix-design.json`. Include
  actual pinned streaming-state-machine execution without loading a model.
- [x] Add fake LocalEouRecognizer cases for early EOU ignored, held accept/reset,
  prefix/full closed call partition equality and unsupported concurrent calls.
- [x] Run the API/red gate under a lease. Implement same-config returned-state
  observation and single-flight adapter; keep legacy accept/recognize APIs.
- [x] Green the new cases and original FluidAdapterTests, then commit with exact
  source/test evidence. No ordinary production mode switch yet.

## Task 3: Source pipeline integration with baseline-preserving fallback

**Files:** `SourcePipeline.swift`, Task 1 lane, and focused SessionPipeline tests.

**Consumes:** optional detector/recognizer contracts. **Produces:** explicit
default-off component capability; one live lane/source; original `onEnd`/`onFinal`
and real `waitForQuiescence()` retain ownership across all worker operations.

- [x] Add native-controller cases proving zero prefix calls before actual start
  lease, all original start/end/padding samples consumed, and prefix work before
  closure without an early EOU. Unsupported components retain legacy behavior.
- [x] Add invalid watermark/model error, original source gap/rotation, held stop,
  next-activity FIFO and held-remote/microphone-completes controls. Assert original
  event counters, leases and late-history identities, never replacement stamping.
- [x] Observe API/behavior red under the shared lease; implement the conditional
  source branch. Prefix saturation selects one original closed fallback.
- [x] Run affected full native/capture packages under a lease, preserve skips and
  commit the integrated but default-off implementation for root review.

## Task 4: Matched offline local inference and activation gate

**Files:** opt-in `PrefixSpeechBenchmarkTests.swift`, own lane report; production
component factory only after the observed gate and root approval.

- [x] Add a no-download benchmark requiring the existing verified public cache
  and fictional WAVE. Use the exact same warmed model/accept partition and paced
  input for baseline/prefix comparisons; cold setup is separate. Opt-out compile
  exits 0 with exactly one early guarded skip, 0.003 s; no actual run yet.
- [x] Record original start/end indices, full text equality, prefix/tail/fallback
  counts, endpoint→ASR-final, both sources overlapping and actual process RSS.
  Failures stay in the report. No p95 or full-app/account speed claim.
- [x] Run under one root heavy lease with reserved staging/resource budget and
  reused inputs. Stop on unexpected allocation/error; no download/rebuild loop.
- [x] Root independently reviews source and measured evidence. The one exact-667
  gate passed (135.629→40.602 ms closure→final median, exact words/cuts, no
  fallback/RSS increase). Root read the receipt and approved narrow actual-factory
  selection. The exact normal assembly helper now selects safePrefixes; generic
  components retain closedSpan. Full activation package passes 84/87 cases with
  three explicit model/download/benchmark skips, including actual selection
  behavior without model download.
- [x] Include a broader actual speech regression of the normal assembly in final
  acceptance. Controller checkpoint 7302dcf passes actual WAVE→normal prefix
  assembly→helper/synthetic answer→reducer in 6.353 s, original assertions/input
  unchanged. Do not relabel it as full app/window/cloud/usefulness latency.

## Task 5: Actual Model and protected-account response gate

**Files:** preserved four-case ResponseLatencyApplicationTests, shared Model seam
owned by Memory/root, existing EVALS prompt comparison and own evidence report.

- [x] Four actual Model cases observed missing-readonly-API red in 59.903 s.
- [ ] Import only root-accepted shared Model hooks, keeping post-accept original
  owner/currentness checks outside the native publication lock.
- [ ] Under lease run the unchanged four cases and original publication/held
  image/watchdog controls; keep window state distinct from paint/usefulness.
- [ ] Root coordinates current explicit protected account setup and bounded
  synthetic comparison; no credential fallback or live call before authorization.
- [ ] Review matched actual results and preserve all failures. Current worker
  model remains Sol 6.1 xhigh; normal runtime model/effort default is unchanged
  unless separately supported by measured correctness and root approval.
