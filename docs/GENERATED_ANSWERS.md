# Proposed automatic generated-answer policy

Status 2026-10-23: owner approved building the full contextual answer experience. Implementation uses separate host provenance for **AI-generated suggestions** and reviewed references behind one interface. The shared implementation contract and source budgets are in [BUILD_CONTRACT](BUILD_CONTRACT.md); code and product acceptance are tracked in [BUILD_STATUS](BUILD_STATUS.md). [SESSION_BRIDGE](SESSION_BRIDGE.md) owns the common result/display contract.

## Full-experience clarification

The owner wants one assistant on standby throughout an interview, answering technical, résumé/project and general explanation requests in context. Reviewed/generated states describe provenance, not separate product modes. The earlier technical-only milestone is insufficient for that experience. The contextual engine needs selected verified personal background in the first useful version, plus bounded live dialogue and follow-up context. This clarification does not claim real private imports or grounded personal generation already exist.

General technical knowledge may be generated. A claim about the user's experience must be supported by actual approved source-backed facts and preserve individual/team attribution. The personal-context lane must specify claim binding, retrieval and revocation with the existing BrainStore before personal-answer publication is enabled. Never let model-created fact/source identifiers establish that authority. Missing biography can be stated honestly or turn into a useful clarification without fabricating a story.

## Recommended path and alternatives

A full independently reviewed match uses the reviewed reference. An eligible unmatched general technical question makes one request through the existing official ChatGPT-plan OAuth route, asks for a bounded whole JSON card, waits for successful stream completion, validates locally, and produces generated_suggestion. No manual question acceptance, mandatory second critic, automatic repair retry or API-key fallback.

Prompt-JSON plus strict local parsing is the smallest proposed first version. Provider Structured Outputs could improve shape reliability only after the exact preview route is authorized and tested; it does not prove factual truth. A second model can provide a selective opinion but adds latency/usage and is not a correctness certificate. Neither is a mandatory baseline dependency.

Current ReferenceCard and canonical-only publication policy remain intact. Do not set trusted personal classification to absent, select a reference from candidate prose, or pass arbitrary output through the old technical grammar merely to make it displayable. Add a separate GeneratedCard policy and visible state.

## Admission, output and authority

Use the complete current QuestionSnapshot, constraints and dependency identity, through the shared composite strategy. Technical intent remains evaluated tentative classification, not ASR confidence or speaker identity. Missing context can produce a bounded clarification/abstention state. Unsupported biographical claims cannot become personal facts. Statements, unknown speech, unresolved referents, incomplete source activity and stale/unauthorized input do not authorize a request.

The model returns content plus bounded assumptions and structural coverage records. The host owns all status, authority and provenance. Strictly parse the complete candidate object; reject extra/duplicate keys, malformed/truncated JSON, invalid UTF-8, nonfinite values, controls, depth or byte overflow. Do not extract plausible JSON from surrounding prose, fill in missing tails or silently clip content. Invalid output withholds without another model request.

Generated provenance may name the actually selected model and actual completion/check versions. It cannot claim a reviewed reference, verified personal source, executed test result, independent review or useful-answer timestamp. A model's confidence or claim that it tested code cannot grant publication. A self-reported problem may veto output.

The initial result is immutable after publication. One coordinator seals the request before enqueueing its terminal decision, and native uses the same terminal latch. A late success cannot reopen a timeout/failure/abstention. Follow-ups retain bounded labeled prior context; prior model output is data, never evidence of the user's skills.

## Completion and checks

- Require successful response.completed with a coherent response/item/content lifecycle. Reject refusal, failure, incomplete, missing terminal, changed identity, unfinished items and replay. Buffer internal deltas; do not display raw partial prose in this first contract.
- Always check the whole schema/card, native and Python freshness, needed code presence, explicit assumptions, structural subpart accounting and unsupported personal/source/test claims. Passing structural checks means format_checked, not correct.
- Use independently authored held-out rubrics for actual correctness and multipart coverage. Model-provided coverage records and keyword hints are not semantic proof. A code-writing question cannot pass with prose-only detail.
- Python detail can be parsed/compiled in a bounded validation subprocess without executing model code. Syntax success is not algorithm correctness. Reviewed binary-search references additionally use independent executable cases.
- Optional SQL checks are restricted to a host-owned synthetic SQLite schema and allowlisted SELECT behavior, bounded time/rows, authorizer, disabled extensions and cancellation. Never execute against private/user data. Evidence is specific to dialect/schema/cases; missing checks stay not_checked.

## Cancelable transport and budgets to discuss

The current synchronous urllib read may block until its next event/socket timeout. A single serial coordinator must not perform that read inline. A single bounded blocking thread can suppress stale output but may delay a new question while the old request remains stuck.

Recommended candidate: one session-scoped HTTPX AsyncClient using the same auth.active_access_token, response_payload, official endpoint, headers and error mapping; explicit no retries/redirects, one active task and one replaceable newest pending candidate. Keep the existing sync CLI unchanged. Reuse source cancellation cleanup patterns and independently test real blocked local sockets, not only cooperative iterators. This dependency/adapter remains proposed.

Proposed starting limits, to evaluate: accepted-question deadline 15 seconds, connect 5 seconds, read inactivity 10 seconds, at most 10 requests/minute and 60/session. Replays do not reset spent budgets. Enforce fixed-size reads, <=64 KiB SSE event, <=512 KiB total wire, <=32 output items, <=8 KiB candidate JSON and the shared <=16 KiB bridge frame. Bounds are enforced before unbounded line/object allocation. They are candidate product defaults, not measured optimal values or new approved latency promises.

Official preview limitations exclude max_output_tokens; client deadlines/disconnects bound local work and waiting, not guaranteed provider token use after cancellation. Preserve the product's existing first-useful-answer goal and measure actual accepted-question/ASR-final/request/first-private-text/completed/check/native-commit/observed-draw times separately. Do not call first text useful or invent p50/p95 from fixture execution.

## Ownership, reuse and acceptance

Open-ended lane owns generated_answer.py, response_assembly.py, oauth_answer_stream.py, focused tests and synthetic evaluation fixtures. These are proposed new files. Reviewed/panel lane owns the router/helper/display; controller assigns shared eligibility/dependency seams and requirements pins. Reuse PR46's existing onset/context suspension; prove native VAD/final association instead of duplicating it.

[UPSTREAM_REUSE](research/UPSTREAM_REUSE.md) records exact SDK, HTTPX, jsonschema and evaluation-source pins/licenses/tests. Adapt the small response accumulator and offline assertions that meet Relay's contract; do not replace OAuth or adopt a whole provider-running framework for this lane.

Before live acceptance, offline fixtures must cover representative correct and incorrect open-ended answers, hidden/extra constraints, missing schemas, SQL NULL/fanout, binary-search boundaries, prose-only code requests, personal fabrication, malformed/refused/failed streams, all request/replay/rate bounds and stale publication schedules. Include blocked-socket cancellation and child/pipe/native commit races. Report false accepts, false withholds and semantic coverage separately. One authorized real-model/Mac evaluation is a later gate; synthetic tests do not establish usefulness, correctness or latency.

Official references: [models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
