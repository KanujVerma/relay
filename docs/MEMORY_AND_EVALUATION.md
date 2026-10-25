# Personal Brain, learning memory, and evaluation design

Current status,2026-10-24: the integrated source now implements separately enabled, source-linked Learning Memory. Actual-app fictional sessions verify available suggestion → original microphone reply → remote continuation, protected retention, later scoped presentation changes, inspection/Undo and source invalidation. A separate four-process gate verifies restart and durable controls. The confirmed-personal acceptance preserves reviewed fact units and provenance with zero model calls; its identical-draft preparation correction independently passes the joined application gate. [Current source evidence](evidence/2026-10-24-learning-integration.md) and [requirement map](handoffs/2026-10-24-learning-memory.md) distinguish this from unproved real-model, personal-voice, usefulness and interview-outcome improvement. The final artifact needs the latest guard; actual account/device acceptance remains open.

Historical foundation: the Personal Brain Slice02A-A local SQLite prototype landed in merged [PR18](https://github.com/KanujVerma/relay/pull/18); [PR26](https://github.com/KanujVerma/relay/pull/26) added synthetic v2 candidate evidence for [issue21](https://github.com/KanujVerma/relay/issues/21). The prototype/table discussion below explains that original trust boundary. It does not describe the full later encrypted native import/approval implementation as missing. Future draft entities below are not committed production schemas.

## Personal knowledge layers
- Confirmed structured facts: education, actual roles, technologies used, individual contributions and project outcomes. Source, timestamp, verification and uncertainty are mandatory.
- Experience stories: situation, constraints, user actions versus others' actions, important technical decisions, results and trade-offs.
- Underlying evidence: resume version, selected document/Drive item, chosen GitHub repository/PR, user's direct response or consented recording.
- Unverified candidate facts: suggestions discovered by parsing or model inference, never trusted until confirmed.
- Role context: company, job description, round, known stack and question families; uncertain sources marked accordingly.

## Learning Memory is separate
Question themes, clarifications, user-corrected assistant errors, answer verbosity preferences, style preferences, success/failure of model responses, and observed topic frequency. These do not automatically change personal biography, nor prove proficiency from generated answers.

## Tracked cross-meeting improvement milestone

The owner reaffirmed this requirement on2026-10-24. Completing saved History or AI session notes does not complete Learning Memory. After accepted source/retention ownership is available, the controller must give the learning loop its own reviewed end-to-end slice:

The owner clarified that learning must also observe the natural interaction: the suggestion actually made available, what the user subsequently said through the microphone, and how the other side continued. Explicit ratings alone are insufficient. The proposed chain is **question → available suggestion → original spoken response → remote continuation → updated context/style candidate**. Availability is not proof of reading; phrase similarity is tentative uptake, and a follow-up is not proof of success/failure. Preserve original source timing/identities and ambiguity instead of guessing causal attribution.

Immediate meeting continuity and later-session learning are separate. The12utterance/6000byte recent-dialogue window remains; the new bounded Learning session separately retains up to64original finals/32KiB,16semantic quotes/4KiB and8episodes/32KiB. It keeps relevant explanations, constraints and unresolved follow-ups beyond the raw ring, with source retirement and unrelated-request exclusion. This is not unbounded whole-interview memory. Across saved sessions, deterministic scoped rules use clean possible-uptake examples and retain source-backed why/Undo; explicit current requests and guides take precedence. New career facts still require Personal Brain confirmation. [Pinned source/test/license research](research/LEARNING_MEMORY_DESIGN_INPUT.md) records reuse; no LangMem/Graphiti framework, embedding model or second database is adopted.

- Observe recurring question concepts within the user's permitted saved sessions and role context, retaining actual supporting source identities. Frequency describes those sessions, not all interviews at a company.
- Capture explicit helpful/unhelpful feedback, assistant-error corrections and preferences such as shorter answers or a clearer coding approach. An interviewer statement, silence or an AI-generated debrief is not proof of a successful answer.
- Apply bounded, versioned, inspectable and reversible retrieval/presentation adjustments to future requests. Explicit preferences take precedence over inferred candidates. Model-generated suggestions never become verified technical corrections merely because they were generated.
- Propagate source/session deletion, retention expiry and disabling learning to dependent derived data; preserve an explicit user-owned correction only under its own clear retention choice. Do not create invisible permanent memory from an opted-out or deleted session.
- Show what was learned and allow correction/removal/reset. New biographical claims still require the separate Personal Brain confirmation path.
- Demonstrate a real later-session advice change and held-out correctness/privacy regressions against the unchanged baseline before calling the loop delivered. Initial adaptation reuses memory/retrieval/preferences; model-weight training is not required or currently implemented.

Current evidence: cross-meeting event capture, protected derived-learning persistence, later-request application and reversible controls pass actual-app fictional acceptance. Personal presentation preserves complete approved self/team units and their qualifiers instead of freely paraphrasing biography. Real-model correctness, voice/style usefulness, held-out improvement and interview outcomes remain unchecked. The broader learning requirements above remain requirements; source tests do not prove those real-world outcomes. [BUILD_STATUS](BUILD_STATUS.md) and [HANDOFF](../HANDOFF.md) own current source, artifact and remaining gates.

## Implemented subset and future draft entities

For the original SQLite subset and trust boundary, use [PERSONAL_BRAIN_STORAGE.md](PERSONAL_BRAIN_STORAGE.md). The implemented tables are source, experience (source-linked grouping only), candidate_fact, verified_fact and append-only history_event; PR #26 adds candidate_evidence in schema v2 for exact source spans, hashes and review revision. A claim does not become verified without a separate explicit user confirmation reference from a future trusted UI. Teammate/team facts cannot be represented as the user's personal implementation. A source revocation invalidates dependent verified records and redacts **all** dependent candidate text/keys, including cross-source facts linked through its experience grouping. The complete story schema below is still a design sketch.
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
