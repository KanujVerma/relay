# Standalone typed assistant: approved native noncapture lifetime

2026-10-23. Approved engineering direction, GPT-6.1 Sol extra-high; implementation is separate active work. Read-only baseline `db768fdeebb7f084b8619b2eae54d8aabebe0065` in `work/relay-idle-assistant-design-db768fd`; clean. The worker owns the full feature on its isolated branch; root owns independent review and integration reconciliation. **Recommendation: add an explicit noncapture scope to the existing helper, issued by a separate native controller/authority, and reuse the existing request worker/router/publication pipeline.** No runtime code or repository documentation changed. Root approved the explicit assistant namespace and optional owned preparation seams; the worker implements native/helper/transport/controller and the actual app owner/lifecycle/UI join on its isolated branch. Root independently reviews the frozen result and tests the actual GUI.

## Product boundary and current evidence

Typed Ask should work from Home, while audio is paused, and after audio becomes unavailable. Typing alone performs no IO. Explicit Send may start the bundled helper, restore existing opted-in protected context, and submit through the configured inference/reference/personal gates. It must not provision speech assets, load ASR/VAD, start audio capture, request recording permission or require recording-conversation consent. Audio Start remains a distinct action with its existing checks.

Current Relay is intentionally different: `NativeSessionController.issueUserQuestion` requires actual sources; the app's typed session closure requires running/not-stopping and an actual source. `SessionHost.live` and its question permission are initialized by an actual capture `session_started`, which resumes `SyntheticEOUBridge` with `CaptureContext('authorized', True)`. The typed `QuestionTurnMachine.begin_explicit_request` itself already creates a fresh semantic token without a transcript. Reuse that explicit method, not the capture authorization path.

The existing wire decoder accepts a structurally valid null selected app/false microphone configuration, but the native capture controller does not issue it. Sending a fabricated zero-source capture start would still grant capture-context authorization in the helper. It is not an implementation option. Do not loosen native source admission, manufacture EOU/activity/ASR timestamps, or mark a microphone active.

The inspected Cluely2.1.24 renderer supports ordinary chat-mode typed submission without an audio session. S18 file `dist/assets/chat-DIvku-qQ.js`, verified SHA-256 `805ede5bfe6f1ec47678f9f814534c727427f71bd9fd2a95d4eab13a0804b137`, bytes758098..758576: session presence controls optional partial-audio work and transcript context; the constructed message still reaches the ready-agent send or newest-pending/stop path when no session exists. Bytes758565..759000 vary blank-action copy, not typing permission. Authentication-loaded, agent error/persistent-disconnect and plan/client gating remain. Expanded dashboard/search inputs have separate callbacks. This is static client evidence only; no server acceptance, account, quota, OS behavior or proprietary implementation is adopted. Raw source stays local under the existing REA workspace; this proposal copies no competitor source/assets/prompts.

## Approaches

| Approach | Benefit | Cost / decision |
| --- | --- | --- |
| **Explicit assistant scope; existing bounded typed/answer envelopes** | Small new control plane, separate native owner, existing card/provider/one-worker/transport reuse; capture issuer and audio wire stay intact | Retains legacy identity field names in reused envelopes. Requires an explicit namespace contract and strict mode separation. **Recommended.** |
| Generalize all capture/assistant traffic to a new conversation wire/type family | Neutral identity names and one uniform abstraction | Migrates every audio/image/profile-adjacent binding/parser/publication test and increases the current regression surface. Unnecessary for genuine idle Ask. |

Both viable choices keep one actual helper and one inference worker. There is no second model client, voice SDK, model/runtime installation or hidden background recording scope.

## Proposed native and wire seam

Add `NativeAssistantSessionController` in macos-session's pure native target, independent of `NativeCaptureSession` and `NativeSessionController`. It owns its own `SessionPresentationAuthority`, native UUID, private state/lock, current request UUID, generation and small control sequence. No source pipelines, packet API, speech setup, ASR or VAD dependencies are used by this controller.

Proposed public operations, with privately constructed issued values:

```swift
begin(enqueue: @Sendable (NativeAssistantScopeRequest) throws -> Void)
    throws -> NativeAssistantScopeRequest
issueUserQuestion(expectedLease: PresentationLease, intent: UserQuestionIntent,
                  question: String?, baseRequestID: UUID?,
                  enqueue: @Sendable (NativeUserQuestionRequest) throws -> Void)
    throws -> NativeUserQuestionRequest
issueAnswerCancellation(expectedLease: PresentationLease, targetRequestID: UUID,
                        enqueue: @Sendable (NativeAnswerCancelRequest) throws -> Void)
    throws -> NativeAnswerCancelRequest
beginClose(enqueue: @Sendable (NativeAssistantScopeRequest) throws -> Void)
    throws -> NativeAssistantScopeRequest?
```

`beginClose` synchronously stops local issuance/publication before returning, even if enqueue fails; asynchronous close/waiter ownership belongs to the app/helper transport. Repeated close joins the same issued control. Enqueue under the controller lock only registers bounded ingress; it performs no helper IO or await. Open starts generation1/controlSequence1; typed/cancel issuance advances generation exactly like the existing issuer and anchors to that original assistant control sequence. Close captures its final retirement generation and controlSequence2, then withdraws local authority. This is a real assistant control counter, not an audio event or a mutation of audio's sequence.

Use a native `AssistantScopeLease`/owner wrapper to name the assistant ID at application boundaries. Internally its presentation lease can use the existing generic authority/reducer representation. Existing typed/cancel/answer envelopes keep their exact field sets: their legacy `captureSessionID` transport slot holds the actual assistant scope UUID **only in the explicitly opened assistant namespace**. It is not a claim that capture occurred. No `NativeSessionEvent.sessionStarted`, selectedBundleID, microphoneEnabled or CaptureContext is emitted or invented for it. The wrapper/controller must not expose an API that lets app code construct an issued typed/cancel value from JSON.

Proposed strict new control request has exactly nine keys:

```text
schemaVersion:1, kind:assistant_scope_request, action:open|close,
requestID, assistantSessionID, sessionEpoch,
presentationGeneration, controlSequence, emittedUptimeNanoseconds
```

Open reply has exactly `schemaVersion,kind:assistant_scope_response,action,requestID,assistantSessionID,sessionEpoch,presentationGeneration,controlSequence,status` (nine keys), with `status:ready|busy|unavailable`. Close reply adds `quiesced` (ten keys): only `status:closed,quiesced:true` confirms actual completion. An unavailable reply cannot assert quiescence. Counters are exact UInt64, UUIDs canonical, frames at most16KiB, native control freshness2s. Stamping happens immediately before enqueue, after optional preparation, so setup waits cannot consume request freshness.

Transport waiters are registered synchronously before ordered enqueue, owned by helper identity + request UUID + action + full scope/sequence/generation. Validate before removing a continuation. Exact replay shares pending/final results; changed UUID reuse fails the channel. Use the existing15s metadata/control deadline,512-operation ledger/eight latest reply budget and32-frame/256KiB writer/ingress bounds. A deadline/EOF/wrong-action/scope failure retires the actual helper and joins stop/reap; it never supplies a synthetic closed/quiesced receipt.

The legacy identity-slot compatibility is an explicit approval choice. If root requires neutral wire names everywhere, choose the second approach and budget the parser migration rather than quietly mixing namespaces.

## Helper: one mutually exclusive scope, same worker

Add a private helper scope kind (`capture` or `assistant`) beside the actual session identity. At most one is live. Opening assistant is accepted only after the previous scope's real completion; otherwise return busy without changing active capture/session state. It initializes a fresh bounded ConversationContext, QuestionTurnMachine/ActiveTurns and explicit-question ReferencePermission through a dedicated method. It does **not** resume or authorize SyntheticEOUBridge/CaptureContext. Typed permission represents this explicit input action; it grants no recording permission.

Reuse UserQuestionCoordinator for Ask/Help, fresh semantic tokens, eight read-only basis records/6000-byte ancestry,512 request/replay/denial budgets, provider retrieval, card QA and the existing one-active-worker/newest-pending budget. Existing capture initialization and audio identity/finality/activity checks remain unchanged. Native audio and legacy ManualHelp are inadmissible in assistant mode. Old-scope frames cannot mutate or retire a newer scope. Namespace checks precede any state-changing cross-mode transition; no boolean in a request grants a different mode.

Close synchronously retires active/pending request, supplemental observations/bytes, visual authority and semantic permission. It captures the actual worker/control task owner, then completes only after that owner, queued work/cancellation receipts and actual probe cleanup finish. Keep stdio responsive by owning this completion task instead of blocking the reader in an uncooperative inference await. Track the scope completion separately from the inference/cancellation task sets it drains, so it cannot await itself. Until completion, new scope open/new work returns busy. On failure, actual helper shutdown/reap is the fallback boundary. A timed-out close never authorizes a replacement.

Reuse the existing same-process ProfileBridge. Scope close locks/retire-protects profile through the existing app coordinator and preserves the user's use preference; it does not create a second store. The profile binding remains tied to its actual helper lifetime, distinct from the shorter assistant/capture scope lifetime. No earlier fact bundle, image observation/permit or semantic publication token moves into the next scope.

## Root-owned preparation, presentation and handoff

The current synchronous typed issue port cannot do helper/profile preparation before stamping. Add an **optional owned asynchronous preparation port** to TypedAssistantController while preserving its current active-session sync path/default initializer behavior:

```swift
canPrepareSession: @MainActor () -> Bool
prepareSession: @MainActor (_ intentID: UUID,
                            _ isCurrent: @escaping @MainActor () -> Bool) async throws -> PresentationLease
```

These are readiness/explicit-action ports, not native authority. `canSend` may offer an idle Send when a valid draft can begin this preparation. Only the real lease returned after readiness permits issuance. Capture draft text, revision, chosen basis and intent UUID before waiting. One preparation owns the task until actual cleanup returns. New edits remain editable and must not be silently sent, cleared or overwritten by old completion. Cancellation/End/Start/mode/account changes retire the intent synchronously; wait for its actual operation, including held profile response/control teardown, before availability returns.

First idle Send: validate local draft -> lazily ensure the existing bundled helper -> restore **only existing** opted-in context using the accepted current target/intent guards -> open assistant scope and validate its exact actual receipt -> synchronously recheck original intent, profile use/opened/not-busy/current binding and actual scope owner -> issue the fresh native typed request -> clear only the unchanged submitted draft. Lock or profile work during the open-receipt await must also withhold issuance and retire that empty scope. Missing/corrupt/denied opted-in context fails preparation with current recovery; Lock remains reachable. No native question is minted before these awaits. Default-off fixture/context stays zero operations until explicit Send; profile opt-out still skips key/vault work. No account credential is read merely by drafting/constructor/open metadata.

Keep the app's existing single bounded global ingress. Associate every queued callback/forwarder/composer/reducer with its **original owned conversation object**, not a mutable global current authority. Each owner contains its actual authority, panel/publication gate, current binding, forwarder and helper reference/identity. The assistant owner uses its own authority; capture retains its original authority/controller. Old owner callbacks check object identity/retired state before local clearing or publication. This is particularly necessary with one reused helper: helper identity alone cannot distinguish a late audio-source failure from a new assistant conversation.

Existing capture/assistant request denial and supplemental retirement must enqueue before local producer cancellation releases a held frame. New assistant requests may use fresh explicitly enabled current selected-text/OCR/PNG through the same composer and its assistant owner authority. Default remains off, image verification remains real/idle-only, and scope close revokes capability as today. No old pixels/receipt/source grant crosses the handoff. Pending image writes retain current-request/deadline/cancellation/whole-frame rules.

Transitions:

| Trigger | Required prefix and join | Next state |
| --- | --- | --- |
| Idle explicit Send | Prepare existing context, open native assistant scope, stamp after ready | Assistant active; audio not running |
| Audio still has a live source | Use existing capture-issued typed route | Same actual capture scope |
| Last audio source unavailable or user Pause | Retire audio admission/display; drain original native source/model/queue/helper scope before opening assistant | Idle-ready or retained unsent draft; no fake source |
| Audio Start while assistant active | Synchronously retire assistant issuance/display; actual close/worker/probe/context join first; then normal speech/source/consent checks and fresh audio start | Fresh capture scope |
| End/Quit | Retire both current preparation/owner, join, lock protected profile, stop/reap helper as current End policy | Home; preference retained |
| AI mode/account identity/sign-out | Retire original owner before configuration/credential replacement; join worker/helper ownership as required by existing policy | No automatic request replay; explicit new Send |
| Transport failure | Withdraw current owner immediately; actual stop/reap before replacement | Fixed recoverable error, draft retained |

Fresh scope boundaries reset helper dialogue/task/basis and cannot inherit old capture authority. Preserve an unsent draft and show its old basis unavailable until explicit Send as new, matching current Pause/Resume policy. Do not silently rebase. This first lifetime slice does not add persistent history or cross-scope semantic transfer. Assistant controls do not enter SessionTranscriptStore; typed/model text remains separate from actual audio finals. A new assistant scope can clear the old transient transcript read view, with a truthful not-listening state.

UI activity must distinguish capture running from assistant readiness/preparing/generating/closing. Use the actual controller snapshot for Send as new/Help/Stop, retaining d969's missing-authority basis preservation. No audio/recording consent is inferred from a typed action. AI off can still return reviewed references or currently supported personal answers; general model requests continue to require the configured existing OAuth path and actual credentials. No new paid-key fallback or account capability flag.

## Approved implementation ownership and acceptance

Worker ownership after seam approval: new native AssistantSessionController/issued control types/tests; new Python assistant-scope decoder/coordinator and narrow SessionHost dispatch/mode gate/tests; HelperTransport strict owned scope waiters/tests; bounded optional prepare port/tests in TypedAssistantController; lane handoff. The same worker owns SessionApplicationModel/owner selection/preparation/transition and UI on its isolated feature branch. Root retains the integration checkout, independent review/reconciliation and actual GUI verification. No capture controller/source gate, ASR/VAD/models, auth/store/provider policy or packaging architecture changes. Packaging should include new modules automatically through its existing collected package; verify that exact final bundle afterward.

Reviewable steps: first strict pure-native/helper scope foundation with unchanged capture regression controls; next owned transport/prepare API and draft/cancel negatives; then the worker actual app join and synthetic process proof before independent root review. Use fresh isolated implementation ownership/branch once assigned. This document is a design contract proposal, not an implementation plan or source acceptance claim.

Focused required cases:

- First typed Ask with no speech cache/source/recording consent: no speech prepare/download/load, microphone/process tap/TCC call, NativeSessionEvent or transcript row; actual helper reference/personal/completed mocked OAuth answers still follow their real gates.
- Default construction/draft editing: no helper/key/account/network operation. One explicit Send only; double Send and held preparation coalesce without duplicate issuance/model call. Changed draft/revision survives old readiness/error/cancel.
- Strict begin/close request/reply/replay domains; wrong UUID/session/epoch/action/control sequence/generation/EOF resolves original waiter with error, validates before removal, no orphan continuation or invented success.
- Close held behind an uncooperative worker/probe/profile receipt: synchronous display/issuance retirement, actual close not complete, Audio Start blocked; release then actual join permits fresh capture. Failure requires actual child gone/reaped before replacement.
- Capture->assistant and assistant->capture use the same helper and one worker; real captured old native callbacks, late errors, receipts and optional image callbacks cannot clear/paint/upload into the new owner. No fabricated onset/EOU fixtures.
- Old audio/basis token/image/permit cannot authorize assistant work. Fresh native IDs/tokens/source observation and same final synchronous publication check are required. Cross-mode audio/ManualHelp rejection and existing audio source/sequence/closed-activity negatives stay unchanged.
- Native last-source loss permits standalone Ask only after real source teardown; d969 direct-command preservation remains true while transitioning/unavailable. Explicit new question works after real readiness.
- Explicit Lock during idle preparation/answer retires personal support and blocks old publication; missing enabled vault never creates key/vault or silently ignores preference. End/AI/account replacement joins old helper/provider and never resends a draft automatically.
- Actual packaged helper from a relocated non-repository CWD supports first idle reference/text request and owned close with fake credentials/completion only; no system Python or speech weights needed.

## Primary reuse verification and limits

Existing runtime reuse is Relay's pinned native presentation/typed issuer patterns, QuestionTurnMachine.begin_explicit_request, UserQuestionCoordinator, original one-worker SessionHost, provider/reference/card QA, profile coordinator and bounded transport. No new external runtime/library is selected.

Vercel AI SDK is a reference for request lifecycle, not an adopted dependency. Exact commit `84d788027f44a87a489d14bb2aea194b284ac1d0` was fetched through the GitHub connector after web/raw cache misses: [chat.ts740-810](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.ts#L740), blob `96c56aaed1462d3503154a513c4189b990d99e23`; [tests1210-1335](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.test.ts#L1210), blob `3f8a9c46b08a00832b3b3088f66efe79b71b611e`; [Apache-2.0 notice](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/LICENSE), blob `6c16c29f41168411dbf6e3ba3a063ce789c27334`. Stop aborts owned work and waits for request completion and executor drain; its tests verify completion before Stop resolves. This supports retaining actual quiescence rather than a UI-only stopped flag. No source was copied, modified or invoked.

Current [official AI SDK chat documentation](https://ai-sdk.dev/docs/ai-sdk-ui/chatbot) separately describes local input/status and explicit Send/Stop controls. Its UI streaming semantics are not adopted: Relay keeps completed-response/card QA and current native final publication. Current [Cluely Quickstart](https://docs.cluely.com/quickstart) remains call-oriented and does not by itself establish idle server behavior; the scoped renderer evidence above is the actual client premise.

No implementation, speculative model/API call, capture, OS permission, private file/profile/account/Keychain read, model download/load, source/index/HEAD mutation, commit/push or additional agent occurred. Research read public upstream source/docs and the already authorized local REA artifact. The source checkout remains clean. The controller has now approved explicit assistant control/legacy-envelope namespace compatibility and the optional owned preparation API, as amended below. Implementation proceeds without changing recording guards.

## Controller approval amendment

The controller approved explicit assistant open/close control and legacy typed/answer identity slots only inside the genuinely opened assistant namespace, rather than a broad wire-v2 migration. The separate native authority must not create an audio event/CaptureContext or relax capture admission. Optional owned preparation preserves the existing active-sync/default initializer path. Preserve original draft text, revision and chosen basis until actual issuance, including failed/cancelled Send-as-new preparation. Eligibility alone must not discard basis. New edits survive old readiness/completion. Root retains Model/UI/actual scope-owner and transition integration; this engineering decision implements the owner-authorized feature and is not a claim of finished behavior.

Implementation branch feature/idle-assistant-scope-2026-10-23 starts at frozen build/idle-assistant-foundation-2026-10-23, exactdb768fdeebb7f084b8619b2eae54d8aabebe0065. Native/helper strict scope first, then transport/owned preparation, each published/reviewed before the actual root join.
