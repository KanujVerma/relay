# Relay: agent entrypoint (read this first)

This repository is the durable source of truth. A new agent must be able to take over without access to any preceding ChatGPT conversation. The repo describes intent, verified decisions, constraints, current reality, evaluation cases, and next actions.

## Reading order
1. HANDOFF.md: actually completed work, active issue, blockers, next action. For the current integration effort, read docs/PARALLEL_PLAN.md and docs/research/UPSTREAM_REUSE.md next.
2. PRODUCT.md and docs/PRODUCT_VISION.md: what Relay is, whom it serves, and what it must not become.
3. ARCHITECTURE.md, docs/DECISIONS.md and docs/WORKFLOWS.md: design choices and data flow.
4. docs/INFERENCE_AUTH.md and docs/MEMORY_AND_EVALUATION.md when relevant. For Personal Brain persistence, also read docs/PERSONAL_BRAIN_STORAGE.md and check actual source-revocation/confirmation implementation before claiming facts are verified.
5. ROLE_PACKS and EVALS for the exact active slice. See docs/SLICES.md for roadmap and docs/REFERENCES.md for research sources.

## Relay in 90 seconds
Relay is a native macOS, local-first personal AI interview copilot. Its intended use is authorized job interviews and realistic mock sessions. It recognizes questions and follow-ups, retrieves the right role-specific information and verified personal experience, and provides short, accurate talking points with optional code/SQL detail. The objective is real interview performance and job outcomes, NOT a generic learning or studying platform.

First role specializations: Epic Software Developer, and junior AI/BI/data analytics/data visualization. Target hardware: a 16 GB M2 Pro MacBook Pro. Be particularly accurate about SQL joins, grouping, metric definitions, Python/coding corner cases, individual project contributions, and surprise follow-ups.

Two foundational memories:
- Personal Brain: confirmed biographical facts, actual individual responsibilities, project stories, resume, user-approved external files.
- Learning Memory: question patterns, assistant response errors, user corrections, role relevance, presentation preferences. An AI-generated suggestion is not proof of user skill.

Continuous learning optimizes the copilot itself. The quality gate checks correctness, relevance, personal support and concision, using cheap deterministic checks and selective model review rather than a mandatory slow second pass.

## Invariants
- Read [the local resource budget](docs/LOCAL_RESOURCE_BUDGET.md) before builds, downloads, environment creation or artifact copies. Parallel code/research ownership does not authorize parallel heavy jobs. Reuse bounded caches; never create a new large review cache by default. The 2026-10-24 disk incident stopped all workers; do not restart their interrupted builds automatically.
- Each agent owns one small slice, issue, isolated checkout, branch and reviewable PR. Parallel slices are allowed under the controller's explicit write ownership and shared contracts in docs/PARALLEL_PLAN.md. Do not edit another lane's files or shared HANDOFF/ADRs concurrently.
- For the current parallel effort, use GPT-6.1 Sol with extra-high reasoning or higher for every worker. Report model unavailability instead of silently downgrading.
- Automatic question routing and both reviewed technical answers and open-ended model answers are owner-approved targets. Detailed new publication/transport designs remain proposals until agreed; do not mistake a target for delivered behavior.
- Update HANDOFF.md, relevant ADRs, and tests in each slice. Do not silently rewrite settled scope.
- The owner authorized frequent commits and pushes of agreed work at meaningful verified checkpoints. Keep GitHub and HANDOFF current; do not ask again for routine scoped publication. Clearly label any saved partial state and skipped checks. Merge approval, destructive operations and material scope expansion remain separate.
- Distinguish implemented/measured from proposed or documented. Never claim account entitlement or latency without a live verification.
- Verify project participation; never invent credentials, metrics, Power BI/Tableau experience, or personally written code attributed to another contributor.
- Keep private user material out of Git, logs and CI, even after repo becomes private: no OAuth tokens, secrets, resumes, recordings, transcripts, Drive files or raw imports. This repository is currently PUBLIC by owner choice.
- Plan inference using officially documented ChatGPT subscription OAuth if account is eligible, with no automatic separately billed API fallback. Do not scrape browser cookies or undocumented backend endpoints.
- Meeting capture and assistance only with appropriate permission and consent. Do not implement stealth screen sharing or prohibited undisclosed assessment assistance.
- Store original question/correction events distinctly from derived profiles. New personal facts require user confirmation.
- Prefer offline Linux tests. Do not run private-user OAuth or paid inference in CI. Avoid large macOS Actions usage unless justified.
- Before new architecture or feature implementation, inspect relevant upstream source and tests. Record exact URL/ref, license, platform/dependency/model requirements, actual copied or invoked components, modifications, rejected alternatives and local validation. Prefer suitable reuse; distinguish adopted code from conceptual references.
- Live UX: concise answer first, up to two supporting points, optional expansion; no noisy dashboards or unnecessary tutoring.

## Completion checklist
1. State exact current repository state and issue being addressed.
2. Make the smallest change that meets acceptance conditions, with negative tests.
3. Verify locally or via relevant CI; report exact observable results, not promises.
4. Update design decisions if a choice is made or falsified.
5. Update HANDOFF.md with completed tests, current blockers and one exact next action.
6. Review the precise PR head before merging; do not merge failed or unknown critical checks.

## If context is lost
Read HANDOFF.md and docs/PARALLEL_PLAN.md, inspect live GitHub PR/issues and source, then read the associated contract files. Continue an explicitly assigned disjoint slice. Verify published versus local-only state, exact heads, actual checks/reviews and the next action before coding. Conversation summaries and unresolved old review comments are not authoritative implementation evidence.

## Code Review Rules
### OAuth and billing boundary
- Flag authentication that permits inference without the granted plan scope, verified ID token, matching callback state/Host, or Bearer credential validation.
- Flag browser-cookie reuse, undocumented ChatGPT backends, silent conventional API-key fallback, secrets in logs, and accidental paid model/CI requests. Supported pattern: user-authorized plan OAuth only.
### Knowledge and response integrity
- Flag fabrication of personal credentials, projects, implementer attribution, test results, or treating model-generated answers as evidence of user skill. Safe behavior: verify source and explicitly abstain on missing personal context.
- Flag unchecked promotion of interview transcripts into confirmed personal history, ignoring user corrections, or failure to invalidate stale question answers.
### Stream and data boundaries
- Flag treating partial/failed SSE streams as successful without response.completed, leaking private files/tokens, or capturing meeting content without required consent. Keep review high-signal; leave formatting to CI.
- Flag failing to invalidate an in-flight answer when a question is interrupted, corrected, or superseded; use turn-version checks so stale outputs cannot appear after a new question.
