# Relay architecture (provisional)

Status: proposal. Technical feasibility gates precede committing to a dependency.

## Proposed components
1. **macOS application:** Swift + SwiftUI, single main process initially; compact, accessible panel with user-controlled visibility.
2. **Audio acquisition (later slice):** Native microphone and permitted per-process system audio using Apple capture APIs. Study SystemAudioKit; verify microphone/remote-channel separation and echo behavior on actual Zoom versions.
3. **Transcription (later slice):** Local Apple Silicon speech recognizer (investigate FluidAudio), voice activity detection, interruption-aware utterance segmentation. Benchmark RAM/CPU on a 16 GB M2 Pro before selecting final models.
4. **Question and conversation state:** Streaming transcript events; speaker labels; question completion; multi-part extraction; stale-response cancellation; follow-up context.
5. **Personal Brain:** SQLite local data store and FTS5 keyword retrieval first. Add on-device semantic embeddings if tests show a benefit; maintain records with source ID, original timestamp, verification status, sensitivity, last-updated date, and user consent.
6. **Connectors:** Explicit resume/file import and user-selected Google Drive/GitHub access; separate OAuth grants from any ChatGPT inference authorization. A subscription-backed model session does not inherit ChatGPT history, memory, or ChatGPT's existing connected apps.
7. **Inference adapter:** Authenticate through an officially documented ChatGPT-supported mechanism if available to this account, then stream structured answer output. Validate preview eligibility, limits and feature set. If unavailable, document the limitation rather than scrape app sessions or silently incur an API bill.
8. **Answer quality pipeline:** Stage 1 deterministic relevance, sources, missing constraints and content length; stage 2 optional small scoped review for high-risk or complex answers; stream a concise validated part without waiting on expensive optional details.
9. **Continuous learning:** Append-only question/answer/correction/session events, user-approved memory promotion, versioned assessment and retrieval rules, reversible preference changes, and regression evaluation.

## Trust and data-flow boundaries
- Default: raw meeting audio and transcripts stay local; only selected text needed for generation is transmitted with user permission.
- Every imported source carries origin and revocation metadata. Delete indexed derivatives when sources are removed unless the user explicitly preserves a verified fact.
- Avoid uploading resumes, transcripts, secrets, access tokens or personal interview records to this GitHub repository, including in fixtures or build logs.
- Recordings/transcriptions only when legally authorized and consistent with meeting rules. Do not treat an invisible window as a reliable capture-privacy mechanism.
- Authenticate provider tokens via macOS Keychain. Encrypt private local content appropriately; final design subject to security review.

## Slice sequence and gates
- **00 (this PR):** Contract, architecture, role packs, representative question fixtures, fixture validation, continuity handoff.
- **01:** Text-only inference feasibility and answer engine (streaming, quality checks, latency instrumented). Gate: subscription-backed authorization confirmed or honestly documented unavailable.
- **02:** Personal Brain ingestion, fact verification and provenance retrieval.
- **03:** Authorized audio transcription, speaker/question extraction and interruptions.
- **04:** Native UI and end-to-end permitted meeting session.
- **05:** Continuous learning feedback and verified memory promotion; event hooks and data boundaries designed from day one.
- **06:** Hardening for edge cases, UX, security and performance.
- **07:** Optional mock interviewer / answer stress testing.

## CI budget policy
- Prefer a minimal Ubuntu job only for fixture and cross-platform checks.
- Do not run macOS cloud jobs by default until native functionality exists and manual/local testing cannot replace them.
- Do not introduce paid runners, large matrix jobs, schedules, uploads or long artifact retention without cost review.
- Actions allowances are account-shared; check usage and budgets before high-volume CI.

## Open questions to verify experimentally
- Whether official ChatGPT plan-backed inference is currently authorized for this account/app.
- Which models and streaming/function capabilities are allowed under that authorization.
- Actual first useful token latency including transcription and question detection.
- Local ASR accuracy/resource footprint and system-audio behavior under headphones/overlap.
- Reliable background/context retrieval within the 16 GB memory budget.
