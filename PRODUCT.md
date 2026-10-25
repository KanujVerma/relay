# Relay product contract (Slice 00)

Status: proposed, version 0.1. The source of truth for product scope; update deliberately through reviewed PRs.

## Mission
A local-first macOS personal interview copilot that uses authorized context to help the user perform effectively in job interviews, with particular strength in software development and junior data/BI/analytics interviews. The central metric is the usefulness, accuracy, and timeliness of relevant talking points, not hours of tutoring.

## Non-negotiable requirements
1. **Job-specific:** Load a role pack per interview, including job description, likely question families, unexpected cases, and applicable verified background. Company-specific predictions are hypotheses, never guarantees.
2. **Personal Brain:** Import a resume, explicitly selected documents and connected sources, and conversationally confirmed life/project experience. Index with provenance; distinguish individual contributions from group contributions. Never manufacture credentials, tools used, or outcomes.
3. **Fast responses:** During a permitted live session, present a short direct answer first; offer additional detail and code when useful. Set an initial engineering target of first useful response within 4 seconds after a complete question, with p95 evaluated separately; these are targets, not measured capability.
4. **Answer quality gate:** Check factual correctness where testable, question coverage, context support, and concise conversational style. Use deterministic checks and selective AI review rather than forcing a full second model call on every question.
5. **Continuous learning is foundational:** Capture permitted session question patterns, explicit corrections, output quality feedback, source attribution, role relevance, and response-style preferences. New biographical facts remain unverified until user confirmation. Improvement must be measurable on held-out evaluations.
6. **Technical questions:** Strong at SQL, Python, coding tasks, debugging, algorithmic edge cases, data visualization and business reasoning; respond to missing schemas/constraints by making uncertainty or follow-up explicit.
7. **Privacy and control:** Local default storage, granular import permissions, consent-aware recording, deletable session data, protected OAuth tokens, source revocation and a clear live assistance state.
8. **Inference economics:** Target no separate per-token AI API bill by evaluating official ChatGPT-authenticated integration first. Capability, account entitlement, model limits and acceptable use are unproven until Slice 01 validation. Do not use browser-cookie scraping or claim that a ChatGPT subscription universally includes API credit.
9. **Permitted use:** Provide rehearsal, transcription, notes, and live assistance where permitted and with necessary consent. Do not promise full-screen-share invisibility or build undisclosed assessment assistance or detection avoidance.

## Primary modes
- **Interview context:** Configure role, employer, job description, expected round, and verified relevant projects before a session.
- **Permitted live session:** Detect questions, track multi-turn follow-ups, surface compact high-confidence talking points, signal ambiguity, provide optional expand/code.
- **Debrief and improvement:** Record questions, quality issues, user corrections and role-specific gaps; adapt future retrieval and presentation.
- **Optional mock interviewer:** Stress-test assistant answers with follow-up questions; not a mandatory learning course.

## Non-goals for the MVP
Generic education platform, full CRM/job tracker, unsupported sentiment-based hiring predictions, blanket Google account ingestion, unchecked autobiographical memory changes, heavy always-on background model training, stealth screen-sharing, and paid external inference by default.

## Acceptance at the product level
- Accurate and sourced personal claims; explicit fallback for missing or contradictory information.
- Short SQL/coding answers that address edge cases and do not invent missing inputs.
- No conflation between model-suggested responses and the user's demonstrated competence.
- No persistence of unconfirmed biographical claims.
- Easy source/record deletion and credential revocation.
- Track p50/p95 latency, unsupported-claim rate, question coverage, correction rate and memory accuracy on a manually reviewed evaluation set.
- Each implementation slice has a small PR, reproducible checks and a current HANDOFF.md.

## Clarification, 2026-10-23

The intended experience is a single always-ready conversational copilot. After session setup, it listens to the interviewer and the user's replies, understands the current question and follow-ups, and automatically provides concise technical explanations or suggestions grounded in the user's real résumé/projects and job context. Both reusable reviewed material and on-demand generation serve this one experience. Source/review status must not require the user to choose an answer mode or approve each question. Verified personal grounding is part of the first useful integrated product. The controller's revised proposal is in the [parallel delivery plan](docs/PARALLEL_PLAN.md); architecture and acceptance still need agreement before new implementation.
