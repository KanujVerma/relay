# Parallel delivery plan

Status 2026-10-23: approved goals, proposed implementation. No new native/session, expanded reviewed-answer or open-ended-answer feature code has been built in this planning effort. [HANDOFF](../HANDOFF.md) owns actual repository status.

## Approved target

Automatic permitted audio -> question -> visible answer, with **both** a reviewed SQL/coding path and an open-ended model path. No manual question-confirmation milestone. GPT-6.1 Sol extra-high or higher for every worker. Controller manages dependencies, review, integration and durable GitHub documentation. Research relevant open-source source/tests before new architecture and record reuse/version/license. The owner also authorized frequent coherent commits/pushes within agreed scope; update the durable handoff at each checkpoint, with no repeated routine-publication approval.

## Three worker slots and ownership

The current environment supports three simultaneous workers plus the controller. Rotate a slot for fixes or independent review rather than creating a fourth concurrent writer. Each lane is one issue/branch/isolated checkout and reviewable PR. Implementation starts only after its concrete design is agreed.

| Lane | Runnable end-to-end outcome | Exclusive write scope |
| --- | --- | --- |
| Existing fixes, first | PR46 quarantine diagnostic and PR49 stop/reset invalidation repaired and verified | Existing adapter/ASR fix files and their tests; no new features |
| Native session | Selected app -> bounded owned PCM -> local VAD/ASR -> versioned source/control events | New native session package, native clock/serializer/lifecycle/VAD adapter/tests; coordinated ASR provenance seam after repairs |
| Reviewed answers and panel | Typed final -> complete reviewed technical match -> actual visible SwiftUI card | Reviewed catalog/evaluations, Python host/bridge, native panel reducer/view/transport; single UI owner |
| Open-ended answers | Typed technical question -> one existing authorized model request -> validated generated card | Dynamic answer orchestration, model-output assembly/validation and held-out evaluation; same router/card contract as reviewed lane |
| Controller | Joined integration and source-of-truth state | Shared schema/golden fixtures, manifest wiring, HANDOFF/ADRs/roadmap and review coordination |

The fixes slot initially replaces native implementation capacity. After repair review, the steady state is native session, reviewed answers/panel, and open-ended answers. A finished worker becomes an independent reviewer. Never edit the same source file from two lanes; controller explicitly assigns small shared-file seams.

## Proposed architecture for discussion

Keep native permission/capture/transcription/window ownership in Swift. Reuse Relay's existing Python question state, OAuth and QA through one local child helper, with bounded framed messages on inherited pipes. No new server or full application framework is needed for this transport. Compare any proposed dependency with the existing implementation before adding it.

One router selects a coverage-complete reviewed answer first; unmatched supported technical questions may use the open-ended model path under its new publication policy. Both paths produce one typed answer decision. The native panel clearly distinguishes reviewed-reference provenance from generated suggestions. Personal claims remain blocked without verified Personal Brain evidence.

### Shared contract and cancellation

[SESSION_BRIDGE](SESSION_BRIDGE.md) is the canonical proposed schema/display contract. [GENERATED_ANSWERS](GENERATED_ANSWERS.md) is the canonical proposed dynamic publication policy; do not copy divergent field lists into lane docs.

- Preserve the exact existing 13-key native EOU v1 payload. A separately versioned outer session envelope carries native session ID, lifecycle epoch, event sequence, presentation generation and typed controls.
- Stamp identities at native creation/admission, not delivery. Keep capture generation, Python TurnToken generation and native display generation distinct. Detect replay, overflow, gaps and worker/session restart.
- True speech onset invalidates native display admission before an asynchronous helper round trip. Reuse PR46's `remote_speech_started` context suspension. Prove VAD activity-to-final source-range association; do not relabel IDs or attach a late final to the newest onset.
- Reuse the single Python ActiveTurns and actual in-process ReferenceCard objects. Python publication checks happen before serialization; the native admission check plus synchronous panel reducer commit is an additional display gate. A JSON copy is not Python object identity or a remote actual-paint check.
- Stop, permission/source loss, blank/unknown terminal, malformed input, queue overflow and helper failure retire affected authority and clear stale output. Native-observed cancellation is the guarantee boundary, not physical speech before detection or simultaneous cross-process pixels.
- All queues, frames, retained context and decoded text have explicit tested bounds. A slow consumer cannot silently drop a control marker and later publish an apparently successful question.
- ASR confidence stays null when absent. A versioned evaluated intent/eligibility strategy may accept supported input without pretending it has ASR confidence. VAD probability cannot fill that field.

### Answer contract

Proposed common content: short lead, up to two points, optional bounded prose/code detail, fixed decision/reason, originating native request/fences, Python turn identity and host-controlled provenance. Reviewed references and generated suggestions are separate states; a model cannot choose its own reviewed status or source authority. Exact bounds and status names are still proposals to reconcile with existing native limits.

The existing D02 reference proves the first connection only. The reviewed lane should add executable binary search and SQL joins/NULL/fanout/grouping cases with positive and negative full-question/constraint examples. The open-ended lane needs a distinct generated-answer policy; do not set personal classification to absent just to make arbitrary output pass. No mandatory second model call is assumed. A completed stream and local schema checks do not certify technical truth.

The current blocking urllib SSE loop checks freshness only after another event arrives. Discuss a cancellable adapter that reuses official OAuth/payload semantics versus a single bounded blocking worker with slower recovery. Cancellation can suppress local output; it does not prove upstream compute or token use stopped. No automatic API-key fallback or hidden retry/repair model call.

## Work order and acceptance

1. Finish and independently review existing repairs. Publish and verify exact repaired heads; update HANDOFF with real links/checks. Current repaired PR heads are already published; remote gates remain distinct.
2. Freeze the smallest shared session and answer fixtures, limits, ownership and provenance semantics. Agree the new generated-answer publication policy.
3. Build the three lanes independently with fake source/model processes and offline tests. Panel work must run a real helper process with synthetic input, not only a mock sample-card button.
4. Join on one exact integration head. Test already-visible answer cancellation while capture, helper, model completion, pipe delivery and MainActor commit are delayed independently. Stop/resume, overlap, blank finals, malformed/replayed events, source gaps and child exit must not resurrect content.
5. Measure an explicitly authorized synthetic selected-app speech session on M2 Pro: transcript accuracy, automatic route outcomes, correct visible cards, final-to-display timing, resource use and drop/discontinuity counts. Keep first-text, ASR-final, model-complete and useful-visible-answer timings distinct. No p95 claim without an adequate observed sample.

Current non-goals for these lanes: real private résumé imports, new connectors, automatic biography promotion, continuous-learning runtime, stealth behavior and wholesale app/framework replacement.

## Evidence and continuation

Use [UPSTREAM_REUSE](research/UPSTREAM_REUSE.md) for research evidence and [SLICES](SLICES.md) for the broader roadmap. Each slice must record exact base/head, scoped files, commands/results/skips, independent findings, implementation status and one next action. Keep a single canonical contract per shared interface; link to it instead of copying incompatible definitions into every lane document.
