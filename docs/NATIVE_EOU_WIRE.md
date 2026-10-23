# Proposed native EOU wire contract, 03B-B1A

Status: independent, **offline/synthetic only**. Parent issue #43 has a separate
stacked Python event/intent adapter in PR #46 and Swift on-device EOU audio
work in PR #49. Both are owned by other agents. This contract does **not**
connect or modify them, does not authorize real meeting capture, and does not
turn an ASR result into a verified interview question or answer.

Implementation: relay_spike/native_eou_wire.py
Tests: tests/test_native_eou_wire.py
Scope: child issue #51, a follow-up to issue #43.

## Why this is needed

The actual Swift source in PR #49 currently exposes FinalTranscriptEvent with:

| Swift field | Actual meaning |
| --- | --- |
| status | final, discontinuity or unavailable, not streaming text partial |
| source (PCMSource) | 1 = microphone, 2 = remoteAudio (selected-app output), not speaker identity |
| streamGeneration, segmentID, revision | UInt64 identifiers, not user evidence |
| startHostTime, endHostTime | optional Core Audio host-clock ticks, NOT Unix milliseconds or guaranteed nanoseconds |
| finalizedUptimeNanoseconds | DispatchTime monotonic uptime nanoseconds |
| text, confidence | optional, no calibrated model confidence in the current EOU manager |

PR #46's Python synthetic EOU bridge expects a single monotonic millisecond
domain for start/end/finalization/reception and uses nil confidence to fail
closed to review. Dividing host ticks by 1 million or treating them as already
in DispatchTime's epoch would silently invent latency/order metrics. A real
host-owned boundary must explicitly calibrate and serialize these clocks.

**Observed source gap:** PR #49's PCMTranscriptWorker.finalize() currently
discards successful EOU results with empty text by returning nil. PR #46
expects an explicit terminal blank-final event to invalidate stale answers.
This was reported in PR #49's review comments. The present Python validator
can represent a blank final, but it does NOT cause the Swift worker to emit
one. Don't assume that interface gap is closed until a reviewed native fix
and synthetic Mac regression land.

## Proposed, versioned host envelope

A future trusted **native host** must attach the following bounded, UTF-8
JSON object. This is not a wire format that current PR #49 already emits:

| Field | Allowed values |
| --- | --- |
| version | integer 1, exact schema |
| status | final / unavailable / discontinuity |
| sourceCode | integer 1 or 2, matching upstream PCMSource |
| streamGeneration, segmentID, revision | unsigned 64-bit integers, not bools |
| startHostTime, endHostTime | both unsigned host ticks or both null |
| finalizedUptimeNanoseconds | unsigned 64-bit native monotonic uptime |
| receivedUptimeNanoseconds | unsigned 64-bit local receive uptime sampled by native host |
| text | final UTF-8 text up to 1,200 Unicode characters, or null/empty; null for control |
| confidence | null or finite numeric 0 to 1; do NOT infer it from a fabricated quality score |
| timebase | null for control; required explicit native host calibration for finals |

The timebase object has exactly four unsigned/integer fields: hostTicksAtAnchor,
uptimeNsAtAnchor, nsNumer and nsDenom. The last two are a positive bounded
ticks-to-nanoseconds ratio obtained from the native OS timebase. A host clock
anchor must be sampled at roughly the same instant on **both** counters and
be no more than 10 minutes from transcript finalization. The decoder computes:

    monotonic_ns = uptimeNsAtAnchor
                   + floor((host_ticks - hostTicksAtAnchor) * nsNumer / nsDenom)

This prevents accidental raw-tick division by 1e6. It does not prove the
native host sampled the counters correctly or establish physical user
presence. The writer should use public Core Audio/Darwin timebase APIs
(such as AudioConvertHostTimeToNanos/mach_timebase_info), without introducing
private TCC or stealth recording techniques.

Required ordering: start <= end <= finalized <= received, all on this
one calibrated monotonic timeline. Conservative prototype caps are 120s
per utterance and 30s finalization lag; no inferred or invented missing
timestamps. The normalized output uses integer milliseconds and retains
null confidence as null. It does not compute a first-useful response metric.

## Fail-closed semantics

- Successful final EOU with empty/whitespace/missing recognized words is
  represented as a **blank_final** outcome, not silently dropped; a later
  integration must map it to PR #46's blank terminal review/tombstone path.
- An unavailable or discontinuity event has no user text or fabricated
  location; the caller must cancel/mark unavailable rather than invent an
  ASR question. These controls accept null host spans and no timebase.
- A normal nonblank final becomes only schema-valid, NOT inference-ready:
  NormalizedNativeEOU.can_auto_route is always false until external user
  permission, selected-source, question-intent, confidence and actual
  publishing gates independently pass.
- Duplicate or unknown JSON keys, embedded fake "authorized", "speakerID"
  or "verifiedPersonalClaim" fields, invalid UTF-8, NaN/Infinity, booleans
  masquerading as counters, mixed/missing clocks, reverse times, stale
  calibration, impossible audio durations, and raw secret-filled errors
  are all rejected. Error strings never echo transcript data.
- Nothing is persisted, logged, sent to a model, imported from a personal
  file, or read from a microphone. Synthetic tests use fabricated SQL
  questions only.

## Native integration dependency

Merge and complete review of parent PR #42, synthetic bridge PR #46 and
audio worker PR #49 separately. Next, the native owner needs to add an
explicit selected-app/user-consent source boundary and a serializer that
produces the host-calibrated envelope, handle true terminal blank EOU,
and map native status to the existing question-machine cancellation logic.
That serializer must be tested with actual authorized synthetic M2 Pro
capture and uptime/timebase calibration. Do not use this validator to claim
that a live Zoom question or an actual useful response was measured.

No external library was copied or vendored here. The existing Swift
FinalTranscriptEvent / PCMSource types and Python QA/ActiveTurns remain the
authoritative application components. This small stdlib adapter is
intentionally separate from Pipecat, LiveKit and generic speech servers,
which would introduce complexity without resolving host clock provenance.
