# Model strategy and evidence, 2026-10-22

Status: **evidence-limited development routing**. The owner supplied **22 completed synthetic model requests** (18 default-effort responses across nine matched Luna/Sol pairs, and four explicit Low/Medium requests), in addition to the original single-model feasibility response. This supports a *provisional* Luna Medium default during the next development slice, not production or real-interview correctness claims.

## Observed local baseline
User ran the Relay CLI with browser OAuth, verified ChatGPT plan permission, listed eight available models, and completed a synthetic SQL WHERE/HAVING response on `gpt-6.1-sol`. Reported timings: first text 2640 ms, response.completed 8306 ms, 906 characters. The OAuth-only CLI has no ordinary billed API key path. These are user-reported numbers, not independently repeated measurements or proof of unlimited access.

Model list at that moment: `gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-daybreak-blue-latest`. Future model availability is not guaranteed.

## Provisional routing for the next development slice
- **Default candidate:** `gpt-6-luna` at its observed Medium default for ordinary questions and initial coding/SQL replies, subject to actual QA results. It finished sooner in 8 of 9 paired comparisons and did not show an obvious correctness deficit in this narrow fixture subset.
- **Selective candidate:** `gpt-6.1-sol` for explicitly requested depth or answers flagged by a future grounded QA policy. Harder coding alone does **not** prove Sol should always be called; it began output faster in the two E09 runs but finished later.
- **Offline complex analysis:** `gpt-6-astra` remains optional, not a live default without testing.
- No unconditional parallel inference, silent second model call, high-effort override, or separately billed API-key fallback. Routing must remain user-controllable and be revisited with held-out factual-accuracy and first-*useful*-answer measures.

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
The CLI and benchmark are **merged in PR #8**, after passing offline CI and a completed Codex GitHub review with three P2 fixes. The `--execute` flag permits a **bounded** local model comparison with the authorized ChatGPT plan; `--show-answers` prints only synthetic-case model outputs for human review. The format metrics are purely mechanical, not factual correctness scores. See [RUN_LOCAL_MODEL_BENCHMARK.md](RUN_LOCAL_MODEL_BENCHMARK.md). An initial three-case paired comparison and a subsequent three-case repeated harder comparison have been supplied and recorded below. The assistant inspected printed synthetic answers against fixture rubrics but did not execute code/SQL or perform independent expert adjudication. Production routing remains unvalidated. [Issue #9](https://github.com/KanujVerma/relay/issues/9) tracks the local validation.

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

## Repeated harder-case local benchmark, 2026-10-22 (12 additional responses)

The owner completed `--cases D13,D07,E09 --repeats 2 --show-answers` on Luna and Sol 6.1 at default (server-reported Medium) effort. All twelve streams completed. Times below are first nonempty generated text / full completion, in milliseconds.

| Case and repetition | Luna first / total | Sol 6.1 first / total |
| --- | ---: | ---: |
| D13, salary RANK/ROW_NUMBER, rep 1 | 2235 / 5305 | 7987 / 11337 |
| D13, rep 2 | 3601 / 6818 | 5179 / 8968 |
| D07, CTE/subquery/performance, rep 1 | 5220 / 7467 | 3692 / 8184 |
| D07, rep 2 | 1195 / 3804 | 8292 / 12797 |
| E09, binary search, rep 1 | 4932 / 7918 | 4258 / 8761 |
| E09, rep 2 | 3265 / 6371 | 2957 / 7519 |
| **Median of these six per model** | **3433 / 6594.5** | **4718.5 / 8864.5** |

**Assistant inspection against the 26-fixture evaluation corpus, not an execution-based correctness score:** All four D13 answers distinguish `RANK` and `ROW_NUMBER` tie behavior and partition by department. Examples choose either top-one or top-three, illustrating the ambiguity of "top earners." All four D07 answers address each part and correctly avoid universal CTE performance guarantees. All four E09 answers supply plausible correct iterative binary search for an ascending-order list, with O(log n) time, O(1) extra space and code that handles empty input. One Luna E09 response leads with code and omits an *explicit spoken* empty-input caveat, although the code returns -1 for an empty list. None of this proves factual correctness in an unobserved interview or validates the SQL against an actual database.

## Combined exploratory default-effort observations

Across **nine matched question/repetition pairs per model** (D02, D01, E01 once, plus D13/D07/E09 twice), the median **first text / full completion** was **Luna 3265 / 6371 ms** and **Sol 6.1 4258 / 8761 ms**. Luna completed sooner in **8 of 9** paired cases but started nonempty output first in only **5 of 9**. Both E09 coding runs started earlier on Sol but finished earlier on Luna. This argues for a Luna-first *development policy*, not a permanent or exhaustive quality ranking.

These nine samples per model remain below the current **10-per-model-and-effort p95 reporting threshold**. Do not claim p95 or guaranteed sub-4-second usefulness; first nonempty text does not measure the time to a readable answer. The stream timing does not include permitted audio capture, local ASR, retrieval, verification, or rendering latency. The four explicit Low/Medium results above remain separate and do not demonstrate a reasoning-effort winner.

## Decision and next slice

The synthetic comparison gate in [issue #9](https://github.com/KanujVerma/relay/issues/9) is complete with the above limitations. Stop spending plan requests on trivial re-benchmarks for now. [Issue #12](https://github.com/KanujVerma/relay/issues/12) is now completed in merged [PR #14](https://github.com/KanujVerma/relay/pull/14): an offline, deterministic QA contract rejects incomplete/stale turns and unverified personal claims, flags possible multipart omissions, and emits a **nonbinding** selective-review recommendation without making another model call. Next [issue #15](https://github.com/KanujVerma/relay/issues/15) integrates it into synthetic streaming. Future tests must assess *first useful text*, actual correctness on held-out harder cases, personal provenance, and whether selective Sol/second-pass review gives measurable improvement. Never treat a deterministic `pass` or a model critique as independent ground truth.
