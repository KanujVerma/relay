# Standalone typed scope implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Parent explicitly disallows additional agents; work inline with checkpoint review.

**Goal:** Expose real noncapture native/helper scope ownership and owned asynchronous draft preparation without fake audio or a second helper.

**Architecture:** A separate pure native controller issues the existing typed/cancel values after its explicit assistant scope opens. The same helper uses mutually exclusive capture/assistant modes and the existing worker/router; new strict controls and owned transport receipts govern readiness and actual close. After independent checkpoint review, this lane also integrates the actual app owner/lifecycle/UI under root's expanded write ownership.

**Tech Stack:** Swift6/macOS15.2 app, pure native SessionPresentationAuthority, Python3.11+ SessionHost, existing BE32/16KiB framing and HTTPX synthetic test transport.

**Spec:** `docs/superpowers/specs/2026-10-23-idle-assistant-design.md` and its preservation amendment; exact unchanged canonical copy from rootf86bc3af. Current ownership is in `docs/lanes/IDLE_ASSISTANT.md`.

## Global constraints

- Frozen base db768fdeebb7f084b8619b2eae54d8aabebe0065; no author/root/review checkout edits.
- No audio events, fake sources, CaptureContext grant, recording consent inference, ASR/VAD/load/download, auth/profile/provider policy change or new runtime dependency.
- One actual helper/one worker, exact scope/request ownership, bounded replay/queues, close only after actual cleanup; no timeout-as-quiescence.
- Existing typed/answer envelope identity slots are legacy names in an explicit assistant namespace; capture validation stays unchanged.
- Native stamping follows helper/profile/open readiness; keep original draft revision/text/basis until actual issuance and preserve newer edits.
- No real capture/permission/private file/Keychain/account/model/network inference in tests. Synthetic original native events, fake keys and HTTPX MockTransport only.

## Checkpoint 1: strict native/helper foundation

**Files:** create native `NativeAssistantScopeRequest.swift`, `NativeAssistantSessionController.swift`, `AssistantScopeTests.swift`; create Python `assistant_scope.py` and `tests/test_assistant_scope.py`; narrowly modify `session_host.py` dispatch/scope gate. Update lane evidence.

**Interfaces:** native begin/confirm-open/issue-user/issue-cancel/begin-close/finish-close under one private lock; privately constructed existing typed/cancel values. Assistant request has nine exact fields: schemaVersion/kind/action/requestID/assistantSessionID/sessionEpoch/presentationGeneration/controlSequence/emittedUptimeNanoseconds. Open response has nine identity/status fields; close adds actual quiesced. Python scope coordinator handles exact replay, fresh admission, mutual exclusion and separate close-task ownership.

- [x] Run existing focused user/native issuance tests as baseline, using isolated caches and the explicit existing interpreter.
- [x] Add failing native tests: no source required/no NativeSessionEvent; opening state rejects typed issuance until original ready; stale lease/wrong open ticket reject; typed/cancel advance only own authority; synchronous close rejects late open/user/cancel; exact enqueue failure retires; real capture source guard remains.
- [x] Run the new native class, confirming missing APIs are the failure; implement minimum pure native state/issued controls; rerun those cases plus old user issuance.
- [x] Add failing helper strict-domain and mode tests, e.g. a fresh assistant open followed by a real user request must return the reviewed WHERE/HAVING reference with zero model calls and no fabricated audio. Test malformed fields/types, stale open, open while capture/old worker/probe live, unknown/wrong close identity, exact pending/final replay and changed UUID reuse.
- [x] Run those tests against absent scope support; implement strict decoder/coordinator and narrow dispatch, keeping capture bootstrap untouched. Open uses explicit machine/permission initialization, never SyntheticEOUBridge authorization.
- [x] Add held-worker/probe/cancel-receipt tests before implementing async close ownership. Assert admission withdrawn synchronously, close terminal absent while held, new open busy, actual release joins before exact terminal; old scope cannot clear a replacement. Keep completion outside its drained task set.
- [x] Add actual stdio no-inference/fixture smoke and existing capture/user/visual focused controls; assert original framing/replay and only one actual worker. No account or external inference.
- [x] Verify diff/source hygiene, record exact red/green commands/results/limits, commit/push checkpoint and send immutable native/helper API provenance to root.

## Checkpoint 2: transport and owned draft preparation

**Files:** new panel `AssistantScopeResponse.swift` plus focused tests; narrow `HelperTransport.swift` scope waiters; new `TypedSessionPreparationPorts.swift`; narrow `TypedAssistantController.swift` and its focused tests; lane evidence. No Model/View edits.

**Interfaces:** registered pending scope response with async value, full expected action/scope/epoch/generation/control-sequence and helper ownership; default-nil `TypedSessionPreparationPorts` contains canPrepareSession, prepareSession(intentID,isCurrent) async throws and the parent-approved retireUnusedSession(intentID,originalLease) async cleanup join. Controller exposes actual preparing state, synchronous cancellation and wait-for-preparation quiescence; existing active submit/default initialization stay compatible.

- [x] Add failing actual-child receipt tests for reply-before-await, exact duplicate waiter, wrong scope/action/sequence/generation, malformed response/EOF/timeout and pending close held until real work returns. Assert error resolution, no continuation loss and actual stop/reap.
- [x] Implement strict response parse/validate-before-pop and register-before-enqueue using the same writer bounds. Rerun scope and accepted waiter/control tests.
- [x] Add failing preparation tests: idle valid draft can prepare without issuing; no IO at construction/editing; hold actual prepare result and edit/cancel/End; no fresh native value or draft/basis clearing before ready; failure/cancellation of Send as new keeps exact original text/revision/basis; new edit survives late success/error; duplicate Send single-flights; late old cancellation cannot retire replacement.
- [x] Implement optional owned prepare path and common submission routine selecting basis locally, mutating chosen/draft only after actual successful issuance. Use owned operation UUID and revision checks; keep busy until prepare/cleanup returns. Preserve active-sync behavior and d969 unavailable-source direct-command test.
- [x] Run focused native/helper/transport/controller suites and actual synthetic stdio flow with begin->Ask->Help->Cancel->Close, positive text/reference/personal guards and source-independent authority. Do not repeat unrelated full suites absent a concrete failure.
- [x] Record verified checkpoint and precise app integration API/tests. Commit/push and publish/attach draft PR against root's frozen idle base. Root performs independent checkpoint review before app integration continues.

## Checkpoint 3: actual noncapture app lifetime and UI

**Files:** narrow `SessionApplicationModel.swift`, helper failure gate, Home/live/composer presentation and command routing; new actual app lifetime tests and lane evidence. Root explicitly expanded this lane's ownership; account worker owns no pending Model/HelperTransport join, and résumé worker owns only ProfileDTO/View.

**Interfaces:** a private current conversation owner object contains its actual kind/authority/panel/publication/forwarder/helper and retirement state. Actual audio-running state remains separate from assistant readiness. Preparation/close tasks capture original owner, helper identity, intent and draft revision. Every queued source/result/error/receipt/context callback checks original ownership; a shared helper identity alone cannot distinguish consecutive scopes.

- [ ] Add failing actual app idle reference/personal/completed MockTransport tests proving no speech preparation/load, NativeSessionEvent, capture backend or TCC calls. Home Send remains a real command; editing performs no IO.
- [ ] Implement the owned preparation and independent scope/authority join, preserving existing audio Start checks. Use original actual helper/profile target and delay native issuance until readiness/final intent/binding guards.
- [ ] Add failing held-close/old-callback/Start/Pause/End/AI/profile-Lock tests before each corresponding handoff. Assert old authority retires before await, actual helper worker/probe/native owners join, no second helper/worker and no late old callback can clear/upload/paint into a replacement.
- [ ] Integrate Home/live UI with truthful assistant/capture state, real Send/Help/Stop/preparation cancellation and exact snapshot eligibility. Preserve unsent drafts/basis and avoid audio/recording consent inference.
- [ ] Run affected app/native/helper tests and real bundled helper from a relocated no-repository CWD with synthetic completions/fake keys only. Root owns actual CUA/window inspection; do not operate GUI concurrently.
- [ ] Freeze/push final verified head, scoped report/evidence and draft PR update for root's independent final review/reconciliation. Attribute any prior built artifact to its exact old source until rebuilt.
