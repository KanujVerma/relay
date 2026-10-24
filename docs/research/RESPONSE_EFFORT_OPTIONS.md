# Current official effort options for the response-speed gate

Read on 2026-10-24 using the OpenAI Docs workflow. This is documentation/source
research only: no account catalog, credential, entitlement or inference call.

| Runtime candidate | Documented Responses efforts | Documented default |
| --- | --- | --- |
| `gpt-6-luna` | `none`, `low`, `medium`, `high`, `xhigh`, `max` | `medium` |
| `gpt-6.1-sol` | `low`, `medium`, `high`, `xhigh`, `max`; `none`/`minimal` unsupported | `medium` |

Primary model pages: [Luna](https://developers.openai.com/api/docs/models/gpt-6-luna),
[Sol 6.1](https://developers.openai.com/api/docs/models/gpt-6.1-sol).
Lower effort is a documented speed/token tradeoff, with quality depending on
the task; [official reasoning guidance](https://developers.openai.com/api/docs/guides/reasoning).
It is a candidate for measured comparison, not evidence of Relay's current speed.

The [ChatGPT plan route](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
requires the selected account's current model catalog, public Responses endpoint,
`store:false`, `stream:true`, and successful terminal `response.completed`.
Its [preview restrictions](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
do not list `reasoning` as unsupported. That absence and generic model docs do
not establish that a particular current account/effort request is accepted.
Failures/incomplete/refused streams stay failures; there is no paid API-key or
automatic changed-effort retry. No service-tier override is proposed.

Live local source matches the documented effort allowlist in `stream.py`.
`None`/`default` omit the field; the string `"none"` is a distinct explicit Luna
override. `OAuthAnswerStream` already supports an explicit effort constructor,
but the protected product factory and native helper parser currently pass only
the chosen model, so normal product requests omit effort. Worker model/effort
instructions are independent of this runtime policy and remain unchanged.

`MODEL_STRATEGY.md` separately records older owner-reported explicit Low/Medium
acceptance on Luna/Sol for D02. It does not establish current None acceptance,
an accuracy ranking or a reliable Low-vs-Medium speed result.

Proposed next authorized comparison: hold the compact prompt/model/question
constant and compare omitted effort with explicit `none` on Luna across SQL
multipart, executable coding/edges and feature-case rubrics. If the owner elects
to investigate `low`, use a separately bounded declared comparison. Preserve
every failure/format withhold, requested versus server-reported effort where
available, output length, first delta, valid completion, native availability
and human rubric assessment. No p95 from a tiny sample. Do not change the normal
default or infer plan support before that actual protected-factory gate.

## Prepared bounded evaluation

`EVALS/benchmark_answer_latency.py` now exposes
`compare_effort_variants(stream, include_answers=False)` for a dedicated,
explicitly supplied protected product stream. Both declared variants use the
identical compact instructions and question input; `default` omits effort and
`none` sends that exact Luna value. Unsupported Sol None rejects through the
existing validator before token/client access. The original stream setting is
restored on completion, failure or cancellation; normal runtime defaults do not
change. A hard six-attempt cap is enforced even if the case inventory expands.
Personal-missing controls make zero model attempts. No changed-effort retry or
credential/client creation is introduced.

Failures, completed-but-format-rejected cards, refusals/incomplete markers and
human correctness status remain in the results. `serverReportedEffort` is null
because the current product adapter does not expose that echo; do not report
requested level as independently observed effective reasoning. Running the
module still prints its plan only. Five new offline cases plus existing focused
transport/helper/effort controls pass **35 tests / zero skips / 0.307 s**, after
three initial missing-API failures. No account execution occurred.
