# Relay handoff: exact project state

## Local proof observed (user-reported, 2026-10-22)
The user ran the experimental CLI on their Mac. OAuth identity and ChatGPT plan permission succeeded. The account listed eight models. A synthetic SQL WHERE/HAVING question completed with `gpt-6.1-sol`: first text 2640 ms, total 8306 ms, 906 output characters, response.completed true. No API key was entered. This is **one user-reported test**, not an independent measured benchmark or unlimited entitlement.

**Status:** Slice 01A feasibility gate satisfied for this account/sample. Next Slice 01B-A: model comparison and concise-response formatting (docs/MODEL_STRATEGY.md), then quality gate. Do not run live calls in CI. A Codex GitHub PR review has been requested for this document change (check the actual PR status; a request does not prove completed review). See docs/PR_REVIEW.md.


Updated: 2026-10-22. Read [AGENTS.md](AGENTS.md) for new-agent protocol.

## Verified completed
- Slice 00 merged via PR #1: initial product contract, two role packs, 26 synthetic question cases, Python fixture validator and successful low-cost Linux CI.
- Slice 00B source-of-truth documentation merged in PR #3, with CI passing: AGENTS.md, vision, ADRs, flows, memory/evals, inference reference and roadmap.
- Slice 01A code merged in PR #4 (2026-10-22): local Python OAuth/PKCE/OIDC, model listing, Responses SSE and synthetic question CLI; offline CI succeeded (run 39731823184). **User later provided successful live OAuth and inference terminal output; see top-of-file proof.**

## Immediate next task
Issue [#2, Slice 01A: prove official ChatGPT subscription-backed text inference](https://github.com/KanujVerma/relay/issues/2). The Slice 01A experimental CLI is now on main. **This blocker is resolved for the user-reported sample.** Next build the short-answer and model comparison slice, keeping actual account usage limits in view. Instructions: docs/RUN_LOCAL_SPIKE.md. A response.completed was reported. Proceed to Slice 01B-A model benchmark after review/merge of the proof documentation. Keep it separate from live audio/UI/memory ingestion and from any charged API fallback.

## Locked goals
Name Relay. Real authorized interview performance, not tutoring. Epic Software Developer and junior AI/BI/data analytics focus. Local-first native macOS targeting 16 GB M2 Pro. Personal Brain and Learning Memory foundational. Fast concise grounded answer and selective QA. Role/follow-up awareness. Minimal scoped PRs with verified tests and GitHub documentation.

## Truth about implementation
- One successful authenticated inference has now been reported and recorded in this file. CLI OAuth, catalog and streaming logic plus offline tests have passed in Linux CI, but **not run with a user's credentials**.
- No live macOS app, Zoom audio capture, diarization, Personal Brain store, Drive/GitHub import, or adaptive learning engine exists yet.
- Official Sign in with ChatGPT docs describe optional plan inference scopes; account entitlement needs an interactive local authorization and completed response. Sources: docs/INFERENCE_AUTH.md.
- Repository remains PUBLIC intentionally; owner will make private before sensitive work. NEVER commit actual user private artifacts or secrets, regardless of visibility.

## Known risks
Plan eligibility, available models, usage caps, full auth safety, streaming latency, audio routing, local ASR performance under 16 GB RAM, connector permissions, prompt injection and deletion semantics.

## Slice 01A callback hardening
**PR #5 merged (2026-10-22)**: the local CLI now ignores wrong-state/wrong-Host callback requests and rejects missing or malformed token records. Offline regression tests, fixture checks and documentation validation passed on the exact PR head. **A subsequent user-provided local authorization and streamed response succeeded; see proof above.**

## New code in Slice 01A
- relay_spike/auth.py: interactive browser PKCE registration, OAuth code exchange, JWKS-based ID-token verification, protected local token file and plan scope checks.
- relay_spike/stream.py: model-catalog parsing, preview-safe response payload, strict terminal SSE validation and monotonic response timings.
- relay_spike/__main__.py: auth, models, infer and disconnect commands.
- tests/test_spike.py: offline no-network OAuth/stream tests.
- docs/RUN_LOCAL_SPIKE.md: local Mac validation without pasting tokens into GitHub.
- requirements-spike.txt: PyJWT cryptographic ID-token validation dependency (local only).
- CI validates offline behavior, not user account entitlement.

## Exact next action
Implement Slice 01B-A benchmark and short answer templates using the account-proven OAuth route. Keep live model comparisons local and optional, no GitHub CI network use, no paid API fallback. Compare Luna and Sol before choosing a permanent default.

## Exit gate for next issue
User-provided CLI output shows scope, eight models, and a completed streamed response; this gate is satisfied for the observed account, with reliability and quota still requiring later testing.

## New agent handoff
Check live GitHub issue/PR state before work, read AGENTS.md and scope documentation, then implement only Slice 01A. Finish with exact checks, status updates, risks, and next action in this file.
