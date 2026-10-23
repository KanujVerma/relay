# Continuous Interview Copilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement each lane with meaningful red/green cycles, independent review and frequent verified commits. The owner's explicit parallel instruction overrides serial-only implementation guidance; each lane is isolated and has disjoint ownership.

**Goal:** Build a continuous contextual interview copilot spanning live conversation, verified personal background and a useful actual answer panel.

**Architecture:** Native Swift owns selected sources, local transcription, protected preparation and display admission. One local Python helper composes the existing question authority, verified-context provider and reviewed/generated answer paths. Source-stamped requests and an explicit native commit gate suppress stale output.

**Tech Stack:** Existing Swift/SwiftUI/Core Audio/FluidAudio and Python/SQLite/OAuth; native Security/CryptoKit; narrowly researched pinned dependencies only where justified.

**Spec:** ../../BUILD_CONTRACT.md and ../../PARALLEL_PLAN.md, approved for implementation by the owner on 2026-10-23.

## Global Constraints

- GPT-6.1 Sol with extra-high reasoning for all workers.
- Automatic questions/follow-ups; no per-question confirmation.
- Verified personal grounding in the first useful version; never invent individual achievements.
- Keep mic and selected remote source distinct; null ASR confidence stays null.
- Preserve original native request/session fences through actual UI commit.
- Reuse existing source/tested components; record exact upstream version/license/copied symbols and modifications.
- Each lane owns its isolated branch and files. Controller owns common contract/global HANDOFF and integration.
- Frequent scoped commits/pushes are authorized; main merge, private/hardware/account acceptance and material scope expansion remain separate gates.

## Preflight and interfaces

| Pair | Producer/consumer | Finding and ruling |
| --- | --- | --- |
| Conversation / answers | Native event and synchronous lease -> Python host + panel | Use BUILD_CONTRACT exact fields and generation rules. Microphone updates context without retracting remote talking points. |
| Personal / answers | Provider-issued ContextBundle + currentness -> grounded card | Use retrieve/validate_current port. Never accept model-authored fact IDs or a caller authorization boolean. |
| Conversation / personal | Both expose Swift libraries to the final panel | Separate packages; panel owner alone edits its manifest and native app bundle. |
| All lanes | Shared source/review docs | Only controller edits canonical HANDOFF/contracts/ADRs; each builder owns its lane handoff/plan. |

### Task 1: Continuous conversation, issue #60

**Files:** Create spikes/macos-session, docs/NATIVE_SESSION.md, docs/lanes/CONVERSATION.md and a lane-specific plan. Narrow existing ASR provenance seam is owned here.

**Consumes:** Actual owned PCM/capture and repaired ASR; BUILD_CONTRACT native envelope.
**Produces:** RelayNativeSession library, synchronous presentation authority, explicit-start session executable and bounded real source/control events.

- [ ] Write lane plan with exact public Swift signatures and first stale-lease/closed-activity tests.
- [ ] Run failing synthetic tests before implementing bounded lifecycle/VAD/ASR/event code.
- [ ] Implement mic/remote sources, native clocks, whole closed-activity provenance and stop/backpressure behavior; adapt pinned source with notices.
- [ ] Run `swift test --package-path spikes/macos-session`, affected ASR tests and `git diff --check`; record actual counts/skips.
- [ ] Commit/push each independently passing slice plus lane handoff; provide immutable diff/report for independent review.

### Task 2: Personal context, issue #61

**Files:** Create personal_context/profile_preparation/profile_bridge modules+tests, spikes/macos-profile, docs/PERSONAL_CONTEXT.md, docs/lanes/PERSONAL.md and a lane plan. Existing store/converter seams are owned here.

**Consumes:** Existing BrainStore/ReviewGateway/converters and synthetic explicitly selected sources.
**Produces:** Immutable ContextBundle provider, native preparation/review library and protected persistence/bridge.

- [ ] Write lane plan and failing source-selection, self/team, relevant retrieval and revocation tests.
- [ ] Research exact native security/crypto source/tests and implement injected-key full encrypted persistence without a plaintext disk DB.
- [ ] Implement bounded profile transfer and real native preparation action boundaries; provide provider fixtures to answer lane.
- [ ] Run targeted and full affected Python tests, `swift test --package-path spikes/macos-profile`, fixture/docs checks and diff checks.
- [ ] Commit/push coherent slices and lane handoff; provide immutable diff/report for independent review.

### Task 3: Contextual answers and native panel, issue #62

**Files:** Create generated/assembly/async transport/session host/context modules+tests and extend spikes/macos-panel; own continuous-purpose-string bundle. Create docs/CONTEXTUAL_ANSWERS.md, docs/lanes/ANSWERS.md and a lane plan.

**Consumes:** Native event/lease port, ContextBundle provider, existing OAuth/question/reference/panel components.
**Produces:** One runnable helper + real panel with automatic reviewed, novel technical and grounded personal fixture flow.

- [ ] Write lane plan and failing multi-turn context, generated-card, malformed/completed stream and stale-publication tests.
- [ ] Implement one coordinator/router, bounded async model adapter, exact personal grounding and shared typed cards.
- [ ] Implement actual child-process framing and Swift panel lease checks; integrate the other lane libraries through the agreed ports.
- [ ] Exercise live-coding and feature-case-study fixtures, missing context, profile revoke, old model completion, stop/resume, helper failure and delayed UI commit.
- [ ] Run affected/full Python tests and native panel tests/build, then commit/push slices plus lane handoff for independent review.

### Task 4: Joined integration and verification

- [ ] Review each immutable lane diff independently; fixes return to original implementer and get scoped re-review.
- [ ] Integrate reviewed lane commits into build/parallel-foundation-2026-10-23 without merging main; preserve source/test and scope history.
- [ ] Run complete Python fixture/docs/tests, native session/profile/panel and affected ASR suites. Re-run only when changes/failures justify it.
- [ ] Run a real local child helper with synthetic source/model/profile inputs through the actual native state path; separate visible-window and external hardware proof.
- [ ] Commit the exact joined head, source evidence, lane state and next action to GitHub. Open/attach draft feature PRs against the build foundation, making parent dependencies explicit.
- [ ] Prepare the bounded consented live-Mac/model acceptance after code is reviewable; do not report unrun hardware/private/account tests as passing.
