# Relay

**Native, local-first macOS personal interview copilot.** Relay is being designed to detect questions in authorized interviews, retrieve verified personal/job context, and surface fast, accurate, concise talking points. Continuous learning improves the assistant's answers and relevance, not a generic tutoring curriculum.

**Status (2026-10-22):** Slice 00 contract and 26 synthetic fixtures merged. Slice 00B documents the complete architecture and new-agent handoff. Inference authentication, live audio and the app are still **unimplemented/unverified**. Repository is public by owner's choice; never commit private data or credentials.

## New agent: start here
[AGENTS.md](AGENTS.md) -> [HANDOFF.md](HANDOFF.md) -> [PRODUCT.md](PRODUCT.md) -> [docs/DECISIONS.md](docs/DECISIONS.md). GitHub is the durable source of truth, no conversation history required.

## Product and design
- [PRODUCT.md](PRODUCT.md): locked product contract and acceptance criteria
- [docs/PRODUCT_VISION.md](docs/PRODUCT_VISION.md): UX, role specialization, answer style and continuous learning
- [ARCHITECTURE.md](ARCHITECTURE.md): components and trust boundaries
- [docs/DECISIONS.md](docs/DECISIONS.md): why architectural choices exist and what remains provisional
- [docs/WORKFLOWS.md](docs/WORKFLOWS.md): onboarding, permitted live session, quality gate, interruptions and feedback
- [docs/MEMORY_AND_EVALUATION.md](docs/MEMORY_AND_EVALUATION.md): Personal Brain, Learning Memory, schema sketches and eval rules
- [docs/INFERENCE_AUTH.md](docs/INFERENCE_AUTH.md): official subscription OAuth/streaming requirements and gaps
- [docs/SLICES.md](docs/SLICES.md): incremental PR roadmap
- [docs/REFERENCES.md](docs/REFERENCES.md): official sources and open-source projects under evaluation
- [ROLE_PACKS/epic-software-developer.md](ROLE_PACKS/epic-software-developer.md)
- [ROLE_PACKS/junior-data-analytics.md](ROLE_PACKS/junior-data-analytics.md)

## Checks and next step
Run: python3 EVALS/validate.py (structural validation, not language-model grading). GitHub Actions runs a short Linux fixture check. Next technical issue: [#2, prove subscription-backed text inference](https://github.com/KanujVerma/relay/issues/2), with no separately charged API calls and no real user data in code or CI.

Consent and privacy matter: the app will not guarantee undetectability or facilitate undisclosed live assessment help where prohibited.
