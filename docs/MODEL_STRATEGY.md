# Model strategy and evidence, 2026-10-22

Status: **provisional model routing**. The initial local paired benchmark now has **10 owner-reported, completed requests** (six default-effort, four explicit-effort) in addition to the earlier single feasibility response. This is a small exploratory sample, not production performance evidence.

## Observed local baseline
User ran the Relay CLI with browser OAuth, verified ChatGPT plan permission, listed eight available models, and completed a synthetic SQL WHERE/HAVING response on `gpt-6.1-sol`. Reported timings: first text 2640 ms, response.completed 8306 ms, 906 characters. The OAuth-only CLI has no ordinary billed API key path. These are user-reported numbers, not independently repeated measurements or proof of unlimited access.

Model list at that moment: `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-daybreak-blue-latest`. Future model availability is not guaranteed.

## Proposed routing, pending broader correctness and latency evidence
- **Fast questions:** `gpt-6-luna` candidate for common SQL definitions, brief explanations and scoped topics. Favor only if technical accuracy and multi-part coverage meet acceptance.
- **Complex questions:** `gpt-6.1-sol` candidate for code, debugging, SQL edge cases, nontrivial follow-ups and nuanced grounded personal experiences.
- **Offline complex analysis:** `gpt-6-astra` optional, never a latency-sensitive default without evidence.
- No automatic parallel model generation or mandatory full second-model critique: usage and latency matter.

OpenAI describes Luna as fastest/efficient, Sol as balanced near-Astra, and Astra as its most capable. These labels are not a substitute for measured performance on Relay's tasks.

## Constrained response format
- One direct sentence first; up to two short supporting details.
- Aim for roughly 35–70 words on simple questions, not 906-character essays. Avoid tables and huge code fences in the primary response.
- One compact SQL/code example only when directly useful, otherwise an expandable detail.
- When schema, code or personal history is missing, abstain or state conditions, never invent a fact or test result.
- For multi-part questions, cover each part.

## Slice 01B-A benchmark requirement
On the actual Mac, compare `gpt-6-luna` and `gpt-6.1-sol` using identical synthetic questions and prompts from EVALS. Include SQL join fanout, WHERE/HAVING, array edge cases, multi-part debugging, corrections, and personal questions with no verified context.

For each run capture selected model, fixture ID, prompt variant, first_text_ms, total_ms, output length, completion/error and manual correctness. Run repeated cases when available usage allows, reporting median and p95 cautiously. No paid API keys or live account calls from CI. Use local prompts and observable text, not self-assessed model grades alone.

## Sources
- https://developers.openai.com/api/docs/guides/latest-model
- https://developers.openai.com/api/docs/guides/model-selection
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

## Slice 01B-A implementation status
The CLI and benchmark are **merged in PR #8**, after passing offline CI and a completed Codex GitHub review with three P2 fixes. The `--execute` flag permits a **bounded** local model comparison with the authorized ChatGPT plan; `--show-answers` prints only synthetic-case model outputs for human review. The format metrics are purely mechanical, not factual correctness scores. See [RUN_LOCAL_MODEL_BENCHMARK.md](RUN_LOCAL_MODEL_BENCHMARK.md). A first user-run paired comparison on three cases has now been supplied and recorded below; the production default remains provisional until harder repeated cases and independent correctness review. [Issue #9](https://github.com/KanujVerma/relay/issues/9) tracks the local validation.

## Reasoning effort settings: Slice 01B-A1 (Low/Medium verified locally)

OpenAI's standard Responses API supports top-level `reasoning: {"effort": LEVEL}`; official GPT-6 docs state **both Luna and Sol 6.1 default to medium when the field is omitted**. The Sign in with ChatGPT preview limits do not list `reasoning` as an unsupported field, and the user has now reported completed explicit Low and Medium requests for both models, with matching server-reported levels on the tested OAuth account. A model-list response alone does not prove a parameter works.

| Model | Explicit permitted efforts | Documented default |
|---|---|---|
| gpt-6-luna | none, low, medium, high, xhigh, max | medium |
| gpt-6-sol | none, low, medium, high, xhigh, max | medium |
| gpt-6.1-sol | low, medium, high, xhigh, max | medium |
| gpt-6-astra | low, medium, high, xhigh, max | verify for particular model; Relay leaves it unspecified by default |

Relay's `infer --effort` and `benchmark --efforts` are opt-in. `default` omits the field and does not claim a server-reported effective level. Real benchmark output separates **requested** effort from an optional **server-reported** effort. Comparisons must group by both model and effort. A request that the subscription preview rejects is recorded as a failed test, not silently retried with a higher effort or paid API key.

**Observed compatibility:** The tested OAuth account accepted both Low and Medium on Luna and Sol 6.1. This does **not** establish that one effort is faster or more accurate from a single case. Do not automatically use High or Pro mode in a latency-sensitive interview.

References:
- https://developers.openai.com/api/docs/guides/reasoning
- https://developers.openai.com/api/docs/models/gpt-6-luna
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

## User-reported local benchmark, 2026-10-22 (10 completed model requests)

This record summarizes sanitized Mac terminal output shared by the owner. It is **not independently re-run** by CI, and `correctness=unreviewed` in the machine output. Each request completed; no p95 can be responsibly reported from these samples. `first_text_ms` means first nonempty generated text, **not** first genuinely usable talking point. The observed server-reported effort was Medium on all requests where the input effort was omitted.

| Fixture | Luna: first text / total (ms) | Sol 6.1: first text / total (ms) |
| --- | ---: | ---: |
| D02: WHERE vs HAVING | 1362 / 2636 | 2248 / 5017 |
| D01: revenue join fanout | 2138 / 3880 | 2615 / 5587 |
| E01: two-sum | 5151 / 10421 | 4686 / 9798 |
| **Median across 3 prompts** | **2138 / 3880** | **2615 / 5587** |

Both models produced plausible, technically sound responses on this fixture subset according to **assistant inspection**, not an independent human rating. D01 Sol additionally noted that `SUM(DISTINCT revenue)` can be wrong when distinct orders have the same total; Sol E01 explicitly explained duplicates. Luna was quicker on both SQL first-text timings; Sol was slightly quicker on the coding question. All six responses stayed under the implementation's *upper* word ceiling, which alone does not establish completeness; Luna D02 contained 33 words versus the aspirational 35–70-word simple-answer range.

**Explicit effort verification on D02 only:**

| Model | Requested and server-reported | First text (ms) | Total (ms) |
| --- | --- | ---: | ---: |
| Luna | Low | 2533 | 4149 |
| Sol 6.1 | Low | 2886 | 5320 |
| Luna | Medium | 2083 | 3665 |
| Sol 6.1 | Medium | 5074 | 7180 |

This proves the **four tested override combinations** work with this account/preview, not that Low universally beats Medium. Confirmed default-server Medium is different from **explicit** Medium; keep those groups separate. Do not select automatic production routing or claim a reliable p95 from three or fewer observations per model/effort group.

## Next verification gate: harder, repeated local fixtures

Keep [issue #9](https://github.com/KanujVerma/relay/issues/9) open for a single 12-request paired benchmark at default effort: D13 (SQL salary ties/rank semantics), D07 (multipart CTE/subquery optimizer caveats), E09 (binary search, sortedness, empty input). Use `--repeats 2` with identical prompts for Luna and Sol 6.1, manually judge **technical accuracy, completeness, assumptions and interview readability**, and preserve synthetic answers locally. See [RUN_LOCAL_MODEL_BENCHMARK.md](RUN_LOCAL_MODEL_BENCHMARK.md). Even then, latency and routing remain exploratory, not production guarantees. The upcoming [Slice 01B-B0 issue #12](https://github.com/KanujVerma/relay/issues/12) adds an offline QA contract rather than mandatory second-model calls.
