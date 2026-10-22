# Research and source registry

Verified/reviewed on 2026-10-22 unless otherwise noted. External projects are CANDIDATES/REFERENCES, not adopted dependencies. Recheck upstream licensing and current releases before using code.

## Primary platform sources
- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server
- https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery

## Open-source research
- https://github.com/FluidInference/FluidAudio : on-device Swift CoreML ASR/VAD/diarization candidate. Benchmark target Mac before selection.
- https://github.com/pieralukasz/SystemAudioKit : system/mic audio capture candidate; verify license, OS permissions and actual Zoom routing.
- https://github.com/iskandaryv/meetingly-ai : meeting assistant and compact response UX reference.
- https://github.com/Blueturboguy07/cue : meeting overlay/context UX reference.
- https://github.com/Natively-AI-assistant/natively-cluely-ai-assistant : extended project context example, reuse license must be checked.
- https://github.com/sohzm/cheating-daddy : prior art/architecture reference only; not an intended dependency or stealth implementation.

## Potential local analytics/retrieval libraries
- https://www.sqlite.org/fts5.html : keyword retrieval.
- https://github.com/asg017/sqlite-vec : optional semantic retrieval, only if helpful in benchmarks.
- https://github.com/duckdb/duckdb : possible executable SQL validation for known-schema questions.
- https://github.com/tobymao/sqlglot : SQL parser/dialect analysis option.
- https://docs.github.com/en/billing/concepts/product-billing/github-actions : runner costs/allowance; check current account balance separately.

## Personal Brain storage and memory frameworks, reviewed 2026-10-22
- https://www.sqlite.org/foreignkeys.html and https://www.sqlite.org/pragma.html : accepted low-dependency SQLite primitives for local fact provenance, referential integrity, secure-delete limitations and transactions. Python stdlib sqlite3 is in the current slice, no dependency vendoring.
- https://github.com/groue/GRDB.swift : MIT-licensed native SQLite migrations/observations toolkit; preferred future Swift adapter evaluation when building the macOS app, not installed into the Python spike.
- https://github.com/mem0ai/mem0 : Apache-2.0 memory platform. Useful architecture/retrieval reference, **not** automatically adopted: model- or agent-generated facts must not become verified Relay autobiographical claims without explicit approval.
- https://github.com/letta-ai/letta : long-running agent memory/orchestration prior art, including an active-code-location change; over-scoped for this deterministic local fact store, not a dependency.
- https://github.com/asg017/sqlite-vec : pre-v1, MIT/Apache SQLite vector search extension; no embeddings in the 02A-A factual ledger, defer until benchmarks justify retrieval complexity.
- [PERSONAL_BRAIN_STORAGE.md](PERSONAL_BRAIN_STORAGE.md) : decision matrix and exact implemented-vs-deferred data lifecycle; no upstream code copied.

## Source reliability discipline
Official documentation governs protocol; project README governs upstream intent; real measured local tests govern practical behavior. Anecdotal interview reports are weak priors, not a guarantee that a company will ask a specific question. Record citation URL, verification date, version, OS, benchmark methodology and observed result before promoting proposed technology to settled ADR.
