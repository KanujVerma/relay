# Scoped controls cancellation re-review

2026-10-23. PR #70. Baseline `006b7bdc75ac6376e9711c3733a8094fa25f9b02`; corrected head `2fc2db5c767d8ef892d030487bd7a281f418e366`.

## Verdict

The prior P2 canceled-parent selected-text finding is addressed. No actionable finding or nearby regression in this scoped delta. The corrected head is acceptable for this finding; the original review's separate integration and interactive acceptance limits remain unchanged.

## Reviewed change

Read the complete three-file delta, 54 insertions and 2 deletions, the cancellation correction report, both new regressions, and the immediately surrounding read/invalidation/snapshot lifecycle. No new broad audit was performed.

- `SelectedTextService.swift:143` checks caller cancellation before permission/provider work or replacing `observationID`. A pre-canceled invocation cannot start a provider read or retire a current snapshot.
- `SelectedTextService.swift:166` checks cancellation immediately after the provider await and before snapshot admission. A provider that returns successfully despite cancellation no longer causes a canceled caller to receive a snapshot; the existing wrapper maps cancellation to `SelectionError.stale`.
- `SelectedTextService.swift:156-159` retires observation authority only when the caller is canceled and the stored observation still matches that read's UUID. Cleanup still releases the single-flight state and task reference. A pre-canceled call exits before installing this cleanup; a canceled older read cannot clear a different observation UUID.
- The two new tests directly exercise a canceled parent with a successful late provider and otherwise unchanged authority, plus a pre-canceled caller preserving an existing snapshot with no extra provider call. The late-provider regression also checks that a subsequent fresh read remains usable. Neither test relies on `invalidate()` to hide the original defect.

Public APIs, request/session/epoch/presentation identity, consent/focus/trust checks, age/size bounds and snapshot provenance remain unchanged by this patch.

## Independent verification

Recompiled the original focused synthetic reproduction against the unchanged production selection source files at the corrected head, using Apple Swift 6.4. The same injected provider deliberately returned successfully after its caller was canceled. Observed output:

```text
read_rejected=stale
```

The baseline reproduction had returned a still-valid snapshot. The corrected executable is `/private/tmp/relay-controls-cancellation-2fc2db5`; the unchanged reproduction source is `/private/tmp/relay-controls-cancellation-006b7bd.swift`. Compilation required the same authorized macro-compiler sandbox escalation as the original review. Execution used only injected synthetic request, app, clock and text values.

Verified the frozen patch artifact and live Git delta independently have identical SHA-256 `a3041e22f101e8e82a54c443e261c9ecaaaf41f119f02a00ef8a662763a88232`. `git diff --check` passed. The lane checkout remained clean at `2fc2db5c767d8ef892d030487bd7a281f418e366`.

The builder reports both regressions failed on the old implementation, passed with this correction, and the full package passed 18 tests in 3 suites. I inspected that evidence and the exact tests; I did not rerun the full suite. No source, index, HEAD or branch mutation, subagent, actual AX prompt/read, real global key registration, private content, pasteboard, capture, Keychain, model or account operation occurred.
