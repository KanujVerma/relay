# B3A-0: technical candidate-to-reviewed-card evaluation (offline only)

This is a deliberately bounded experimental evaluation, NOT a general
answer-truth classifier, autobiography verifier, streaming UI or source of
model-authored public text.

## Problem established by real Mac B2 testing

Two one-request Luna tests (D02 and E09) completed OAuth-backed Responses SSE
on the owner's M2 Pro and reached deterministic QA. The whole-string B2 smoke
allowlist withheld both natural responses as "personal_attribution_not_classified".
Model transport passed; no actual talking point was published.

## Chosen narrow trust boundary

- Reuse the existing synthetic D02 SQL and E09 coding fixture topics.
- Accept small variations of model phrasing only when a CLOSED technical
  vocabulary and reviewed proposition rules pass. For D02 the candidate needs
  WHERE+row filtering and HAVING+group filtering in noncontradictory order. For
  E09 it needs sorted input, halving, logarithmic time and constant auxiliary
  space for an *iterative* algorithm.
- Reject EVERY unknown token or unsupported punctuation, including named,
  third-person or implied work history, fabricated achievements, Unicode
  confusables, instructions, incorrect and incomplete answers.
- The model candidate is NEVER the published output. An accepted verdict
  selects immutable local reviewed reference copy, separate from model words.
  This removes the need to infer autobiography from the absence of regex hits.
- "Publishable" means synthetically eligible to select one local reference card.
  It does NOT prove the entire generated text is correct, a user has that
  experience, or a future response is accurate. Keyword/proposition matching
  can miss semantic negation, and the closed vocabulary sacrifices coverage.

The original B2 whole-answer exact match path remains untouched. No
authentication, model usage, stream, UI, audio or personal memory calls occur.

## Fixed evidence gate

Hand-authored file: EVALS/technical-answer-gate.jsonl (18 approved, 26 withheld cases). Includes varied positive
paraphrases and adversarial negatives, including unsupported career claims,
wrong clause ordering/complexities, prompt injection and Unicode confusables.

To run offline:

    python3 -m relay_spike.technical_gate
    python3 -m unittest discover -s tests -v

The evaluator reports only aggregate counts and must see all reviewed benign
paraphrases accepted and NO curated unsafe candidate accepted. These are fixed,
author-labeled cases rather than a held-out or blinded accuracy evaluation.
Never extrapolate test-set false acceptance to a production error guarantee.
No personal questions may use this gate.

## Separate B3A-1 implementation acceptance

1. Keep unchanged legacy B2 smoke CLI behavior. Implement explicit opt-in
   bounded technical-card mode only for D02/E09, outside any 03B-A/ASR scope.
2. Feed original bounded Responses SSE to existing consume_stream; require
   response.completed, active TurnToken, and exactly one user-authorized
   request. No partially displayed text before terminal completion.
3. Apply the independent gate to the completed *untrusted* raw model text.
   Convert accepted responses to the separately reviewed technical card.
   Reject nonmatching outputs with status only; do not leak raw output in
   callbacks, error strings, logs or JSON metrics.
4. Pass the fixed canonical card to the existing deterministic qa.assess
   path. The trusted "absent" classification is limited to the canonical
   card, never the original model response. Prevent a bad classifier/renderer
   output or interrupted turn from publishing anything.
5. Test both accepted and withheld candidates via injected synthetic SSE,
   failed/incomplete/malformed/replayed streams, stale turn replacement,
   adversarial biography assertions, extra model request absence and
   dry-run preflight. Report first_text, completion, QA and presentation
   separately. Do not call first_text "first useful".
6. Run exact-head CI and Codex review. Do not convert this to a general
   inferred-biography sanitizer or require a mandatory second model call.

Future work: general technical correctness and grounded personal-answer
evaluation, native ASR-to-turn adaptation, and separately designed early
provisional presentation with careful failure/rollback UX.
