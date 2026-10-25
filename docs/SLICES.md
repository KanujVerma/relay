# Slice-based roadmap and execution discipline

Each slice gets a narrow issue, isolated checkout, branch, small PR, reproducible tests, updated architectural docs and an exact HANDOFF.md status. Parallel work follows the controller-owned [delivery plan](PARALLEL_PLAN.md), with disjoint file ownership. Done is evidence, not merely a code commit.

| Slice | Work | Completion gate |
|---|---|---|
| 00 | Product contract, initial roles, synthetic evaluation cases | PR #1 merged, fixture validation CI passed |
| 00B | Durable agent handoff, ADRs, flows, personal memory design, inference contract | PR merged, links and status consistent |
| 01A | ChatGPT subscription-backed inference authorization proof | Met in user-reported local OAuth and gpt-6.1-sol response.completed on 2026-10-22; offline tests in PRs #4 and #5 |
| 01A-R | Auto-refresh rotating OAuth grant and preflight missing PyJWT | **PR #31 merged, issue #30 closed**. Guarded rotation, cross-process lock, terminal vs transient recovery and pre-browser dependency check. 142 merged-head offline tests and final Codex review clear; **one owner-reported 2026-10-22 M2 Pro/APFS refresh succeeded**, rotating both tokens and reusing valid access on a second `models` request. Repeated idle/terminal error reliability unverified |
| 01B-A | Concise formatting and synthetic Luna/Sol comparison | PR #8 merged; 22 owner-reported requests completed in two rounds (18 default and 4 explicit Low/Medium); #9 gate completed, rigorous accuracy and first-useful-text evaluation remain future work |
| 01B-A1 | Optional model-specific reasoning effort CLI | PR #11 merged and reviewed; 4 owner-reported Low/Medium requests succeeded with matching server-reported effort on the tested OAuth account |
| 01B-B0 | Offline grounded answer QA contract | **PR #14 merged, issue #12 closed**. Green offline CI; three substantive Codex findings fixed and final exact-head review clear. Typed pass/revise/abstain, trusted attribution classification, active turn identity/version, conservative coverage heuristics and selective-review recommendation |
| 01B-B1 | Synthetic SSE assembly to fast QA and safe publication | **PR #16 merged, issue #15 closed**. 76 offline tests, exact-head green CI, two Codex P2 stream findings fixed and final review clear. Bounded SSE, ID/version/generation cancellation, distinct first-text/provisional-scannable/final timestamps, safe publication and advisory review only |
| 01B-B2 | Real OAuth text inference through synthetic QA, independent of audio/personal-data work | **PR #25 merged, issue #23 closed**. D02/E09 whole-answer synthetic smoke integration. 113 offline tests and final Codex review clear; later owner-reported Mac streams completed but ordinary answers were withheld. Useful broad publication remains pending |
| 02A-A | Local verified Personal Brain schema and provenance lifecycle | **PR #18 merged, issue #17 closed**. Stdlib SQLite, source consent, candidate/verified facts, actor provenance, atomic supersession and cross-source revocation/redaction. 92 synthetic offline tests; one P1 finding fixed and final Codex re-review clear |
| 02A-B0 | Synthetic résumé candidates and host-review contract | **PR #26 merged, issue #21 closed**. SQLite v2 candidate_evidence spans/source hashes, explicit actor/key review, atomic staging/supersession, normalized claim identity and rejected unsafe legacy approvals; green exact-head CI and final Codex review clear. In-process capability is not a verified UI click |
| 02A-B1a | Synthetic PDF/DOCX converter evaluation | **PR #34 merged, issue #29 closed**. Both exact-head CI checks passed. Pinned native PDF/DOCX with honest page/paragraph provenance, bounded atomic staging and flattened comparator rejection. Post-merge noncanonical DOCX header/footer relationship risk was fixed in **merged PR #36 (issue #35 closed)**, with both CI workflows green and final Codex review clear. No real private file import |
| 02A-B1 | Explicitly selected real résumé ingestion and conversational probing | After #29, evaluate actual opt-in sources, source-linked claims and verified personal project stories; private data remains off Git/CI, real user approval required |
| 02B | Selected Drive/GitHub imports, incremental sync | Independent OAuth, least privilege, revoke/delete tests |
| 03A | Authorized macOS audio capture and local ASR | **Capture PRs #27/#32 merged**, issue #28 closed; 11 synthetic macOS tests and bundle checks passed for #32. Parent issue #22 open: owner-reported synthetic Chrome/mic signal passed; actual Zoom/device/denial coverage, measured resource use and local FluidAudio speech proof remain pending. PR #49 remains open; repaired/main-reconciled head cf30aaa is published, native CI/review and hardware proof remain gates |
| 03B-A | Offline transcript-to-question turn state machine | **PR #42 merged** at snapshot main `eb28d15`, issue #41 closed. Shared ActiveTurns, corrections/follow-ups, bounded replay and cancellation are offline implementations; no live ASR integration |
| 03B-B | Finalized on-device ASR event adapter and intent-classifier evaluation | Synthetic adapter PR #46 is open; quarantine fix published as 7cba4e1 with green contract CI. Wire validator PR #52 merged. Real serializer/source/VAD-final alignment, confidence-free automatic policy and hardware evidence remain pending |
| 04A | Native short-answer panel and integrated authorized session | Mock-only panel PR #54 merged. Real source/helper transport, native display authority and measured permitted mock session remain pending |
| 05A | Learning-event store and fact verification workflow | User corrections and reversible memory promotions work |
| 05B | Adaptive retrieval/response improvement | Held-out regression improves or change rolls back |
| 06 | Security, accessibility, latency, reliability hardening | End-to-end verification on target hardware |
| 07 | Optional adaptive mock interviewer | Realistic challenge cases improve assistant responses, not mandatory education |

## Current parallel integration target, approved goals only

See [PARALLEL_PLAN](PARALLEL_PLAN.md) for write ownership, proposed interfaces, dependencies and acceptance. The owner requires automatic routing from the first integrated version and both reviewed SQL/coding answers and open-ended model answers. Current reviewed host PRs #56/#58 cover D02 only; expanded reviewed coverage and a distinct generated-answer policy are proposed new work. Native session, reviewed-answer/panel and open-ended-answer lanes may proceed in parallel only after shared contract/design agreement. Published repair heads still need exact-head remote review and the remaining checks; publication is not main merge or hardware completion.

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
