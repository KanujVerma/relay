# Parallel delivery plan

Status 2026-10-23: owner-approved implementation is underway. [BUILD_STATUS](BUILD_STATUS.md) records published lane heads and remaining gates; [BUILD_CONTRACT](BUILD_CONTRACT.md) is the frozen shared implementation contract. [HANDOFF](../HANDOFF.md) owns actual repository status.

## Approved target

One automatic permitted interview companion: listen throughout the conversation, understand technical/résumé/explanation requests and natural follow-ups, retrieve the relevant user/job context, and present concise suggestions. This includes **both** reviewed technical references and open-ended generated answers behind one experience. No manual question-confirmation milestone. The first useful integrated version needs verified personal grounding as well as general technical answers. GPT-6.1 Sol extra-high or higher for every worker. Controller manages dependencies, review, integration and durable GitHub documentation. Research relevant open-source source/tests before new architecture and record reuse/version/license. The owner also authorized frequent coherent commits/pushes within agreed scope; update the durable handoff at each checkpoint, with no repeated routine-publication approval.

## Three worker slots and ownership

The current environment supports three simultaneous workers plus the controller. Rotate a slot for fixes or independent review rather than creating a fourth concurrent writer. Each lane is one issue/branch/isolated checkout and reviewable PR. The owner approved the three core features and directed implementation. Runtime changes still require verification and independent review.

| Lane | Runnable end-to-end outcome | Exclusive write scope |
| --- | --- | --- |
| Existing fixes, completed locally and published | PR46 quarantine diagnostic and PR49 stop/reset invalidation repaired and verified | Existing adapter/ASR repair files and tests; current published status is in HANDOFF |
| Continuous conversation | Separate user/remote capture -> local transcript -> bounded conversation context and question/follow-up/correction events | Native session/audio/VAD/provenance and coordinated question-state seams; native inputs do not assert biometric speaker identity |
| Personal and job context | Explicitly selected résumé/project/job inputs -> reviewed source-backed facts -> relevant per-question retrieval | Native preparation/import/approval boundary, existing Personal Brain/converters, retrieval and source-revocation tests; production storage/import design still required |
| Contextual answers and panel | Current question + live conversation + relevant verified background -> concise technical/personal suggestion in the actual window | One answer/router/helper/display path, generated-answer policy, reviewed-reference integration, context/coverage/freshness evaluation |
| Reviewed reference expansion, rotated slot | Reusable tested SQL/coding examples improve speed/quality inside the same engine | Catalog content and independent executable/labeled evaluation after a core lane frees capacity |
| Controller | Joined integration and source-of-truth state | Shared schema/golden fixtures, manifest wiring, HANDOFF/ADRs/roadmap and review coordination |

The owner approved this revised core assignment after clarifying the full conversational goal. It changes the earlier steady-state split that assigned two slots to separate answer paths while postponing personal context. Both answer paths remain in scope and use the same engine; separate user-visible modes or a fixed question bank are not the product. The earlier dedicated-reference-worker preference can be satisfied by rotating that work into the next free slot rather than displacing the personal-context foundation.

Three workers can build against agreed synthetic interfaces in parallel. Real private imports and capture remain gated by their explicit native permission, storage and source-approval implementation; the product requirement does not authorize loading private data into the current synthetic store. A finished worker becomes an independent reviewer. No simultaneous writers to the same shared source file.

## Current end-to-end owners

This table supersedes historical lane assignments above for the active feature work. Each worker uses GPT-6.1 Sol xhigh and an isolated checkout/branch. All three may build their complete feature through its app surface. Overlapping Model/transport changes stay on separate branches; root independently reviews and reconciles them into the controller checkout. Root does not serially take every app join away from a worker.

| Worker | Feature and branch | Current review boundary |
| --- | --- | --- |
| research_visual_inputs | Protected account/idle join, PR95 `feature/account-idle-integration-2026-10-23` | Accepted300c joined15d6f6d, exact715Python/188native gates. Complete frozen300c artifact; next first-launch Connect entry design only. Preserve immutable ownerBox/max4profileflight, account helper-only retirement and no real account calls. |
| review_composition | Response preferences, PR96 `feature/response-preferences-2026-10-23` | Idle4972 and terminala37 accepted/joined, actual bundled UI checked. Full modes design5e095 approved on frozen3e83; own protected preferences/coordinator/Settings/Model/helper/prompt/retirement end to end. General automatic; explicit built-in Use shares Save/use creation action. Reuse accepted194. |
| compose_context_controls | Local history, PR93 `feature/local-session-history-2026-10-23` | Résumé complete/joined. Frozenac70 history primitive194 accepted55profile+independent GRDB probe; ledger269 under separate review. Own coordinator/issued observation/Model/Home/Settings/manual notes/export/delete. Generated notes require separate contract. |
| Root | Joined PR71, documentation and independent verification | Integration checkout is root-only. Freeze author checkpoints before review; publish evidence, reconcile accepted changes and preserve actual child/source lifetime checks. Main merge remains separate. |

## Accepted implementation direction

Keep native permission/capture/transcription/window ownership in Swift. Reuse Relay's existing Python question state, OAuth and QA through one local child helper, with bounded framed messages on inherited pipes. No new server or full application framework is needed for this transport. Compare any proposed dependency with the existing implementation before adding it.

One contextual engine uses a bounded recent conversation and a compact running summary, the complete current request, relevant verified personal facts, and role/job context. It must understand references to the user's own latest answer and distinguish current constraints from superseded ones. A coverage-complete reviewed reference may be reused; other supported questions use the model path under an explicit publication policy. Both paths produce one typed answer decision. The normal panel stays consistent: concise lead, useful talking points, optional code/detail. Source and uncertainty details can be quiet provenance rather than extra user-operated modes. Personal assertions must be supported by the retrieved verified background; missing facts produce an honest limitation or useful clarification, not fabricated achievements.

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

## Product decisions to discuss

1. Before the interview, prepare selected résumé/projects/job description and resolve important factual gaps. The user should not reconfirm every question during the interview.
2. During the session, retain bounded recent dialogue and a running summary of topic, user answers, question constraints and unresolved follow-ups. Live speech/model text is conversation evidence, never automatic biography verification.
3. Detect requests and follow-ups automatically; allow silence/ordinary conversation without producing constant cards. Clear superseded suggestions on an observed correction or interruption.
4. General knowledge and personal grounding feed the same answer writer. Provenance remains available without making the user manage reviewed/generated modes.

## Work order and acceptance

1. Finish and independently review existing repairs. Publish and verify exact repaired heads; update HANDOFF with real links/checks. Current repaired PR heads are already published; remote gates remain distinct.
2. Freeze the smallest shared session and answer fixtures, limits, ownership and provenance semantics. Agree the new generated-answer publication policy.
3. Build the three core lanes independently with fake source/model/import interfaces and offline tests. Include selected source review/retrieval rather than indefinitely expanding prewritten question coverage. Panel work must run a real helper process with synthetic input, not only a mock sample-card button.
4. Join on one exact integration head. Test already-visible answer cancellation while capture, helper, model completion, pipe delivery and MainActor commit are delayed independently. Stop/resume, overlap, blank finals, malformed/replayed events, source gaps and child exit must not resurrect content.
5. Run a natural authorized mock interview mixing technical questions, résumé/project questions, references to the user's previous answer, multi-part requests and corrections. This is the first useful end-to-end acceptance; a single D02 card is only a connection test. Measure on M2 Pro: transcript accuracy, automatic route outcomes, correct visible cards, final-to-display timing, resource use and drop/discontinuity counts. Keep first-text, ASR-final, model-complete and useful-visible-answer timings distinct. No p95 claim without an adequate observed sample.

Deferred breadth: bulk/new connectors, automatic biography promotion, a complete continuous-learning runtime, stealth behavior and wholesale app/framework replacement. Explicitly selected personal sources and verified retrieval are required for the first useful product, after the real import/storage/approval boundary is implemented.

## Evidence and continuation

Use [UPSTREAM_REUSE](research/UPSTREAM_REUSE.md) for research evidence and [SLICES](SLICES.md) for the broader roadmap. Each slice must record exact base/head, scoped files, commands/results/skips, independent findings, implementation status and one next action. Keep a single canonical contract per shared interface; link to it instead of copying incompatible definitions into every lane document.

## Additional owner requests

The live flow must also support coding with an engineer (clarify, explain an approach, solve, discuss improvements) and feature case studies (users, requirements, behavior, trade-offs). Optional selected screen context is issue #64; shortcuts/app controls are issue #65; separate REA investigation is issue #66. [Cluely research](research/CLUELY_LESSONS.md) records evidence and limits. These additions use separate workers as the three available runtime slots free; current slot limits are an orchestration constraint, not a product architecture choice.
