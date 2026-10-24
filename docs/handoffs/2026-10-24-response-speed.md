# Response speed continuation

2026-10-24, Relay, branch `feature/response-latency-2026-10-24`.
Verified published source: `18f982c672a1c4671203af86a1a2e659be6640e2`.
Verify live Git before continuation; this record accompanies the guarded
benchmark checkpoint following that source commit.

## GOAL

Finish actual end-to-end response-speed work, not merely telemetry or the small
client-setup improvement. Preserve correctness, exact native provenance, stale
answer denial and actual cleanup. Product timing targets remain unachieved.

## DONE

- `a8fb232` retains the helper-owned client and immutable transport timings;
  `3f634c0` denies image validation after transport close. Exact focused close
  gate passed 141 tests / zero skips / 3.957 s. Local matched loopback warm
  component medians 5.701→1.703 ms are setup-only, not model/app performance.
- `23bf594` adds optional helper/native stage timing and soft compact guidance;
  `591495a` documents exact wire semantics. `python -m unittest discover -s tests`
  passed 777 collected / 745 passed / 32 optional skips / 10.027 s. Native panel
  package gate passed 94 collected / 93 passed / one artifact skip / 7.625 s;
  app targets compiled with zero selected app cases, not actual Model acceptance.
- Actual four-case Model API-red exited 1 / 59.903 s because the coordinated
  `responseLatencySamples` view is missing. Local receipt is
  `response-latency-actual-model-api-red.log`; no passing claim.
- `9e07e11` freezes pinned-source ASR cutoff design/metadata fixtures and current
  official None/Low documentation. `python -m unittest tests.test_asr_prefix_design
  tests.test_effort` passed 13 / zero skips / 0.072 s; metadata covers 9,841
  bounded probability-class sequences, not actual Swift/model acceptance.
- `9829c58` freezes root-approved implementation plan, including mandatory one
  local closed-span fallback on optimization-only PCM queue pressure.
- `43f2c99` adds an inert owned prefix lane. Coordinated native command selected
  `ActivityPreprocessingTests` in `spikes/macos-session`: API-red exited 1 in
  13.258 s; green passed four / zero skips / 0.024 s (37.776 s including build).
  Local receipts: `asr-prefix-core-api-red.log`, `asr-prefix-core-first-green.log`.
  Original exact commands/resource receipts remain in local coordination data.
- `python EVALS/verify_docs.py` passes 20 required files and all local Markdown
  links; `git diff --check` passed before the checkpoint.
- Adapter API-red exited 1 in 40.857 s; an unrelated fixture expression was
  simplified without changing its sequence/assertions. Matching green passed
  five new actual pinned/no-model VAD+prefix cases, three legacy Fluid cases and
  four lane cases: 12 / zero skips; 0.056 s capture + 0.022 s core, 8.543 s command.
  Receipt: `asr-prefix-fluid-first-green.log`. No actual model weights loaded.
- Conditional source API-red exited 1 / 40.339 s on missing recognitionMode.
  Full green: 85 collected / 83 passed / two explicit model/download skips;
  native 47 pass / 0.977 s and capture 36/38 pass / 0.414 s, 13.937 s command.
  Receipt: `asr-prefix-source-full-green.log`. Ten new native cases include actual
  stop/join, two-source independence, original late-final identity, queue-pressure
  local fallback and release of the retired recognizer graph.
- Guarded benchmark compiled: Swift 0 / 39.907 s, exactly one early opt-out skip
  / zero failures / 0.003 s. Receipt: `asr-prefix-benchmark-optout.log`. No cache,
  audio, model or child action. Actual model comparison remains unexecuted.

## IN PROGRESS

Active plan: [safe-prefix ASR](../superpowers/plans/2026-10-24-safe-prefix-asr.md).
Approved [design](../superpowers/specs/2026-10-24-lagged-asr-preprocessing-design.md).
Tasks 1–3 are verified foundations. SourcePipeline has a conditional path;
SourceComponents defaults to closedSpan and normal factory remains unchanged.
Task 4 real paced public-WAVE comparison/RSS is prepared and root source-reviewed.
The benchmark has compiled and safely opted out. One separately granted actual
model run is next, with root's reviewed reporting controls and existing inputs.

## AT RISK

The actual Model four-case fixture remains uncommitted in
`spikes/macos-panel/Tests/RelaySessionApplicationTests/ResponseLatencyApplicationTests.swift`
and intentionally cannot compile until the shared observation seam joins.
The benchmark code compiles/guards only; no actual model/performance success is
claimed. Do not activate the normal factory from its opt-out result.

## DECISIONS

- Use actual returned VAD state: `min(P-C,S+B-C when pending)`, clamp at the
  original start; no prefix watermark at end. Fixed lag alone fails long
  middle-band hysteresis. Keep existing silence/padding/model weights.
- Keep one existing manager/serial lane per source, two independent states for
  two sources. No new framework/download/model state or before-permission ASR.
- On `offer == false`, stop advancing/feeding prefixes for that activity. Join
  actual accept, then reset and run the retained complete closed span once at
  actual closure. No capture fault solely from optimization PCM capacity and
  no provider retry. Invalid watermark/source/gap/model state remains fail closed.
- Source integration must use capture/source `isActive`, never old display-lease
  currentness. Legitimate old final can remain history-only after new onset.
- Native `onEnd` precedes lane close. Recheck source/failed/original key after
  every awaited lane call before indexing history that cancel can clear.
- Keep implementation default-off until exact text/cutoff, paced existing WAVE,
  two-source independence, remaining sample counts and actual RSS pass.
- Benchmark uses only the unchanged installed fictional WAVE, SHA-256
  `98f0000e24688c1e665bd90de70d99b378b661bb749b483aeeed90cd5b2be9c7`,
  39,516 mono Float32 samples at 16 kHz (read-only afinfo observation). Root
  confirmed the existing real public cache, manifest
  `parakeet-eou320-silero621-v1`, 21 hashes / 225,301,695 bytes. No file copies,
  TTS, trim/repeat, playback, downloads or private-source/account operation.
- Controlled benchmark has sequential baseline/prefix children, each with two
  existing ASR managers, fresh VAD states per trial, one declared native warm-up
  and two unchanged paced trials. Report 8,000 leading / 32,000 trailing zeros,
  actual per-source paced count and final-packet padding. Check treatment mode,
  baseline one legacy call / zero prefix acknowledgements, exact words/cuts,
  >10% median native-end→final improvement, no normal-rate local fallback and
  <=256 MiB peak-RSS increase. Report all outcomes; no automatic real-gate rerun.

## STANDING INSTRUCTIONS

Root coordinates every heavy lease; one job globally, reused retained caches,
jobs 2, 180 s external deadline, fresh 30 GiB free / 25 GiB aggregate temporary
limit and reserved staging. No heavy job is active at this handoff. Use existing
Python/public inputs. No real account/Keychain/capture/inference call, download,
new environment/cache, source deletion or main merge without its separate scope.
Frequent verified scoped commits/pushes are authorized. Worker remains Sol 6.1
xhigh; runtime default effort is unchanged. Notes owns its later typed transport
permit delta; this lane currently does not edit OAuth transport. Root/Memory own
the single Model observation hook outside the native publication lock.

## NEXT STEP

Obtain the separate actual-model lease to select PrefixSpeechBenchmarkTests with
root's confirmed unchanged public inputs and the controlled opt-in. Do not rerun
a failed real gate automatically. Run unchanged Model fixtures when the accepted shared
observation seam arrives. Keep normal factory closedSpan until measured approval.

## OPEN QUESTIONS

No architecture clarification is blocking implementation. Root must coordinate
the accepted Model hook and eventual protected-account comparison; measured
ASR/end-to-end speed and resource benefit remain unknown until those gates.
