# Relay: agent entrypoint (read this first)

This repository is the durable source of truth. A new agent must be able to take over without access to any preceding ChatGPT conversation. The repo describes intent, verified decisions, constraints, current reality, evaluation cases, and next actions.

## Reading order
1. HANDOFF.md: actually completed work, active issue, blockers, next action.
2. PRODUCT.md and docs/PRODUCT_VISION.md: what Relay is, whom it serves, and what it must not become.
3. ARCHITECTURE.md, docs/DECISIONS.md and docs/WORKFLOWS.md: design choices and data flow.
4. docs/INFERENCE_AUTH.md and docs/MEMORY_AND_EVALUATION.md when relevant.
5. ROLE_PACKS and EVALS for the exact active slice. See docs/SLICES.md for roadmap and docs/REFERENCES.md for research sources.

## Relay in 90 seconds
Relay is a native macOS, local-first personal AI interview copilot. Its intended use is authorized job interviews and realistic mock sessions. It recognizes questions and follow-ups, retrieves the right role-specific information and verified personal experience, and provides short, accurate talking points with optional code/SQL detail. The objective is real interview performance and job outcomes, NOT a generic learning or studying platform.

First role specializations: Epic Software Developer, and junior AI/BI/data analytics/data visualization. Target hardware: a 16 GB M2 Pro MacBook Pro. Be particularly accurate about SQL joins, grouping, metric definitions, Python/coding corner cases, individual project contributions, and surprise follow-ups.

Two foundational memories:
- Personal Brain: confirmed biographical facts, actual individual responsibilities, project stories, resume, user-approved external files.
- Learning Memory: question patterns, assistant response errors, user corrections, role relevance, presentation preferences. An AI-generated suggestion is not proof of user skill.

Continuous learning optimizes the copilot itself. The quality gate checks correctness, relevance, personal support and concision, using cheap deterministic checks and selective model review rather than a mandatory slow second pass.

## Invariants
- One small slice, issue, branch and reviewable PR at a time. Do not start unrelated work.
- Update HANDOFF.md, relevant ADRs, and tests in each slice. Do not silently rewrite settled scope.
- Distinguish implemented/measured from proposed or documented. Never claim account entitlement or latency without a live verification.
- Verify project participation; never invent credentials, metrics, Power BI/Tableau experience, or personally written code attributed to another contributor.
- Keep private user material out of Git, logs and CI, even after repo becomes private: no OAuth tokens, secrets, resumes, recordings, transcripts, Drive files or raw imports. This repository is currently PUBLIC by owner choice.
- Plan inference using officially documented ChatGPT subscription OAuth if account is eligible, with no automatic separately billed API fallback. Do not scrape browser cookies or undocumented backend endpoints.
- Meeting capture and assistance only with appropriate permission and consent. Do not implement stealth screen sharing or prohibited undisclosed assessment assistance.
- Store original question/correction events distinctly from derived profiles. New personal facts require user confirmation.
- Prefer offline Linux tests. Do not run private-user OAuth or paid inference in CI. Avoid large macOS Actions usage unless justified.
- For upstream technologies, review source URL, version, license and platform requirements before dependency adoption.
- Live UX: concise answer first, up to two supporting points, optional expansion; no noisy dashboards or unnecessary tutoring.

## Completion checklist
1. State exact current repository state and issue being addressed.
2. Make the smallest change that meets acceptance conditions, with negative tests.
3. Verify locally or via relevant CI; report exact observable results, not promises.
4. Update design decisions if a choice is made or falsified.
5. Update HANDOFF.md with completed tests, current blockers and one exact next action.
6. Review the precise PR head before merging; do not merge failed or unknown critical checks.

## If context is lost
Read HANDOFF.md, inspect live GitHub PR/issues, then read the associated contract files. Continue the explicitly active slice only. Conversation summaries are not authoritative implementation evidence.

## Code Review Rules
### OAuth and billing boundary
- Flag authentication that permits inference without the granted plan scope, verified ID token, matching callback state/Host, or Bearer credential validation.
- Flag browser-cookie reuse, undocumented ChatGPT backends, silent conventional API-key fallback, secrets in logs, and accidental paid model/CI requests. Supported pattern: user-authorized plan OAuth only.
### Knowledge and response integrity
- Flag fabrication of personal credentials, projects, implementer attribution, test results, or treating model-generated answers as evidence of user skill. Safe behavior: verify source and explicitly abstain on missing personal context.
- Flag unchecked promotion of interview transcripts into confirmed personal history, ignoring user corrections, or failure to invalidate stale question answers.
### Stream and data boundaries
- Flag treating partial/failed SSE streams as successful without response.completed, leaking private files/tokens, or capturing meeting content without required consent. Keep review high-signal; leave formatting to CI.
