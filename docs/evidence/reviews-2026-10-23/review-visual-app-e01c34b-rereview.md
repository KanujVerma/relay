# Native writer correction: scoped independent re-review

**Specification verdict: changes required. Quality verdict: changes required.** The original queued cancellation/deadline finding is corrected. One distinct P2 first-write I/O failure defect remains in the new error handling.

## Exact scope

Frozen checkout: `<workspace>/work/relay-review-visual-app-e01c34b`, clean and detached at `e01c34b3c6a0076f2bcbe2e2b0ca97412cd4cb61`.

Reviewed the complete own HEAD correction, plus only `HelperTransport.swift` and `ImageWriteBackpressureTests.swift` differences from `e896c2af8deb8c40bd22b4365eb7170e7a24afaa`. HEAD changes three files,153 additions/14 deletions; the source/test correction is143 additions/14 deletions. Own parent: `5aa72b2fedc612ec3ac3c0a02c4543313ec1f50f`; own binary diff SHA-256: `6f9df1328a0ae490484945505cf2a2cebfc72308fec2c14c1293632a4789a4f8`. Prior report: `review-visual-app-e896c2a.md` in this directory. Accepted visual/Python imports at21e0154/5aa72b2, unchanged parser/setup state, accepted e455 behavior, and the owner's later producer/UI snapshot were excluded from re-audit.

## Original P2: corrected

The original exact-source slow-reader schedules now settle the queued waiter before the reader opens and do not transmit its image. Observed:

```text
cancel before reader release: finished=true elapsed_ms=505
cancel after release: result=CancellationError() image_received=false elapsed_ms=541
deadline before reader release: finished=true elapsed_ms=503
deadline after release: result=timedOut image_received=false elapsed_ms=532
```

The private reservation prevents double settlement, clears queued payloads and preserves bounded slots until writer drain. The MainActor source/deadline check and reservation lock cover first-write arbitration; EAGAIN has not committed writing state. A positive first write commits the full-frame requirement.

## New finding

### [P2] Retire the transport on a genuine first-write I/O error

Location: `spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift:307-309`; first-write error originates in `ImageWriteReservation.start`.

The new catch calls `fail()` only when `reservation.hasStarted`. This correctly preserves unrelated transport for benign queued source/cancellation/deadline retirement, but also suppresses failure for genuine first-write errors such as EPIPE before any byte was written. A dead helper input therefore returns `closed` to this image caller without retiring helper admission, rejecting other transport waiters, invoking the native failure callback or starting shutdown/reaping. The child may keep stdout and its process alive, so the read path need not supply an independent EOF. Later controls can be admitted to a known-broken writer until another operation encounters the failure.

Exact-source reproduction: an owned synthetic Python child closes fd0, signals readiness through a reviewer temporary file, then keeps its stdout/process alive. `sendJSONAwaitingWrite` attempts one current frame with a future deadline. Observed:

```text
first write returned error=closed
before explicit shutdown: transport_failure_notified=false
after explicit shutdown: transport_failure_notified=false
```

The caller had to invoke explicit `shutdownAndWait`; the first write did not trigger transport retirement. This differs from the previous writer, where genuine write failures always called `fail()`.

Fix narrowly: distinguish benign pre-start reservation retirement from actual write/descriptor I/O failure. The latter must fail/retire the transport even if no byte started, while preserving nonfatal queued cancellation/source/deadline behavior and exactly-once completion. Add a child that closes stdin while retaining stdout, and assert failure notification/admission retirement, rejection of pending controls and actual reap without a caller-provided rescue shutdown. No speculative redesign is requested. The controller has forwarded this finding to the original implementer.

## Focused lifecycle evidence

An additional exact-source harness checks cancelled reservation bounds and started-frame integrity. It uses read-only reflection while the queue is stably blocked to observe private counts/payload clearing; no production source or state is changed through reflection.

```text
tombstones: waiters_settled=35 queued_slots=32 image_reservations=26 payloads_retained=0
after tombstone drain: images_received=0 later_controls=1
before partial-write cancellation: first_write_started=true writer_finished=false
after cancellation before reader release: writer_finished=false
atomic-frame result=CancellationError() received=14014:padding,14014:padding,14014:padding,14014:padding,16384:image,19:later_control,
```

All35 cancelled waiters returned; bounded tombstones held no PNG/frame bytes. After the reader opened, no cancelled image was delivered and the later control arrived exactly once. In the separate partial-write schedule, a positive first write was observed before cancellation; the waiter correctly stayed pending until the whole16384-byte JSON frame completed, and the following control remained framed. Reservation `retire`/`finish` result guards and the single writer-defer slot release also support exactly-once behavior statically.

## Exact reproduction commands

Working directory is the frozen checkout above. All commands compile the corrected production helper, strict parser and unchanged visual parser directly; the unchanged native event/authority module from the prior exact-source review is reused. Only the unused answer-decoding branch is stubbed in harnesses. The children consume generated JSON through owned pipes and use reviewer temporary files only.

```sh
/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-e896c2a-probes/WriterProbe.swift -o /private/tmp/relay-review-visual-app-e896c2a-probes/writer-probe-e01c34b -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache
/private/tmp/relay-review-visual-app-e896c2a-probes/writer-probe-e01c34b

/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-e01c34b-probes/FirstWriteFailure.swift -o /private/tmp/relay-review-visual-app-e01c34b-probes/first-write-failure -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache
/private/tmp/relay-review-visual-app-e01c34b-probes/first-write-failure

/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-e01c34b-probes/LifecycleProbe.swift -o /private/tmp/relay-review-visual-app-e01c34b-probes/lifecycle-probe -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache
/private/tmp/relay-review-visual-app-e01c34b-probes/lifecycle-probe
```

All final compilation/execution commands exited0. The first-write failure probe is observational and reports the defect rather than failing the process. An initial max-size frame attempt fit the pipe fully before cancellation, so it did not establish partial-write coverage; the recorded lifecycle schedule then used four preceding14KB frames and directly observed the started-but-unfinished state. No production source changed.

No full native/Python suite was run. The builder's four writer tests and full49 panel tests remain builder evidence. Final source cleanliness/exact head and own-commit diff whitespace were verified.

## Limits

Headless compiler/owned-child checks only; the Mac remains locked. No actual UI, capture, OS permission/AX/global key, private source, pasteboard, Keychain, account, model/network request or image inference occurred. No source/index/HEAD edit, commit, push, subagent or peer cache/build mutation occurred. This report closes the original queued-retirement defect separately from the new genuine-I/O retirement defect and requires a narrow corrected-head re-review.
