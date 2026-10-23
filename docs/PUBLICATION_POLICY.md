# Slice 01B-B3A-2: offline technical-answer publication and evaluation

**Issue:** [#55](https://github.com/KanujVerma/relay/issues/55). **Scope:** offline
policy and synthetic evidence only. No OAuth, model requests, capture, actual user
history, private documents, source imports or native UI. This document is also
the slice's decision record, kept separate from the shared DECISIONS.md while
other agents edit that file.

## Decision: reviewed-reference first, unverified model second

The owner's real Mac B3A-1 result at main 75ed6a6 demonstrated a completed
D02 Luna request in 4,262 ms, first text at 2,731 ms, zero published answer and
technical_gate_reason candidate_not_approved. That means transport and
fail-closed QA work, but a normal model-generated response does not fit the
narrow full-response grammar. Do not expand keyword-based acceptance just to
obtain a PASS.

For a **known, complete, independently reviewed technical question**, choose
a local reviewed reference **before** any inference. Match the actual
host-supplied final question text, role, category and unchanged constraints
instead of trusting the caller's case ID or an LLM's answer. The reference
and source identifier are local constants, not model output. An unseen model
answer is **model_suggestion_unverified**, internal-only, not published.
Personal or behavioral claims require real consented, actor-specific verified
Personal Brain evidence and cannot be certified by source-ID strings.

Initially only **D02 WHERE versus HAVING** is eligible for a direct reviewed
reference. Its two required technical propositions cover the exact fixture,
and independent SQLite queries test row-versus-group filtering. **E09 is
deliberately ineligible**: its existing canonical card describes binary
search and O(log n) time / O(1) iterative space, but its actual EVALS question
says *write binary search* and the card provides no code. Publishing it as a
complete response would violate question coverage. The other 24 EVALS
questions also have no matching coverage-complete reviewed reference.

## State and publication contract

| State | Public text | Meaning |
|---|---|---|
| reviewed_reference | Exact independently reviewed local D02 card | Full permitted host question, category, role and constraints match |
| model_suggestion_unverified | **None** | Completed candidate exists, but correctness and personal attribution unverified |
| needs_revision | **None** | Personal/behavioral content, extra constraints, unknown category, oversized candidate or correction requiring verification |
| unavailable | **None** | Missing reviewed match, denied source, partial/discontinuous question, stale turn or incomplete SSE |

This contract is an **offline decision object**, not a publishing callback.
The production host must revalidate ActiveTurns at the actual synchronous
display boundary and again if a UI render is deferred. Unspecified runtime
policy inputs default to **host not authorized, unknown source and partial
question**, so omitting any permission/finality evidence fails closed.
Only the controlled synthetic evaluation fixture factory supplies positive
source/finality/permission defaults. A source_channel value
is a trusted-host assertion, not proof of the interviewer's biometric identity
or consent by itself. The host must obtain permission before treating remote
ASR as a final question.

Exact normalized match permits only ASCII case and whitespace variation;
it preserves punctuation, negation, year, JOIN type, metrics, and question
subparts. Additional host constraints fail closed. Any unreviewed model
candidate cannot select a reviewed local reference, even if it contains
the right terms or a claimed source ID. All other output states expose no
candidate text or citation and never trigger network or model inference.
Offline first_useful_verified_ms is always null, not measured latency.

## Reproducible evaluation

Run, from the repository root, using the repository's virtual environment:

    python3 -m relay_spike.publication_policy
    python3 -m unittest tests.test_publication_policy -v
    python3 EVALS/validate.py
    python3 EVALS/verify_docs.py
    python3 -m unittest discover -s tests -v

The pinned EVALS/publication-policy-cases.jsonl file contains **64 synthetic
author-labeled cases**, split into **21 development and 43 evaluation**. All
26 existing Epic/analytics EVALS questions are REQUIRED exactly once under
their BASE-IDs, with the original question_ref and no forged replacement;
the harness fails closed if a baseline is missing or mapped to another case. additional cases exercise benign variants, false or unsupported SQL,
JOIN fanout, COUNT and NULL, ranking ties, missing code in E09, multi-part
coverage, negations, changed requirements, invented first/third-person
work achievements, model prompt injection, stale/cancelled turns, unknown
remote source, mic-only input, unnumbered or partial ASR semantics and
permission denial.

Each row has an explicit expected state, author-labeled safe-to-publish
status, independently separate technical-correctness and question-coverage
labels, annotated usefulness and rationale. The harness reports split
counts, expected/actual state mismatches, unsafe published, benign withheld,
manually annotated useful published, zero model requests, and no first-useful
timing. **all_guards_met** requires zero unsafe published AND zero state
mismatches across both partitions. A published row is counted unsafe if its
author label says it should not publish, its technical-correctness label
is not correct, its question-coverage label is not complete, or its annotated
usefulness is false. A changed known-question mapping is also checked against
the original EVALS question, role and category. Returned decision reasons
are restricted to a closed set of local, state-specific codes, never copied
from model text, question input, or claimed source identifiers.

SQL's WHERE/HAVING grouping, JOIN grain inflation and NULL-counting cases
have small **executable in-memory SQLite independent oracles** in
tests/test_publication_policy.py. Other correctness and usefulness labels
are author annotations, **not** independently adjudicated coding correctness.
The evaluation partition is fixed separately but was authored in the same
development pass: it is **not blinded, independently collected or a
deployment-representative sample**. Zero unsafe accepts on this fixture set
cannot justify a general safety claim. False withholding of benign
technical suggestions is expected until a new review/publication policy exists.

## Next separately reviewed runtime slice

**B3A-3: zero-model reviewed-reference routing**, initially D02 only.

1. Integrate the exact host-authorized final question match before OAuth
   inference, using the existing shared turn coordinator. A known reviewed
   D02 match needs **zero** model calls; unmatched questions cannot fall
   through into automatic unverified model publication.
2. Keep distinct rendered states, reviewed technical reference provenance,
   explicit coverage, current consent/role, and a final atomic ActiveTurns
   check before publication. Stale, partial, corrected, interrupted,
   unauthorized or misattributed questions must never display a card.
3. Preserve the existing legacy B2/B3A opt-in path and plan-backed inference
   restrictions. Do not route E09 until a truly complete code-bearing
   reference is reviewed and independently evaluated.
4. Mocked integration tests must prove zero network for matched D02, zero
   stale outputs, no model-created personal context and no private output.
   Obtain real Mac hardware/permission and latency measurements separately.
5. Reconcile HANDOFF.md, docs/SLICES.md and docs/DECISIONS.md after active
   PRs #42/#46/#49/#54 settle; do not overwrite those agents' files.

**Later:** independently evaluate a practical policy for unseen SQL,
coding and analytics responses, with domain-executable checks where feasible,
human-rated technical usefulness and personal provenance review. Early
sentence-level model-text display deserves its own race/failure contract;
a completed model stream or absent first-person regex hit is not proof of
correctness or of invented-work absence. Never add mandatory extra model
calls or a separately billed API key without an explicit decision.
