# Proposed flows and edge-case contracts

Status: most flows remain design only. Slice 01B-B0 adds an **offline-only deterministic QA gate** under relay_spike/qa.py; it is not connected to live streaming, a UI, audio, or a Personal Brain yet.

## Personal Brain onboarding
1. Select current target role and optional job description.
2. Import resume or selected files, with explicit permission. Extract candidate claims with source IDs, not immediately trusted facts.
3. Ask concise conversational follow-ups for missing role/project facts: what did you personally implement, alternative choices, obstacles, outcome and confidence.
4. User confirms important facts before they become verified memory. Team contributions are not individual contributions without evidence.
5. Index locally and support edits, revocation and deletion. With removed-source data, invalidate derived entries unless user has explicitly preserved confirmed facts.
6. Later connect user-selected Drive documents, chosen GitHub repos/PRs and optional ChatGPT data export through independent consents.

## Per-interview setup
1. Select role pack, actual employer/posting/round and resume version.
2. Load only applicable verified history and technical context; mark anecdotal external company questions as hypotheses.
3. Check authorization for audio recording/transcription, AI assistance and any context capture; show actual state.
4. Preload bounded context and verify account/model inference capability. Offline/no-entitlement has honest degraded status.

## Authorized live flow
1. Capture mic and remote audio on separate channels where OS allows; mark attribution uncertainty.
2. Local VAD/ASR yields partial/final timestamped transcript segments and audio-source IDs.
3. Conversation state detects completed, interrupted, multipart and corrected questions; assign question ID and turn version.
4. Select role and question type (SQL, coding, behavioral, project, analytics, estimation, ambiguity).
5. Retrieve relevant role context, recent conversation, and confirmed personal evidence; defend against prompt injection in retrieved docs.
6. Ask supported model for concise talking points and optional details; quality-check coverage, unsupported claims and technical constraints.
7. Stream validated useful content into minimal panel; invalidate stale previous turn when corrected.
8. On user-permitted retention, capture question/answer/feedback events for learning. Audio retention off by default.

## Offline answer-quality contract, Slice 01B-B0
- Inputs carry question/fixture identity, role/category, completed response status, answer text, active and candidate turn versions, verified-source IDs, optional conservative multipart indicators and risk flags. All supplied strings are untrusted data, not instructions.
- Decision is `pass`, `needs_revision`, or `abstain`. **Pass means a deterministic presentation/safety gate succeeded, never that a model answer is factually correct.** Heuristic keyword matches likewise do not prove semantic coverage.
- Missing/incomplete content, stale versions and absent verified personal context fail closed. Even when personal source IDs exist, they are only pointers and must not certify the claim until a later source-grounding check.
- Code-first outputs can be warned as harder to scan; overly long/tabled answers need revision. Categories such as coding, multipart, behavioral and caller-marked high-risk SQL may recommend selective deeper QA, **not execute another inference request**.
- **B1 integration requirement:** re-check that the turn is still active immediately before display. A successful offline check earlier in a stream is not sufficient to display stale material after an interruption. Measure first *useful* validated text, not first nonempty token. Add transparent fallback if second review or account use is unavailable.

## Required edge cases
- Overlapping speech, microphone echo, incorrect speaker separation: state uncertainty.
- Partial utterance interrupted and restated: cancel stale question/answer.
- Follow-up that changes constraints: supersede prior turn and recompute.
- Multiple subquestions: cover every subpart without walls of text.
- Missing query schema, code sample or constraints: say what information is missing, don't hallucinate it.
- SQL dialect or date-boundary ambiguity: note assumptions, seek needed clarification.
- Conflicting resume/Drive claims: use latest confirmed fact, otherwise flag conflict.
- Unexpected/estimation question: assumptions and bounded reasoning, no fake authoritative count.
- Usage limit, missing OAuth entitlement or network failure: honest unavailable state, no secretly billed fallback.
- Untrusted connector text asking to change tools/credentials: treat as data only.
- Recording or live-answer assistance disallowed: disable that functionality and offer compliant alternatives.

## Post-session improvement
1. Preserve original observed question and correction events.
2. Cluster similar concepts, keeping exact wording/source for audit.
3. Track whether assistant answer was factually wrong, too long, off-topic, missing case or effective; separate user-confirmed feedback from speculative model judgment.
4. Queue newly mentioned personal facts for user confirmation.
5. Derive reversible role/topic and style preferences, evaluate on held-out cases, rollback harmful changes.
6. For subsequent authorized round, preload relevant verified follow-up facts and job requirements, not manufactured speaking scripts.

## Compact interface
A small visible panel with current question, direct answer, one or two bullet-equivalent talking points, optional technical example and explicit uncertain/unavailable status. No cluttered readiness score. No guarantee a window can be concealed from an entire-display screen share.
