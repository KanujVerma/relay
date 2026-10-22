# Relay handoff: exact project state

Updated: 2026-10-22. [AGENTS.md](AGENTS.md) defines how each new coding agent starts; check live GitHub issues, PRs and CI before trusting this snapshot.

## Verified completed repository work
- Slice 00: product contract, Epic developer and junior analytics Role Packs, 26 synthetic evaluation cases, offline validator, PR #1 merged and CI green.
- Slice 00B: durable AGENTS.md, architecture ADRs, project workflows and complete documentation baseline, PR #3 merged.
- Slice 01A: supported OAuth/PKCE/OIDC CLI, plan permission validation, model catalog and fail-closed streamed Responses, PR #4 merged; OAuth callback and token hardening, PR #5 merged. Offline CI passed.
- Slice 01A real-user feasibility: **the user provided successful Mac terminal output** on 2026-10-22. Browser authentication and ChatGPT plan inference permission succeeded, eight models listed and `gpt-6.1-sol` returned `response.completed` for a synthetic SQL WHERE/HAVING question. First text: **2640 ms**, total stream: **8306 ms**, output: **906 characters**. This is one user-reported run, not an independently repeated benchmark or evidence of unlimited usage.

## Current change
**PR #6 merged**, after Codex GitHub review identified three documentation P2 issues, all fixed and resolved, with passing exact-head CI; issue #2 closed. Issue #7, Slice 01B-A, is the active implementation.

## Exact next implementation slice
**Issue [#7: Slice 01B-A](https://github.com/KanujVerma/relay/issues/7)**. Implement short-answer prompts and a locally invoked, offline-tested benchmark comparing `gpt-6-luna` and `gpt-6.1-sol` on identical synthetic role-specific questions. No billable API fallback, no model calls from CI, no recording/Personal Brain implementation in this slice. Update HANDOFF.md with actual results.

## Slice 01B-A in-progress artifacts (not yet merged)
- `relay_spike/benchmark.py`: synthetic role cases, bounded paired comparison plan, output-format metrics, no automatically assigned correctness score.
- `relay_spike/stream.py`: preview-safe top-level concise instructions.
- `relay_spike/__main__.py`: `benchmark` command; dry-run unless `--execute` is supplied; no OAuth or model requests without execution permission.
- `tests/test_benchmark.py`: offline negative tests; `docs/RUN_LOCAL_MODEL_BENCHMARK.md`: local instructions.
- No live Luna vs Sol measurements have yet been performed, and CI must never call a model.

## Provisional model routing
- Luna: preferred fast/simple-question candidate, must pass factual and coverage checks.
- GPT-6.1 Sol: preferred more complex coding/debugging/follow-up candidate.
- Astra: optional deeper offline analysis, not a default live model.
- Official model descriptions support this division, but **Luna versus Sol latency and accuracy have not yet been compared on Relay tasks**. See [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md).

## Foundation and non-goals
Relay is a local-first native macOS interview copilot for **authorized assistance**, not a tutoring app. Primary target roles are Epic Software Developer and junior AI/BI/analytics. It should relay concise technical and verified personalized talking points, review response quality, recognize corrections/follow-ups and improve over time.
- **Personal Brain** stores verified first-person history and source provenance; never invent skills or contributions.
- **Learning Memory** tracks observed question patterns and explicit assistant corrections; it never promotes unverified speech/model text into personal facts.
- ChatGPT OAuth authentication is independent from any Drive/GitHub app connectors or ChatGPT Memory.

## Still unimplemented
No native SwiftUI app, authorized Zoom audio capture, diarization, live question detection, Personal Brain database, Drive/GitHub import, production QA pipeline or continuous learning runtime. Model latency/usage reliability, token rotation and Mac ASR resource needs require later tests.

## Privacy and CI
Repository is PUBLIC until the owner chooses otherwise. Never commit credentials, OAuth callbacks, recordings, résumés or private interview source content even after going private. Linux CI performs offline fixture/doc/tests only. GitHub Codex PR reviews are tracked usage and should be explicitly verified, not assumed free or finished just because a comment was submitted.

## New-agent action
Read [AGENTS.md](AGENTS.md), [PRODUCT.md](PRODUCT.md), [ARCHITECTURE.md](ARCHITECTURE.md), [docs/DECISIONS.md](docs/DECISIONS.md), and [docs/SLICES.md](docs/SLICES.md). Inspect the latest PR and then implement **only Slice 01B-A (issue #7)**. One small PR, actual tests, reviewed findings, updated handoff and exact next step.
