# Proposed flows and edge-case contracts

Status: most flows remain design only. Slice 01B-B0 added the offline QA gate; **Slice 01B-B1 (merged PR #16)** integrates that gate into a **synthetic SSE adapter**. Merged PR #25 connects B1 to the OAuth CLI for two synthetic technical smoke questions only. No native UI, audio-to-answer integration or personal-answer grounding is implemented.

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
- Inputs carry question/fixture identity, role/category, completed response status, answer text, **active and candidate turn IDs as well as versions**, verified-source IDs, a mandatory-for-PASS trusted personal-attribution classification (unknown fails closed), optional conservative multipart indicators and risk flags. All supplied strings are untrusted data, not instructions.
- Decision is `pass`, `needs_revision`, or `abstain`. **Pass means a deterministic presentation/safety gate succeeded, never that a model answer is factually correct.** Heuristic keyword matches likewise do not prove semantic coverage.
- Missing/incomplete content, stale turn **ID or version**, unknown attribution classification and absent verified personal context fail closed. Even when personal source IDs exist, they are only pointers and must not certify the claim until a later source-grounding check.
- Code-first outputs can be warned as harder to scan; overly long/tabled answers need revision. Categories such as coding, multipart, behavioral and caller-marked high-risk SQL may recommend selective deeper QA, **not execute another inference request**.
- **B1 implementation:** re-check that the active turn ID, version and monotonic activation generation are unchanged at the synchronous presentation boundary. A QA PASS earlier in a stream is insufficient to display stale material. Track first output, a weak first-scannable provisional sentence candidate, stream completion, QA completion and presentation independently; true first **useful** validated text still requires independent/human assessment.

## Synthetic SSE-to-QA adapter, Slice 01B-B1

Implemented in [streaming_qa.py](../relay_spike/streaming_qa.py), with offline-only tests in [test_streaming_qa.py](../tests/test_streaming_qa.py):
1. Activate a named question turn (ID, version, generation) in a small thread-safe coordinator. Replacement or cancellation invalidates the older turn, including reuse of an identical ID/version.
2. Feed mock or caller-supplied SSE lines through the **existing** `consume_stream` terminal semantics. A stream is complete only on `response.completed`; failed, incomplete, malformed, conflicting duplicate or overly large streams fail closed. Exact adjacent SSE sequence-number replays are ignored with a bounded fingerprint; older/out-of-order or conflicting sequence events fail closed. Malformed completion payloads (including a missing explicit completed status) are rejected, and deltas after terminal completion are not presented.
3. Assemble completed text in memory, silently time the first emitted text and first **heuristic scannable lead sentence**, and apply deterministic B0 QA using synthetic fixture metadata. No early text is displayed. A scannable candidate is **not** proven correct or usable in an actual interview.
4. Each synthetic test must explicitly supply a **trusted** personal-attribution classification to permit PASS; the default `uncertain` prevents a clean final answer. Personal/behavioral cases with no approved evidence abstain, and source-ID strings alone cannot certify a personal claim.
5. At publication, take an atomic freshness check against active ID, version and generation. Return only `final_unverified`, `needs_revision`, `unavailable` or `suppressed`. Non-PASS output is never exposed raw; a superseded response calls no presentation callback. Callback must synchronously commit the local view; delayed UI queues must themselves re-check the token.
6. The provisional development `ModelPolicy` selects Luna by default and permits Sol explicitly; QA can recommend Sol for human-triggered review but **never invokes** a second model. No automatic API usage occurs.
7. No production first-useful-answer metric or general correctness claim exists yet. `first_scannable_candidate_ms` is a weak display-format proxy; `first_useful_verified_ms` remains null. The native UI, validated attribution classifier and real-audio end-to-end timing are separate later slices.

## Offline transcript/question turn coordinator, Slice 03B-A
- [question_turns.py](../relay_spike/question_turns.py) reuses the **same** ActiveTurns instance as SSE/QA. Only complete remote-source events labeled tentative question/correction/follow-up may become routable TurnTokens; mic/unknown, statement/unknown intent and partial transcripts never trigger inference. A channel label is **not speaker diarization**.
- Corrections, partial interruptions and follow-ups invalidate the old turn; corrected text remains verbatim authoritative with earlier words explicitly labeled superseded/context-only. Source text is never blindly used as an application directive.
- Duplicate segment/revision fingerprints, late finalizations of old partials, revisions of superseded segments, old stream generations, overlapping remote question timestamps, unclassified remote speech, retractions and discontinuities are bounded/fail-closed. Unknown semantics and remote speaker identity are not silently inferred. An explicit stop blocks all generations until the native host explicitly resumes; a Python resume call is not proof of OS recording permission.
- Verbatim multi-part splitting is only a heuristic suggestion. E11/D12 and E04/D07 synthetic tests check cancellation, corrected SQL metrics/year and source-span parts. This does **not** constitute a natural-language question classifier, a real FluidAudio adapter or an actual end-to-end interview session. See [docs/QUESTION_TURNS.md](QUESTION_TURNS.md).

## Local EOU ASR to question intent bridge, offline 03B-B0
- [asr_turn_adapter.py](https://github.com/KanujVerma/relay/blob/4c955fb431de7dd497bca443e12fae440f0d679c/relay_spike/asr_turn_adapter.py) is a synthetic-only typed terminal ASR adapter that **reuses** [QuestionTurnMachine](../relay_spike/question_turns.py) from merged 03B-A. It does not import FluidAudio, capture PCM, talk to ChatGPT, or persist interviews. PR #46 builds on merged PR #42 and remains offline synthetic-only.
- The native host later supplies permission state, selected remote source, ASR generation/segment/revision and trusted monotonic time mapping. A Python `CaptureContext(authorized)` is **not** proof of genuine macOS TCC permission. Missing scope or source selection stops the old active turn until explicit host resume. Microphone/unknown source cannot assert interviewer speech.
- FluidAudio StreamingEouAsrManager does not provide text partials from process(audioBuffer:). Processing remains pending without text. EOU-final text may get only a **tentative syntactic intent**; empty/silence/failure/discontinuity cannot authorize an interview answer. Missing or low ASR confidence and semantically ambiguous remote speech require review and invalidate stale prior answers when appropriate.
- Keep speech-end, EOU finalization and adapter receive timestamps separate; those metrics never establish useful/correct model answer latency. Later real ASR/intent benchmarks require actual consented Mac hardware evidence, independent held-out labels and permission-aware source provenance. See [docs/ASR_TURN_ADAPTER.md](ASR_TURN_ADAPTER.md).

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

## OAuth-backed synthetic QA bridge, Slice 01B-B2 (merged PR #25, Mac proof pending)
- The `live-qa` CLI is **dry-run by default**. `--execute` requests exactly one account-catalog-checked Luna or Sol 6.1 inference on one of two explicitly pre-reviewed D02/E09 **technical** EVALS smoke questions using an existing validated ChatGPT-plan OAuth token. Personal, behavioral and interruption fixtures are rejected before inference. No automatic Sol retry or additional billable key path.
- The shared Responses SSE transport supplies raw byte lines to the B1 adapter. A final output is shown **only** after `response.completed`, completion of the deterministic B0 QA gate, and active-turn publication recheck. The state `final_unverified` explicitly does **not** certify technical correctness, user facts, or practical interview usefulness.
- A narrow independently reviewed synthetic-only **whole-answer allowlist** can mark absent attribution for complete matches to D02/E09 technical smoke text. All other generated text, including acceptable technical paraphrases and unrecognized third-person professional claims, remains uncertain or suspected personal and is withheld. The work-history regex only raises suspicion and never authorizes display. This is **not** a general trusted classifier or production biography verifier.
- The clock starts before HTTPS setup. Separate metrics track first text, a purely heuristic scannable lead, response completion, QA and presentation. `first_useful_verified_ms` stays null; no native UI/audio latency measurements exist.
- Runbook [RUN_LOCAL_LIVE_QA.md](RUN_LOCAL_LIVE_QA.md). Offline CI uses mocked HTTP and no live account, model or source documents. Owner-run validation on the target Mac remains an independent gate.
