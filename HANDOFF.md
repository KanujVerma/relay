# Relay handoff: exact project state

Updated: 2026-10-22. [AGENTS.md](AGENTS.md) defines how each new coding agent starts; check live GitHub issues, PRs and CI before trusting this snapshot.

## Verified completed repository work
- Slice 00: product contract, Epic developer and junior analytics Role Packs, 26 synthetic evaluation cases, offline validator, PR #1 merged and CI green.
- Slice 00B: durable AGENTS.md, architecture ADRs, project workflows and complete documentation baseline, PR #3 merged.
- Slice 01A: supported OAuth/PKCE/OIDC CLI, plan permission validation, model catalog and fail-closed streamed Responses, PR #4 merged; OAuth callback and token hardening, PR #5 merged. Offline CI passed.
- Slice 01A real-user feasibility: **the user provided successful Mac terminal output** on 2026-10-22. Browser authentication and ChatGPT plan inference permission succeeded, eight models listed and `gpt-6.1-sol` returned `response.completed` for a synthetic SQL WHERE/HAVING question. First text: **2640 ms**, total stream: **8306 ms**, output: **906 characters**. This is one user-reported run, not an independently repeated benchmark or evidence of unlimited usage.

## Current change
**PR #6 merged**, after Codex review found three documentation inconsistencies, all resolved with green CI; issue #2 closed. **PR #8 merged** after Codex review found three P2 correctness/metrics issues, all fixed with regression tests and green exact-head CI; issue #7 closed. **PR #11 merged** after offline CI and Codex review with no findings. The initial user-run Luna/Sol and reasoning-effort benchmark is now reported; [issue #9](https://github.com/KanujVerma/relay/issues/9) tracks the next harder-case repetitions, with [issue #12](https://github.com/KanujVerma/relay/issues/12) queued for offline grounded answer QA.

## Exact next implementation slice
**Issue [#9: repeat harder local comparisons](https://github.com/KanujVerma/relay/issues/9)**. The first **10** user-reported model requests have already completed. The remaining owner-run gate is a 12-request `D13,D07,E09 --repeats 2` comparison of Luna/Sol with explicit local opt-in, followed by manual answer grading. See [docs/RUN_LOCAL_MODEL_BENCHMARK.md](docs/RUN_LOCAL_MODEL_BENCHMARK.md). Do not silently rerun models, use paid inference or claim this small sample establishes p95. **Next implementation:** [issue #12](https://github.com/KanujVerma/relay/issues/12), one small offline-only 01B-B0 QA contract/negative-test PR, after #9 is triaged.

## Slice 01B-A completed artifacts (merged in PR #8)
- `relay_spike/benchmark.py`: synthetic role cases, bounded paired comparison plan, output-format metrics, no automatically assigned correctness score.
- `relay_spike/stream.py`: preview-safe top-level concise instructions.
- `relay_spike/__main__.py`: `benchmark` command; dry-run unless `--execute` is supplied; no OAuth or model requests without execution permission.
- `tests/test_benchmark.py`: offline negative tests; `docs/RUN_LOCAL_MODEL_BENCHMARK.md`: local instructions.
- Codex PR #8 review completed, three P2 findings fixed (truthful compactness metric, actual p95 emission, explicit role for direct inference), all threads resolved and exact-head CI passed. **A user-run initial Luna/Sol comparison has since been supplied** (see observed results below); CI must never call a model.

## Slice 01B-A1 completed: reasoning effort controls (PR #11 merged)
PR #11 passed offline CI and Codex GitHub review (**completed, no findings**) at the exact merged head. It added optional `infer --effort`, `benchmark --efforts`, model-specific effort validation, bounded cross-product requests and per-model/per-effort timing groups with new regression tests. Default CLI calls **omit** `reasoning.effort`, so Luna and Sol 6.1 use their documented Medium defaults. **Explicit Low and Medium were accepted** in four user-reported Mac requests across Luna/Sol 6.1, and the server reported matching efforts. This establishes these account-specific combinations, not cross-account compatibility, model quality or a speed advantage. The next gate is [issue #9](https://github.com/KanujVerma/relay/issues/9): harder repeated questions plus manual grading.

## Observed initial model results (owner-reported 2026-10-22)
After reauthorizing expired OAuth credentials, the owner completed **six paired default-effort** responses on synthetic D02 (WHERE/HAVING), D01 (join fanout) and E01 (two-sum), then **four more explicit Low/Medium** D02 responses. For the default-effort requests the server reported Medium. Median first-text/total across three cases: **Luna 2138/3880 ms**, **Sol 6.1 2615/5587 ms**. First-text for E01 coding alone was **5151 ms Luna / 4686 ms Sol**, with full streams **10421/9798 ms**. Both sets of simple SQL/coding answers looked technically reasonable under assistant inspection, **not formal human correctness adjudication**. Low/Medium requests returned matching server-reported effort for both models. No p95 or first-*useful*-answer latency has been measured. All ten sanitized rows and next commands are preserved in [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md) and [issue #9](https://github.com/KanujVerma/relay/issues/9).

## Provisional model routing
- Luna: preferred fast/simple-question candidate, must pass factual and coverage checks.
- GPT-6.1 Sol: preferred more complex coding/debugging/follow-up candidate.
- Astra: optional deeper offline analysis, not a default live model.
- Three synthetic fixtures now have paired latency observations: Luna led on D01/D02 first text, Sol led narrowly on E01 first text. **Technical correctness/routing are not production-validated**; sample size is too small for p95 and timings measure first output text, not first useful answer. See [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md).

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
Read [AGENTS.md](AGENTS.md), [PRODUCT.md](PRODUCT.md), [ARCHITECTURE.md](ARCHITECTURE.md), [docs/DECISIONS.md](docs/DECISIONS.md), and [docs/SLICES.md](docs/SLICES.md). Inspect merged PRs #8 and #11, observed benchmark in [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md), and open [issue #9](https://github.com/KanujVerma/relay/issues/9). **Current remaining Mac gate: bounded 12-request harder-case comparison and human review.** [Issue #12](https://github.com/KanujVerma/relay/issues/12) defines the next offline QA implementation; start only one small PR at a time. Preserve observed-vs-assumed boundaries, tests, review findings and this handoff.
