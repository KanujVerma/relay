# Typed assistant foundation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** Implement real typed Ask/Help-current/Stop and bounded actual transcript/activity ports for the Cluely-style session surface.

**Architecture:** Privately issued native user actions use the same controller-locked ingress and inference worker, with distinct explicit semantic tokens and no fake audio. A deny-only original-request marker precedes held-frame release; cancellation waits for the captured worker. Draft basis is bounded read-only same-session history under a fresh request, not old permission.

**Tech Stack:** Existing Swift6.2 native/controller/composition/transport, Python QuestionTurnMachine/ConversationContext/SessionHost/QA/OAuth, HTTPX MockTransport tests.

**Spec:** [Approved typed design and controller amendments](../specs/2026-10-23-typed-assistant-design.md).

## Global constraints

- Preserve existing ManualHelp equality/forwarded-sequence tests and all audio sequence/generation/lease behavior.
- Exact typed11-key, denial7-key, cancel9-key and completion10-key schemas in the spec; BE32/16KiB, strict integer/UUID/text validation.
- One active inference and newest pending; no second model transport/framework or API-key fallback. Real target completion before quiesced receipt.
- No SessionApplicationModel, auth/profile/vault, UI views or model-provisioning edits in this foundation phase. Root later wires explicit app hooks; no visible stubs.
- Transcript64 rows/64KiB with whole-row eviction, actual native finals only, no speaker identity inference or persistent history/biography promotion.
- Owner-approved GPT-6.1 Sol extra-high workers, meaningful scoped commits/pushes and draft PR. No main merge.

## Task1: Semantic/helper foundation

- [ ] Add strict user-question/retirement/cancel types/decoder negative tests; implement actual live helper admission before source/model work. Preserve prior current-question Help behavior.
- [ ] Add explicit fresh-token issuance and pure task projection without mutating audio replay/history/task ownership. Bound retained same-session historical basis to8 records and revalidate current personal/source grounding.
- [ ] Share existing references/personal/generated QA/OAuth engine and one-worker lifecycle. Add deny-only original-request fences before held release and owned targeted actual cancellation receipts/replay.
- [ ] Verify actual synthetic child Ask before first remote question, biography withholding/reference no-model paths, malformed/replayed/stale requests, completed SSE and uncooperative cancellation with injected transport. Keep exact source/provenance counters.

## Task2: Native ports and activity

- [ ] Add private native issuance types/methods under the controller lock and same ordered ingress; do not allocate audio sequences or manufacture EOU.
- [ ] Add forwarder/helper parser/waiter and injected draft/controller/activity DTOs. Root-owned app hooks remain a concrete local integration patch until permitted.
- [ ] Prove actual held original EOU/PNG plus typed Send/Stop/later onset: original order, matching retirements before release, zero model POST for a stopped held request and no stale publication. No raw frame recording substitute for the real helper proof.
- [ ] Verify draft revision/retained basis, exact cancel receipt ownership, actual finals and bound/retire/no-late-restore transcript behavior. Run affected packages; do not re-audit accepted capture/profile internals.

## Task3: Root/UI integration

- [ ] Independently review frozen own delta, return fixes and narrow re-review.
- [ ] After automatic source is frozen/accepted, root wires actual SessionApplicationModel ingress/receive/bind/commands, then UI wires top Send/Stop/Help and transcript. Build/test real app/helper with synthetic data and render current states.
- [ ] Publish exact results/remaining standalone idle Ask, modes/history/account gaps. This active-session slice does not close full product parity.
