# Independent answer and native-panel review

Reviewed immutable head `cd5286a50700b8040f9e9b03b65c8f960e98fb1c`, tested-source ancestor `870396415708ac3ca40176add33234b6ff0c1d3d`, against base `a8f8359354f44e11be39e22a55422b2cef9f6c91` in `<workspace>/work/relay-build-answers`.

This was a read-only source review plus focused injected Python reproductions. No source/index/HEAD/branch changes, full-suite reruns, builds, account calls, capture, permissions, private material, Keychain access, model loads or inference were performed. The only written artifact is this report.

## Verdict

**Spec verdict: changes required.** Four concrete defects remain: generated biographical claims can bypass provider grounding; microphone source loss silently disables future answers while the native session stays running; ordinary follow-ups can be withheld solely because internal context is placed in the bounded display-question field; and deque eviction discards the active task's original problem and constraints.

**Quality verdict: promising structure, insufficient acceptance for this head.** The separation of reviewed and generated cards, original request/lease checks at MainActor commit, terminal latches, one-worker/newest-waiting scheduling and bounded transport stages are visible in the implementation. The inspected tests exercise important races and real-child composition. They do not catch the four reproductions below. No new independent defect was established in the inspected SSE completion/cancellation or native decision-commit logic. That is a scoped review result, not live acceptance or proof of generated correctness.

## Findings

### 1. [P1] General generation can publish unsupported personal history

**Locations:** `relay_spike/session_host.py:252-253` and `relay_spike/generated_answer.py:76-78,112-114`.

The personal router uses a limited phrase list, while the general card validator uses a limited list of verbs/nouns following a pronoun. Neither is a fail-closed boundary for biographical assertions. A normal personal question outside those phrases reaches the model with no provider evidence, and an unsupported autobiographical response can pass validation and appear as talking points. This is a general grounding gap, not merely a missing education synonym.

**Exact integrated trigger:** a fresh `SessionHost(complete=injected_complete, emit=out.append)` with no personal provider receives the valid synthetic sequence from `tests/test_session_host.py`: `start()`, `speech(2)`, `end(3)`, `final(4, 'Where were you educated?')`. The injected completion returns:

```json
{"lead":"I graduated from Stanford University in 2022.","points":[],"detail":null,"assumptions":[],"coverage":["education"],"personal_fact_ids":[]}
```

**Observed output:** `model_calls=1`, `personal_bundle=false`, terminal `disposition="answer"`, and the visible card lead is exactly `I graduated from Stanford University in 2022.` Provenance is `generated_suggestion`, `checks=["format_checked"]`, `independentlyReviewed=false`. No provider-issued fact or approved evidence exists.

Direct calls to `parse_generated_card` also accepted all these lead strings with the same otherwise valid empty-fact JSON shape:

- `I graduated from Stanford University in 2022.`
- `I hold an AWS certification.`
- `I was a senior engineer at Acme for five years.`
- `My GPA is 3.9.`

The system instruction forbidding personal claims and the accurate `independentlyReviewed=false` label do not enforce the required boundary. The exact provider-rendering path is bypassed entirely.

**Correction:** enforce a fail-closed personal-intent/output policy across the general path. Personal questions such as this must retrieve approved provider facts or clarify; unsupported autobiographical assertions must be rejected even when `personal_fact_ids=[]`. Preserve exact provider-rendered facts as the only source of biographical assertions. Add integrated regressions for multiple personal question forms and generated employment/education/credential/metric assertions, including a general question whose injected candidate unexpectedly contains biography. Extending only the education word list leaves the demonstrated broader gap.

### 2. [P1] Microphone source failure silently retires all answer processing

**Primary location:** `relay_spike/session_host.py:148-149`.

**Composition evidence:** `spikes/macos-session/Sources/RelayNativeSession/SessionController.swift:164-172` removes the failed source and preserves the presentation lease for source 1. `spikes/macos-panel/Sources/RelaySessionPanel/SessionPanelController.swift:20-21` ignores microphone events; `SessionApplicationModel.forward` at `120-123` forwards them without changing `running`.

The host nevertheless calls `close()` on `source_unavailable` or `discontinuity` from either source. There is no matching full-session native stop/error transition. After microphone failure the remote pipeline still runs and the UI can retain the current card, but `host.live` is false, so all later remote events return at line 142 without answers. This is a host/native composition defect, not a finding against the imported native library's source-scoped policy.

**Exact focused sequence:** with a valid injected completion, send `start()`, `speech(2)`, `end(3)`, `final(4, 'Explain queues.')`, drain, then:

```python
event('source_unavailable', 5, 2, 1, {'reasonCode': 'capture_error'})
speech(6, 2, 3)
end(7, 2, 3)
final(8, 'Explain hash tables.', 2, 3)
```

**Observed output:** before failure `host.live=True`, one prompt, one answer. After the next complete remote question, `host.live=False`, still one prompt, and the last answer question remains `Explain queues.`

**Correction:** reconcile source-scoped failure at this seam. For an optional microphone failure, retire the microphone activity/context admission and continue remote questions under the still-live native session, with an explicit context-gap state where needed. If the chosen product behavior is to end the whole session, synchronously retire/clear the native session and visibly make it restartable instead of silently closing only the helper's answer state. Test microphone `source_unavailable` and `discontinuity` through the composed host/panel path with a subsequent remote question.

### 3. [P2] Internal follow-up context is incorrectly charged to the display-question limit

**Location:** `relay_spike/session_host.py:201-205`.

For follow-ups/corrections, `question` becomes `snap.prompt`, which includes machine-generated labels and prior/root question text. The 500-byte display-question check then rejects this expanded internal context even when every actual utterance fits the wire/display limit. Natural coding follow-ups after a moderately detailed task are withheld without reaching the generator.

**Exact first question (357 UTF-8 bytes):**

> How would you implement a bounded LRU cache for a service that accepts arbitrary string keys, stores JSON values, handles concurrent callers, and must evict the least recently used item when capacity is reached? Explain what you would clarify before choosing the data structures, especially around missing keys, updates, capacity limits, and error handling.

After it answers, send the next valid remote activity with this follow-up (66 bytes):

> What about updating an existing key while another caller reads it?

**Observed output:** the accepted machine snapshot's synthesized prompt is 526 bytes; the total model-call count stays at one; the follow-up terminates with `reasonCode="question_overflow"`. Neither actual question exceeds 500 bytes.

**Correction:** keep the current verbatim utterance/display question separate from the full semantic request context. Apply the 500-byte bound to the visible current question and include prior/root material in the already separately bounded prompt/context. Preserve correction authority and original token/fences. Add a regression with a roughly 350-byte root plus a short follow-up/correction that checks a second request is made and the complete context remains available.

### 4. [P2] History eviction silently replaces the active task's problem and drops constraints

**Locations:** `relay_spike/conversation_context.py:62-65,67-81`.

The raw-history limit of 12 observations/6000 bytes is approved and disclosed. The defect is that the independent-looking task record is rebuilt entirely from that deque: `known_problem=remote[:1]` and constraints are selected from retained remote strings. After normal exchanges evict the first task statement, the active task's known problem becomes the oldest retained follow-up and its original constraints disappear. `_kind` can still say `coding`, making the resulting task state misleading.

**Exact focused input:**

```python
c = ConversationContext()
c.observe('remote', 'Implement an LRU cache. Capacity must be three; keys are strings.')
for index in range(6):
    c.observe('microphone', f'My attempt at step {index} uses the previous approach.')
    c.observe('remote', f'How would you test case {index}?')
```

**Observed snapshot:** 12 retained dialogue rows, `task.known_problem=('How would you test case 0?',)`, `task.constraints=()`. The LRU problem, capacity three and string-key constraints are absent from the entire snapshot after only six exchanges. No explicit new task or correction replaced them.

**Correction:** retain bounded active-task problem/current constraints independently of the raw conversation ring, with explicit new-task/correction replacement and overflow handling. Eviction of raw observations must not silently rewrite the current task. Add a long mixed-speaker coding/case scenario that evicts raw rows while preserving the current problem and constraints, then changes a constraint and verifies only the new supported value is current.

## Evidence and scope

Read repository `AGENTS.md`, `docs/CONTEXTUAL_ANSWERS.md`, `docs/lanes/ANSWERS.md`, the answer implementation plan, the controller's current `relay-build-integration/docs/BUILD_CONTRACT.md`, and `coordination-2026-10-23/build-answers-report.md`.

Inspected the changed answer-owned Python modules and focused tests, all new native panel sources/tests/package/bundle script, and existing question-machine/adapter/reference and imported source/profile seams as needed. Imported macos-session/profile implementations were not independently re-audited. Known in-progress personal fixes (failed lock/emergency shutdown, late open after close, C/R relevance, Swift 6.1 MainActor closure) are intentionally not refiled. The final host must still wire the required `ProfilePort.emergencyShutdown` callback and verify that integration after the personal port changes.

Focused reproductions used the ordinary Python interpreter with `PYTHONDONTWRITEBYTECODE=1`, valid synthetic native event constructors from `tests/test_session_host.py`, and injected static completion JSON. They did not execute model-generated code. The first three findings were exercised through the real `SessionHost`; the fourth directly exercised its `ConversationContext`; the broader unsupported-claim examples directly exercised its real generated-card validator.

The builder's reported 449 Python tests, 23 native panel tests, optional HTTPX socket tests, build, fixture smoke and evaluation results were read as prior evidence, not rerun or independently re-certified here. Full regression/build/CI at the corrected final integration head remains the controller's responsibility. No live speech accuracy, entitlement, account protocol success, permissions/denial behavior, latency, usefulness, factual correctness or real-device acceptance is established by this review.
