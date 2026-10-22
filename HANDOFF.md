# Relay handoff: exact project state

Updated: 2026-10-22. Read [AGENTS.md](AGENTS.md) for new-agent protocol.

## Verified completed
- Slice 00 merged via PR #1: initial product contract, two role packs, 26 synthetic question cases, Python fixture validator and successful low-cost Linux CI.
- Slice 00B source-of-truth documentation merged in PR #3, with CI passing: AGENTS.md, vision, ADRs, flows, memory/evals, inference reference and roadmap.
- Slice 01A code merged in PR #4 (2026-10-22): local Python OAuth/PKCE/OIDC, model listing, Responses SSE and synthetic question CLI; offline CI succeeded (run 39731823184). **No live ChatGPT authorization or inference was performed.**

## Immediate next task
Issue [#2, Slice 01A: prove official ChatGPT subscription-backed text inference](https://github.com/KanujVerma/relay/issues/2). The Slice 01A experimental CLI is now on main. **Outstanding blocker:** the user must run interactive authorization and one synthetic streamed inference locally on their Mac. Instructions: docs/RUN_LOCAL_SPIKE.md. Only after response.completed should we consider account entitlement verified and proceed to Slice 01B. Keep it separate from live audio/UI/memory ingestion and from any charged API fallback.

## Locked goals
Name Relay. Real authorized interview performance, not tutoring. Epic Software Developer and junior AI/BI/data analytics focus. Local-first native macOS targeting 16 GB M2 Pro. Personal Brain and Learning Memory foundational. Fast concise grounded answer and selective QA. Role/follow-up awareness. Minimal scoped PRs with verified tests and GitHub documentation.

## Truth about implementation
- No authenticated inference through a ChatGPT-plan token has been observed for this account. CLI OAuth, catalog and streaming logic plus offline tests have passed in Linux CI, but **not run with a user's credentials**.
- No live macOS app, Zoom audio capture, diarization, Personal Brain store, Drive/GitHub import, or adaptive learning engine exists yet.
- Official Sign in with ChatGPT docs describe optional plan inference scopes; account entitlement needs an interactive local authorization and completed response. Sources: docs/INFERENCE_AUTH.md.
- Repository remains PUBLIC intentionally; owner will make private before sensitive work. NEVER commit actual user private artifacts or secrets, regardless of visibility.

## Known risks
Plan eligibility, available models, usage caps, full auth safety, streaming latency, audio routing, local ASR performance under 16 GB RAM, connector permissions, prompt injection and deletion semantics.

## New code in Slice 01A
- relay_spike/auth.py: interactive browser PKCE registration, OAuth code exchange, JWKS-based ID-token verification, protected local token file and plan scope checks.
- relay_spike/stream.py: model-catalog parsing, preview-safe response payload, strict terminal SSE validation and monotonic response timings.
- relay_spike/__main__.py: auth, models, infer and disconnect commands.
- tests/test_spike.py: offline no-network OAuth/stream tests.
- docs/RUN_LOCAL_SPIKE.md: local Mac validation without pasting tokens into GitHub.
- requirements-spike.txt: PyJWT cryptographic ID-token validation dependency (local only).
- CI validates offline behavior, not user account entitlement.

## Exact next action
User-run, local only: follow docs/RUN_LOCAL_SPIKE.md. Share just sanitized success/failure, model slug and timing numbers; **never** paste callback URLs, tokens or credentials. If permission is unavailable, record the failure and evaluate a supported alternative rather than automatically spending money.

## Exit gate for next issue
Either: actual OAuth identity and scope validation, real model-list and response.completed with observed timings on user account; OR: precise, reproducible entitlement/blocker report. Offline unit tests alone do not establish live access.

## New agent handoff
Check live GitHub issue/PR state before work, read AGENTS.md and scope documentation, then implement only Slice 01A. Finish with exact checks, status updates, risks, and next action in this file.
