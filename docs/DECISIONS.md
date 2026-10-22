# Architectural decision records (ADR ledger)

Statuses: Accepted = established requirement; Provisional = preferred implementation requiring proof; Blocked = external condition not satisfied; Deferred = outside current slice. Reviewed 2026-10-22. Update in reviewed PRs; do not quietly change history.

| ID | Status | Decision | Trade-offs / validation |
|---|---|---|---|
| ADR-001 | Accepted | Local-first native macOS app, Apple Silicon target | Fits hardware and audio API. Avoid early cross-platform framework overhead. |
| ADR-002 | Accepted | Real authorized interview performance, not tutoring, drives priority | Optimize response usefulness, accuracy, speed, and personal relevance. |
| ADR-003 | Accepted | Start with Epic developer and junior BI/analytics Role Packs | Specific job posts override anecdotal company interview patterns. |
| ADR-004 | Accepted | Separate Personal Brain from Learning Memory | Never confuse model suggestions with proven user ability or biography. |
| ADR-005 | Accepted | Personal facts need source/provenance, scope, confirmation and freshness | Prevent fabricated metrics, roles and tool experience. |
| ADR-006 | Accepted | Continuous learning foundational with reversible derived preferences | Track explicit corrections, topic patterns and regression results, not model fine-tuning by default. |
| ADR-007 | Accepted | Minimal answer-first UI, optional expansion | Full essays are unusable during a live conversation. |
| ADR-008 | Accepted | Fast deterministic answer checks and selective second-stage model review | Double generating every answer risks unusable latency and plan usage. |
| ADR-009 | Provisional | SwiftUI with native Core Audio/SystemAudioKit, FluidAudio local ASR/VAD | Benchmark mic/remote capture, permissions, latency and RAM; evaluate upstream licenses. |
| ADR-010 | Provisional | SQLite + FTS5 retrieval first, local embeddings only if necessary | Low RAM, provenance, local deletion; validate retrieval before adding vector models. |
| ADR-011 | Accepted for local feasibility | Official ChatGPT-plan OAuth to Responses | User-reported local browser OAuth plan grant, eight-model catalog and gpt-6.1-sol response.completed on 2026-10-22. Production reliability, refresh and usage caps remain unverified. |
| ADR-012 | Accepted | External Drive/GitHub/ChatGPT permissions are independent | ChatGPT sign-in does not grant ChatGPT memory, conversations or connected apps. |
| ADR-013 | Accepted | Versioned append-only events and reversible derived state | Maintain auditability and permit improved evaluation rubrics. |
| ADR-014 | Accepted | No personal data or secrets committed to Git even if private later | Public repo is intentional until owner changes it. |
| ADR-015 | Accepted | Authorized recording/transcription and compliant AI use only | No stealth capture, detection evasion or guarantee of invisibility. |
| ADR-016 | Accepted | One small scoped PR per slice and durable GitHub handoff | Avoid context rot and giant, unreviewable agent changes. |
| ADR-017 | Accepted | Cheap offline Linux CI by default | Protect account-shared private Actions minutes; local Mac testing first. |
| ADR-018 | Deferred | Advanced dashboards, mandatory practice plans and spaced repetition | Optional mock interviewer can test assistant response quality later. |
| ADR-019 | Provisional development policy | Production model choice requires measured accuracy and first-useful-text speed | Across 9 owner-reported matched default-effort pairs, Luna median first text/full 3265/6371ms vs Sol 6.1 4258/8761ms; Luna finished first 8/9. Assistant inspection only, no p95 or real usage evidence. Prefer Luna Medium for next development slice, not a fixed production policy. See docs/MODEL_STRATEGY.md. |
| ADR-020 | Accepted | OAuth callback must verify bound loopback Host and state before consuming a browser redirect; persist only validated Bearer credentials | Limits unsolicited loopback callback DoS and malformed credential persistence. Negative tests in tests/test_spike.py; **not yet security-tested on user Mac**. |

| ADR-021 | Provisional | Adaptive model routing (Luna-first, Sol selectively, Astra offline optional) | New repeated fixtures do not show a clear Sol accuracy advantage: Sol started E09 earlier but finished slower. The model must remain selectable, with escalations tied to verified quality benefit rather than coding complexity alone. |
| ADR-022 | Accepted | Request high-signal GitHub Codex reviews through PR comments; verify actual result | Use `@codex review` with AGENTS.md rules; GitHub PR review usage is not the same as free Codex approval auto-review. See docs/PR_REVIEW.md. |

| ADR-023 | Provisional implementation | A dry-run-first, fixture-only local comparison CLI must require explicit --execute and cap requests per invocation | Prevent surprise plan usage, avoid personal content in CI, and compare models on identical prompts. Verify offline tests and actual user-run results separately. |

| ADR-024 | Partially validated | Optional model-specific reasoning.effort in Responses; default field omitted, Medium observed for Luna and Sol 6.1 | Four user-reported completed OAuth plan requests returned matching Low/Medium efforts for both models on the tested account. Other levels/accounts, latency benefit and long-term preview support remain unverified. Validate before auth, cap calls, report requested versus server effort separately; no automatic high/pro or paid fallback. See docs/MODEL_STRATEGY.md. |

| ADR-025 | Accepted for offline Slice 01B-B0 | Deterministic QA gate returns pass/revise/abstain plus optional deeper-review recommendation, not factual correctness | Fail closed on incomplete/stale **turn IDs and versions**, unknown trusted personal-attribution classification and absent verified personal context; source IDs never independently support first-person claims. Multi-part indicators require token boundaries and are still only weak missing-part heuristics. No extra model call from the gate. B1 must re-check freshness at publish and independently test correctness/latency. See issue #12 and PR #14. |

| ADR-026 | Implemented offline, production integration deferred | Synthetic Responses SSE text flows through existing fail-closed completion semantics, into deterministic QA, then an active-turn-checked synchronous publish operation | `relay_spike/streaming_qa.py`: turn ID + version + generation prevent stale publications; only completed QA-pass answers may be exposed as `final_unverified`, with honest unavailable/revision/suppressed states. Adjacent SSE sequence replays deduplicate with constant-size fingerprint; out-of-order events and invalid/missing completion status fail closed. `first_scannable_candidate_ms` is only a heuristic and **not** a verified first-useful metric. No early publication, model usage, real provenance classifier, audio or UI in B1. Candidate Sol review is advisory only. See issue #15 / PR #16. |

| ADR-027 | Implemented prototype, production boundary deferred | SQLite stdlib local Personal Brain with explicit source consent, immutable audit history and separate candidate/verified claims (PR #18) | Reuse native SQLite transactions, foreign keys and a partial unique active-claim index rather than shipping an entire memory agent. Confirmation references must originate in a trusted user-action UI (not provided here). Actor self/team/teammate remains distinct; source/claim revocation invalidates retrieval and redacts dependent content. In-memory default; no production disk encryption/FTS, real import or model promotion. See docs/PERSONAL_BRAIN_STORAGE.md. |
| ADR-028 | Deferred | Native Swift SQLite adapter and semantic retrieval | GRDB.swift (MIT) is a strong macOS candidate, Mem0 (Apache-2.0) a learning/retrieval reference, and sqlite-vec (pre-v1) an optional future extension. None is required for deterministic, small 02A-A; do not adopt automatic agent-derived biographical memory or add dependency overhead without evidence. |

| ADR-029 | Prototype in review, live proof pending | Reuse the original OAuth SSE byte transport for one opt-in synthetic technical case and submit its completed text to existing deterministic QA and atomic turn-checked publication | No duplicate stream parser, API-key fallback or mandatory second model. Live QA dry-runs by default; strict model/effort allowlist and account catalog check before one request. Only whole-response exact matches to pre-reviewed D02/E09 technical smoke strings can earn absent attribution; novel model output is unknown or suspected personal, never auto-approved by a regex miss. This is **not** user-fact verification or general semantic correctness. Include HTTPS setup in timing; do not expose partial output or claim first useful text. See issue #23 and docs/RUN_LOCAL_LIVE_QA.md. |

| ADR-030 | Prototype implementation, local session proof pending | Renew ChatGPT-plan OAuth access within the existing local CLI using a refresh-token grant with the saved issued client ID; serialize token rotation with a protected cross-process lock | Validate Bearer, exact scopes, expiry, changed refresh/access token and optional client ID before file and parent-directory fsync-backed atomic replacement. Confirmed invalid refresh clears credentials but preserves registration identity. Network/5xx and malformed responses preserve state and never trigger automatic inference or a separate billed API route. Preflight PyJWT before browser sign-in. CI is offline; macOS Keychain, remote revocation, full multi-account management and owner-run refresh proof remain future slices. See issue #30 and docs/INFERENCE_AUTH.md. |

## Adding an ADR
Record context, options, chosen trade-off, security implications, validation/evidence, implementation location, status and date. If tests falsify a provisional decision, supersede it in a new entry and update dependent docs.

## Permission boundaries
ChatGPT plan token, Drive file access, GitHub access, microphone and system-audio capture are independent consents. Do not cross their trust boundaries. Imported documents and transcripts are untrusted data, never executable instructions.

## Security before shipping
Keychain-based tokens, safe refresh rotation, granular connector revocation, local data encryption, retention/deletion controls, prompt injection filtering, and recording consent all require implementation and tests. Being named here does not mean those protections exist yet.
