# Personal shutdown scoped re-review

**Scope:** The seven-file, 163-insertion shutdown delta `eb98e41ebec670452f96313289203ebe1853afa6..7ace412194987ee08c97945cf16ca425f8b120d5`. Reviewed the changed production receipt/port, regression, capability-check helper and lane documentation. No broader personal or answer-host re-audit.

**Verdict: scoped correction accepted.** No critical, important or minor actionable finding was identified in this delta. The blocking run-loop wait shown in root's sample is removed, and the replacement retains ownership until an actual exit receipt. This verdict permits integration of the shutdown correction; it does not establish the separate answer-helper receipt implementation or joined/hosted acceptance.

## Source evidence

- **Prelaunch lifetime:** `ProfileClient.swift:48-68` creates the receipt and installs the termination handler before `run()`. The closure retains the receipt without capturing the child. The actor subsequently owns both process and receipt, so an exit before actor assignment or shutdown waiter registration is retained rather than lost.
- **Latch races:** `ProfileProcessExitReceipt.swift:12-30` records completion and registers waiters under the same lock. Completion-before-registration returns the saved status; registration-before-completion is drained once. Duplicate completion is ignored, and continuations are resumed outside the lock. There is no window that can miss completion or resume one waiter twice.
- **Coalescing and admission:** `ProfileClient.swift:136-156` shares one shutdown task. Actor isolation covers IO closure and installation of that task before the first suspension. Requests reject while the task exists (`114-115`); emergency shutdown marks the port permanently retired before awaiting it (`159-161`). Concurrent shutdown callers wait for the same receipt rather than racing separate reapers or releasing the process early.
- **Cancellation and completion:** The shutdown work is held in an unstructured, nonthrowing task, and receipt waiting has no cancellation-driven early return. Ownership is cleared only after `await task.value`. The 500 ms grace merely triggers KILL escalation; it never substitutes for the exit receipt (`141-156`). Cancellation or an unsuccessful signal therefore cannot be mistaken for successful retirement. No public path cancels the shared shutdown task.
- **Reaping:** Production shutdown no longer calls `waitUntilExit`, `Thread.sleep` or `waitpid`. Foundation supplies termination status through the handler and remains the production reaper. The child and receipt stay retained until that callback has been observed. No fixed shutdown-latency guarantee is added.
- **Unchanged composition:** The public port/client API and acknowledged shared-profile lock path are unchanged. A normal shared adapter can still keep the conversation helper alive; forced retirement continues to require the independently implemented host emergency callback.

## Regression and fresh focused check

The added `ProfileProcessExitTests.swift:30-61` uses 36 actual synthetic child schedules: 16 EOF cases, 16 children already gone before close, and four SIGTERM-ignoring children requiring escalation. A separately scheduled cooperative task performs shutdown. Every case then checks `waitpid(pid, WNOHANG) == -1` with `ECHILD`, observes the port stopped, and verifies that emergency-retired ownership cannot restart. These post-completion syscalls are test observations rather than a competing production reaper.

I ran only this new focused test at the reviewed head under an external 50-second process-group deadline. It passed with zero failures in **3.426 seconds**, after a **0.31-second** incremental build; the watchdog returned exit 0 without intervention. No full suite was rerun. The builder's 17-test result remains separately reported evidence. Cancellation and coalescing behavior were assessed from the implementation; this one regression does not enumerate every such interleaving.

The changed Python capability-check fixture also installs its handler before launch and uses a five-second failure deadline (`ProfileTestEnvironment.swift:22-29`) instead of the former run-loop wait. No production API was added for that fixture.

## Limits and repository state

Root's saved stack confirms the old `ProfileClient.close -> emergencyShutdown -> PipeProfilePort.shutdown -> Process.waitUntilExit` stall. The prior local pass at eb98e41 did not establish reliable shutdown and is not treated as such here.

The final answer-helper exit receipt, real shared-host emergency callback, joined integration and hosted Swift 6.1.2 behavior remain outside this verdict. No private source, real Keychain, capture or model operation was exercised. No source, index, HEAD, push or GitHub mutation was made; only this report was authored, with focused test artifacts in temporary build/cache paths.
