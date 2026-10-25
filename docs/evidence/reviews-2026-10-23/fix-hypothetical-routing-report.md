# Hypothetical routing correction report

Issue: [#76](https://github.com/KanujVerma/relay/issues/76). Published draft: [PR #77](https://github.com/KanujVerma/relay/pull/77), attached to the current Codex task. Main was not merged; issue #76 remains open.

- Checkout: `<workspace>/work/relay-build-hypothetical-routing`.
- Branch: `feature/hypothetical-routing-2026-10-23`.
- Frozen PR base: `build/hypothetical-routing-foundation-2026-10-23` at `5bde19bf10fec71fc05a55b41d05c4e367bc07e6`.
- Verified source/test commit: `a5827dc72752eb019450a25c13abc12a6292f0ab`.
- Published final head: `62b30c417f451b761a80528ef3de7468cb7dd441` (one documentation-only commit after the source head).
- Source/test diff SHA-256: `2245e3b15927e44877405bcd0126ba9337512702585d7d715cadb3bf6317b30e`.
- Complete base-to-final diff SHA-256: `27a1d573eae8e83e71ea3932f1d1d3125206e1d99af5bb015d94fee0c49135e9`.

Hashes are for `git diff --binary BASE HEAD`. Connector creation returned the exact base/final head above, draft true, two commits and three changed files. Source/test equivalence between the reviewed source and final documentation head was checked with `git diff --exit-code SOURCE HEAD -- relay_spike tests` and passed. Final working tree and diff whitespace check are clean.

## Scope and cause

`relay_spike/generated_answer.py` request classification only: add build to the existing modal/procedural neutral action alternatives, after the unchanged whole-request attribution, personal-history and possessive checks. The earlier classifier included design and implement but omitted build, causing the exact ordinary clinic case study and “What would you build for these users?” to route to personal_context_missing before generation. There is no case-study-prefix or bare-build-token bypass. Generated output attribution/parser, SessionHost, visual/image/UI, profile, authentication, capture, global documentation and CI are unchanged.

`tests/test_hypothetical_routing.py` contains four new methods, six neutral build forms and thirteen conservative personal/mixed cases. The clinic end-to-end test consumes actual length-framed synthetic native session/onset/end/final events, including closed-activity evidence. The generated prompt retains the exact current request, case study problem, flow stage, ready state and empty constraints; exactly one generated card preserves original request/sequence identity. Thirteen past, resume/experience, named/passive/possessive and mixed hypothetical/history requests yield personal_context_missing, no card and zero model calls. No model, account, private source, permission or capture is exercised.

## Fresh evidence

1. Existing contextual answers, round-1 review, round-2 review and SessionHost baseline: 44 tests passed.
2. New tests before production change: seven expected assertion failures (six neutral classification cases plus clinic host zero generation); all negative tests passed. After correcting the injected fixture to the established neutral output form, removal of the build addition again reproduced all seven expected failures. The production change was restored in a finally block.
3. Final verification, repeated after lane documentation: `PYTHONPATH=tests /private/tmp/relay-answers-venv/bin/python -m unittest test_hypothetical_routing test_contextual_answers test_answer_review_regressions test_answer_round2_regressions test_session_host -q`: 48 tests passed, zero skips/failures. Diff check passed.
4. Root independently accepted frozen source a5827dc in a separate detached clone: four new tests, five additional routing controls, two unchanged-output attribution controls and diff check passed. Root supplied this review result through the coordination channel; the worker did not self-claim independent review.

## Limits and next action

An initial broad answer-pattern discovery selected 32 tests: 30 passed and two unchanged OAuth socket tests errored because sandbox localhost binding was denied. No transport rerun/escalation was needed; root confirmed prior joined transport evidence. Full suite, native/Swift app builds, hosted checks, hardware quality, live account/model behavior and latency were not measured for this classifier-only patch. The conservative English lexical policy is not a full semantic intent classifier.

Root should record its scoped review, compare the frozen final source and assemble PR #77 into the controller build. Main merge, issue closure and joined/live acceptance remain separate controller/owner decisions. No further source edits are queued in this worker.
