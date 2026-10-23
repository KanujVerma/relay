# Typed questions, quick Help and live activity

2026-10-23. **Approved active-session implementation contract with the controller amendments below.** Owner explicitly requested Cluely-style functionality and implementation. Preserve the exact source/authority boundaries; do not treat an old request as renewed authority. Runtime baseline: `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`; shared parity contract: `0d68368833558ac1753e273c66deb80d5c030643`.

## Controller amendments and ownership

The draft-basis proposal below is amended to avoid repeated confirmation while an interview keeps moving. A draft basis is read-only context, never authority. Never silently rebase it to another question. A visible basis chip may retain the originally chosen/displayed question; sending issues a fresh current native request/token. An ask basis can refer to a bounded retained same-session immutable request/task record even after its old token retires. Validate membership/session/epoch and re-retrieve/revalidate current personal/source context; do not revive an old lease/token, reuse stale pixels/permits, or treat old model output as personal evidence. Retain at most8 such records within existing bounded payload budgets. If the record is absent/expired or crosses session/epoch, preserve the draft and return context_unavailable; explicit send-as-new remains available. Help-current remains strict current-question semantics. Standalone ask with no basis starts fresh task constraints while receiving labelled current dialogue context.

Backend/native worker owns new typed-request/deny-only retirement/cancel schema and tests; narrow session_host admission/worker/result-replay dispatch; QuestionTurnMachine explicit semantic issuance; ConversationContext pure typed projection; native private request issuance in SessionController and new wire types/tests; ordered forwarder and HelperTransport owned cancellation parser/waiter; new injected TypedAssistantController/SessionTranscriptStore and focused tests. No auth/profile/vault/capture teardown/model-provisioning edits. No SessionApplicationModel edits during this foundation phase: root owns its later enum/receive/bind/command hooks after automatic source is accepted. Supply a concrete integration patch/guide with exact real ports, not runtime stubs. UI owner integrates top prompt/transcript only after working foundation and root hook.

The original stale-basis live-token check is replaced by the bounded historical-context rule above. Other exact frame schemas, fresh native issuance, retirement-before-held-release, one inference worker, actual targeted cancellation receipt, source/QA guards and transcript bounds remain required. Active-session v1 is a first functional step; idle/audio-unavailable Ask remains a required subsequent independent assistant-lifetime slice, not completed parity.

## Recommended first functional slice

Implement short typed questions and the real Help-current-question action during an active authorized session, plus Stop response, a bounded actual-final transcript and read-only current activity. Use the same helper, personal grounding, reviewed references, card QA, configured OAuth stream and one-worker/newest-pending budget. Keep ordinary draft editing local. The top56px prompt footprint is already reserved in the UI branch.

A new typed request must be distinct from manual_help_request and from every ASR/audio event. Do not make an arbitrary question pass the old equality check, manufacture EOU, reuse an EOU UUID, restamp a source lease, claim a speaker role, or add a model-supplied authority Boolean.

Three approaches were considered:

1. **Distinct user-request route over existing native authority and ingress, recommended.** Small explicit wire, native issuance, shared request engine and all existing gates; active-session scope is concrete.
2. **Accept arbitrary text in manual_help_request, rejected.** That branch deliberately proves an exact accepted current audio question; relaxing it obscures provenance and breaks its semantic-token contract.
3. **Introduce a general noncapture assistant lifetime now, defer.** Feasible with the same inference engine, but it needs distinct lifecycle/permission identifiers and helper/native publication ownership. Calling NativeSessionController.start with fake audio components or an invented capture UUID is not an acceptable shortcut.

Idle Ask and Ask after remote audio becomes unavailable are therefore explicit gaps in slice1. Keep them disabled with Start-session guidance. Microphone-only live sessions can support typed Ask after their real session_started, although they will not create automatic remote questions. Pause is inactive for Ask. A later standalone-assistant contract can remove the audio dependency without weakening capture authority.

## Existing code facts and actual reuse

- NativeManualHelpRequest has internal construction,500-byte text, original lease/request/anchor/time fields. SessionController.issueManualHelp checks the exact forwarded sequence and current lease, then advances only presentation generation. Its callback must synchronously enqueue bounded work.
- SessionHost.handle_manual_help also requires exact equality with previous.display_question and a current audio QuestionTurnMachine snapshot/token. The test that rejects Invent a different question must remain unchanged.
- SessionIngress, MainEventQueue and OrderedContextForwarder already carry manual requests without consuming audio eventSequence. MainEventQueue submits to the main serial queue synchronously inside each controller-locked callback. Original source events retain their original order and leases.
- SessionAnswerDecision has exactly16 fields, pending revision1 and terminal revision2. PanelRequestBinding, synchronous native lease/commit, original-context ownership and the bounded final context recheck already exist.
- SessionHost._current checks the original Request object, active semantic token, native session/presentation, personal bundle and visual authority. Its worker drains cancelled work before starting newest pending work. Reuse this engine, not a second model loop.
- ConversationContext currently accepts remote/microphone observations only. Typed text must not enter either source channel or mutate the actual recorded audio task.
- QuestionContextComposer, SupplementalContextProvider and verified visual permit/transport already stage selected text/OCR/PNG for an original request. Reuse those exact gates; selected text remains text-only, and the image path still requires valid OCR.

Primary external code/tests inspected: Vercel AI SDK public commit `84d788027f44a87a489d14bb2aea194b284ac1d0`, Apache-2.0, license actually read. Its [chat implementation](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.ts#L769) waits for actual request completion and queued processing after cancellation. Its [tests](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.test.ts#L1224) cover stop completion, cancellation during preparation and overlapping resumed responses. This supports the cancellation design; it supplies no Relay source authority. No JavaScript SDK, framework, source or dependency is adopted. Existing Relay native/HTTPX0.28.1/SSE/card QA is the actual intended reuse.

## Exact proposed user request

BE32 framing and16KiB maximum JSON remain unchanged. Exact11-key object:

```json
{
  "schemaVersion": 1,
  "kind": "user_question_request",
  "captureSessionID": "00000000-0000-0000-0000-000000000001",
  "sessionEpoch": 1,
  "presentationGeneration": 9,
  "requestID": "00000000-0000-0000-0000-000000000002",
  "anchorEventSequence": 12,
  "emittedUptimeNanoseconds": 1000000000,
  "intent": "ask",
  "question": "How should this cache handle eviction?",
  "baseRequestID": null
}
```

The values above are synthetic examples, not a current session or clock receipt. Counters are exact UInt64 JSON integers, never bool/float, with positive epoch/generation/anchor; time is UInt64. UUID fields parse strictly. Unknown/duplicate fields fail closed. No caller/model capability field is accepted.

| intent | question | baseRequestID | Meaning |
|---|---|---|---|
| ask | Nonempty, unmodified, trimmed-for-emptiness-only single line, at most500 UTF8 bytes | null or actual owned current request UUID | Ask this explicit user question; optional exact current-question basis for a typed follow-up |
| help_current | null | Required actual owned current request UUID | Answer the current accepted question using its original full semantic context; real quick Help, no invented query |

Reject control/format/line/paragraph separator scalars as current manual text does. Do not silently truncate or rewrite text. Slice1 is short questions, not a long code/document paste editor. Existing selected source/context ports handle their separately bounded content.

The native issued type has no public initializer. Proposed native API:

```swift
func issueUserQuestion(expectedLease: PresentationLease,
                       intent: UserQuestionIntent, question: String?, baseRequestID: UUID?,
                       enqueue: @Sendable (NativeUserQuestionRequest) throws -> Void)
    throws -> NativeUserQuestionRequest
```

Under the existing controller lock: require a live actual session/current expected lease; validate intent/text; allocate a fresh UUID; atomically advance the native presentation lease; capture the controller's ACTUAL current sequence as anchor; enqueue onto the SAME MainEventQueue used by onEvent, before releasing the controller lock. Enqueue failure retires admission as existing manual issuance does. Do not consume the audio event sequence.

This new request may anchor earlier stamped-but-not-yet-forwarded audio, because all those original queue submissions precede it under that same lock. It must not jump directly to helper.sendJSON from a UI task. Existing ManualHelp retains its stricter lastForwardedSequence guard for backward compatibility. A held-EOU/onset regression must prove the proposed new order before acceptance.

## Draft, context and supersession

Typing changes only draft state. It does not issue a request, invalidate a lease, capture a screen, inspect selection or call auth/inference.

For a contextual typed follow-up, the editor records a read-only draft basis from the chosen/displayed owned request and visibly labels it. If conversation advances before Send, keep that original same-session basis as context and issue a fresh current native request; do not demand repeated confirmation merely because an old token retired, and never silently rebase Why that choice to another question. Only an absent/evicted/cross-session basis produces context_unavailable with the draft retained and an explicit send-as-new option. A new-question draft has baseRequestID:null and reads the actual current native lease at Send.

Send checks the current basis/helper/lifecycle and invokes native issuance. Failed issuance preserves the draft. Successful issuance binds the new request, clears only the submitted draft revision and retires the previous request. Edits made after Send are a newer draft revision and cannot be cleared by a late completion. Help-current captures its current binding at click; helper equality/currentness validates that exact basis again.

New remote onset supersedes an issued typed request exactly as it supersedes an audio answer. Microphone finals update dialogue but do not impersonate a new question or cancel the current answer. Another typed Send supersedes prior work. Source/context/personal/config changes preserve the existing dependent-work invalidation rules; they never grant a new request automatically.

Add .userQuestion and .answerCancel to SessionIngress. They invalidate held optional work. Before an invalidation can release a held original request frame, enqueue the original staged-context retirement, retire its image offer and cancel its optional producer. Then forward the held ORIGINAL request without context, followed by the new user/cancel frame and later original audio events. Preserve the accepted visual P1 callback-order invariant; do not drop a retirement identity or reorder an onset around EOU.

Explicit selected text is attempted only when the actual focused allowed application still matches. Clicking Relay's prompt does not authorize selection from another app. Unavailable selected text may fall back to the already enabled selected-window OCR path, with truthful provenance. No focus manipulation is needed.

## Helper admission and semantic ownership

Decode a distinct exact request object. Require host.live, matching actual native session/epoch, anchor equal to the sequence after processing earlier queued audio, presentationGeneration greater than current, a fresh request UUID and age0..2seconds. For ask, a nonnull basis must belong to the bounded retained same-session/epoch host request/task records; its old token/lease is not reused or reactivated. Re-retrieve current personal context and independently bind new screen context. For help_current, the basis must still be the actual current request with a current retained semantic token (a completed answer may qualify without the terminal-excluding publication predicate). Validate these distinct rules before source staging or model work. Malformed protocol/UUID reuse with different payload fails the channel closed; no competing terminal may seal the original request. Exact duplicate UUID/payload replays the bounded cached latest result, with zero new model work. Keep the existing512-operation session budget; retain at most8 result payloads and invalidate them on session retirement.

Introduce a narrowly named QuestionTurnMachine.begin_explicit_request(requestID) method. Under its own lock it refuses stopped state, retires retained audio semantic dependencies/interruption hypotheses, and activates a fresh token in the SAME ActiveTurns with a reserved user-request namespace and version1. It does not construct/ingest TranscriptEvent, change native audio identity, advance remote stream generation or reset audio replay/time watermarks. machine.current remains the audio snapshot query; it must not present typed text as an interviewer question. Host retains the explicit request's immutable semantic record. A later actual remote onset cancels the shared token through the existing path.

For ask, verbatim question is display/current request; a valid basis is supplied separately as context from the original host request, never reconstructed from model output. For help_current, take original question/display/task from that basis, but issue a new explicit token and native request. Nothing can reuse a previous token to authorize a new arbitrary question.

Each Request retains its own bounded task/dialogue projection. Add a pure ConversationContext projection/fork operation that copies the existing bounded mechanical task state, applies explicit user text as explicitly labelled user_text, and returns an immutable snapshot without observing it as remote/microphone or changing the actual audio ring. Retain the bounded private fork state needed by the correction grammar; do not reconstruct it from visible wording or a lossy task summary. A standalone typed question starts fresh task constraints; a basis-bound follow-up forks the original request projection and adds current actual dialogue as untrusted context. Reuse existing correction grammar and overflow/unresolved handling. A typed task must not inherit unrelated stale audio constraints merely because the audio ring is still live. Ordinary audio requests retain their existing source interpretation.

Route all origins through the existing personal question classifier FIRST. Personal questions only use live approved source/actor facts or clarify; raw conversation, typed assertions, selected text and images cannot become personal authority. General requests reuse reference/card generation and QA. Add explicit_user to the reviewed-reference source allowlist only at this trusted adapter, with the same final explicit-question/current-token/permission checks; never label typed input user_synthetic or remote_final. The original exact full-question and constraint checks remain mandatory. A host-owned origin/action value may enter prompt metadata; a model/serialized flag never supplies authority.

Keep one actual worker and newest pending request. Cancellation, screen failure or provider failure cannot silently generate a second model POST. The existing image permit must be owned by the original newly accepted Request.native object and pass actual credential/config/source/request/pixel gates before POST and publication. Retire bytes on failure and preserve successful publication evidence as already reviewed.

## Reply schema and UI origin

Reuse the exact existing16-key answer envelope:

```text
schemaVersion, captureSessionID, sessionEpoch, presentationGeneration,
requestID, eventSequence, resultRevision, disposition, reasonCode,
pythonToken, displayID, question, answerID, answerKind, card, provenance
```

For this route eventSequence equals the immutable native anchor, not a newly invented audio counter. Pending is revision1 and terminal revision2; at most one terminal. Card and provenance schemas stay unchanged, including optional canonical imageDigest only when actual permit.used_image is true. New fixed reason user_request_context_unavailable can describe a lost quick-action basis. Inference-disabled and personal/context clarification use existing safe results. A malformed frame never becomes visible provider text.

Native presentation derives Typed question or Current question Help from its original locally issued ingress binding. Do not add a model-controlled origin flag or mistake the Python token for native authority. Final answer publication still needs the exact original binding, Python semantic identity, helper generation, actual native lease and source-specific final gate. Copy/detail access rechecks the same ownership.

## Full-request retirement before a held frame

Cancellation cannot rely only on a control frame sent AFTER releasing a held EOU/request. The helper could begin a text POST between those two frames. Add a deny-only exact7-key marker, analogous to the accepted staged-context retirement pattern:

```text
schemaVersion=1, kind=answer_request_retired,
captureSessionID, sessionEpoch, presentationGeneration,
requestID, reasonCode=request_retired
```

These are the TARGET's original identity/generation, not the new cancellation lease. Enqueue this before any optional-work cancellation callback releases its held original frame. The marker does not consume/advance audio sequence or presentation, create a question, grant inference or claim quiescence. The helper retains at most512 exact target tombstones for the actual session. Wrong sessions cannot affect current work. Exact repeated markers are inert.

If that request already owns work, capture its specific worker receipt before retiring it. If its original frame has not arrived, consume the later real EOU normally for source/activity ordering and read-only dialogue/history, but do not activate semantic/inference work for that retired UUID. A retired typed frame similarly cannot start a request. Do not drop/restamp audio, and do not let retirement of an old ID cancel a newer active request. Session close clears tombstones. A request already POSTed cannot be unsent; cancellation still blocks publication and waits for its real owner.

This marker should be used for explicit Send supersession and Stop while optional preparation is held. It needs an actual-helper regression, because a frame-recording mock alone cannot prove zero inference before cancellation. Existing automatic audio retirement semantics must remain separately tested; the new marker is not a reason to rewrite source events.

## Stop response and real quiescence

Stop response cancels answer work while audio capture continues. It is distinct from Pause and End. Proposed exact9-key request:

```text
schemaVersion=1, kind=answer_cancel_request,
captureSessionID, sessionEpoch, presentationGeneration,
requestID, targetRequestID, anchorEventSequence, emittedUptimeNanoseconds
```

The native issuer requires the actual current target binding, advances the presentation lease, captures actual sequence under the controller lock, and enqueues through the same ingress. It never emits fake stopping/stopped audio events. Helper validates session/anchor/generation/target before cancelling that owned request and dropping its pending work/context. If its deny-only marker arrived first, use the retained original target/worker receipt rather than requiring active still to name the retired request. It captures the specific worker task to await, rather than later cancelling a different replacement.

Keep stdin responsive: an owned bounded cancellation task waits for the targeted worker's actual completion. Proposed exact10-key terminal receipt:

```text
schemaVersion=1, kind=answer_cancel_response, requestID,
captureSessionID, sessionEpoch, presentationGeneration, targetRequestID,
resultRevision=2, reasonCode=request_cancelled|already_finished, quiesced=true
```

Only actual completion may supply quiesced:true. A UI deadline cannot. Register the waiter before enqueue. Duplicate operation replay does not cancel twice; differing reuse fails closed. A late receipt for a superseded target cannot mark a newer request ready or clear its card. A missed deadline retires/fails the helper through existing teardown, without pretending the old worker joined. No automatic retry/resume of the cancelled question. Later real audio may create a new request under normal ordering and the existing worker drain barrier.

Pause/End retain their existing native capture stop, producer/model joins, helper session quiescence and profile/helper retirement behavior. Start/Resume/config changes remain blocked while those real owners have not joined. The automatic-speech owner retains init/start/cancel/canStart regions until its branch is frozen.

## Bounded transcript and current activity

No new helper transcript RPC is needed: the app already receives original NativeSessionEvent values. Add a read-only native reducer fed at ordered receive, before optional context capture can delay forwarding. It never writes BrainStore/ProfileBridge or drives question eligibility.

Proposed local DTOs, not wire authority:

```swift
struct SessionTranscriptRow: Identifiable, Equatable, Sendable {
    let id: TranscriptRowID // session UUID + source + stream generation + original segment ID
    let activityID: UInt64
    let source: TranscriptSource // microphone | selectedAppAudio
    let startUptimeNanoseconds: UInt64
    let endUptimeNanoseconds: UInt64
    let text: String
}
struct SessionActivitySnapshot: Equatable, Sendable {
    let sessionID: UUID?
    let revision: UInt64
    let phase: ActivityPhase
    let rows: [SessionTranscriptRow]
    let omittedRowCount: UInt64
    let microphone: SourceActivity
    let selectedAudio: SourceActivity
    let request: CurrentRequestActivity?
}
```

Bounds: at most64 whole rows and64KiB total UTF8 text; each row at most1,200 Unicode scalars/4,800UTF8 bytes, matching the strict helper's final-text domain. Never truncate a transcript row. Evict oldest whole rows and increment omittedRowCount. Validate final schema, exact source/generation/segment, original activity association/closed range, timebase/timestamps and nonempty valid text before insertion. Unknown/blank/failed/unassociated finals do not produce rows. Original older finals can enter history at their original times but cannot change current request/lease. Deduplicate by original identity; do not restamp revisions or source.

Labels are Microphone and Selected app audio, not You/Interviewer or biometric speaker claims. Model answers, typed drafts, typed requests and screen text are never transcript rows. Activity derives only from actual onset, end/final, source failure, host pending/terminal and teardown receipts. Use detected/transcribing/thinking/stopping/paused/unavailable wording, no fake percent or latency/accuracy claim. Current request origin is local issued state.

Pause seals the old session's rows read-only and disables Ask; Resume starts a fresh capture identity and clears the old ring, matching existing conversation reset semantics. End clears rows at retirement. Explicit consent revocation purges affected private rows; selected source change/new session clears them. Late finals after retirement cannot restore text. The64KiB UI ring does not enlarge the existing model dialogue/prompt budget. No history persistence, automatic learning, memory approval, speaker inference or transcript export is delivered in slice1.

## UI adapter and disjoint ownership

New MainActor TypedAssistantController owns draft/revision/basis and read-only activity, using injected closures into existing native/model ports. It owns no second presentation authority or model client. Public presentation API:

```swift
@Published var draft: String
@Published private(set) var snapshot: TypedAssistantSnapshot
func submitDraft() // real ask issuance; preserves draft on failure
func useLatestQuestionForDraft()
func sendDraftAsNewQuestion()
func requestCurrentQuestionHelp()
func cancelCurrentResponse() async
func setTranscriptVisible(_ visible: Bool)
```

Snapshot exposes canSend/canHelpCurrent/canStop, draftBasisState, actual pending/terminal state and bounded activity. It does not expose credentials/capability receipts. Init is inert. UI observes the real adapter only after it exists; no enabled stub controls. Current Help continues working through its existing route until this explicit-current adapter is joined. Explain/Say next/Follow-up/Recap actions need separately frozen intent/output semantics, especially personal-grounding and code-required rules; do not claim them from labels or expose placeholders in slice1.

Suggested implementation ownership after root freeze:

| Lane | Files |
|---|---|
| Backend/semantic | New user_question.py and tests; narrow session_host Request/admission/routing/deny-only-retirement/cancel dispatch; QuestionTurnMachine explicit method/tests; pure ConversationContext projection/tests; explicit_user reference-policy adapter/tests. No auth/transport/framework replacement. |
| Native request/composition | New NativeUserQuestionRequest/NativeAnswerCancelRequest and private issuance methods/tests; SessionIngress and OrderedContextForwarder typed/cancel cases; PendingAnswerCancellation receipt/parser in HelperTransport. Preserve existing capture core teardown. |
| App adapter/activity | New TypedAssistantController, SessionTranscriptStore and pure snapshot tests; root-owned narrow SessionApplicationModel receive/bind/accept/command hooks AFTER audio owner freezes its changes. Existing properties are private, so an unrelated extension cannot safely wire them without an explicit owned seam. |
| UI | UI owner's LiveSessionView top row, real Send/Stop/Help and actual transcript/activity pane; keep Home/Context/Settings source ownership separate. |

Do not concurrently edit SessionApplicationModel init/start/cancel/canStart, ProfileController/View, memory bridge or global contracts. Root sequences the small app hook after automatic setup and UI acceptance.

## Meaningful acceptance and sequencing

1. Freeze schema/intent/token/queue semantics and ownership with root. First add exact decoder/issuance/semantic negative tests; preserve all existing manual-help rejection tests.
2. Build real helper active-session Ask before any native TextField is enabled. Synthetic child must answer an arbitrary typed question after actual session_started, including before any remote question; no fake EOU. Exercise personal grounding and exact reviewed references with zero provider calls for those paths.
3. Prove the critical queue schedule: real native earlier onset/end/held EOU, old staged text/PNG, typed Send/Stop and later onset. Assert original event order/leases, staging retirement BEFORE held request release, no old image POST after retirement, zero POST for a target stopped before its held preparation is released, and no stale publication. Test native issuance during stamped-but-not-delivered audio.
4. Test draft change versus submitted revision, retained superseded basis without silent rebasing, evicted/cross-session basis, Help basis mismatch, empty/oversized/multibyte/control text, bool/float/unknown/duplicate fields, stale age/session/generation and replay UUID/payload. No second inference on duplicates or failure.
5. Test fresh explicit tokens, old-final history-only behavior, future actual remote correction/follow-up and microphone dialogue. Typed task projection must not mutate audio task/biography, inherit unrelated constraints or bypass unresolved/overflow clarification.
6. Actual helper with injected OAuthAnswerStream + HTTPX MockTransport: exactly one completed POST, typed question preserved, optional source/image metadata truthful, credential/config/source changes before publication rejected, one active/newest pending, cancellation during capture/token await/SSE. No real credentials/network/account/model request.
7. Stop response receipts must remain pending until a held cancellation-ignoring worker actually returns; stdin must still accept disable/End. Late receipt cannot clear replacement work. Existing Pause/End/Resume quiescence and helper reaping tests stay mandatory.
8. Transcript reducer tests use actual issued synthetic native finals for both sources; validate bounds, complete rows, source labels, duplicates, out-of-order old finals, gap states, Pause/End/revoke clearing and no late restoration. No model output can enter the ring or memory.
9. Wire real native/UI actions only after these ports pass; render synthetic typed/thinking/cancelled/transcript/paused/error states, then run affected native packages and one scoped actual app/helper end-to-end test. Locked Mac is not visible/runtime acceptance.

No implementation, runtime tests or account/capture actions were performed for this design. Source and primary upstream tests were inspected; this document is the reviewable proposal. The separately requested My Context review is recorded in [My Context review](../../evidence/reviews-2026-10-23/review-context-62a1f85.md) and does not change this design's ownership or approval status.
