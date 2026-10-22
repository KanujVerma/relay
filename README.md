# Relay

**Native, local-first macOS personal interview copilot.** Relay is being designed to detect questions in authorized interviews, retrieve verified personal/job context, and surface fast, accurate, concise talking points. Continuous learning improves the assistant's answers and relevance, not a generic tutoring curriculum.

**Status (2026-10-22):** Slice 00 contract and 26 synthetic fixtures merged. Slice 00B documents the complete architecture and new-agent handoff. The Slice 01A OAuth/Responses CLI is **implemented and has a successful user-reported local OAuth + gpt-6.1-sol streamed response**; live audio and the macOS app are still unimplemented. Repository is public by owner's choice; never commit private data or credentials.

## New agent: start here
[AGENTS.md](AGENTS.md) -> [HANDOFF.md](HANDOFF.md) -> [PRODUCT.md](PRODUCT.md) -> [docs/DECISIONS.md](docs/DECISIONS.md). GitHub is the durable source of truth, no conversation history required.

## Product and design
- [PRODUCT.md](PRODUCT.md): locked product contract and acceptance criteria
- [docs/PRODUCT_VISION.md](docs/PRODUCT_VISION.md): UX, role specialization, answer style and continuous learning
- [ARCHITECTURE.md](ARCHITECTURE.md): components and trust boundaries
- [docs/DECISIONS.md](docs/DECISIONS.md): why architectural choices exist and what remains provisional
- [docs/WORKFLOWS.md](docs/WORKFLOWS.md): onboarding, permitted live session, quality gate, interruptions and feedback
- [docs/MEMORY_AND_EVALUATION.md](docs/MEMORY_AND_EVALUATION.md): Personal Brain, Learning Memory, schema sketches and eval rules
- [docs/INFERENCE_AUTH.md](docs/INFERENCE_AUTH.md): official subscription OAuth/streaming and actual proof status
- [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md): model routing and controlled benchmark
- [docs/PR_REVIEW.md](docs/PR_REVIEW.md): GitHub Codex review requirements and usage caveats
- [docs/SLICES.md](docs/SLICES.md): incremental PR roadmap
- [docs/REFERENCES.md](docs/REFERENCES.md): official sources and open-source projects under evaluation
- [ROLE_PACKS/epic-software-developer.md](ROLE_PACKS/epic-software-developer.md)
- [ROLE_PACKS/junior-data-analytics.md](ROLE_PACKS/junior-data-analytics.md)

## Checks and next step
Run: python3 EVALS/validate.py, python3 EVALS/verify_docs.py, and python3 -m unittest discover -s tests -v (offline checks only). The minimal experimental CLI is in [relay_spike/](relay_spike/) and the safe local verification procedure is [docs/RUN_LOCAL_SPIKE.md](docs/RUN_LOCAL_SPIKE.md). Slice 01A local feasibility was user-reported successful. Slice 01B-A introduces concise-response instructions and a dry-run-first Luna-vs-Sol comparison CLI. PR #8 merged after offline CI and Codex review. An initial **10-request owner-reported local benchmark** compared Luna and Sol, and confirmed that explicit Low/Medium effort works for both models on the tested OAuth account. Results and limitations are in [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md). Optional effort controls are **merged in [PR #11](https://github.com/KanujVerma/relay/pull/11)**; default Medium behavior is unchanged. The harder-case repeated benchmark is also completed: **22 owner-reported synthetic model responses overall**, 18 default-effort and 4 explicit Low/Medium. Nine matched default-effort pairs favor Luna Medium for *exploratory development* latency, not validated production quality. Full results in [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md) and [issue #9](https://github.com/KanujVerma/relay/issues/9). [PR #14](https://github.com/KanujVerma/relay/pull/14) implements the next narrow offline QA contract ([issue #12](https://github.com/KanujVerma/relay/issues/12)); this module does not yet wire into live inference or perform AI reviews. See [docs/RUN_LOCAL_MODEL_BENCHMARK.md](docs/RUN_LOCAL_MODEL_BENCHMARK.md). See [HANDOFF.md](HANDOFF.md). No separately charged API calls or private data in CI.

Consent and privacy matter: the app will not guarantee undetectability or facilitate undisclosed live assessment help where prohibited.
