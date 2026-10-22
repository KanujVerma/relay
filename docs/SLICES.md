# Slice-based roadmap and execution discipline

Each slice gets a narrow issue, branch, small PR, reproducible tests, updated architectural docs and an exact HANDOFF.md status. Done is evidence, not merely a code commit.

| Slice | Work | Completion gate |
|---|---|---|
| 00 | Product contract, initial roles, synthetic evaluation cases | PR #1 merged, fixture validation CI passed |
| 00B | Durable agent handoff, ADRs, flows, personal memory design, inference contract | PR merged, links and status consistent |
| 01A | ChatGPT subscription-backed inference authorization proof | Met in user-reported local OAuth and gpt-6.1-sol response.completed on 2026-10-22; offline tests in PRs #4 and #5 |
| 01B-A | Concise answer formatting and fast-vs-complex model comparison | Compare Luna and Sol on identical synthetic interview prompts, local only; collect correctness and latency |
| 01B-B | Grounded text answer pipeline and fast quality review | Human-reviewed negative/edge cases, no invented personal claims, measured p50/p95 latency |
| 02A | Resume ingestion, verified facts, conversational probing | No invented personal facts, attribution and deletion tests |
| 02B | Selected Drive/GitHub imports, incremental sync | Independent OAuth, least privilege, revoke/delete tests |
| 03A | Authorized macOS audio capture and local ASR | Real mic/remote channel and memory benchmark on Mac |
| 03B | Question/turn state machine | Multipart/interruption/correction tests |
| 04A | Native short-answer panel and integrated authorized session | Measured permitted mock call and honest unavailable states |
| 05A | Learning-event store and fact verification workflow | User corrections and reversible memory promotions work |
| 05B | Adaptive retrieval/response improvement | Held-out regression improves or change rolls back |
| 06 | Security, accessibility, latency, reliability hardening | End-to-end verification on target hardware |
| 07 | Optional adaptive mock interviewer | Realistic challenge cases improve assistant responses, not mandatory education |

## Authentication feasibility gate
User-reported local OAuth and completed synthetic gpt-6.1-sol response confirms this gate for the currently tested account. Retest when authorization, account or model changes; never silently introduce API credits, scraping, or paid inference.

## Context-rot prevention
- HANDOFF.md: actual state and precise next action.
- PRODUCT.md and docs/PRODUCT_VISION.md: goals, non-goals, acceptance.
- docs/DECISIONS.md: why architecture choices were made, which are provisional.
- ARCHITECTURE.md and docs/WORKFLOWS.md: components and flows.
- EVALS: behavioral contract and regression fixtures.
- docs/INFERENCE_AUTH.md: provider-specific integration requirements.
- AGENTS.md: strict reading and change discipline.

## Cost and CI
Prefer short, offline ubuntu-slim workflows; user may later make repository private. Native macOS hosted runners can consume the account's shared Actions allowance quickly. No paid inference or OAuth in CI. No secrets in Actions artifacts/logs.
