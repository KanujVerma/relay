# Slice-based roadmap and execution discipline

Each slice gets a narrow issue, branch, small PR, reproducible tests, updated architectural docs and an exact HANDOFF.md status. Done is evidence, not merely a code commit.

| Slice | Work | Completion gate |
|---|---|---|
| 00 | Product contract, initial roles, synthetic evaluation cases | PR #1 merged, fixture validation CI passed |
| 00B | Durable agent handoff, ADRs, flows, personal memory design, inference contract | PR merged, links and status consistent |
| 01A | ChatGPT subscription-backed inference authorization proof | Real OAuth consent+scope+model response completed on user account OR precise blocker documented |
| 01B | Text-only response formatting, grounding, quick validation/review | Quality benchmark with negative cases and measured latency |
| 02A | Resume ingestion, verified facts, conversational probing | No invented personal facts, attribution and deletion tests |
| 02B | Selected Drive/GitHub imports, incremental sync | Independent OAuth, least privilege, revoke/delete tests |
| 03A | Authorized macOS audio capture and local ASR | Real mic/remote channel and memory benchmark on Mac |
| 03B | Question/turn state machine | Multipart/interruption/correction tests |
| 04A | Native short-answer panel and integrated authorized session | Measured permitted mock call and honest unavailable states |
| 05A | Learning-event store and fact verification workflow | User corrections and reversible memory promotions work |
| 05B | Adaptive retrieval/response improvement | Held-out regression improves or change rolls back |
| 06 | Security, accessibility, latency, reliability hardening | End-to-end verification on target hardware |
| 07 | Optional adaptive mock interviewer | Realistic challenge cases improve assistant responses, not mandatory education |

## First technical dependency gate
If official subscription-backed inference is unavailable for the user's ChatGPT plan/workspace, document the exact outcome. Do not silently use API credits, scraping, a web session cookie, or paid inference. A test using synthetic mock responses is not live-model proof.

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
