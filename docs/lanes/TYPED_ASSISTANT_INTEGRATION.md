# Typed assistant app integration

This is the concrete root-owned join for the foundation PR. The foundation compiles against the frozen app without editing `SessionApplicationModel`, `SessionIngress`, or views. These ports are implemented and tested; the live app does not expose typed controls until this join is completed and tested. Full idle/audio-unavailable Ask needs a separate noncapture session lifetime and remains required follow-on work.

## Original ordering and authority

Extend the app's private ingress wrapper with typed and cancellation cases. Keep audio, existing ManualHelp, typed and cancellation items in the **same** `MainEventQueue`. Invoke the actual fixture/native capture controller's new methods; their enqueue closures execute while the same native source lock is held. Do not manufacture an EOU, allocate an audio sequence, send a typed frame directly from a view, or instantiate the native issued values externally.

The native methods are:

```swift
controller.issueUserQuestion(
    expectedLease: currentLease,
    intent: .ask, // or .helpCurrent
    question: draft, // nil for helpCurrent
    baseRequestID: chosenOriginalRequestID, // required for helpCurrent
    enqueue: { issued in try events.enqueue(.typed(issued), receive) })

let issuedCancel = try controller.issueAnswerCancellation(
    expectedLease: originalTarget.lease,
    targetRequestID: originalTarget.requestID,
    enqueue: { issued in
        // Synchronously register BEFORE ordered enqueue. This sends no frame.
        _ = try helper.registerAnswerCancellation(issued)
        try events.enqueue(.answerCancel(issued), receive)
    })
// Exact duplicate registration returns the SAME owned waiter. This avoids
// mutating a captured main-actor variable inside the @Sendable native closure.
let pending = try helper.registerAnswerCancellation(issuedCancel)
return try await pending.value()
```

The queue `enqueue` spelling above represents the root-owned overload; it is not a new public foundation API. Reuse its existing bounded queue and helper identity failure handling. Capture the actual helper/queue locally for the native `@Sendable` closure; do not mutate main-actor state from that closure. Do not await a response while the native lock is held. Exact repeat registration is idempotent; the async cancellation closure obtains that original waiter after synchronous issuance/registration/enqueue completes. Enqueue/registration failure retires the actual controller/helper through the existing failure path.

Capture the **old original** `PanelRequestBinding` on the main actor before issuance. Native issuance advances the actual presentation generation; it does not authorize that old binding again. On receiving typed/cancel ingress, the root callback must run this sequence synchronously:

1. Write `helper.sendJSON(oldBinding.retirementJSON())` before any old optional-work callback can release its held frame. This is a seven-field denial of the original request, with its original generation and UUID.
2. Send the existing matching `supplemental_context_retired` frame via `enqueueContextRetirement(oldBinding)` while the old identity is still available.
3. Retire the old context composer/producer; only now may `retireOptionalWork`, `cancelOptionalWork`, and existing clear/retirement callbacks run. Clear the old model/panel binding and producer state. Never call the current `retireOptionalWork()` first: it can release a held original EOU before the deny frame.
4. Enqueue the issued item through `forwarder.enqueueUserQuestion(issued, retiring: oldBinding)` or `forwarder.enqueueAnswerCancellation(issued, retiring: oldBinding)`.
5. Bind the new question in the explicit capture/send port using its fresh lease/request/anchor. Cancellation is not a question bind. A late cancel receipt must not clear a newer binding/card.

Passing the original target to the forwarder also makes it send denial before cancelling its held flight. Duplicate original denials are harmless. The forwarder callback must still be deny-first; a duplicate after an earlier callback already released EOU cannot repair ordering. If there was no prior binding, typed Send simply has no old-target retirement.

This full request denial is for typed supersession and Stop response. Existing source-only/context-only invalidation must continue to preserve independent personal/reference answers that did not use optional context.

## Explicit forwarding ports

Create `ExplicitContextForwardingPorts` as the last argument of the existing `OrderedContextForwarder` constructor. All five closures are required:

```swift
ExplicitContextForwardingPorts(
    shouldCapture: (NativeUserQuestionRequest) -> Bool,
    capture: (NativeUserQuestionRequest) async -> [Data],
    retire: (PanelRequestBinding) throws -> Void,
    sendQuestion: (NativeUserQuestionRequest, [Data]) throws -> Void,
    sendCancellation: (NativeAnswerCancelRequest) throws -> Void)
```

For typed capture/send, construct the fresh `PanelRequestBinding(lease: issued.lease, requestID: issued.requestID, eventSequence: issued.anchorEventSequence)`. Reuse the actual root bind routine, current lease checks, selected Accessibility-text priority, OCR composition and lazy PNG write path. The capture result holds at most one 16 KiB text frame; image frames continue through bounded `sendJSONAwaitingWrite` backpressure, never the `[Data]` array. Send the matching supplemental text/image frames before `issued.encodedJSON()` and preserve original native events after it. Capture must use fresh original-source observation and request ownership. No historical pixels, image receipt, permit, producer or old native lease may be reused from a draft basis.

`retire` performs the deny/context sequence above before retiring the producer. `sendCancellation` sends only `issued.encodedJSON()`; its waiter was already registered. The helper consumes `answer_cancel_response` internally, requiring exact original request/target/session/epoch/new generation and actual task quiescence. Do not route that receipt to the answer parser or synthesize success on timeout. Transport failure resolves the owned waiter with an error.

The usual original `SessionAnswerDecision` and `SessionPanelController` gates remain unchanged. Feed schema-valid helper answer DTOs to `TypedAssistantController.observeDecision` before the current-binding panel veto, so a known older submitted request can recover its untouched draft on context-unavailable. That recovery requires the exact privately recorded submitted UUID/session/epoch/generation/anchor; it never records an old question as current or authorizes its card. All visible answer publication still requires the current original binding, existing independent bounded native source/pixel re-observation and synchronous publication gate. The new coordinator shares the same model stream, budget, one active worker and newest pending request.

## Actual presentation adapter

`TypedAssistantController` is a main-actor observable object. Its constructor has no reads, capture or inference side effects:

```swift
TypedAssistantController(
    session: () -> PresentationLease?,
    currentRequest: () -> PanelRequestBinding?,
    issue: (UserQuestionIntent, String?, UUID?) throws -> NativeUserQuestionRequest,
    cancel: (PanelRequestBinding) async throws -> AnswerCancellationResponse)
```

The `session` closure returns only the actual current active-session authority while running, not stopping, with a live permitted source. Return nil while idle, paused, stopped, helper-failed or all sources unavailable. The `issue` and `cancel` closures implement the actual locked/ordered route above. They do not directly send model/request frames. Use weak app captures for the lazy app-owned instance.

Bind the editor to `draft`; render `snapshot.canSend`, `canHelpCurrent`, `canStop`, `basis`, `basisState`, `status` and `transcriptVisible`. The real commands are `submitDraft()`, `requestCurrentQuestionHelp()`, `cancelCurrentResponse() async`, `useLatestQuestionForDraft()`, `sendDraftAsNewQuestion()` and `setTranscriptVisible(_:)`. A draft edit performs no capture/model action. Avoid exposing buttons before their actual closures are joined.

Call `recordQuestion(binding, question:)` for the real accepted original question, and `observeRequest(binding)` when that actual native binding becomes current. Feed original native events once, in receive order, to `observeNative(event)`, including session start/source activity/finals. Feed schema-valid answer decisions to `observeDecision` as above; only exact current decisions can update current question/work state. Call `refresh()` on authority/helper/source/lifecycle changes.

The first nonempty draft retains the visible question's original read-only basis. New audio/current questions do not silently change it. Eight same-session question records are retained; a retired token alone does not make basis unavailable. Eviction, missing helper basis or a new session produces unavailable context. A helper `user_request_context_unavailable` restores submitted text/original basis only if its cleared draft revision is still untouched. Newer edits survive. Render the unavailable message with explicit Send as a new question and Use latest question actions; never silently rebase. Explicit Send as new discards the basis only for the new request and re-retrieves current personal/source context.

`transcript` is an actual `SessionTranscriptStore`, with its own published `snapshot`; views should observe that nested object directly. It accepts associated native final events only and labels sources Microphone / Selected app audio, without asserting speaker identity. It keeps at most64 whole rows and64 KiB of text, with `omittedRowCount`. No model text, typed draft, partial ASR, file, persistence or personal memory is added. At actual Pause call `transcript.pause()` before stopping events can clear it; late finals stay sealed. At End call `transcript.end()`. Fresh session start creates a new transient read view. Source consent revocation purges that source's rows.

For an actual typed current request, toolbar Help must call `requestCurrentQuestionHelp()` / the new `help_current` route. The legacy ManualHelp path deliberately requires `machine.current()`'s actual audio semantic snapshot and cannot authorize an explicit typed token. Keep that legacy path for compatible audio requests. Choose the route from the app's original locally issued request origin, never a model/serialized authority flag.

An accepted legacy audio Help request is also retained as read-only bounded question context under its visible Help UUID, with its original display/semantic question and actual current task projection. A later typed follow-up can select that visible basis normally; it still issues a fresh explicit token and retrieves current context. Rejected/stale/mismatched legacy Help creates no basis and no additional model work; legacy admission/equality/anchor/token behavior is unchanged.

The helper retains the original semantic request separately from exact display text. Typed follow-ups carry a flat list of their supplied question contexts, capped at6000 UTF-8 bytes including labels; Help reuses the exact stored semantic request with a fresh token and fresh current personal/source retrieval. Overflow returns the existing `user_request_context_unavailable` before provider/model work, so the normal exact-owned draft recovery/send-as-new path applies. Earlier personal context is never silently dropped to fit this bound, and labels do not recursively nest.

## Wire forms

Keep feeding original matching-session consent-revocation controls to the transcript reducer while paused. Its sealed path permits source-specific removal only, preserves the paused phase, rejects replay/wrong scope and never inserts late finals. A prior session's revocation cannot clear a replacement session. End still clears all rows explicitly.

All frames use the existing BE32 length prefix and16 KiB action budget. The typed request has exactly11 keys: `schemaVersion`, `kind:user_question_request`, `captureSessionID`, `sessionEpoch`, `presentationGeneration`, `requestID`, `anchorEventSequence`, `emittedUptimeNanoseconds`, `intent:ask|help_current`, `question`, `baseRequestID`. Ask requires a nonempty single-line string at most500 UTF-8 bytes; optional basis UUID or null. Help requires `question:null`, a nonnull actual current UUID and current helper semantic basis. Native stamping supplies the actual request, generation, anchor and time; JSON supplies no authority.

Original denial has exactly7 keys: `schemaVersion`, `kind:answer_request_retired`, original `captureSessionID`, `sessionEpoch`, `presentationGeneration`, `requestID`, `reasonCode:request_retired`. It can only withdraw authority. Cancellation has exactly9 keys: `schemaVersion`, `kind:answer_cancel_request`, new `captureSessionID`, `sessionEpoch`, `presentationGeneration`, `requestID`, original `targetRequestID`, `anchorEventSequence`, `emittedUptimeNanoseconds`.

Completion has exactly10 keys: `schemaVersion`, `kind:answer_cancel_response`, `captureSessionID`, `sessionEpoch`, `presentationGeneration`, `requestID`, `targetRequestID`, `resultRevision:2`, `reasonCode:request_cancelled|already_finished`, `quiesced:true`. It is emitted only after the captured target task has actually completed, including an uncooperative worker. It does not wait for an unrelated newer worker. A denied original frame that expires before admission can still receive a fresh actual-native cancellation: its known target must be at or ahead of helper presentation and the new generation exactly target+1. An old target can never cancel a newer presentation; original request freshness remains2s. The helper ledger is512 operations, last8 latest responses,8 retained basis records,512 original denials, one active inference and one newest pending inference. Exact UUID replay cannot invoke another model; changed UUID reuse closes the channel.

## Joined acceptance still required

The foundation tests prove actual controller issuance/ordered forwarding/stdio helper/HTTPX MockTransport, completed SSE, personal/reference gating, stopped held audio EOU+PNG zero POST, positive image control, original audio order, typed supersession and draft/transcript reducers. They do not prove the root's later app callback ordering or UI. Root must add a joined app test using its real receive/bind/composer hooks for typed Send/Stop while EOU/PNG is held, plus a positive unchanged control and late cancellation/new-edit/basis recovery cases. No live microphone, capture, account or model behavior is claimed.
