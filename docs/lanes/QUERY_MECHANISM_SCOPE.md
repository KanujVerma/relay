# Query mechanism grammar

2026-10-23. Owner: `/root/compose_context_controls`, GPT-6.1 Sol xhigh.
Base: `db768fdeebb7f084b8619b2eae54d8aabebe0065`, frozen branch
`build/resume-coverage-foundation-2026-10-23`. Own branch:
`fix/query-mechanism-grammar-2026-10-23`.

## Problem and change

The ordinary typed follow-up “How does that queue work?” was withheld as
`personal_context_missing` even with an accepted technical question as its
basis. The conservative attribution matcher interpreted capitalized “How” as
a named subject and “does” as an attribution predicate. Technology names in
“How does Python work?” could independently match the history-request rule.

The correction is confined to query admission. A leading present-tense
How/What-does mechanism relation is grammatical framing. Its remaining clauses
still undergo the existing attribution checks. Past-tense, possession,
biography, current/historical my/our team, passive attribution and mixed personal
tails continue to require approved personal evidence. Prospective team planning
uses the existing modal/procedural coaching grammar; it asserts no past team
ownership. Every nonplanning team mention still needs facts. Typed host-owned semantic
captions are removed before this query check; the original current question
and retained basis remain separate lines and retain their content.

No name registry, technology registry, new model route, fact authority or
generated-output policy was added. The existing generated-output attribution
function and its consumers are unchanged.

## Approved ambiguity and limit

“How does Morgan implement a queue?” may request generic coaching or
clarification. Admission does not establish who Morgan is or what Morgan
actually implemented. A generated claim such as “State service was built by
morgan” still fails final card validation. “How did Morgan implement the
queue?”, “your queue”, team ownership and attributed extra clauses still need
approved facts. This is a bounded lexical admission rule, not semantic identity
resolution. The broader résumé coverage work is separate and unimplemented in
this patch.

## Verification

`tests/test_query_mechanism_scope.py` has seven tests with twelve positive
mechanism/planning phrases, twenty-four personal/attribution negatives, real
`SessionHost` automatic and typed-basis flows, and malicious generated-output
controls. Each technical follow-up uses
an actually accepted fresh technical basis within the existing retained-basis
budget. Completions are injected neutral synthetic JSON; no account or network
model is used.

- Exact base source with the new regression: six tests, 21 failed assertions.
- First scoped review found an introduced planning false withhold: the initial
  unconditional my/our-team guard blocked two previously eligible prospective
  case-study requests. The expanded regression fails six assertions against
  that initial source, and its automatic team-planning control passes base.
- Corrected source: all seven pass.
- New tests plus existing round-two attribution, contextual answer, review,
  typed-request and session-host files: all 74 pass.
- AST-extracted source of `_has_individual_attribution`, `_ATTRIBUTION`,
  `_HISTORY_REQUEST`, `_CONTRIBUTION_ASSERTION` and `_NEUTRAL_START` compares
  equal to base.

Run from the repository root:

```sh
PYTHONPATH=tests /private/tmp/relay-answers-venv/bin/python -m unittest \
  tests.test_query_mechanism_scope tests.test_answer_round2_regressions \
  tests.test_contextual_answers tests.test_answer_review_regressions \
  tests.test_user_question tests.test_session_host -q
```

No native source, shared handoff, contract, workflow, package or private data is
changed. Full product build and full-suite/hosted acceptance are outside this
query-only checkpoint; independent own-delta review remains required.
