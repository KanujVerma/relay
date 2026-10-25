# Composition correction R1: scoped independent re-review

**Accepted for the two reviewed finding families. No actionable P findings remain in this delta.** Both the specification and code-quality verdicts pass within the scope below. This does not establish real-device acceptance or acceptance of any later joined/image-adapter head.

Reviewed immutable `86d69e627c86ec17073c8bd57a9a2deb68c8356a..e45549ab0ffe8004d64cef9bb2b272c0fa18d407` in `work/relay-review-composition-86d69e6`. The checkout is detached, clean and unchanged at `e45549a`. The prior report is `review-composition-86d69e6-report.md` in this directory. Read current AGENTS instructions and the correction evidence in `docs/lanes/COMPOSITION.md`; reviewed the complete six-file delta only. No source/index/HEAD edits, commits, pushes or subagents were used.

## Finding disposition

1. **Original P1, OCR self-invalidation: corrected.** `QuestionContextComposer.swift:35-57` retires old composer state, completes expected synchronous screen supersession while no new OCR binding exists, checks the unchanged original native lease, then installs the new binding. It does not suppress invalidation callbacks. The explicit selection path retains its required request binding; OCR fallback clears that binding before supersession. A callback-connected regression and the independent reproduction both produce one OCR frame. A later real coordinator source change still synchronously retires the binding and prevents ownership/publication.

2. **Original P2, waiter ownership and requested profile sibling: corrected.** `HelperTransport.swift:162-181` validates/prepares the object profile payload before removing its waiter, avoiding Foundation top-level-fragment serialization. Quiescence response schema plus stored session/epoch are validated under the lock before continuation ownership is removed. Invalid responses therefore leave a registered waiter for transport failure/stop to reject. Exact source checks show matching responses complete, malformed/wrong-session/wrong-epoch/unknown-request responses reject, and the owned child is reaped. Null, scalar and array profile payloads reject without a crash or orphan. The actual `SessionApplicationModel` End barrier completes against wrong-session, wrong-epoch and closed-child responses.

## Fresh focused tests

Working directory for all commands:

```text
<workspace>/work/relay-review-composition-86d69e6
```

The reviewer cloned the previously pinned public dependency/build cache into separate `/private/tmp/relay-review-e45549a-*` locations, reconciled only the temporary workspace-state paths to this frozen checkout, and used resolved versions with no dependency update. These are reviewer-owned temporary build artifacts; no peer cache or source was changed.

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-e45549a-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-e45549a-swift swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-panel --cache-path /private/tmp/relay-review-e45549a-cache --scratch-path /private/tmp/relay-review-e45549a-build --filter 'HelperResponseLifecycleTests|SessionApplicationTests.testEndCompletesAfterMalformedOrClosedQuiescenceChild' > /private/tmp/relay-review-e45549a-panel-focused.log 2>&1

CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-e45549a-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-e45549a-swift swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-composition --cache-path /private/tmp/relay-review-e45549a-cache --scratch-path /private/tmp/relay-review-e45549a-build --filter 'automaticOCRSurvivesOldRetirementCallbackButLaterSourceChangeRetiresIt' > /private/tmp/relay-review-e45549a-ocr-focused.log 2>&1
```

Observed exit0 for both commands:

- **5 transport lifecycle tests passed**, zero failures,0.205s. Includes valid response, wrong session, wrong epoch, EOF and the three nonobject profile cases.
- **1 actual app End test passed**, zero failures,0.286s; its loop traverses wrong session, wrong epoch and EOF through the production app model and inherited-pipe transport.
- **1 callback-connected OCR test passed**,0.008s; verifies capture and validation, then later source invalidation and failed subsequent publication.

No complete native or Python suite was rerun. The cloned Swift build metadata logged stale-path warnings and the restricted app test logged NSWorkspace notification-registration diagnostics; these did not produce test failures or trigger a real UI/capture operation.

## Independent exact-source reproductions

Harnesses are in `/private/tmp/relay-review-e45549a-probes`. The unchanged exact native/screen/selection dependencies were reused from the prior reviewer compilation; the changed helper/composer and their strict JSON/publication sources were compiled directly from this frozen checkout. The response harness stubs only an unused answer-decoding branch. It sends control/profile responses from owned synthetic Python children, with a10-second external process bound. No real profile data or service is involved.

Exact compilation/execution commands:

```sh
/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-e45549a-probes -L /private/tmp/relay-review-e45549a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-e45549a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift /private/tmp/relay-review-e45549a-probes/ResponseProbe.swift -o /private/tmp/relay-review-e45549a-probes/response-probe -module-cache-path /private/tmp/relay-review-e45549a-probes/fresh-cache

python3 - <<'PY'
import subprocess
from pathlib import Path
result=subprocess.run(['/private/tmp/relay-review-e45549a-probes/response-probe'],capture_output=True,text=True,timeout=10)
Path('/private/tmp/relay-review-e45549a-response-probe.log').write_text(result.stdout+result.stderr)
print(result.stdout,end='');print(result.stderr,end='');raise SystemExit(result.returncode)
PY

/usr/bin/swiftc -parse-as-library -emit-library -emit-module -module-name RelayContextComposition -I /private/tmp/relay-review-e45549a-probes -L /private/tmp/relay-review-e45549a-probes -lRelayNativeSession -lRelayScreenContext -lRelayControls spikes/macos-composition/Sources/RelayContextComposition/ContextPublicationGate.swift spikes/macos-composition/Sources/RelayContextComposition/QuestionContextComposer.swift -o /private/tmp/relay-review-e45549a-probes/libRelayContextComposition.dylib -emit-module-path /private/tmp/relay-review-e45549a-probes/RelayContextComposition.swiftmodule -module-cache-path /private/tmp/relay-review-e45549a-probes/fresh-cache

/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-e45549a-probes -L /private/tmp/relay-review-e45549a-probes -lRelayNativeSession -lRelayScreenContext -lRelayControls -lRelayContextComposition -Xlinker -rpath -Xlinker /private/tmp/relay-review-e45549a-probes /private/tmp/relay-review-e45549a-probes/ComposerProbe.swift -o /private/tmp/relay-review-e45549a-probes/composer-probe -module-cache-path /private/tmp/relay-review-e45549a-probes/fresh-cache

/private/tmp/relay-review-e45549a-probes/composer-probe > /private/tmp/relay-review-e45549a-composer-probe.log
```

All final compilation/execution commands exited0. An initial attempt to relocate the old compiler module cache failed its embedded-path check; the fresh reviewer cache above resolved that environment issue. The composer compilation also logged two sandbox subprocess diagnostics while still succeeding. No production source was altered to accommodate the environment.

Observed OCR output:

```text
appCallback=false captureCalls=1 contextFrames=1 bindingCurrent=true hasContext=true invalidations=0
appCallback=true captureCalls=1 contextFrames=1 bindingCurrent=true hasContext=true invalidations=0
laterSourceChange: validBefore=true bindingCurrent=false owns=false validAfter=false invalidations=1
```

Response probe: **14 modes,0 unexpected results**. Matching quiescence and object profile responses accepted. Wrong session, wrong epoch, `quiesced:false`, string-valued quiesced, an extra field, invalid session UUID and unknown request UUID all rejected. Null, string, array, number and Boolean profile payloads all rejected. Every request returned and every child shutdown/reap wait completed; no continuation warning or Foundation exception occurred. Full per-mode output is in `/private/tmp/relay-review-e45549a-response-probe.log`.

Final `git status -sb` showed only `HEAD (no branch)`, `git rev-parse HEAD` returned the exact reviewed hash, and `git diff --check 86d69e627c86ec17073c8bd57a9a2deb68c8356a..e45549ab0ffe8004d64cef9bb2b272c0fa18d407` passed.

## Limits

This was a scoped correction re-review of OCR request ordering and response/continuation ownership. Settled answer semantics, accepted imported libraries, controller CI/documentation and later visual wiring were not re-audited. No real window, permission prompt, screen/audio capture, Accessibility read, global key registration, pasteboard, private source, Keychain, account, image/model request or network inference was exercised. The controller still needs exact joined-head verification and separate external acceptance gates.
