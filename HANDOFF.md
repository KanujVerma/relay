# Relay handoff: current state and continuation

Updated 2026-10-23. Snapshot base: `eb28d1586e52b7f0fd2e3b15580ae08ff295872e` on GitHub main. This documentation branch does not implement the proposed features below. Recheck live branches, PR heads, checks and working-tree state before acting.

## Goal and approved decisions

Deliver a permitted native Mac audio -> question -> visible answer flow. The owner explicitly requires **automatic routing from the first integrated version**, with both reviewed SQL/coding answers and open-ended technical model answers. A manual question-confirmation step is not the milestone.

The owner requested parallel agents managed by a controller, with one agent first repairing existing work. The owner subsequently authorized frequent commits and pushes of agreed work at meaningful verified checkpoints; routine scoped publication does not require repeated confirmation. Merge approval and material scope expansion remain separate. Every worker for this effort must use **GPT-6.1 Sol with extra-high reasoning or higher**. Before creating new architecture, inspect relevant open-source source and tests, check version/license/platform requirements, and record actual reuse versus lessons or rejected alternatives.

GitHub is the durable source of truth. A new chat or agent must be able to continue from this repository, not a preceding conversation. Update this file and the relevant contract/evidence in each slice. [PARALLEL_PLAN.md](docs/PARALLEL_PLAN.md) owns lane scope, write ownership, proposed interfaces and integration order. [UPSTREAM_REUSE.md](docs/research/UPSTREAM_REUSE.md) owns the new source-research record. Proposed detailed contracts are [SESSION_BRIDGE.md](docs/SESSION_BRIDGE.md) and [GENERATED_ANSWERS.md](docs/GENERATED_ANSWERS.md); [repair evidence](docs/evidence/2026-10-23-pr-fixes.md) records local verification.

## Implemented on the snapshot main

| Component | Actual scope |
| --- | --- |
| OAuth and refresh | Existing official plan-backed transport and guarded token rotation. Owner-reported Mac inference/refresh succeeded; broad reliability is not established. |
| Mic and selected-app PCM | PRs #27/#32/#38 merged. Owner-reported synthetic Chrome tone and mic signal succeeded on M2 Pro; Zoom/device/denial coverage and ASR speech quality remain separate. |
| Question state | PR #42 merged at this snapshot. Offline transcript corrections, follow-ups, replay protection and shared ActiveTurns; no actual native audio integration. |
| Native EOU wire | PR #52 merged. Strict schema/timebase validator only; no native serializer/transport. |
| Native panel | PR #54 merged. Ordinary visible SwiftUI mock window and freshness reducer; no real question/answer transport. |
| Reviewed answer route | PRs #56/#58 landed. Local reviewed WHERE/HAVING reference and Python publication gates. One eligible reviewed question is not general technical Q&A. |
| Personal Brain and converters | PRs #18/#26/#34/#36 merged. Synthetic provenance/review/conversion work; real user imports, native confirmation and protected production storage remain unimplemented. |

Detailed historical measurements and original slice evidence remain in [the prior handoff at the snapshot base](https://github.com/KanujVerma/relay/blob/eb28d1586e52b7f0fd2e3b15580ae08ff295872e/HANDOFF.md). Treat its old active-PR and next-action language as historical. Product intent remains in [PRODUCT.md](PRODUCT.md), not an implementation claim.

## Existing repairs: published PR heads, not merged to main

The owner approved publication. [PR #46](https://github.com/KanujVerma/relay/pull/46) now has repair head [7cba4e1](https://github.com/KanujVerma/relay/commit/7cba4e1fcffcf16358945253e6511c0d355aa5b6); [PR #49](https://github.com/KanujVerma/relay/pull/49) now has repair/main-reconciliation head [cf30aaa](https://github.com/KanujVerma/relay/commit/cf30aaa8ff7ae03529e31cae343b69199856415b). Both normal fast-forward pushes succeeded. Neither PR was merged to main and no GitHub review threads were resolved by this effort. Inspect checks and review on these exact new heads; local review evidence is not a remote completed-review claim.

- **PR #46**, repaired baseline `1eaa189eaca58e6d27d809071cf763f263a7eac2`: the three old unresolved review findings were already repaired in that source. Their regressions were independently checked. The remaining CI failure lost the `needs_review` reason when a contradictory blank-terminal revision arrived during full quarantine. The local 30-line adapter/test patch preserves that signal without restoring any token/context. Full **391 tests, 21 optional converter skips, zero failures**; fixtures/docs pass; independent local review passed. Remote exact-head CI/review still required after publication.
- **PR #49**, repaired baseline `7ec148d2bc0c2ce19560663d6d86ed6c1e9fe669`: stop during an awaited transition reset could emit no invalidation. The initial local fix passed 20 Swift tests and 342 Python tests with 21 optional skips after reconciling main. Extra-high review then found and reproduced a duplicate-terminal regression on error/limit resets. The final transition-only identity fix passed **21 Swift fake-recognizer tests**, including the three transition cases and a five-case deterministic regression that failed ten expected assertions on the initial repair. Independent extra-high re-review marked the finding addressed with no new actionable findings. The final combined patch SHA-256 is `ab98abd0681efddab0eca1e8e8597ba9da447a522366cb2da4b7e970cdd749ce`; the superseded initial patch must not be published. Only HANDOFF conflicted with main; it was resolved locally without replacing later main source. Published cf30aaa has the original ASR head and snapshot main eb28d15 as its two parents, preserving the reconciliation ancestry.

At the publication check, PR46 contract CI [passed](https://github.com/KanujVerma/relay/actions/runs/39984513674). PR49 contract CI [passed](https://github.com/KanujVerma/relay/actions/runs/39984523653), while [native audio](https://github.com/KanujVerma/relay/actions/runs/39984523674) and [ASR fake tests](https://github.com/KanujVerma/relay/actions/runs/39984523654) were still running. Recheck those exact runs before treating native CI as complete.

The 21 Python skips are optional document-converter integration tests; their dependencies were not installed for these repairs. Synthetic tests do not establish on-device recognition, microphone/system permission coverage, model latency or real UI behavior.

## Proposed work, not implemented

Three end-to-end lanes are planned: native selected-app session -> honest transcript/control events; reviewed technical question -> reviewed answer in the actual panel; open-ended technical question -> model-generated answer under a new explicit publication policy. All feed one router and one native display contract. The automatic/both-lanes goals are approved; the detailed transport, generated-answer publication policy and implementation briefs remain proposals for architecture discussion.

Important current gaps:

- ASR supplies null confidence. VAD probability is speech probability, not transcript accuracy. Automatic intent/eligibility needs an evaluated confidence-free strategy, not a fabricated score.
- The existing inner EOU v1 schema has **13 exact keys**. Session IDs, ordering, speech onset and stop need an explicit versioned outer contract; do not silently add inner fields.
- PR #46 already has `remote_speech_started(...)` and retained interrupted context. Reuse it. VAD activity IDs and ASR segment IDs cannot be equated without proven consumed-audio provenance.
- Python object identity/locks do not survive transport. Native must reject stale cards again at actual UI state commit, using source-stamped session/request fences.
- Current broad model output is withheld. Showing a generated suggestion needs an explicit new status/policy, distinct from an independently reviewed reference or verified personal fact.
- The current synchronous SSE read can block; safe stale-output suppression alone does not establish prompt cancellation or useful interruption recovery.

## At risk and publication boundary

Repair source is committed and available on the two PR branches. The essential verification and design/source evidence is recorded in this documentation branch, coordination/parallel-plan-2026-10-23. Its merge to default main is a separate pending action; a GitHub-only agent should inspect the open documentation PR as well as main. Machine-local scratch logs and superseded patches are supporting artifacts, not the only copy of the repair or the continuation plan. The owner's existing checkout and unrelated build/Package.resolved files were not edited. Do not commit caches, model artifacts, credentials, recordings, transcripts or private imports.

For each subsequent checkpoint, record exact commit/PR links and observed check/review outcomes here. Do not repeat approval requests for routine commits/pushes within agreed scope. Keep pending remote CI, code review, architecture decisions and hardware gates explicit. Never label a review request as a completed review.

## One exact next action

Verify remote exact-head checks and completed review for published PR46 head 7cba4e1 and PR49 head cf30aaa. Then agree the proposed generated-answer/shared-session contract before starting new feature code. Main merges remain separately approved actions.

## Resume procedure and open decisions

1. Read [AGENTS.md](AGENTS.md), this handoff and [PARALLEL_PLAN.md](docs/PARALLEL_PLAN.md).
2. Inspect live GitHub main, PRs #46/#49, open issues #22/#33/#43/#45, checks and review threads. Compare actual source with comments; unresolved threads can describe fixes already present.
3. Inspect Git status and the published repair commits plus evidence before reusing local artifacts. Do not reapply superseded patches to a repaired branch or assume an old unresolved comment proves the current source is still broken.
4. Continue the next action above, or an explicitly approved disjoint lane. Do not repeat merged prototypes or turn proposed architecture into a completion claim.

Open architecture decisions: generated-answer release rules, cancelable transport choice, and exact shared session/answer schema. The owner invited discussion. Real source/ASR/UI/inference acceptance remains separately measured on the target M2 Pro.
