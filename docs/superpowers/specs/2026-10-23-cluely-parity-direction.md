# Cluely-style Relay product direction

Owner-approved target, 2026-10-23: reproduce the normal individual Cluely desktop workflow and visual hierarchy, add user résumé ingestion and persistent personal memory, and make speech setup automatic. Frequent reviewed commits/pushes and GPT-6.1 Sol extra-high workers remain authorized. Existing passed engine tests establish runtime contracts, not satisfaction with the product UI.

## Required experience

- First run guides through account, audio/screen permissions and automatic speech preparation. No speech-model/detector folder chooser or model-license checkbox in the normal home/session flow. Preserve actual permission/license requirements in managed setup and appropriate Settings information.
- Compact, polished session controls and answer/chat surface; a separate dashboard for Activity, Context and Settings. Start, audio/pause, stop, show/hide, transcript and current context should behave coherently. Use functional Cluely research to specify concrete states, layout and controls.
- Continuous automatic questions/follow-ups remain required even where observed competitor controls require an explicit action. Preserve coding-with-an-engineer and feature-case-study guidance.
- Screen/audio context is request-bound; configured images and account support must be real, not a UI switch that fabricates capability. Source selection and permission revocation remain meaningful; do not substitute unrelated content.
- Résumé, project and job context live under My Context. Imported statements retain source provenance and clear review/ownership, saved context survives sessions, and corrections/revocation invalidate dependent suggestions. Personal memory is separate from session transcripts and generated output.
- Typed questions, quick actions, modes/custom instructions, transcript/history, session notes and usable account setup are included in the functional parity inventory. Implemented ports must drive visible controls; unimplemented controls cannot pretend to work. The inventory sequences independently reviewable end-to-end slices.
- Advanced technical diagnostics and overrides belong in Settings. Default behavior on the target16GBM2Pro must be explicit and tested rather than asking the user to choose implementation components.

## Evidence and reuse

Use the supplied [REA repository](https://github.com/morluto/rea), its skill and methodology to investigate the installed Cluely client and its full relevant module inventory. Existing work/rea-research holds extraction, REA6.7.0 and retained evidence; preserve older records and expand coverage in a new research area. Record target/tool hashes, selected coverage, limitations, measured UI configuration and actual code paths. Distinguish shipped-client facts, versioned/current official product documentation, inference and unavailable backend behavior. Do not claim inaccessible server internals were recovered.

Cluely raw source, prompts and assets remain local research material. Relay implementation reuses suitable licensed open-source components/native APIs, preserving notices. Research source/tests/license/ref before adopting new architecture. Keep the accepted native request/lease/order and helper/profile shutdown contracts.

## Parallel research and implementation boundaries

1. REA/product lane: comprehensive functional/UI parity matrix, source evidence and priorities; local research report only until controller publishes sanitized findings. Initial exact2.1.24 window facts already identify separate control/chat/settings/onboarding windows.
2. Native UX lane: source-based current UI inventory, concrete view hierarchy/layout and isolated native implementation. Own views/window shell; avoid changing the audio readiness engine or authority wire.
3. Automatic speech lane: compatible pinned default ASR/VAD assets, integrity/cache/progress/cancellation and readiness contract. Own provisioning/native model startup seams; avoid UI layout changes.
4. Controller: freeze exact shared seams after source/design research, map résumé/memory/account/chat/history gaps, sequence remaining feature lanes, review and join verified work, keep HANDOFF/GitHub current.

Every implementation slice gets a concrete plan with file ownership, interfaces and acceptance before edits. User has approved the product direction and requested implementation; resolve routine choices autonomously. A material unknown requiring new authority or irreversible behavior must be made concrete before requesting user input.

## Verification boundary

Current frozen baseline is1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7. Fully tested product runtime7685572 passed176 native tests,558 Python tests with21 optional skips and app compilation on Swift6.2.3. Later setup-only951 passed seven focused app tests with identical runtime. New parity work must establish its own evidence. The Mac is locked, blocking visible runtime inspection; synthetic state/transport tests, source-based UI review and compilation continue. Real account, capture, speech quality/latency/resources and distribution acceptance remain separate measurements.
