# Personal Brain, learning memory, and evaluation design

Status: the **Personal Brain Slice 02A-A local SQLite prototype** is implemented on a feature branch in [PR #18](https://github.com/KanujVerma/relay/pull/18), with synthetic-only consent/approval, candidate/verified claims, source revocation and audit events. This is **not** user data ingestion or a production encrypted Mac database. Learning Memory and other entities below remain proposals. Reviewed 2026-10-22.

## Personal knowledge layers
- Confirmed structured facts: education, actual roles, technologies used, individual contributions and project outcomes. Source, timestamp, verification and uncertainty are mandatory.
- Experience stories: situation, constraints, user actions versus others' actions, important technical decisions, results and trade-offs.
- Underlying evidence: resume version, selected document/Drive item, chosen GitHub repository/PR, user's direct response or consented recording.
- Unverified candidate facts: suggestions discovered by parsing or model inference, never trusted until confirmed.
- Role context: company, job description, round, known stack and question families; uncertain sources marked accordingly.

## Learning Memory is separate
Question themes, clarifications, user-corrected assistant errors, answer verbosity preferences, style preferences, success/failure of model responses, and observed topic frequency. These do not automatically change personal biography, nor prove proficiency from generated answers.

## Implemented subset and future draft entities

For the actual SQLite v1 subset and trust boundary, use [PERSONAL_BRAIN_STORAGE.md](PERSONAL_BRAIN_STORAGE.md). The current implemented tables are source, experience (source-linked grouping only), candidate_fact, verified_fact and append-only history_event. A claim does not become verified without a separate explicit user confirmation reference from a future trusted UI. Teammate/team facts cannot be represented as the user's personal implementation. A source revocation invalidates dependent verified records and redacts **all** dependent candidate text/keys, including cross-source facts linked through its experience grouping. The complete story schema below is still a design sketch.
- source: id, provider, external ID, selected scope, checksum, observed time, consent, revoked time, sensitivity.
- fact: id, claim, actor/owner of work, source ID, observed time, confidence, confirmed/rejected/superseded, revision.
- experience: id, project, role, situation, personal action, choices, outcome, user verification time.
- role_pack: id, employer, job title, posting source, round, version, updated time.
- session: id, role pack, permissions, timestamps, retention policy.
- transcript_segment: session, audio source, speaker estimate, time range, partial/final text, confidence.
- question: session, source segment references, normalized concept, version, supersedes question ID.
- assistant_response: question ID, model, retrieved source refs, text, stream state, first-useful latency, completion time, error flags.
- feedback_event: response ID, user correction/rating, evidence, evaluation rubric version.
- derived_preference: preference key, value, revision, supporting events, rollback support.
- evaluation_run: fixture version, model/rules version, aggregate scores and latency.

These are NOT committed production schemas or promises of persistent transcript retention.

## Local retrieval
Start with SQLite indexed exact-ID/key retrieval for source-verified facts (implemented in 02A-A). Add FTS5 later only after enforcing retention and deletion semantics, because SQLite's secure_delete alone does not guarantee erasure of future FTS shadow tables. FTS and vector search are **not** implemented yet. For later search, index exact names, projects, SQL jargon and Role Packs. Include bounded recent conversation turns. Preserve provenance and redact unneeded details before inference. Evaluate semantic embedding retrieval on held-out cases before adding extra models/dependencies. Untrusted file content never becomes a tool instruction.

## Learning promotion
1. Append original event with source and type: observation, model output, explicit user correction, tentative inference.
2. Evaluate what it means with uncertainty; avoid inferring interviewer approval/hiring intent.
3. Ask user to confirm any autobiographical fact not already verified.
4. Update derived retrieval/style/role weighting with a reversible version.
5. Run regression evaluation; rollback if correctness or privacy degrades.
6. Provide user access to review, correction, retention and deletion.

## What evidence proves what
- Correct SQL on supplied schema: can be checked against executable tests.
- Technical explanation: compare to reference and rubric, judge uncertainty honestly.
- Personal question: can verify consistency with confirmed records, not whether interviewer liked the answer.
- Speaking rate/fillers: measurable only from consented original audio; not a proxy for interview acceptance.
- Question frequency in a few interviews: describes user-observed sessions only, not market-wide trends.

## Evaluation signals
- Correctness, subquestion coverage, hallucinated personal-claim rate, source attribution.
- SQL join fanout, null handling, time windows, dialect assumptions, missing-schema recognition.
- Coding empty/duplicate/overflow/Unicode/complexity/follow-up cases.
- p50/p95 first useful response and full response; stale-turn cancellation.
- Ability to explain unknown/contradictory personal history without inventing facts.
- Human adjudication agreement for model-based quality labels; learning improves held-out tests.

Current dataset is 26 synthetic question cases under EVALS. It is a structural benchmark, not proof of answer accuracy.
