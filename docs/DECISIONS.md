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
| ADR-019 | Provisional | Production model selection depends on measured speed and role-specific correctness | One reported Sol run: 2640ms first text, 8306ms complete, 906 chars. Benchmark Luna vs Sol on identical concise questions. |
| ADR-020 | Accepted | OAuth callback must verify bound loopback Host and state before consuming a browser redirect; persist only validated Bearer credentials | Limits unsolicited loopback callback DoS and malformed credential persistence. Negative tests in tests/test_spike.py; **not yet security-tested on user Mac**. |

| ADR-021 | Provisional | Adaptive model routing (Luna quick, 6.1 Sol complex, Astra optional) | Documented capability/efficiency hierarchy, not empirically measured for Relay. Choose model after quality and p50/p95 latency comparisons. |
| ADR-022 | Accepted | Request high-signal GitHub Codex reviews through PR comments; verify actual result | Use `@codex review` with AGENTS.md rules; GitHub PR review usage is not the same as free Codex approval auto-review. See docs/PR_REVIEW.md. |

| ADR-023 | Provisional implementation | A dry-run-first, fixture-only local comparison CLI must require explicit --execute and cap requests per invocation | Prevent surprise plan usage, avoid personal content in CI, and compare models on identical prompts. Verify offline tests and actual user-run results separately. |

## Adding an ADR
Record context, options, chosen trade-off, security implications, validation/evidence, implementation location, status and date. If tests falsify a provisional decision, supersede it in a new entry and update dependent docs.

## Permission boundaries
ChatGPT plan token, Drive file access, GitHub access, microphone and system-audio capture are independent consents. Do not cross their trust boundaries. Imported documents and transcripts are untrusted data, never executable instructions.

## Security before shipping
Keychain-based tokens, safe refresh rotation, granular connector revocation, local data encryption, retention/deletion controls, prompt injection filtering, and recording consent all require implementation and tests. Being named here does not mean those protections exist yet.
