# Contextual answers implementation plan

Goal: automatically assemble a bounded current-question, recent-dialogue and approved-background request, use reviewed content first or one OAuth model request, then publish one immutable bounded card through native admission.

Approved architecture: existing QuestionTurnMachine and ActiveTurns; injected confidence-free eligibility; read-only PersonalContextProvider; separate GeneratedCard authority; strict length-prefixed helper; ordinary SwiftUI window with native lease check at MainActor commit. Offline injected inputs are the development default. No live credentials, capture or inference acceptance is claimed.

1. [x] TDD bounded conversation/task context, strict card JSON and coherent completed Responses accumulator. Coding tasks retain problem/constraints/attempt/feedback/assumptions/next step; case studies retain users/problem/requirements/flows/design/tradeoffs/validation as dialogue data, never personal authority.
2. [x] TDD one reviewed-first router, composite eligibility and async OAuth transport using the existing endpoint/payload/auth. Bound deadlines, events, bytes, requests, cancellation and revocation.
3. [x] TDD framed stdio coordinator using existing turn state, original immutable native fence/token, one terminal latch, and real-process offline scenarios.
4. [x] TDD Swift typed decision, lease gate and ordinary window/helper transport; compile real production entrypoints, preserve existing demo/reducer tests.
5. [ ] Run held-out multi-turn technical/coding/case/personal/error scenarios, full Python tests, fixtures/docs and Swift tests/build. Record exact boundaries and commands in lane handoff; publish passing checkpoint commits and draft PR.

Owned files: new relay_spike/{conversation_context,generated_answer,response_assembly,oauth_answer_stream,panel_wire,session_host}.py; focused tests; requirements-answers.txt; docs/CONTEXTUAL_ANSWERS.md, docs/lanes/ANSWERS.md; spikes/macos-panel and continuous app build script/bundle. Shared adapter/policy edits only narrow optional seams. Controller owns global instructions/handoff/manifests and integration review.

Source reuse inspected: OpenAI Python SDK e8a0fd2 Apache-2.0 indexed Responses state; HTTPX 26d48e0 BSD-3-Clause AsyncClient response cleanup; MCP Python SDK 2af9e30 MIT real-child lifecycle patterns. These are source/test design references, not vendored code. Direct dependency HTTPX ==0.28.1. Existing Relay reference publisher, turn adapter and SwiftUI are reused. No whole provider SDK, MCP, Muesli or external JSON schema runtime is necessary.
