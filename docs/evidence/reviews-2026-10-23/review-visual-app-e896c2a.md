# Independent native visual library review, PR79

**Specification verdict: changes required. Quality verdict: changes required.** One P2 writer lifecycle defect is confirmed. The strict response/parser, waiter ownership and injected setup state yielded no additional actionable findings in this checkpoint.

## Immutable scope

Checkout: `<workspace>/work/relay-review-visual-app-e896c2a`.

Base: `e45549ab0ffe8004d64cef9bb2b272c0fa18d407`.

Head: `e896c2af8deb8c40bd22b4365eb7170e7a24afaa`, detached and clean at start and finish. [Draft PR79](https://github.com/KanujVerma/relay/pull/79) targets the frozen visual-app foundation. Own patch: eight files,497 additions/3 deletions. Direct `git diff --binary <base>..<head>` SHA-256: `e1b08fce79fc384c586efd56d18de9cbb02263dbce12c37f1780216605636a60`.

Read current AGENTS, `docs/lanes/VISUAL_APP.md` and canonical BUILD_CONTRACT visual sections. Reviewed the complete own delta once. Settled `e45549a` behavior was checked only at necessary seams. Producer, full-offer/image publication and actual UI wiring are explicitly unfinished and excluded from this checkpoint's defect assessment; their declared absence is not a finding.

## Finding

### [P2] Revalidate queued image writes before starting them, and bound the admitted wait

Locations: `spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift:98-107` and218-227.

`sendJSONAwaitingWrite` checks cancellation/currentness/deadline before reservation, then suspends on a continuation until `enqueue`'s serial writer block finishes. That writer block performs no original request/deadline/cancellation check before starting the frame, and starts a fresh two-second per-write deadline instead. An image frame that fits the bounded queue but sits behind a blocked earlier write therefore continues waiting beyond its original deadline and is transmitted after its producer retires. The method notices only after writing the entire frame. The existing new retirement test fills capacity completely, so it exercises the retry loop rather than this admitted-but-not-started state.

This affects the promised bounded current-request writer and can delay the producer's original EOU/control release while still writing stale image chunks. The requirement to finish an already-started frame atomically does not require sending a frame whose own write has never begun. No inference/account disclosure was attempted or claimed by the reproduction; this is a native queue lifecycle defect.

Focused exact-source reproduction uses an owned synthetic Python child that waits on a reviewer temporary file before reading stdin. Ten14KB padding frames remain within32 frames/256KiB and block earlier serial writes. A small image marker then fits the queue and has a100ms original deadline. In one schedule its task is cancelled and source guard becomes false after50ms; the other allows only the deadline to expire. The reader opens after roughly500ms. Neither marker's write could have started while earlier writes remained blocked.

Observed:

```text
cancel before reader release: finished=false elapsed_ms=504
cancel after release: result=CancellationError() image_received=true elapsed_ms=519
deadline before reader release: finished=false elapsed_ms=524
deadline after release: result=timedOut image_received=true elapsed_ms=530
```

Correction should give the admitted reservation explicit cancellation/deadline ownership and revalidate it before its writer starts. A cancelled/expired frame whose first byte has not been written should be removed/rejected without truncating the channel or delaying unrelated controls. Once its first byte is written, preserve full-frame completion or fail/retire the transport and settle its continuation exactly once. Add deterministic cancellation/currentness and deadline regressions for the admitted-behind-blocker state, alongside already-started atomic-frame and stop/EOF behavior. No broad implementation changes are requested.

The controller received this concrete finding and is coordinating a narrow correction with the original implementer. Reviewer source remained unchanged.

## Reproduction and verification

Harness: `/private/tmp/relay-review-visual-app-e896c2a-probes/WriterProbe.swift`. It compiles frozen production helper/strict-JSON/visual-response sources directly. Exact unchanged native event/authority files supply its module. Only the unused answer-decoding branch is stubbed. Children read synthetic JSON and write a reviewer-owned temporary marker log; no real app/window or account is involved.

Working directory is the immutable checkout above. Commands:

```sh
/usr/bin/swiftc -parse-as-library -emit-library -emit-module -module-name RelayNativeSession spikes/macos-session/Sources/RelayNativeSession/SessionEvent.swift spikes/macos-session/Sources/RelayNativeSession/SessionPresentationAuthority.swift -o /private/tmp/relay-review-visual-app-e896c2a-probes/libRelayNativeSession.dylib -emit-module-path /private/tmp/relay-review-visual-app-e896c2a-probes/RelayNativeSession.swiftmodule -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache

/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-e896c2a-probes/WriterProbe.swift -o /private/tmp/relay-review-visual-app-e896c2a-probes/writer-probe -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache

/private/tmp/relay-review-visual-app-e896c2a-probes/writer-probe
```

Final compiles and execution exited0; the program observes the defect rather than treating it as success. An initial temporary harness interpolation typo was corrected before the recorded compilation; production code was untouched.

Static review confirms visual waiters validate parsed schema and owned action/UUID before removal, identical adjacent pending/terminal replay is ignored, and malformed/unknown replies/EOF retire pending transport waiters. The existing profile/quiescence validate-before-removal correction remains intact. Injected setup state retires local image reflections synchronously, fences generation changes, leaves original verification pending until actual sender completion and does not let passive status grant image-offer consent. These are source conclusions, not fresh test-suite claims.

No full native/Python suite or redundant broad check was run. The owner's47 panel tests/10 new tests and two focused writer tests remain owner evidence; the reviewer independently ran only the two exact-source slow-reader schedules above. Final Git cleanliness, exact head and diff whitespace were checked.

## Limits

The Mac was locked; real UI acceptance remains deferred. No real capture, permission prompt, Accessibility/global key, pasteboard, private data, Keychain, account/network model request or image inference was used. No source/index/HEAD mutation, commit, push, PR write, subagent or peer build/cache mutation occurred. No verdict is given on the owner's later producer/UI snapshot. A corrected frozen head requires scoped re-review before acceptance of this library checkpoint.
