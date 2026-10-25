# Profile integration shutdown stall

Controller verification on the integration branch after merging personal head eb98e41, 2026-10-23. This supersedes any inference that the earlier scoped re-review establishes complete native integration acceptance.

- Full combined Python suite passed: 435 tests, 21 optional converter skips.
- `swift test --package-path spikes/macos-profile --scratch-path /private/tmp/relay-personal-build` compiled successfully, then remained running for over five minutes. No success result was observed.
- A read-only process-name/elapsed-time listing identified this test's Swift parent and XCTest child. No Python child remained in that process listing.
- macOS `/usr/bin/sample` of the owned XCTest process showed its cooperative thread waiting in `ProfileClient.close -> ControlledProfilePort.emergencyShutdown -> PipeProfilePort.emergencyShutdown -> PipeProfilePort.shutdown -> Foundation Process.waitUntilExit`, at ProfileClient.swift:138. MainActor XCTest waited for async completion. The raw process sample is local supporting evidence, not copied here.
- After preserving the trace, the controller terminated only that owned stuck XCTest process; the test command exited 1. This is a blocked verification result, not a passing test or real-user incident.
- Original personal owner is diagnosing bounded shutdown/reaping and preparing a focused correction. Source and caller authority must remain retired while process ownership resolves; a timeout alone cannot claim actual quiescence.

All inputs/keys/children in this run were synthetic. No user files, real Keychain items, audio, screen capture, permission prompt, weights or account inference were used. Re-run the corrected native path and scoped review before declaring the composition verified.


## Resolution

Personal owner published `7ace412194987ee08c97945cf16ca425f8b120d5`: a termination callback is installed before launch and records a latched receipt; Foundation remains the sole production reaper. Grace expiry escalates termination, never grants quiescence. The independent [shutdown re-review](review-personal-7ace412-shutdown.md) accepted the correction and reran the 36-child schedule regression under an external deadline. See the [builder report](fix-personal-shutdown-report.md).

Controller integrated that exact correction and reran the complete native profile suite under a 90-second external process-group deadline. All17tests passed in5.492seconds; watchdog exit0 without intervention. This closes the reproduced standalone profile shutdown stall. Final answer-helper composition and hosted acceptance remain separately tracked in BUILD_STATUS.
