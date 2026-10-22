# Relay architecture overview

Status: proposed, no working macOS application as of 2026-10-22. This file is the index; exact rationale is in docs/DECISIONS.md, flows in docs/WORKFLOWS.md, knowledge schema in docs/MEMORY_AND_EVALUATION.md, OAuth contract in docs/INFERENCE_AUTH.md and execution gates in docs/SLICES.md.

## Target components
1. SwiftUI native macOS app with compact user-controlled panel and clear authorization state.
2. Native separate microphone/system audio capture only where permitted. Investigate SystemAudioKit and native Core Audio taps.
3. Local FluidAudio candidate for ASR, voice activity detection and optional diarization on Apple Silicon. Benchmark 16 GB M2 Pro under realistic Zoom conditions.
4. Conversation/turn state machine with speaker-source attribution, multipart questions, interruptions, corrected turns and stale-response cancellation.
5. Role router selecting exact posting/round plus Epic software developer or junior analytics Role Packs.
6. Personal Brain with source-linked and verified facts, user-confirmed experiences and selected external document imports; SQLite/FTS5 first and semantic retrieval only if justified.
7. Official ChatGPT subscription OAuth inference adapter with account-scope checks and streamed Responses, if user eligible. Separate OAuth from future Drive/GitHub connectors; never assume linked ChatGPT Memory access.
8. Fast answer QA pipeline: deterministic checks, source fidelity, multi-part coverage, selective deeper review, optional code/SQL example.
9. Learning Memory as append-only events with reversible derived preferences, question patterns, assistant corrections and regression evaluation.

## Proposed flow
Authorized local audio -> local transcript segments -> question/turn state -> Role Pack + verified Personal Brain retrieval -> streamed model output if authorized -> fast QA -> scannable talking points -> feedback and reversible learning.

## Trust boundaries
- Each data connector and recording/capture mechanism has explicit separate authorization.
- Raw audio/local transcripts are local by default; transmit only minimal approved text needed for inference.
- Imported data may contain prompt injection; treat as evidence, not system instructions.
- Keychain for shipping credential storage and explicit revocation/deletion controls. Nothing secret in Git or CI, including after private visibility.
- No screen-share invisibility assurance; no unauthorized live interview answer assistance.

## Performance and development
First useful answer target approximately 2 to 4 seconds after a completed question, not a measured result. Keep RAM/CPU lean for M2 Pro 16 GB. Validate with p50/p95 timing, factual accuracy, missing-context cases, and source fidelity. Prefer minimal offline Linux CI to preserve future private-repo Actions allowance.

See HANDOFF.md for actual current implementation state. Design does not imply delivered functionality.
