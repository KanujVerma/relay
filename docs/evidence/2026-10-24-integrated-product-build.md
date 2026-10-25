# Integrated stock app, 2026-10-24

The current self-contained artifact was built from clean source
`fd7b283d34edfef2ecabab9cdbfbc74f71e121a1` using the unchanged stock product
builder, its offline option, the retained locked environment and the two
existing Swift build roots. No dependency environment, model or archive was
downloaded. This supersedes the older b270 artifact as the current feature
build; the older artifact and its relocation witness were preserved.

| Gate | Observed result |
| --- | --- |
| Stock release build | Exit 0, 241.306 seconds; 182,730,688 bytes; clean source provenance embedded in the helper |
| Native dependency audit | 100 native files; supported architecture/minimum system, resolved bundled dependencies and no external build-machine paths |
| Signing | Strict nested and outer ad-hoc signature verification passed |
| Stock helper smoke tests | Three cases before assembly and the same three against the assembled app, all passed |
| Whole-app relocation | One additional complete copy into a folder containing spaces; native/helper/provenance hashes unchanged; all 100 native audits and strict signatures passed |
| Relocated helper smoke | Three cases passed, zero skips/failures, 4.472 seconds |
| Relocated actual-Model application tests | 11 cases passed, zero skips/failures, 8.355 seconds of cases; complete command 106.781 seconds |

The 11 native cases comprise four product-runtime cases, four résumé cases,
one saved-context case and two generated-notes cases. Nine positive bundled
cases use the actual relocated helper with normal bundled resolution and
working directory `/`, without a repository or Python-path fallback. Two
runtime guards separately verify broken-bundle rejection and the existing
explicit developer-fixture override with its source helper. Résumé tests cover entered
text and actual TXT/PDF/DOCX import, reviewed individual contribution with its
qualifiers, fresh-helper restoration and Lock withholding. Runtime tests cover
idle typed Ask, Help, coding and prospective feature-design questions, End and
the broken-bundle rejection guard.

The two Notes cases verify actual saved source, generation, literal citations,
same-run protected saving, edit/export/regenerate, helper reaping, reopening and
generated-note deletion while retaining the transcript. The AI-off control
keeps local edits and reviewed-reference assistance available. Account, context,
response and Learning preferences in its nonfixture test constructors are
explicitly isolated with existing in-memory controls. Their test-only
12-insertion/3-deletion successor preserves the original assertions and all
normal helper arguments. It changes no packaged runtime source.

All personal facts, transcripts, keys and transport responses used by these
gates are fictional fixtures. The tests do not read production account/profile
storage, make real model requests, capture hardware audio or inspect the user's
screen. They instantiate the real Model and packaged helper; they do not prove
that the new native executable's on-screen workflow has been inspected.

The build watchdog sampled disk usage every five seconds and would stop its
owned process group below 30 GiB free or above 25 GiB Relay temporary allocation.
Build completion was 24.462 GiB temporary allocation / 33.020 GiB free. The
one relocation added 0.173 GiB, reaching 24.635 / 32.853 GiB. The native gate
used a 0.30 GiB reserve and ended at 24.651 / 32.818 GiB. Native gate figures
are before/after observations, not continuous peak instrumentation. No cleanup
or existing-user-data permissions were changed by this checkpoint.

## Remaining acceptance

The active goal remains incomplete. The dedicated résumé-learning acceptance
still times out at its baseline idle-question preparation, before adaptation;
its cause is under diagnosis. The original 14-case Learning application gate
and the separate four-process restart/source-control acceptance are green.
Actual on-screen final-build inspection, normal account/device setup,
representative technical/personal/case/follow-up quality, and speech-end to
readable useful-answer latency remain open. No full-Cluely-parity, achieved
latency, release, installer or notarization claim follows from this artifact.
Main remains unmerged. Continue from [HANDOFF](../../HANDOFF.md) and the
[active plan](../superpowers/plans/2026-10-24-finish-live-copilot.md).
