# Scoped answer re-review

Frozen head: `2e06c6d03e7606532c9cf16c961fd4841d327160`. Baseline: `cd5286a50700b8040f9e9b03b65c8f960e98fb1c`. Checkout: `<workspace>/work/relay-build-answers`.

Scope was the four original findings and their immediate regressions, plus the required shared-helper emergency adapter. Imported personal-library fixes were treated as separately reviewed dependencies; only their port contract and composition seam were inspected. No source, index, HEAD or branch mutation; no full suite, account/model/capture/permission/Keychain/private-data work.

## Verdict

**Scoped spec verdict: changes required.** The microphone continuation and display/semantic separation fixes close their original reproductions. The durable task record now survives raw-history eviction and reports overflow honestly. The general output policy rejects the original first-person education/credential/employment examples. Two actionable gaps remain: ordinary named-person attribution still bypasses grounding, and task correction detection/recovery disagrees with the existing question machine.

**Scoped quality verdict:** the delta adds useful targeted coverage and clear fail-closed states. All 10 builder regression tests pass independently. The two selected shared-helper emergency/reap tests pass, and an additional exact-source immediate-exit probe completed 24 schedules. No new confirmed shared-helper lifecycle defect was found in this scope. These checks do not establish complete language classification, generated truth/usefulness, live hardware/account acceptance, or final joined-head quality.

## Remaining findings

### 1. [P1] A normal named-person question can still publish unsupported project attribution

**Locations:** `relay_spike/generated_answer.py:88-109` and `relay_spike/session_host.py:262-265`.

`requires_personal_evidence` recognizes pronouns and a biography vocabulary but does not recognize the normal third-person question `What did Kanuj build at Acme?`. The new output policy accepts `State Kanuj built the Atlas SQL pipeline at Acme.` because it begins with an approved neutral directive and contains none of the enumerated pronouns or biography terms. This is the same product-level grounding boundary as the original finding: a model invents an individual's project contribution and the general path displays it without provider evidence.

**Exact integrated reproduction:** fresh `SessionHost(complete=injected_complete, emit=out.append)` with no provider; valid `start()`, `speech(2)`, `end(3)`, `final(4, 'What did Kanuj build at Acme?')` from the existing test constructors. The injected completion is:

```json
{"lead":"State Kanuj built the Atlas SQL pipeline at Acme.","points":[],"detail":null,"assumptions":[],"coverage":["current"],"personal_fact_ids":[]}
```

Observed: `requires_personal_evidence(...) == False`; one model call; `bundle is None`; terminal `disposition="answer"`; visible lead exactly `State Kanuj built the Atlas SQL pipeline at Acme.` Direct `parse_generated_card` also accepts the candidate.

This finding does not demand a formal semantic proof for arbitrary model text. The neutral-form/lexical restriction is appropriately disclosed as conservative. The concrete named-person project question and directive-wrapped attribution are ordinary profile/interview cases, however, and remain outside the intended provider-only biographical render path.

**Correction:** handle named/third-person candidate history and contribution requests within the personal-evidence policy, and reject unsupported individual attribution in general output even when wrapped in an approved coaching verb. Add integrated regressions for named-person project/employment questions and a technical question whose candidate unexpectedly contains a named attribution. Keep exact provider rendering as the authority source; do not treat the neutral opening word as evidence.

### 2. [P2] Task correction state can retain a superseded constraint or remain stuck after clarification

**Locations:** `relay_spike/conversation_context.py:38-40,61-68,84-99,115-117`; generation gate `relay_spike/session_host.py:231-232`.

The new task correction grammar differs from the already accepted question-machine correction grammar. `Make that five.` is recognized as a correction by the existing question machine, but not by `ConversationContext._CORRECTION`. It contains no supported field statement, so the durable task remains `ready` with the old capacity. Generation then receives instructions that the durable constraint record contains the current supported values, making the stale value especially consequential.

**Exact integrated reproduction A:** send these three valid successive remote activities through a fresh host with a neutral injected completion:

1. `Implement an LRU cache. Capacity must be three; keys are strings.`
2. `Make that five.`
3. `Explain how the current capacity changes eviction.`

Observed: three model calls and an answer on the last request; the final prompt's `conversation.task` has `state="ready"`, `constraints=["Capacity must be three;", "keys are strings."]`, and recent engineer feedback includes `Make that five.` No clarification is requested.

The opposite liveness problem occurs for a correction that is recognized but unresolved. `_task_state` becomes `needs_clarification`, but successful later field updates never set it back to `ready`; only beginning a new task resets it. This conflicts with the supplied next-step instruction to restate the affected constraint.

**Exact integrated reproduction B:**

1. `Implement an LRU cache. Capacity must be three.`
2. `Actually, make it five.`
3. `Capacity must be five.`
4. `Explain the current approach.`

Observed: one total model call; final `disposition="clarify"`, `reasonCode="task_context_unresolved"`; task constraints correctly contain `Capacity must be five.`, but state remains `needs_clarification`. Direct context snapshots confirm the explicit field restatement updates the value without clearing the unresolved state.

**Correction:** reconcile task correction handling with the existing question-machine correction forms. Unresolved corrections must retire the affected old authority or block generation rather than leaving stale constraints marked ready. Track what needs clarification so a supported explicit field restatement can resolve that state without requiring an artificial new task. Preserve the separate sticky overflow policy. Add both integrated sequences above, asserting no stale-capacity generation and successful recovery after the explicit clarification.

## Original-finding status

- Original personal-claim examples now reject; multi-form education/employment/GPA/certification routing and exact approved education rendering pass. The concrete third-person contribution case above prevents closing the overall grounding finding.
- Both microphone `source_unavailable` and `discontinuity` preserve remote answer processing, retire further mic admission and record a fixed context gap. The original silent session shutdown is corrected.
- The 357-byte coding root plus 66-byte follow-up now makes a second request, displays only the verbatim follow-up and retains both utterances in `semantic_request`. The original display-budget conflation is corrected.
- Long coding/case dialogue retains the independent problem and supported field constraints after raw deque eviction; supported capacity/latency corrections replace those fields, explicit new tasks reset them, and overflow blocks generation until a bounded restatement. The original eviction defect is corrected; correction-state regressions above remain.

## Shared-helper emergency and child-lifetime seam

`SessionApplicationModel.swift:111-125` permanently retires the binding and closes actual source/presentation/helper identity admission before its first await when the bound helper is current. It clears source-session forwarding and stops the transport. Queued answer delivery checks helper identity; queued source events check the current forwarded session. A retired binding blocks `ensureHelper` until shutdown finishes; a replacement uses a fresh controller/client/port/binding. Emergency shutdown calls the binding's helper receipt path directly rather than recursively closing the profile client.

`HelperTransport.swift:49-53` installs an independently retained receipt before launch; the callback records completion even if its weak helper owner has disappeared. `shutdownAndWait` closes write/profile admission synchronously, then asynchronously waits for that receipt. Delayed TERM/KILL callbacks capture the original child and receipt; they cannot act on a replacement helper. The existing helper-generation failure gate fences old application callbacks. No `waitUntilExit` is introduced. Source inspection did not establish a new actionable defect in this seam.

Focused native evidence:

- Directly ran only `test_required_profile_emergency_retires_and_awaits_shared_child` and `test_exit_receipt_confirms_shared_child_was_reaped` from the existing built panel XCTest bundle: 2 passed, 0 failures. These cover forced shared-helper shutdown, rejected old-client commands/restart, and `waitpid(WNOHANG) == -1`/`ECHILD` after completion. The bundle was not rebuilt/re-certified against source in this re-review; final joined builds remain the controller's gate.
- Compiled current exact `HelperTransport.swift`, `StrictJSON.swift` and `SessionDecision.swift` into an isolated temporary lifecycle harness. The unused native-event send API was satisfied by a stub whose `encodedFrame` traps; no event send/native capture path was invoked. Twenty-four real `/usr/bin/true` immediate-exit schedules, alternating immediate shutdown and a 3 ms pre-shutdown delay, completed without hangs, duplicate failure callbacks or permitting the retired helper to restart. This specifically exercises early exit versus receipt registration and shutdown from current source. Scratch outputs and the module cache stayed under `/private/tmp/relay-answer-rereview-2e06c6d`.

## Verification and limits

Read the original review, precise answer-owned delta, `docs/lanes/ANSWERS_REVIEW_R1.md`, `docs/lanes/ANSWERS.md` and the finalized `fix-answers-round1-report.md`. Independently ran `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_answer_review_regressions.py -q`: 10 passed. Additional focused injected reproductions above used actual `SessionHost`/`ConversationContext`/validator code and no model calls.

The builder's full Python 460/23 skips, profile 17, panel 25, production build and EVALS/docs results are prior evidence, not independently rerun here. Imported personal shutdown implementation and its 36 schedules remain the separate reviewer's scope. Native application queue/recovery conclusions above are source-based, supported by focused helper tests, rather than a new complete end-to-end application lifecycle exercise. Hosted Swift 6.1, joined integration regressions and all separately authorized live acceptance remain pending.
