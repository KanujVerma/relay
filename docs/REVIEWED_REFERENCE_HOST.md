# B3A-3: reviewed-reference host route (Issue #57)

**Scope:** A genuinely callable, purely local Python host and terminal
demonstration for one independently reviewed technical reference, D02 WHERE
versus HAVING. No ChatGPT OAuth, model, stream, audio, real ASR, résumé,
microphone or native panel connection. This is not a generalized technical
answer engine. The existing OAuth B2/B3A CLI modes remain unchanged.

**Ownership:** Independent of ongoing transcript/question-turn PR #42,
EOU intent PR #46 and local FluidAudio PR #49. Reuses the exact existing
ActiveTurns instance through its token and atomic publication check; does
not create a second turn machine or alter question_turns.py. SwiftUI panel
PR #54 is merged, but no Python-to-Swift transport/OS authorization exists.
This slice does NOT pretend terminal stdout is a macOS GUI.

## Why direct reviewed references?

The M2 Pro owner's prior B3A-1 single D02 Luna request completed the model
response in 4,262 ms, but the narrow grammar safely withheld the entire output
as candidate_not_approved. A known fully reviewed D02 technical answer does
not need a 4-second model call. B3A-2 PR #56 established that one D02
reference as a full-question, role/category, source-linked policy match,
and explicitly excluded E09 because the canonical E09 card does not include
the code that the question requests.

This host integration connects that policy to a synchronous callback and a
second deferred-render guard. It does not change the question/topic classifier
or request a model when no reference matches.

## One synthetic terminal acceptance

From the repository root, with the repository virtualenv activated:

    python3 -m relay_spike reference-qa \
      --question "What is the difference between WHERE and HAVING?" \
      --role analytics --category sql \
      --synthetic-source --final --authorized

This is a dry run: no output answer is painted or printed, and the result
reports whether a vetted card would be eligible. To visibly print the trusted
local technical card without inference:

    python3 -m relay_spike reference-qa \
      --question "What is the difference between WHERE and HAVING?" \
      --role analytics --category sql \
      --synthetic-source --final --authorized --publish

Expected second invocation: state reviewed_reference, answer equal to the
frozen local D02 card, source_ref from the local reviewed EVALS fixture,
model_requests 0 and oauth_requests 0. first_useful_verified_ms remains null,
because this terminal demo is not a user-adjudicated native Mac timing result.
There is no paid model usage, no auth prompt or model catalog request.

The explicit --synthetic-source flag is NOT a way to certify real meeting
speech; it is only a local demo assertion. The command accepts synthetic
question text, never user-identifying private transcripts. The real native
host must prove permitted input provenance, session consent and finalized
ASR independently before constructing a remote_final PolicyInput.

An unmatched question, changed condition, dialect/metric constraint, an
unauthorized/partial source or E09 cannot automatically publish, cannot
launch fallback inference and cannot claim unverified technical accuracy.

## Host API and invariants

Production-style host code uses these Python boundaries:

- Host supplies the exact shared ActiveTurns and a current TurnToken from
  the active question/turn state machine. It must not create another turn
  manager for the display stage.
- ReferencePermission(shared_turns) begins DENIED. Only the trusted host may
  call grant() after establishing session permission. revoke(on_clear=...)
  atomically denies further publications, cancels the current ActiveTurns,
  revokes any previously issued card and synchronously clears visible
  content through the supplied host callback. Native OS TCC and meeting
  consent are separate upstream requirements, not implemented here.
- Host creates PolicyInput for an authorized *final* source, with the actual
  full question, role, category and constraints. Default PolicyInput fields
  are unknown/partial/not authorized. No caller-provided case ID can bypass
  text matching. B3A-2 also checks the reviewed reference against the
  current EVALS question source before permitting it.
- preview_reference performs policy evaluation only, exposes no text, and
  never invokes a callback or model/network request.
- publish_reference evaluates the host-authorized request, then checks
  consent AND current token together atomically through the existing
  ActiveTurns._publish_if_current. The synchronous on_present callback gets
  ONLY an immutable, separately reviewed ReferenceCard. On failure the
  result is a fixed reason code with NO card.
- If on_present merely queues SwiftUI work rather than painting immediately,
  the UI host MUST call render_queued_card at ACTUAL deferred paint time,
  using the same exact ReferenceCard object, same consent gate and same
  ActiveTurns instance. The host validates card identity, local provenance,
  current session authorization and token AGAIN before on_paint.
  Never copy the token or re-stamp it when delivery arrives.
- If the active question is corrected, interrupted or cancelled, the question
  host must clear already-visible content immediately and invalidate the
  token. ActiveTurns cancellation and stale queued event suppression are
  tested here; integrating clear-on-question-change into the native panel
  remains a distinct host bridge task, not a claimed result of this PR.
- The permission lock is acquired before ActiveTurns' lock for revoke and
  callback publication. Callbacks must remain synchronous, cheap and
  non-reentrant; a callback that raises does not leave an issued card valid
  for later queued paint.
- Only the locally reviewed D02 technical card can be exposed. Source
  references and state/reason labels are local enums/constants, not
  model-generated text, unverified evidence IDs or personal facts.

## Synthetic security and correctness regressions

Run:

    python3 EVALS/validate.py
    python3 EVALS/verify_docs.py
    python3 -m unittest tests.test_reference_host -v
    python3 -m unittest discover -s tests -v

The tests cover the complete positive reference path; explicit consent/source
and finality; role/category/constraint and Unicode-negation differences;
all 64 author-labeled B3A-2 development/evaluation cases; absence of
fallback authentication, catalog, networking or model inference; E09
ineligible without code; cancellation and new-turn ABA protection; permission
revocation both before and AFTER policy evaluation; synchronized queued UI
render suppression; forged card and policy decisions; callback exceptions
rolling back issued-card authorization; and immutable public envelopes.

No real account or macOS GUI is exercised in CI. A CI test count or zero
unsafe acceptances on this corpus is not production safety proof. The host
API can be unit-tested on Linux; its actual 16 GB M2 Pro permitted-session
latency and usefulness must be measured separately with independent human
review. Do not convert model first_text_ms into first_useful_verified_ms.

## Remaining work after this slice

1. **Native bridge / hardware proof:** Connect actual finalized, consented
   03B-A/03B-B question events and the SwiftUI PR #54 reducer to this trusted
   decision through a reviewed language boundary. Preserve a source-stamped
   session epoch/generation and current token across the queue and recheck at
   MainActor paint. Prevent already-rendered old cards from remaining after
   stop, correction or TCC revocation. Test on the real M2 Pro.
2. **Dynamic technical responses:** Independently evaluate safe, useful
   answers to unseen coding, SQL and analytics questions; current suggestions
   remain unverified/unpublished and must not be auto-selected by keyword
   matching or a model's own assertion.
3. **Personal provenance:** Real approved fact imports, actor contribution
   grounding and revocation checks are separate; a source ID is not proof.
4. **Measured speed:** The zero-network reference path may be much faster
   than a model request, but no p50/p95 first useful or job-outcome
   improvement can be claimed without a real enabled UI and human rating.

Security and consent: this is an ordinary visible user-controlled interview
assistant for permitted use. No stealth capture or undisclosed interview
assessment assistance is implemented or promised.
