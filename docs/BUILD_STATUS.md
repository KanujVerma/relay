# Current build state, 2026-10-23

Main remains `eb28d1586e52b7f0fd2e3b15580ae08ff295872e`. The controller [integration draft PR71](https://github.com/KanujVerma/relay/pull/71) contains the accepted text/context/control app, verified visual service and Python image backend, plus prospective-question routing. Code checkpoint `6fcf2c2c0af1e0ef2cfe2d7468b44c03ce9194ef` adds the accepted native visual-control/writer core; documentation commits may advance the branch. The native screen-image consumer is still being completed; the whole visual app feature is not delivered. Main merges and real hardware/account/quality acceptance remain separate.

The owner authorizes frequent scoped commits/pushes and requires GPT-6.1 Sol extra-high workers. No private source, Keychain material, real capture, model download/load or actual account inference was used by this effort. Default/fixture helpers and normal image setup remain inert until explicitly enabled.

## Source checkpoints and ownership

These are exact reviewed or pending checkpoints, not a claim that every later PR head has the same review.

| Lane | Source / draft | Verified state and next boundary |
| --- | --- | --- |
| Existing repairs | PR46 `7cba4e1`, PR49 `cf30aaa` | Published, locally reviewed and hosted-tested; included in the frozen feature foundation. Neither merged to main. [Repair evidence](evidence/2026-10-23-pr-fixes.md). |
| Conversation #60 | [PR68](https://github.com/KanujVerma/relay/pull/68), `a26181ee068feb4ff1e0f3b965479df7fb07a797` | Accepted and assembled. Actual source/lease ordering and bounded native transport; later two delegated manual/stop seams are reviewed in composition e45549a. Real audio/ASR acceptance remains open. |
| Personal #61 | [PR63](https://github.com/KanujVerma/relay/pull/63), `7ace412194987ee08c97945cf16ca425f8b120d5` | Accepted and assembled. Required emergency shutdown, lifecycle fencing, relevant retrieval and nonblocking actual-child exit receipt. Complete controller/hosted profile17 tests pass. Real private import/Keychain acceptance remains open. |
| Answers #62 | [PR67](https://github.com/KanujVerma/relay/pull/67), `b33292f12dd8148fe41518acf514703a9d01d49f` | Accepted and assembled. Named/personal grounding, microphone fault handling, follow-up display bounds and durable task/correction recovery are reviewed. General output uses conservative English lexical/form checks, not a semantic truth proof. |
| Screen context #64 | [PR69](https://github.com/KanujVerma/relay/pull/69), `e3fcfbe3d7f6caa87e2ba3d95f0cb012fc1781ca` | Accepted and assembled. Selected-window capture/OCR, original observation identity and bounded PNG ports; downscale-only correction accepted. Real screen/permission/OCR quality remains open. |
| Shortcuts/controls #65 | [PR70](https://github.com/KanujVerma/relay/pull/70), `2fc2db5c767d8ef892d030487bd7a281f418e366` | Accepted and assembled. Pinned KeyboardShortcuts, own-window controls and optional allowlisted selected text; cancellation correction accepted. Ordinary hotkeys do not need Accessibility. Real global-key/AX behavior remains open. |
| Text/control app #72 | [PR75](https://github.com/KanujVerma/relay/pull/75), `e45549ab0ffe8004d64cef9bb2b272c0fa18d407` | Accepted and assembled at657aee1. Ordered context, final re-observation, atomic Manual Help, real Pause/Resume/End/quiescence and idle AI mode. OCR callback/waiter corrections passed scoped independent review. |
| Visual service #73 | [PR74](https://github.com/KanujVerma/relay/pull/74), `ad9f587cc83c7239865a0cf758fab185cccba72e` | Exact six-file own patch accepted and assembled. Explicit synthetic-image verification, private current-credential/model capability and one-request permit reuse existing HTTPX/OAuth. Actual account support has not been tested. [Research](research/VISUAL_INPUT.md). |
| Python visual consumer #73 | [PR78](https://github.com/KanujVerma/relay/pull/78), `1c2d8ef2ce5d6207fd74f126845ebab48024537c` | Exact eight-file own patch accepted and assembled at1f1d75a. Strict async control/replay/cleanup, staged original-observation PNG binding, pre-EOU retirement and one-send publication checks. Native image production/commit remains separate. |
| Prospective routing #76 | [PR77](https://github.com/KanujVerma/relay/pull/77), final `62b30c417f451b761a80528ef3de7468cb7dd441`, source `a5827dc` | Accepted and assembled at6152fc8. What would you build now takes the neutral technical route;13 past/mixed personal cases still withhold before generation. Output guard and host were unchanged by this slice. |
| Native visual consumer #73 | [PR79](https://github.com/KanujVerma/relay/pull/79), core `a227a13acf12de8e74dd3763961613d3e89d919b` | Partial parser/status/setup/writer core independently accepted and assembled; controller50 panel tests pass. Two writer findings were corrected through e01/a227: pre-start queued retirement, then first-write I/O failure retirement/reaping. Producer, pixel-dependent publication and actual settings UI remain in progress in work/relay-build-visual-app. |
| REA research #66 | [Sanitized findings](research/CLUELY_LESSONS.md) | Complete bounded static investigation of selected installed Cluely2.1.24 sources using REA6.7.0. No competitor runtime/account claims or proprietary implementation copied. |

[Portable independent review reports](evidence/reviews-2026-10-23/README.md) preserve original reproductions, corrections, exact diffs and limits. Lane documents preserve builder checks. Historical status is available in Git history; old findings are not treated as current after their accepted corrections.

## Controller and hosted evidence

| Exact checkpoint | Observed result | Limits |
| --- | --- | --- |
| Controller657aee1, accepted e45549a plus ad9 service | Python524/21 optional converter skips; native session32, composition12 and panel/app37; app packaging/signature/plist passed. Changed native packages had180-second external deadlines. | Unchanged profile/screen/controls initially retained earlier exact-source proof; subsequent hosted5bde tested all six. |
| Hosted5bde19b | [Native/Python40014242743](https://github.com/KanujVerma/relay/actions/runs/40014242743) and [contract40014242744](https://github.com/KanujVerma/relay/actions/runs/40014242744) succeeded. Logs confirm Python524/21 optional skips, native32+17+28+18+12+37 =144, and app compilation on Swift6.2.3. | Certifies that exact earlier head. The longer run showed compilation progress. Old Swift6.1.2 profile compile failure is historical; this configured supported compiler passed. |
| Controller1f1d75a, backend+routing joined | Python558/21 optional converter skips, zero failures;8 focused native app/helper tests pass; EVALS26/docs20/diff checks pass. Backend files exactly match reviewed1c2; native tree exactly matches accepted e45549a. | Hosted checks on the newer published head must be observed separately. No account/model/private screen used. |
| Visible native fixtures | Coding question/card, expandable Python code, Pause clearing, fresh Resume, current-question Help and End passed in the real window. Initial case fixture displayed/ended; its coding-oriented injected wording was corrected with a real-helper regression. | [Detailed record](evidence/2026-10-23-joined-app.md). Final corrected case visual recheck was blocked by the Mac locking; not counted as passed. Only the owned synthetic process was stopped. |

Optional skips are document-converter integrations without their optional dependencies. Synthetic HTTPX calls and helper subprocesses do not establish actual account support, visual/ASR accuracy, live latency or upstream compute cancellation. Native-owned source/request admission and actual child/capture quiescence remain required.

## Branch topology and continuation

- Frozen common feature base: `build/parallel-foundation-2026-10-23` at `a8f8359354f44e11be39e22a55422b2cef9f6c91`. Never move it just to assemble work.
- Controller: `build/copilot-integration-2026-10-23`, isolated work/relay-build-integration. It assembles only reviewed source; ordinary scoped pushes are authorized, main merge is separate.
- Visual service frozen base: `build/visual-foundation-2026-10-23` at `819e4ae6b88aca4b2cd97c0f508af31c82207fae`.
- Visual backend frozen base: `build/visual-host-foundation-2026-10-23` at `c20e1eb3287397caa15205e0c036afbc6e21deb7`. Its older Swift dependency is not reaccepted; controller retains e45549a.
- Native visual frozen base: `build/visual-app-foundation-2026-10-23` at e45549a. Its worker imports only the accepted ad9 service and1c2 backend own commits, declares peer dependencies and keeps native ownership disjoint.
- Prospective routing frozen base: `build/hypothetical-routing-foundation-2026-10-23` at5bde19b.
- [Documentation PR59](https://github.com/KanujVerma/relay/pull/59) mirrors contracts/research/reviews/handoff without runtime code; runtime links resolve to the corresponding exact source checkpoint.

BUILD_CONTRACT owns exact wire/authority requirements; goldens in contracts are schema evidence, not permission. PARALLEL_PLAN owns coordination. All workers use GPT-6.1 Sol extra-high. Reviews inspect immutable own deltas and focus reproductions; original implementers fix established findings. Do not broaden or rerun settled suites without a new change, failure or concrete concern.

## One next controller action

Independently review the final producer/UI delta when its owner freezes it; the core through a227a13 is accepted. Finish the lazy selected-window image producer, image-dependent final pixel/lease gate and explicit settings UI. Review and join the final native own delta with accepted helper1c2/routinga582, then run current synthetic integration and visible inert setup checks when the Mac is unlocked. Keep images off by default. Real permitted audio/ASR, source/permission revocation, model/account availability, private-profile preparation, quality/latency and main merge remain separate acceptance gates.

Hosted exactb66cf2d also passed: [native/Python40016463296](https://github.com/KanujVerma/relay/actions/runs/40016463296), [contract40016463067](https://github.com/KanujVerma/relay/actions/runs/40016463067). Logs confirm558 Python/21 optional skips,144 native tests and app compilation. New native core has separate controller50-test proof and awaits later hosted checks. Exact prospective case question also passed a manual real fixture-helper run: one users/workflow card, no code, clean child exit0; the locked-Mac visual limitation remains.
