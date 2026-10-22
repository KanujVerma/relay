# Relay handoff: exact project state

Updated: 2026-10-22. Read [AGENTS.md](AGENTS.md) for new-agent protocol.

## Verified completed
- Slice 00 merged via PR #1: initial product contract, two role packs, 26 synthetic question cases, Python fixture validator and successful low-cost Linux CI.
- Slice 00B source-of-truth documentation (current PR): AGENTS.md, expanded vision, ADR ledger, workflows, memory/eval plan, inference research and roadmap. Docs only, not new runtime capability.

## Immediate next task
Issue [#2, Slice 01A: prove official ChatGPT subscription-backed text inference](https://github.com/KanujVerma/relay/issues/2). Once docs are merged, implement a very small user-authorized OAuth + streamed Responses proof or document exact blocker. Keep it separate from live audio/UI/memory ingestion and from any charged API fallback.

## Locked goals
Name Relay. Real authorized interview performance, not tutoring. Epic Software Developer and junior AI/BI/data analytics focus. Local-first native macOS targeting 16 GB M2 Pro. Personal Brain and Learning Memory foundational. Fast concise grounded answer and selective QA. Role/follow-up awareness. Minimal scoped PRs with verified tests and GitHub documentation.

## Truth about implementation
- No authenticated inference through a ChatGPT-plan token has been observed for this account.
- No live macOS app, Zoom audio capture, diarization, Personal Brain store, Drive/GitHub import, or adaptive learning engine exists yet.
- Official Sign in with ChatGPT docs describe optional plan inference scopes; account entitlement needs an interactive local authorization and completed response. Sources: docs/INFERENCE_AUTH.md.
- Repository remains PUBLIC intentionally; owner will make private before sensitive work. NEVER commit actual user private artifacts or secrets, regardless of visibility.

## Known risks
Plan eligibility, available models, usage caps, full auth safety, streaming latency, audio routing, local ASR performance under 16 GB RAM, connector permissions, prompt injection and deletion semantics.

## Exit gate for next issue
Either: actual OAuth identity and scope validation, real model-list and response.completed with observed timings on user account; OR: precise, reproducible entitlement/blocker report. Offline unit tests alone do not establish live access.

## New agent handoff
Check live GitHub issue/PR state before work, read AGENTS.md and scope documentation, then implement only Slice 01A. Finish with exact checks, status updates, risks, and next action in this file.
