# Independent final native producer/UI review

**Specification verdict: changes required. Quality verdict: changes required.** One P1 cross-process retirement defect is confirmed. No additional actionable finding was established in the own delta.

## Immutable scope

- Checkout: `<workspace>/work/relay-review-visual-app-b880fd5`, detached and clean at start and finish.
- Base: accepted `a227a13acf12de8e74dd3763961613d3e89d919b`.
- Head: `b880fd524083a995165035802af381f0ed32aa7b`.
- Own delta:13 files,491 additions/26 deletions.
- Direct binary diff SHA-256: `c4eaea65a75deeded2202ac0c9fef625784168c7a5b17f8352504258dc025a5c`.

Read own lane evidence and canonical BUILD_CONTRACT visual requirements. Reviewed the complete new runtime/test delta once. The accepted writer/control core, accepted Python peers and unchanged native capture/screen libraries were traced only at necessary seams, not re-audited. No source/index/HEAD mutation, commit, push, subagent or peer build/cache mutation occurred.

## Finding

### [P1] Retire already staged context in the helper before releasing the old EOU

Primary location: `spikes/macos-panel/Sources/RelayPanelSession/SessionApplicationModel.swift:339-342`; affected caller at250-257, early image staging at266-281, and callback guard at345-352. New producer seam: `spikes/macos-composition/Sources/RelayContextComposition/QuestionContextComposer.swift:captureForForwarding`.

The new producer writes OCR and PNG frames into the helper before its original EOU. A later remote onset invokes `retireOptionalWork`, which clears local binding, calls `contextComposer.retire()` and then releases the held original EOU through `cancelOptionalWork`. Composer retirement clears its own binding before invoking screen retirement, so the actual app `contextSourceChanged` guard sees no binding and emits no matching `supplemental_context_retired`. The helper's already staged image therefore survives until the old EOU arrives. The newer onset is correctly ordered after that EOU, but it is too late to serve as pre-admission image revocation.

Trigger: a complete image end has physically reached the helper, its write acknowledgment/producer continuation is still held, and the native source retires for a newer remote onset. Native ownership and local image proof retire correctly. The wire nevertheless contains:

```text
local_retired=true wire_order=["screen_context", "screen_image_begin", "screen_image_chunk", "screen_image_end", "eou", "speech_started"]
```

There is no matching retirement before EOU. A valid pipe schedule may make EOU readable before the following onset. Feeding the real generated PNG/text frames from this frozen composer into the accepted backend under that schedule produced:

```text
before old EOU: active_request=None retirement_frame_seen=False
before following onset: model_POSTs=1 image_POST=True image_digest_published=True
```

The host legitimately admits the staged image under the still-observed old native request and makes an image POST. This happens after local native source authority was retired. The final native lease/display veto cannot undo that upload. The accepted backend's pre-EOU retirement handler already supports the necessary no-active-answer case; its behavior is not the defect.

This is new to early image staging: the accepted text-only capture did not put those optional bytes into the helper until final forwarding. Pause/End also use `retireRequest`/`retireOptionalWork`; their visual-disable control is currently submitted asynchronously. Explicit image disable likewise schedules its helper control after local retirement. Those paths require the same ordering guarantee; the runtime proof above isolates the remote-onset case rather than claiming separate completed UI reproductions for all three controls.

Fix narrowly: capture the original staged binding and synchronously enqueue its existing matching retirement, or the applicable already-owned disable/stop control, before any held EOU is released. Preserve original EOU-before-later-native-event order and original identities. Do not weaken the native display gate or treat local cancellation as helper revocation. Include complete-image/end-ack-held tests through the real callback ordering and accepted backend MockTransport, covering source/onset, disable, Pause and End, including when `host.active` is null and a late old retirement must preserve newer staging. The controller has forwarded this finding to the original owner.

## Reproduction evidence

Harnesses:

- `/private/tmp/relay-review-visual-app-b880fd5-probes/RetirementProbe.swift`
- `/private/tmp/relay-review-visual-app-b880fd5-probes/BackendRetirement.py`
- Generated original frames: `/private/tmp/relay-review-visual-app-b880fd5-probes/retired-flow.jsonl`

The Swift harness links the frozen composer/forwarder/native frame code and unchanged accepted screen/selection ports. It uses generated in-memory pixels and synthetic OCR, attaches the actual app callback's binding guard/retire/send semantics, and invokes the actual remote-onset retirement ordering: clear local binding, retire composer, cancel optional work, then enqueue onset. It holds the end-write acknowledgment after recording the complete end frame. This is a synthetic seam reproduction of the source-visible app flow, not a claim that the real OS-backed app model captured a window.

The Python harness consumes those generated frames using the accepted host/provider and actual configured `OAuthAnswerStream` with HTTPX MockTransport. Only the valid native EOU/onset payloads are supplied by the existing synthetic native fixtures. It deliberately processes EOU before a subsequent readable onset, a valid cross-process schedule, and observes the actual emitted image content part and host imageDigest. It makes no external HTTP/account request.

Exact compilation commands, working directory the immutable checkout:

```sh
/usr/bin/swiftc -parse-as-library -emit-library -emit-module -module-name RelayNativeSession spikes/macos-session/Sources/RelayNativeSession/SessionEvent.swift spikes/macos-session/Sources/RelayNativeSession/SessionPresentationAuthority.swift spikes/macos-session/Sources/RelayNativeSession/NativeManualHelpRequest.swift -o /private/tmp/relay-review-visual-app-b880fd5-probes/libRelayNativeSession.dylib -emit-module-path /private/tmp/relay-review-visual-app-b880fd5-probes/RelayNativeSession.swiftmodule -module-cache-path /private/tmp/relay-review-visual-app-b880fd5-probes/cache

/usr/bin/swiftc -parse-as-library -emit-library -emit-module -module-name RelayContextComposition -I /private/tmp/relay-review-visual-app-b880fd5-probes -I /private/tmp/relay-review-e45549a-probes -L /private/tmp/relay-review-visual-app-b880fd5-probes -L /private/tmp/relay-review-e45549a-probes -lRelayNativeSession -lRelayScreenContext -lRelayControls spikes/macos-composition/Sources/RelayContextComposition/ContextPublicationGate.swift spikes/macos-composition/Sources/RelayContextComposition/OrderedContextForwarder.swift spikes/macos-composition/Sources/RelayContextComposition/SessionIngress.swift spikes/macos-composition/Sources/RelayContextComposition/QuestionContextComposer.swift -o /private/tmp/relay-review-visual-app-b880fd5-probes/libRelayContextComposition.dylib -emit-module-path /private/tmp/relay-review-visual-app-b880fd5-probes/RelayContextComposition.swiftmodule -module-cache-path /private/tmp/relay-review-visual-app-b880fd5-probes/cache

/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-b880fd5-probes -I /private/tmp/relay-review-e45549a-probes -L /private/tmp/relay-review-visual-app-b880fd5-probes -L /private/tmp/relay-review-e45549a-probes -lRelayNativeSession -lRelayContextComposition -lRelayScreenContext -lRelayControls -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-b880fd5-probes -Xlinker -rpath -Xlinker /private/tmp/relay-review-e45549a-probes /private/tmp/relay-review-visual-app-b880fd5-probes/RetirementProbe.swift -o /private/tmp/relay-review-visual-app-b880fd5-probes/retirement-probe -module-cache-path /private/tmp/relay-review-visual-app-b880fd5-probes/cache

/private/tmp/relay-review-visual-app-b880fd5-probes/retirement-probe
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /private/tmp/relay-answers-venv/bin/python /private/tmp/relay-review-visual-app-b880fd5-probes/BackendRetirement.py
```

Compilation and execution exited0; the backend probe asserts the unwanted image POST to demonstrate the defect. The producer should be rerun immediately before the Python harness to keep its original monotonic capture timestamps fresh. The unchanged accepted screen/selection modules are from the prior exact-source reviewer build. Two compiler sandbox subprocess diagnostics appeared while compilation still succeeded.

## Other focused verification

Reviewer-private cloned pinned caches/build output were reconciled to this frozen source. No peer cache changed.

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-b880fd5-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-b880fd5-swift swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-panel --cache-path /private/tmp/relay-review-b880fd5-cache --scratch-path /private/tmp/relay-review-b880fd5-build --filter 'VisualForwardingIntegrationTests|VisualApplicationTests|test_image_use_requires_strict_optional_canonical_digest_on_OCR_only' > /private/tmp/relay-review-b880fd5-panel-focused.log 2>&1

CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-b880fd5-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-b880fd5-swift swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-composition --cache-path /private/tmp/relay-review-b880fd5-cache --scratch-path /private/tmp/relay-review-b880fd5-build --filter 'VisualContextComposerTests|selectedTextHasPriorityOnlyForExplicitHelpAndReobservesBeforePublication' > /private/tmp/relay-review-b880fd5-composer-focused.log 2>&1
```

Both exited0: **six focused panel/application tests passed** (three transport/digest and three actual app tests), and **six focused composition tests passed** in0.257s. These support lazy >32-frame backpressure, whole-frame cancellation/order, complete-offer proof, strict digest, same-OCR/different-pixel rejection, selected-text image exclusion and actual app probe/Start/End/Pause barriers. Their passing does not cover the full staged-image-before-EOU retirement schedule reproduced above. Logs contain restricted LaunchServices notification diagnostics and cloned build stale-path warnings, with zero test failures.

The final source/commit/diff whitespace checks passed. No full accepted native/Python suite was rerun. Builder panel56/composition17/Python554 with21 optional skips, app build and ad-hoc signature remain builder evidence.

## Limits

Mac locked; real UI inspection, window permission/capture, actual account probe, private sources, Keychain, AX/global keys, pasteboard, external image/model requests and live latency/quality were not exercised. The native final digest/offer/lease gates were source-traced and synthetically tested, not accepted for real capture. This report preserves the accepted writer/Python boundary and asks only for the missing cross-process revocation ordering before joined acceptance.
