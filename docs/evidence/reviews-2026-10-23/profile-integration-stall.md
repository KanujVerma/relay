# Profile integration shutdown stall

Controller verification on the integration branch after merging personal head eb98e41, 2026-10-23. This supersedes any inference that the earlier scoped re-review establishes complete native integration acceptance.

- Full combined Python suite passed: 435 tests, 21 optional converter skips.
- `swift test --package-path spikes/macos-profile --scratch-path /private/tmp/relay-personal-build` compiled successfully, then remained running for over five minutes. No success result was observed.
- A read-only process-name/elapsed-time listing identified this test's Swift parent and XCTest child. No Python child remained in that process listing.
- macOS `/usr/bin/sample` of the owned XCTest process showed its cooperative thread waiting in `ProfileClient.close -> ControlledProfilePort.emergencyShutdown -> PipeProfilePort.emergencyShutdown -> PipeProfilePort.shutdown -> Foundation Process.waitUntilExit`, at ProfileClient.swift:138. MainActor XCTest waited for async completion. The raw process sample is local supporting evidence, not copied here.
- After preserving the trace, the controller terminated only that owned stuck XCTest process; the test command exited 1. This is a blocked verification result, not a passing test or real-user incident.
- Original personal owner is diagnosing bounded shutdown/reaping and preparing a focused correction. Source and caller authority must remain retired while process ownership resolves; a timeout alone cannot claim actual quiescence.

All inputs/keys/children in this run were synthetic. No user files, real Keychain items, audio, screen capture, permission prompt, weights or account inference were used. Re-run the corrected native path and scoped review before declaring the composition verified.
