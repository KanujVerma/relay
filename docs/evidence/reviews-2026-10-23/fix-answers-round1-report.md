# Answer review round 1 corrections

Immutable corrected head: 2e06c6d03e7606532c9cf16c961fd4841d327160, pushed/clean, feature/contextual-answer-panel-2026-10-23, PR67 https://github.com/KanujVerma/relay/pull/67. Reviewed baseline cd5286a50700b8040f9e9b03b65c8f960e98fb1c. No main merge, screen/controls composition, workflows, native-capture-library edits, live capture/model/account calls, private content or Keychain actions.

## Four corrected findings

The independent report and source were read before patching. New regressions reproduced all four findings, initially producing19failed assertions. tests/test_answer_review_regressions.py now has10passing tests with multiple subcases and real SessionHost paths.

1. Personal authority: ambiguous biographical/addressed requests conservatively use provider facts or clarification. General visible prose uses a restricted neutral directive/talking-point form; person references and biographical/credential/authority content reject regardless of empty model fact IDs. Every visible prose field is checked; code comments/string literals cannot hide those claims, while identifiers such as i remain valid. This fail-closed lexical/form policy is NOT semantic verification, a complete language classifier or factual correctness certification. Legitimate prose outside the form can withhold; no retry/critic was added. Exact issued provider facts remain the only biographical render path. Tests cover education/employment/GPA/certification/employer/behavioral questions, unexpected biography on a technical question, original Stanford/AWS/Acme/GPA outputs, third-person/directive-wrapped biography, code hiding and a positive real approved education fact rendered exactly with zero model calls.
2. Microphone scope: source1 source_unavailable/discontinuity disables further mic admission, removes failed mic activities and records a fixed context_gaps marker. Remote session/card/turn remains live; later remote questions answer for both controls. Source2 failure/full stop still closes the host. Imported native policy was not changed.
3. Display versus semantics: Request.question retains complete semantic context; display_question is the current verbatim utterance. Only display_question has the500byte UI bound. Generation gets current_request and semantic_request; reference/personal routing retains full semantics. The357byte root+66byte follow-up makes the second request and displays the exact follow-up with complete root/follow-up context. No clipping.
4. Durable task: current problem/field constraints are independent of the12row/6000byte raw ring. Explicit new-task/case restatements reset them; supported explicit field corrections replace only that field. Unknown/embedded corrections require clarification. Problem bound4096bytes, at most8current fields/8192combined bytes. Overflow is explicit, survives later raw rows, blocks generation and clears only after a supported bounded restatement. Integrated long coding/case tests evict raw rows, preserve problem/constraints, replace capacity/latency and exclude old current values. Host overflow test confirms no extra generation.

## Required personal emergency adapter

Imported original-owner d8bb0dc as1472c75, eb98e41 as79e19f2, 7ace412 as2775fb4. No peer-owned production source edited after import.

SharedProfileBinding binds one client/controller lifecycle to one helper; retired bindings cannot restart it. Before its first emergency await the app stops the source controller, retires display/helper identities, fences queued source/answer delivery and rejects pending continuations/writes. It awaits actual old-child termination/reap; recovery remains blocked until completion and then requires fresh helper/port/client/controller. Normal close retains the shared helper only after exact ok/locked/ready acknowledgment.

Shared HelperTransport installs its exit receipt in terminationHandler BEFORE launch, retires admission synchronously and awaits the receipt asynchronously. No waitUntilExit, Thread.sleep or second production reaper. Actual-child tests cover missing acknowledgment forcing helperStopped, old-client command/restart rejection and post-completion waitpid(WNOHANG)==-1/ECHILD. Original-owner PipeProfilePort uses the same receipt pattern with36EOF/early-exit/ignored-SIGTERM schedules. Local termination does not certify stopped provider token work.

## Verification

- Full Python460passed/23optional skips:21converters+2HTTPX socket tests absent in ordinary interpreter. Existing ResourceWarnings and expected negative CLI diagnostics remain; no failures.
- Focused round1:10tests passed.
- Native personal after7ace412:17passed, including actual exit/reap schedules and lifecycle/lock/emergency behavior.
- Native panel/helper:25passed, including required emergency close and actual child reaping.
- Production relay-panel-session build passed after final recovery-admission guard. Local Swift6.4; controller-owned hosted Swift6.1/Xcode26.2 CI pending.
- EVALS26questions,20documentation/link checks and git diff --check passed.
- No live/hardware/private/model/account/Keychain acceptance was performed or inferred. Earlier offline-window smoke remains historical; this round used injected sources/completions and actual local helper processes.

## Continuation

Answer-owned changed source: generated_answer/conversation_context/session_host; SessionApplicationModel/HelperTransport/SessionPanelController; focused regressions and panel test dependency. Lane details: docs/lanes/ANSWERS_REVIEW_R1.md and ANSWERS.md. Peer personal commits are separately identified above.

Controller next: independently re-review this exact head against cd5286a. Composition owner may import2e06c6d for separately authorized screen/controls work; no duplicate fixes or main merge implied.
