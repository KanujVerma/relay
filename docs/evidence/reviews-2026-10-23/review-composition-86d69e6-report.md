# Independent composition review, PR75 / issue72

Reviewed immutable head `86d69e627c86ec17073c8bd57a9a2deb68c8356a` in `work/relay-review-composition-86d69e6`, with accepted answer baseline `b33292f12dd8148fe41518acf514703a9d01d49f`. The checkout remained clean and at that head after review. No source, index, HEAD, branch, push or PR mutation occurred.

**Specification verdict: changes required. Quality verdict: changes required.** Two actionable finding families remain. The ordinary automatic OCR path is disabled by its own lifecycle callback, and a rejected quiescence acknowledgment can strand the actual pause/end barrier. The requested immediate profile-response sibling also crashes on a schema-permitted scalar payload.

## Findings

### 1. [P1] Internal screen supersession retires the request being captured

Primary location: `spikes/macos-composition/Sources/RelayContextComposition/QuestionContextComposer.swift:49` (binding is established at35; eventual guard at51). Actual composition wiring: `spikes/macos-panel/Sources/RelayPanelSession/SessionApplicationModel.swift:195` and327-334. Accepted coordinator seam: `spikes/macos-context/Sources/RelayScreenContext/ScreenContextCoordinator.swift:65-74`.

Trigger: enable selected-window OCR and process any current automatic remote EOU through the actual app wiring. `capture` first sets `binding=request`, then calls `screen.supersede(with:)`. The coordinator deliberately calls `retire(.retired)` before assigning the new current request. Its synchronous `onInvalidation` reaches `contextSourceChanged`, sees the newly set composer binding, and calls `contextComposer.retire()`. The coordinator subsequently captures successfully, but the composer's binding has become nil, so the post-capture `current(request)` guard rejects every frame. Manual Help falling back to OCR encounters the same path. This is normal request setup, not a permission failure or external source change.

Focused reproduction compiled the exact frozen composer/publication binding, screen coordinator/types/wire, selection service/adapters and native event/authority sources with synthetic in-memory capture and OCR ports. The callback reproduced the app's actual binding guard followed by composer retirement; it did not access any real window or Accessibility source. Observed:

```text
appCallback=false captureCalls=1 contextFrames=1 bindingCurrent=true hasContext=true invalidations=0
appCallback=true captureCalls=1 contextFrames=0 bindingCurrent=false hasContext=false invalidations=1
```

Fix: distinguish the coordinator's expected request-supersession retirement from external source/permission invalidation, or arrange request ownership establishment after that expected synchronous retirement. Preserve the real source-change retirement gate. Add a regression that connects the actual app invalidation callback while capturing a normal EOU; the existing composer tests leave that callback disconnected and therefore pass.

Reproduction harness: `/private/tmp/relay-review-quiescence-86d69e6/ComposerProbe.swift`; executable `composer-probe` in the same folder.

### 2. [P2] Validate responses before releasing pending continuation ownership

New composition location: `spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift:171-172`. Actual waiting caller: `spikes/macos-panel/Sources/RelayPanelSession/SessionApplicationModel.swift:391`. Requested immediate sibling: `HelperTransport.swift:162-165` (the profile branch is inherited from the accepted answer baseline, not newly authored composition code).

Quiescence trigger: a valid JSON `session_quiescence_response` echoes the outstanding request UUID but has a different valid capture-session UUID or epoch. The code removes the continuation from `quiescenceRequests`, then validates the echoed session/epoch and throws. `fail()` closes the transport, but `stop()` cannot reject the removed waiter, and its15-second timer also finds no entry. The app's teardown task remains awaiting this orphaned continuation indefinitely, so it never reaches profile retirement/lock and helper-reap completion in the failure path, and never clears `stopping`.

An exact-source synthetic transport probe used the frozen `HelperTransport.swift`, `StrictJSON.swift`, and native event/authority sources. Its owned Python child returned the matching request UUID and a different valid session UUID. Only an unused answer-decoding branch was stubbed. Runtime output:

```text
SWIFT TASK CONTINUATION MISUSE: requestSessionQuiescence(sessionID:epoch:) leaked its continuation without resuming it. This may cause tasks waiting on it to remain suspended forever.
after malformed acknowledgment: failure=true requestCompleted=false
child reaped: failure=true requestCompleted=false
after transport timeout: failure=true requestCompleted=false
```

The controller requested inspection of the adjacent profile response case. That branch likewise removes its waiter before fallible processing, and its outer schema permits any payload node. A matching `profile_response` with `payload:null` reached `JSONSerialization.data(withJSONObject:)` and aborted the exact-source probe with exit134 and uncaught `NSInvalidArgumentException`: `Invalid top-level type in JSON write`. The Swift `catch` does not handle that Objective-C exception. No actual profile or Keychain was used.

Fix: keep the pending continuation owned until all response identity/payload validation and response preparation succeed, then remove and resume it exactly once; alternatively, explicitly resume any removed waiter with an error before rejecting the response. Require the expected object payload before Foundation serialization. Add wrong-session/wrong-epoch quiescence tests and scalar/null profile-response tests that prove the waiter rejects, the child is reaped, and the app's end barrier completes.

Reproduction harnesses: `/private/tmp/relay-review-quiescence-86d69e6/Probe.swift` and `ProfileProbe.swift`; executables `probe` and `profile-probe` in that folder.

## Scope and evidence

Read the applicable AGENTS instructions, frozen composition lane handoff and controller-canonical BUILD_CONTRACT/BUILD_STATUS. Reviewed only the composition-owned modules, app/helper/panel/manifest/plist/tests, supplemental/manual/host additions, and the two delegated native seams. Accepted source/profile/screen/control libraries were inspected only at necessary composition seams. Settled answer grounding/correction policy, controller documentation/CI and the disabled, later visual-input route were excluded from new defect hunting.

Static checks found the intended original audio/manual identity/order path, atomic native issuance under the controller lock, bounded optional capture and terminal re-observation gates, host-owned used-context metadata, current-request staging, source-fault app reconciliation, and actual capture/helper ownership barriers. Hide uses the own window's `orderOut`; window close observes `willClose`, disables global controls and enters the actual End barrier. Manual reveal uses ordinary `orderFront` to preserve selected-text focus. These are source conclusions, not real-window acceptance.

Fresh reviewer verification:

- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.test_composition_host tests.test_supplemental_context`:13 tests passed, zero failures,0.607s. These include actual synthetic helper/manual/profile-preservation/quiescence and exact replay rejection paths.
- Exact-source synthetic OCR callback reproduction confirmed finding1, with and without the app callback.
- Exact-source synthetic malformed quiescence and null profile-response children confirmed finding2. The quiescence waiter remained incomplete after child reap and beyond its timeout; the profile probe exited134.
- Head and clean checkout rechecked; scoped cumulative diff whitespace check passed.

The first isolated controls-source compilation was blocked by the nested Swift macro sandbox. Recompiling with the compiler's documented local `-disable-sandbox` subprocess option succeeded. This was a compiler environment issue; no production source was changed. No full suite or app product build was rerun by this reviewer. The owner's501 Python /23 optional skips and137 native tests across six packages, built app and ad hoc signature remain owner-reported evidence for this frozen head.

No real UI window, permission prompt, screen or audio capture, Accessibility selection, global key registration, pasteboard, private source, Keychain, account, image/model request or network inference was exercised. No subagents were used. The controller will verify the final joined head after corrections.
