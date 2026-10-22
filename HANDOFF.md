# Relay handoff: exact project state

Updated: 2026-10-22. [AGENTS.md](AGENTS.md) defines how each new coding agent starts; check live GitHub issues, PRs and CI before trusting this snapshot.

## Verified completed repository work
- Slice 00: product contract, Epic developer and junior analytics Role Packs, 26 synthetic evaluation cases, offline validator, PR #1 merged and CI green.
- Slice 00B: durable AGENTS.md, architecture ADRs, project workflows and complete documentation baseline, PR #3 merged.
- Slice 01A: supported OAuth/PKCE/OIDC CLI, plan permission validation, model catalog and fail-closed streamed Responses, PR #4 merged; OAuth callback and token hardening, PR #5 merged. Offline CI passed.
- Slice 01A real-user feasibility: **the user provided successful Mac terminal output** on 2026-10-22. Browser authentication and ChatGPT plan inference permission succeeded, eight models listed and `gpt-6.1-sol` returned `response.completed` for a synthetic SQL WHERE/HAVING question. First text: **2640 ms**, total stream: **8306 ms**, output: **906 characters**. This is one user-reported run, not an independently repeated benchmark or evidence of unlimited usage.

## Current change
**PR #6 merged**, after Codex review found three documentation inconsistencies, all resolved with green CI; issue #2 closed. **PR #8 merged** after Codex review found three P2 correctness/metrics issues, all fixed with regression tests and green exact-head CI; issue #7 closed. **PR #11 merged** after offline CI and Codex review with no findings. Two user-run Luna/Sol benchmark rounds are now reported: **22 completed synthetic requests**, including the explicit Low/Medium proof. [Issue #9](https://github.com/KanujVerma/relay/issues/9) records the completed exploratory validation. [PR #14](https://github.com/KanujVerma/relay/pull/14), tied to [issue #12](https://github.com/KanujVerma/relay/issues/12), is the next small offline QA implementation and must pass checks/review before merge.

## Exact next implementation slice
**Next active slice: [issue #12](https://github.com/KanujVerma/relay/issues/12), [PR #14](https://github.com/KanujVerma/relay/pull/14)**. The synthetic model-validation gate [#9](https://github.com/KanujVerma/relay/issues/9) has supplied all 22 requested completed responses, including the two-repeat harder cases. In PR #14, implement/test a *pure offline* deterministic decision contract (pass/revise/abstain; source/turn version; conservative multipart signals; optional high-risk second-review recommendation). Confirm exact-head green CI and an actual Codex review before merging. **Do not run another live model test or build Zoom/UI yet**. Next sub-slice [B1, issue #15](https://github.com/KanujVerma/relay/issues/15), integrates the static gate with streamed answer delivery and tests first-useful-text latency and selective QA efficacy.

## Slice 01B-A completed artifacts (merged in PR #8)
- `relay_spike/benchmark.py`: synthetic role cases, bounded paired comparison plan, output-format metrics, no automatically assigned correctness score.
- `relay_spike/stream.py`: preview-safe top-level concise instructions.
- `relay_spike/__main__.py`: `benchmark` command; dry-run unless `--execute` is supplied; no OAuth or model requests without execution permission.
- `tests/test_benchmark.py`: offline negative tests; `docs/RUN_LOCAL_MODEL_BENCHMARK.md`: local instructions.
- Codex PR #8 review completed, three P2 findings fixed (truthful compactness metric, actual p95 emission, explicit role for direct inference), all threads resolved and exact-head CI passed. **A user-run initial Luna/Sol comparison has since been supplied** (see observed results below); CI must never call a model.

## Slice 01B-A1 completed: reasoning effort controls (PR #11 merged)
PR #11 passed offline CI and Codex GitHub review (**completed, no findings**) at the exact merged head. It added optional `infer --effort`, `benchmark --efforts`, model-specific effort validation, bounded cross-product requests and per-model/per-effort timing groups with new regression tests. Default CLI calls **omit** `reasoning.effort`, so Luna and Sol 6.1 use their documented Medium defaults. **Explicit Low and Medium were accepted** in four user-reported Mac requests across Luna/Sol 6.1, and the server reported matching efforts. This establishes these account-specific combinations, not cross-account compatibility, model quality or a speed advantage. The subsequent harder repeated benchmark in [issue #9](https://github.com/KanujVerma/relay/issues/9) has also completed; model-quality and latency rankings remain exploratory.

## Observed model evidence, owner-reported 2026-10-22
The first 10 user-reported requests: six default-effort D02/D01/E01 Luna/Sol pairs plus four explicit Low/Medium D02 tests. The additional **12 default-effort completed requests** used `D13,D07,E09 --repeats 2` for both models. Each response returned completed; default efforts were server-reported Medium. For the *new six per model*, median first text / total was **Luna 3433 / 6594.5 ms**, **Sol 6.1 4718.5 / 8864.5 ms**. Across **all nine default-effort pairs per model**, median first text / total was **Luna 3265 / 6371 ms**, **Sol 6.1 4258 / 8761 ms**. Luna completed before Sol on **8 of 9** pairs, but started text sooner on only **5 of 9**. All 12 new printed answers appeared technically sound under *assistant fixture-based inspection*, not code execution or independent user adjudication. One Luna E09 response was code-first and failed to say its empty-input behavior in prose, despite handling it in the code. Results/caveats are recorded in [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md) and [issue #9](https://github.com/KanujVerma/relay/issues/9). No p95 with fewer than 10 responses per model/effort; first text is not first **usable** answer and excludes ASR/retrieval/QA/rendering latency.

## Provisional model policy for development, not production
- **Luna Medium** is the initial preferred model for latency-sensitive synthetic text QA development, including routine coding/SQL. Its observed outputs did not show an obvious accuracy deficit on this fixture subset.
- **Sol 6.1** remains selectable for deeper follow-up/complexity cases or when a future grounded quality policy recommends additional review. Complexity alone should not force Sol, and a recommended second review must not implicitly trigger an extra paid/plan-backed call.
- **Astra** remains optional offline analysis. Do not make hard-coded final route or high-effort choices from nine paired samples. For future launch validation, compare held-out technical correctness, personal-source fidelity, p50/p95 *first useful text*, and changes to plan availability.

## Slice 01B-B0 implementation contract (PR #14)
- `relay_spike/qa.py`: offline typed `QAInput`/`QAResult`, explicit source IDs/turn IDs and versions, conservative personal-claim classification, `pass`/`needs_revision`/`abstain` and nonbinding `second_review_recommended`.
- No personal answer can pass without **real** source review; empty verified-source references cause abstention, and bare source IDs alone never prove a claim is supported.
- Incomplete or superseded **turn IDs/versions** abstain, even if two distinct turns reuse the same version number. A consumer must *also* re-check both active ID and version immediately before rendering. Without a trusted absence-of-personal-attribution classification, even otherwise clean technical output needs revision.
- Optional keyword indicators only flag **possible** missing subparts. A deterministic PASS is not a correctness score. Code-first answers may warn about scanability; high-risk flags recommend (but do not invoke) deeper review.
- Synthetic negative tests cover missing provenance, stale/failed output, SQL/coding risks, multipart omissions, malformed metadata and format problems. In this slice there is no model request, persistent store, personal import, audio, UI or stream integration; those belong to follow-up slices.

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
Read [AGENTS.md](AGENTS.md), [PRODUCT.md](PRODUCT.md), [ARCHITECTURE.md](ARCHITECTURE.md), [docs/DECISIONS.md](docs/DECISIONS.md), and [docs/SLICES.md](docs/SLICES.md). Read observed benchmark in [docs/MODEL_STRATEGY.md](docs/MODEL_STRATEGY.md) and the completed validation report in [issue #9](https://github.com/KanujVerma/relay/issues/9). **Active work is PR #14 / issue #12**, the small offline QA decision contract. Verify actual PR head, CI, Codex review and issue state. Do not conflate offline gate PASS with factual correctness or claim first-useful-text latency from first generated text. After landing B0, scope B1 integrated validation as a separate PR; retain user privacy and budget bounds.
