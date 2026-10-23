# Pre-EOU visual retirement correction: independent scoped re-review

**Accepted. Specification and quality verdicts pass within the scoped correction; the P1 in `review-visual-app-b880fd5.md` is closed. No new actionable finding was established.** This does not establish real capture/account acceptance or acceptance of an unverified later joined head.

## Immutable scope

- Checkout: `<workspace>/work/relay-review-visual-app-c707ef8`, clean and detached at `c707ef86a47a067f00ad818a6a50ad7b50d346e7`.
- Own correction parent: `1efed4782a0ec66e76291d00a8b3c19411ba60e9`.
- Own correction: six files,280 additions/36 deletions.
- Direct own binary diff SHA-256: `b7cabdf3dd4f51d35711e7b0bdebc4b575b7ad3970ce3b018d0bcd9e8adbc5a3`.

Read the complete HEAD correction, relevant runtime differences from b880, prior P1 report and own lane evidence. The accepted test-only launcher imports were treated as controller-reviewed dependencies. Unchanged writer/producer/native capture/screen code and accepted Python runtime peers were not re-audited. No production Python change, serialized capability, account identity or additional private authority appears in this correction.

## Closure evidence

The app retains the original `PanelRequestBinding` until its exact matching `supplemental_context_retired` has been synchronously enqueued on the same bounded writer. Only then does it clear local composer ownership and release held EOU. The source callback uses the same ordering before nested retirement; Pause/End retire actual native admission, enqueue original context retirement and accepted disable, then release EOU and join existing ownership. An enqueue failure stops native/helper admission and retires the forwarder without sending EOU. Bounded identity/result caching makes repeated retirement idempotent, while a new binding resets that cache; the retirement wire retains original fences and cannot clear a separately fenced replacement.

The extracted `issueVisualInput` registers the same owned UUID/action and synchronously enqueues the existing control. Its private-construction pending object retains a terminal result arriving before `value()` is awaited. Schema/action/revision/replay checks occur before waiter removal; existing four-pending/512-operation/35-second bounds remain. Stop/EOF/malformed response rejects the owned pending response. The wrapper preserves `requestVisualInput` behavior. App Disable now issues its helper control before local callbacks can release EOU, and the setup state records its pending join before invoking those callbacks.

Native image-only disable preserves valid OCR for an honest text fallback. Unused personal/reference display paths remain independent by source tracing: whole-context retirement is fenced and dependent-card retirement still requires actual task/image use. DI defaults are nil in production. The optional synthetic coordinator, post-full-write acknowledgment hook and post-ingress-enqueue observer neither rewrite native events nor create image authority. The internal packet seam rejects normal mode and routes fixture packets through the actual controller stamping path.

## Fresh focused actual app/backend tests

Reviewer-private cloned pinned caches/build state were reconciled to this frozen checkout. No peer cache/build changed. Working directory for all commands is the checkout above.

```sh
RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-c707ef8-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-c707ef8-swift swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-panel --cache-path /private/tmp/relay-review-c707ef8-cache --scratch-path /private/tmp/relay-review-c707ef8-build --filter 'StagedVisualRetirementTests|VisualInputTransportTests|VisualInputSetupStateTests' > /private/tmp/relay-review-c707ef8-focused.log 2>&1
```

Observed exit0, **14 selected test methods passed**, zero failures:

- Seven actual `SessionApplicationModel`/owned-child/accepted-backend MockTransport cases passed in3.342s. End, Pause, actual native remote onset and actual source callback admitted zero image POSTs after retirement. A closed retirement channel released no EOU. Explicit Disable produced one OCR-only POST and a native OCR card before the later actual onset. The positive unchanged-image control still made one image POST and published image provenance. Original request binding and global event sequence were asserted without restamping.
- Four transport and three setup-state methods passed in0.364s. They cover reply-before-await, wrong owned action, unknown UUID/EOF, duplicate pending/terminal replies, responsive disable while the original verify waits for its terminal, generation fencing, passive status and pending-state ownership.

The app tests hold only a post-actual-image-end-write acknowledgment and observe ingress only after synchronous enqueue. Their controlled EOU-before-later-onset scheduling therefore reproduces the original failure boundary using actual app methods and the accepted backend, rather than only testing a parser or manually fabricated onset envelope. The synthetic launcher uses the existing HTTPX0.28.1 environment and fixed attempt-type logs; no account or external model request occurs.

Logs include restricted LaunchServices notification diagnostics and cloned build stale-path warnings, with no test failures.

## Original frame/backend reproduction

The prior minimal original reproduction was updated only to the corrected app callback ordering, with unchanged exact composer/forwarder/accepted screen modules. Harnesses: `/private/tmp/relay-review-visual-app-c707ef8-probes/RetirementFixed.swift` and `BackendRetirementFixed.py`. The actual app tests above independently verify that this ordering is the implemented runtime behavior.

```sh
/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-b880fd5-probes -I /private/tmp/relay-review-e45549a-probes -L /private/tmp/relay-review-visual-app-b880fd5-probes -L /private/tmp/relay-review-e45549a-probes -lRelayNativeSession -lRelayContextComposition -lRelayScreenContext -lRelayControls -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-b880fd5-probes -Xlinker -rpath -Xlinker /private/tmp/relay-review-e45549a-probes /private/tmp/relay-review-visual-app-c707ef8-probes/RetirementFixed.swift -o /private/tmp/relay-review-visual-app-c707ef8-probes/retirement-fixed -module-cache-path /private/tmp/relay-review-visual-app-b880fd5-probes/cache
/private/tmp/relay-review-visual-app-c707ef8-probes/retirement-fixed
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /private/tmp/relay-answers-venv/bin/python /private/tmp/relay-review-visual-app-c707ef8-probes/BackendRetirementFixed.py
```

Observed exit0:

```text
local_retired=true wire_order=["screen_context", "screen_image_begin", "screen_image_chunk", "screen_image_end", "supplemental_context_retired", "eou", "speech_started"]
before old EOU: active_request=None retirement_frame_seen=True
before following onset: model_POSTs=1 image_POST=False image_digest_published=False
```

The backend harness also asserts there is no stale taskContext. The one permitted text POST reflects the original ordered question; staged image/context authority is gone before its admission. Run the producer immediately before the Python harness to preserve original monotonic capture freshness.

## Independent cancelled-caller ownership check

An exact corrected helper/strict-parser/visual-parser harness issues verify synchronously, starts waiting, cancels that caller, then issues Disable. An owned synthetic child returns Disable but holds the original verify terminal until a local gate opens. This checks that caller cancellation cannot falsely certify original probe cleanup.

```sh
/usr/bin/swiftc -parse-as-library -I /private/tmp/relay-review-visual-app-e896c2a-probes -L /private/tmp/relay-review-visual-app-e896c2a-probes -lRelayNativeSession -Xlinker -rpath -Xlinker /private/tmp/relay-review-visual-app-e896c2a-probes spikes/macos-panel/Sources/RelaySessionPanel/HelperTransport.swift spikes/macos-panel/Sources/RelaySessionPanel/StrictJSON.swift spikes/macos-panel/Sources/RelaySessionPanel/VisualInputResponse.swift /private/tmp/relay-review-visual-app-c707ef8-probes/PendingCancellation.swift -o /private/tmp/relay-review-visual-app-c707ef8-probes/pending-cancellation -module-cache-path /private/tmp/relay-review-visual-app-e896c2a-probes/cache
/private/tmp/relay-review-visual-app-c707ef8-probes/pending-cancellation
```

Observed exit0:

```text
before original cleanup: disable_status=disabled cancelled_caller_finished=false
after original cleanup: status=cancelled cached_same=true distinct_disable_identity=true
```

Only an unused answer-decoding branch is stubbed. Original response ownership remains stable, repeat post-completion `value()` returns the same cached result without IO, and the original/Disable request identities remain distinct. Children are shut down and reaped.

## State and limits

Final `git status -sb`, `git rev-parse HEAD` and `git diff --check HEAD^ HEAD` confirmed clean exact source and valid whitespace. No source/index/HEAD mutation, commit, push, subagent or peer cache mutation occurred. No full native/Python rerun was performed; builder panel64/composition17/Python554 with21 optional skips and app build/signature remain builder evidence.

The Mac was locked. No actual UI/capture, permission/AX/global key, private data, pasteboard, Keychain, real OAuth/account request, network model call or image inference was used. The approved launcher and all tokens/catalog/PNGs/SSE are synthetic. This scoped acceptance closes the pre-EOU retirement/control-ownership correction; root must still verify its final joined head and preserve the separate real capture/account/quality/latency acceptance gates.
