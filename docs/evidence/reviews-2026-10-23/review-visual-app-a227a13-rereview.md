# Native first-write I/O correction: scoped re-review

**Accepted. Specification and quality verdicts pass for this narrow correction; no actionable P finding remains in the reviewed writer families.** The original queued-retirement defect remains corrected, and the separate first-write EPIPE retirement defect is now corrected. This is not acceptance of the unfinished producer/UI or a later joined head.

## Exact scope

Clean detached checkout: `<workspace>/work/relay-review-visual-app-a227a13`.

Head: `a227a13acf12de8e74dd3763961613d3e89d919b`.

Parent: `e01c34b3c6a0076f2bcbe2e2b0ca97412cd4cb61`.

Own delta: three files/30 additions, comprising one production catch line,25 regression-test lines and four lane-doc lines. Direct binary diff SHA-256: `55b4e84175421397bef358866a9dcb2a0a30d71c77f6607471ed3f6d80296b38`.

Reviewed only the complete a227 correction, prior report `review-visual-app-e01c34b-rereview.md`, and the necessary original cancellation/deadline control. Accepted imports, unchanged parser/setup state and the owner's later producer/UI work were not re-audited. The separate e01 checkout remains preserved at its prior clean head.

## Finding closure

`HelperTransport.swift:309` now calls `fail()` for `PanelBridgeError.closed` before any positive write, while retaining existing failure behavior after writing starts. Pre-start source/cancellation/deadline retirement remains nonfatal. The first-write syscall wrapper reports genuine descriptor/write failures as `.closed`, so the former silent EPIPE path now reaches shared admission retirement, waiter rejection and actual child shutdown/reaping.

Exact-source first-write reproduction uses the same closed-stdin/retained-stdout child as the prior finding, extended to independently observe the child PID and check reaping before a rescue shutdown. Observed:

```text
first write returned error=closed
before explicit shutdown: transport_failure_notified=true
before explicit shutdown: admission_closed=true child_gone=true child_reaped=true
explicit shutdown returned after existing reap
```

`child_reaped` was checked by `waitpid(...,WNOHANG) == -1` with `ECHILD`, after the PID was no longer present. New sends were rejected. The callback and automatic stop/reap occurred before the caller invoked `shutdownAndWait`.

The original slow-reader cancellation/deadline schedules were rerun with a subsequent valid control. Observed:

```text
cancel before reader release: finished=true elapsed_ms=500
cancel later_control_received=true
cancel after release: result=CancellationError() image_received=false elapsed_ms=512
deadline before reader release: finished=true elapsed_ms=512
deadline later_control_received=true
deadline after release: result=timedOut image_received=false elapsed_ms=520
```

Thus the new classification does not turn benign queued retirement into transport failure. Both waiters finish before reader release, no retired image arrives, and the later control remains usable.

## Exact commands and evidence

Working directory is the frozen a227 checkout above. Harnesses are in `/private/tmp/relay-review-visual-app-a227a13-probes`. Production helper, strict parser and unchanged visual parser compile directly from this checkout. The unchanged native event/authority module is reused from the prior exact-source review; only an unused answer-decoding branch is stubbed.

```sh
/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-a227a13-probes/FirstWriteFailureFinal.swift -o /private/tmp/relay-review-visual-app-a227a13-probes/first-write-final -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache
/private/tmp/relay-review-visual-app-a227a13-probes/first-write-final

/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-a227a13-probes/QueuedControlFinal.swift -o /private/tmp/relay-review-visual-app-a227a13-probes/queued-control-final -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache
/private/tmp/relay-review-visual-app-a227a13-probes/queued-control-final

git status -sb
git rev-parse HEAD
git diff --check HEAD^ HEAD
```

Final compilation/execution commands exited0. The checkout remained clean at the exact reviewed head and diff whitespace validation passed. A temporary harness whitespace typo was corrected before the recorded first-write compilation; production sources were never changed.

Reused e01 evidence, not rerun:35 cancelled waiters settled;32 bounded queued slots;26 tombstoned reservations retained zero payloads; zero cancelled images and one later control after drain. Its independently observed started-but-unfinished image completed one full16384-byte JSON frame under cancellation, then preserved the following control. The a227 catch classification line does not change reservation bytes, counters, arbitration or started-frame handling, so those results remain relevant without redundant tests.

No full native/Python suite was rerun. The builder's focused five writer tests and50 panel tests remain builder evidence. The reviewer independently ran only the exact-source EPIPE and queued cancellation/deadline controls above.

## Limits

Headless generated JSON and owned synthetic children only. No actual UI, capture, permission/AX/global key, private data, pasteboard, Keychain, account, network/model request or image inference occurred. No source/index/HEAD edit, commit, push, subagent or peer cache/build mutation occurred. This closes the two library writer findings; producer/UI completion, joined-head verification and real acceptance gates remain separate.
