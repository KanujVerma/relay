# Slice-based roadmap and execution discipline

Each slice gets a narrow issue, branch, small PR, reproducible tests, updated architectural docs and an exact HANDOFF.md status. Done is evidence, not merely a code commit.

| Slice | Work | Completion gate |
|---|---|---|
| 00 | Product contract, initial roles, synthetic evaluation cases | PR #1 merged, fixture validation CI passed |
| 00B | Durable agent handoff, ADRs, flows, personal memory design, inference contract | PR merged, links and status consistent |
| 01A | ChatGPT subscription-backed inference authorization proof | Met in user-reported local OAuth and gpt-6.1-sol response.completed on 2026-10-22; offline tests in PRs #4 and #5 |
| 01B-A | Concise formatting and synthetic Luna/Sol comparison | PR #8 merged; 22 owner-reported requests completed in two rounds (18 default and 4 explicit Low/Medium); #9 gate completed, rigorous accuracy and first-useful-text evaluation remain future work |
| 01B-A1 | Optional model-specific reasoning effort CLI | PR #11 merged and reviewed; 4 owner-reported Low/Medium requests succeeded with matching server-reported effort on the tested OAuth account |
| 01B-B0 | Offline grounded answer QA contract | **PR #14 merged, issue #12 closed**. Green offline CI; three substantive Codex findings fixed and final exact-head review clear. Typed pass/revise/abstain, trusted attribution classification, active turn identity/version, conservative coverage heuristics and selective-review recommendation |
| 01B-B1 | Synthetic SSE assembly to fast QA and safe publication | **PR #16 merged, issue #15 closed**. 76 offline tests, exact-head green CI, two Codex P2 stream findings fixed and final review clear. Bounded SSE, ID/version/generation cancellation, distinct first-text/provisional-scannable/final timestamps, safe publication and advisory review only |
| 02A-A | Local verified Personal Brain schema and provenance lifecycle | [Issue #17](https://github.com/KanujVerma/relay/issues/17): synthetic SQLite source/fact/experience model, explicit approval, attribution and revocation tests, no private imports yet |
| 02A-B | Approved résumé ingestion and conversational probing | Actual user-approved data and project contributions, accurate source-linked retrieval, no unverified autobiographical promotion |
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
