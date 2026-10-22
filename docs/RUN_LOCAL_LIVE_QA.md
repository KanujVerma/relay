# Slice 01B-B2: one authorized text stream through QA

This is a **synthetic technical fixture only** feasibility test. It is not an interview listener, native overlay, personal-biography verifier, factual-correctness benchmark, or permission to use AI in a prohibited live assessment.

## Why this exists

PR #16 already implemented a safe deterministic SSE assembler, QA and turn-safe publication, but it only consumed mock SSE frames. Issue #23 connects the existing official ChatGPT-plan OAuth Responses **byte stream** to the same adapter rather than introducing another inference transport, parser, cache or model backend. No new third-party dependencies, stored sessions, paid API key path or network calls in CI.

## Dry run first

From the repo root, with an existing local Python environment:

    python3 -m relay_spike live-qa
    python3 -m relay_spike live-qa --case E09 --model gpt-6-luna --effort low

Both commands validate the EVALS fixture and print a JSON plan with one potential request. They **do not** authenticate, read stored credentials, query models or invoke inference.

## One deliberate local Mac inference

Use the existing authorized local setup described in [RUN_LOCAL_SPIKE.md](RUN_LOCAL_SPIKE.md). Only sign in if needed and independently consent to sharing ChatGPT-plan inference usage with Relay.

    python3 -m relay_spike models
    python3 -m relay_spike live-qa --case D02 --model gpt-6-luna --execute

Optional: pass --effort low or --effort medium. This command checks the current account's visible model catalog, and the existing auth module requires an active token with plan-use scope. Each explicit invocation makes **at most one** Responses request. No retry, no automatic Sol review, and no conventional separately billed API-key fallback. Avoid real names, résumés, recorded speech, private datasets and genuine interview transcripts.

## What the result means

- The CLI prints one JSON report **after** the request/QA/presentation path finishes. Only state = final_unverified can contain answer text; needs_revision, unavailable and suppressed contain no raw answer.
- QA PASS means the basic formatting, terminal completion, turn identity and narrow attribution checks succeeded. It does **not** mean the SQL/code was correct, that all subquestions were truly answered, or that an actual first useful answer arrived.
- First-text, scannable-candidate, completed, QA-decided and presented times are milliseconds since **before the HTTPS request**. The scannable-candidate marker is a heuristic, not text presented to a viewer. First-useful-verified remains null. No audio capture, native rendering, p95 or interviewer turn detection is included.
- A small independent first-person wording screen is used only for reviewed non-personal EVALS fixture questions. Any first-person term fails closed. This is not a model-authored claim verifier: all biographical facts must still follow the Personal Brain approval and source lifecycle.
- Return code 0 means final_unverified; 2 means a complete/handled model attempt did not produce an allowed display; 1 means validation/auth/transport error. Auth and HTTP error messages are sanitized and never print raw model deltas on this command.

## Offline regression checks

    python3 EVALS/validate.py
    python3 EVALS/verify_docs.py
    python3 -m unittest discover -s tests -v

New test_live_qa.py mocks HTTP headers/responses and auth: dry run triggers no authorization, one execute opens a single POST, failed/partial/oversized responses never expose generated content, unknown personal claims fail closed, superseded turns suppress callbacks, and existing infer still runs via shared transport. GitHub Actions must not authenticate or spend plan quota.

## Still needed

Ask the owner to run one explicit local Mac OAuth test and report sanitized timings, outcome, model and case ID only, with no personal source material. Before calling Relay production-ready, implement permitted session capture, real turn classification, user-verified grounding, trusted attribution checks, real semantic correctness evaluations, concurrent cancellation, model-failure handling, native rendering and true first-useful text measurements. Revisit only after evidence from actual hardware.
