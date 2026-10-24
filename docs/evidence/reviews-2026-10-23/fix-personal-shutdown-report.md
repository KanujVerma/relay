# Personal native shutdown liveness correction

## Frozen state

- Baseline: `eb98e41ebec670452f96313289203ebe1853afa6`.
- Frozen follow-up: `7ace412194987ee08c97945cf16ca425f8b120d5`.
- Checkout/branch: `<workspace>/work/relay-build-personal`, `feature/personal-context-2026-10-23`.
- Normal push confirmed, working tree clean. Existing draft PR63: https://github.com/KanujVerma/relay/pull/63.
- No global documents, CI, peer source, main merge or issue closure changed.

## Diagnosis and source evidence

Root's complete integrated native run compiled and then stalled beyond five minutes in the delayed selection/review test. Saved evidence: `/private/tmp/relay-profile-stall-sample.txt` and `/private/tmp/relay-integration-profile-tests.log`. The sample showed ProfileClient.close -> ControlledProfilePort.emergencyShutdown -> PipeProfilePort.shutdown -> Foundation waitUntilExit on a cooperative thread. Root observed no remaining Python child and terminated only its owned xctest process. The earlier 16-test local pass did not establish reliable quiescence.

The current Apple SDK NSTask.h and public Process documentation specify that waitUntilExit polls the current thread's run loop, whereas default termination notifications target the launch thread. A Swift actor can migrate threads across awaits. Apple's SDK recommends terminationHandler for tasks launched from secondary threads/queues. This fits the sampled stall; no claim is made that open-source corelibs code is the Darwin implementation.

Primary references inspected:
- https://developer.apple.com/documentation/foundation/process/waituntilexit()
- https://developer.apple.com/documentation/foundation/process/terminationhandler
- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Foundation.framework/Headers/NSTask.h`, lifecycle comments at lines 130-137, 155-190 and 233-239.
- https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/waitpid.2.html for post-completion ECHILD observation.

Compared the answer owner's existing shutdownAndWait pattern: it dispatched the same waitUntilExit onto a utility queue. Moving that wait alone does not establish completion on the correct launch run loop. The answer owner has adopted an exit receipt into its existing prelaunch termination handler separately; its integration remains owner/root verification.

## Focused production correction

PipeProfilePort now installs a ProfileProcessExitReceipt through child.terminationHandler before run(). The receipt stores the actual termination status under a lock and safely resumes asynchronous waiters whether completion races before or after registration. Foundation remains the only production reaper.

Shutdown coalesces concurrent callers, closes inherited IO, sends TERM, yields through the existing 500 ms grace, escalates to KILL only when still running, and awaits the actual exit receipt. Grace expiration is not quiescence evidence. The process and receipt remain owned while unresolved, new requests are rejected while shutdown is pending, and ownership is only released after completion. No waitUntilExit, Thread.sleep or competing production waitpid remains. The public ProfilePort/ClosureProfilePort/ProfileClient API is unchanged; normal acknowledged shared-profile locking still preserves the conversation helper.

The test-only Python capability check also installs its callback before run and has a five-second failure deadline instead of a run-loop wait. No new framework/package or copied upstream implementation was introduced.

## Reproduction and verification

Added a short real-Python-child regression with 36 shutdown schedules: 16 EOF, 16 children proved already exited before close, and 4 children that ignore SIGTERM and require KILL. Shutdown runs from independently scheduled cooperative tasks. Every case asserts post-completion waitpid(pid,WNOHANG) == -1 with ECHILD, showing Foundation already reaped the exact child. This syscall is a test observation after claimed completion, never a second production reaper. Retired owners must reject restart.

RED: on the unchanged eb98e41 production code the new focused test exceeded an external 40-second deadline (exit 124). Only the owned test process group was interrupted; this is not a passing test.
GREEN: the focused correction completed the 36 cases in 3.588 seconds. After tightening the already-exited schedule, the complete native suite passed **17 tests, zero failures, 5.962 seconds**, following an 8.09-second incremental build, under an explicit external **50-second deadline**. The watchdog stops only its own test process group on deadline and never reports timeout as success. These times are observed local fixture evidence, not product latency or cold-build bounds.

Additional checks: EVALS/verify_docs.py passed 20 required files/local links; git diff --check passed. Python source did not change and the unrelated full Python suite was not rerun. Root's joined Python run and earlier Python results remain separate evidence.

Local toolchain: Apple Swift 6.4 arm64. Hosted Swift 6.1.2, fresh joined integration and independent delta review remain pending. Existing restricted Swift user-cache warnings remain.

## Exact handoff

Import `7ace412` after `eb98e41`. Seven files changed: ProfileClient.swift, new ProfileProcessExitReceipt.swift, new ProfileProcessExitTests.swift, ProfileTestEnvironment.swift and the three lane/API/plan documents. No host adapter signature change is required. The existing emergency callback must still synchronously fence native/helper admission and old requests, terminate/reap the old helper, and require a fresh helper/client/controller after forced retirement. The answer owner received the tested receipt pattern and exact commit.

Root should independently review this small ownership/liveness delta and rerun the joined native suite under an explicit deadline. No private inputs, actual Keychain items, capture, model load/download, account inference or paid calls ran. All signed-app/private-user/hardware acceptance gates remain pending.
