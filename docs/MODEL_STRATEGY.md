# Model strategy and evidence, 2026-10-22

Status: **provisional model routing**; only one real user-reported inference has been measured.

## Observed local baseline
User ran the Relay CLI with browser OAuth, verified ChatGPT plan permission, listed eight available models, and completed a synthetic SQL WHERE/HAVING response on `gpt-6.1-sol`. Reported timings: first text 2640 ms, response.completed 8306 ms, 906 characters. The OAuth-only CLI has no ordinary billed API key path. These are user-reported numbers, not independently repeated measurements or proof of unlimited access.

Model list at that moment: `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-daybreak-blue-latest`. Future model availability is not guaranteed.

## Proposed routing, to be benchmarked
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
The CLI and benchmark are **merged in PR #8**, after passing offline CI and a completed Codex GitHub review with three P2 fixes. The `--execute` flag permits a **bounded** local model comparison with the authorized ChatGPT plan; `--show-answers` prints only synthetic-case model outputs for human review. The format metrics are purely mechanical, not factual correctness scores. See [RUN_LOCAL_MODEL_BENCHMARK.md](RUN_LOCAL_MODEL_BENCHMARK.md). No user-run live Luna-versus-Sol comparison has been supplied yet; the production default remains provisional. [Issue #9](https://github.com/KanujVerma/relay/issues/9) tracks the local validation.
