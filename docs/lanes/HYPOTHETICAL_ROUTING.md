# Hypothetical technical request routing

Issue [#76](https://github.com/KanujVerma/relay/issues/76). Frozen base `5bde19bf10fec71fc05a55b41d05c4e367bc07e6`; verified source/test head `a5827dc72752eb019450a25c13abc12a6292f0ab`. SHA-256 of `git diff --binary 5bde19bf10fec71fc05a55b41d05c4e367bc07e6 a5827dc72752eb019450a25c13abc12a6292f0ab`: `2245e3b15927e44877405bcd0126ba9337512702585d7d715cadb3bf6317b30e`.

The exact request “Case study: design a workflow for a clinic intake team. What would you build?” and “What would you build for these users?” previously required personal evidence. The request classifier's neutral modal/procedural action grammar included design and implement but omitted build. SessionHost therefore returned personal_context_missing before generation, despite the accepted coding and feature case study requirements.

The change adds build to that existing grammar. It does not grant authority merely for a case study prefix or a build token. Existing whole-request attribution, past-action, possessive and biography checks still take precedence; the generated-output attribution parser is unchanged. No architecture, dependency, SessionHost, visual, profile, authentication, capture, global documentation or CI changes are included.

Verification uses synthetic input and injected completion only. The final regression module was observed failing seven assertions with the original grammar: six neutral build forms and the exact clinic host flow, which made zero generation calls. Restoring the one-verb addition passes all four new test methods. The host test consumes actual length-framed native session/onset/end/final records, validates closed-activity association, retains the current case study task, and publishes exactly one generated card with the original request identity. Thirteen past, resume/experience, named/passive/possessive and mixed hypothetical/history requests return personal_context_missing with no card and zero model calls. Existing output-guard regressions remain green.

Fresh verification command:

```sh
PYTHONPATH=tests /private/tmp/relay-answers-venv/bin/python -m unittest test_hypothetical_routing test_contextual_answers test_answer_review_regressions test_answer_round2_regressions test_session_host -q
```

Result: 48 tests passed, zero skips or failures; diff whitespace check passed. Before the change, the four existing modules passed 44 tests. An initial broader answer-pattern discovery also selected two unchanged OAuth loopback tests, which failed to bind localhost under the sandbox; transport code is outside this delta and those tests were not rerun. A full suite, Swift/native app build, hosted checks and hardware/account inference were not run for this classifier-only slice. This narrow English lexical policy remains conservative and is not a complete intent or biography classifier. It does not establish model answer quality or live latency. Independent scoped review and controller assembly remain separate gates; main is not merged and issue #76 remains open.
