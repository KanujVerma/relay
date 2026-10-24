# Actual typed app join: b431914

2026-10-23. Independent scoped review, GPT-6.1 Sol extra-high. **Main integration behavior passes; one remaining P2 in unavailable-source basis controls holds this UI candidate for its narrow correction.** Root confirmed the finding and owns the follow-up. Backend72 and transcript3f acceptance are recorded separately.

## Immutable inputs

Final own commit `b431914fe4a9e776a159f5baa0ff31cc7c76e17b`, six files276 additions/nine deletions, parentb9fbd2f imports accepted72. Own binary diff SHA-256 `e0ad64d52e6ec3acbb93e65c486043b7f8d375c6d20038a0a035d27bc4e56ebc`. Fresh detached clone `/Users/kanuj/Documents/ChatGPT/relay/work/relay-review-typed-app-b431914`, clean before/after.

Earlier immutable root patch `/private/tmp/relay-typed-app-root-candidate.patch`,33659 bytes, SHA-256 `1312896587ececc23c0bd24d4354e2e4d1f92416e628d8bfa789081280839516`, was independently applied only to an owned clone at `45a742b58451910aee6f2b0b8c5ca47804f4b4bc`. Its Model and TypedApplication test source are byte-identical to finalb431; final UI additionally disables basis actions while paused/stopping. Original patch and red log are preserved beside this report.

Read full own Model/composer/live/app/test delta. No broad re-audit of accepted source/capture/helper/writer/vault/model/account/packaging code. No production source edits.

## P2: last microphone source loss leaves basis actions enabled without an issuable session

**Own location:** `spikes/macos-panel/Sources/RelayPanelSession/LiveSessionView.swift:28`, passing `state.running && !state.stopping` as composer eligibility. The new composer uses that Boolean for Use latest/Send as new. Actual typed authority separately requires at least one active native source.

In an approved microphone-only session, an actual microphone `sourceUnavailable(.asrUnavailable)` removes its last source while the native authority object can remain present. Model receive only automatically ends source2 failures; source1 failure leaves `running` true (`SessionApplicationModel.swift:343-348`). Its correctly stricter assistant-session closure returns nil. The new UI Boolean therefore remains true even though typed issuance is unavailable. Send as new calls the existing command that clears the chosen basis before submit rechecks authority, losing the original basis without issuing a request. The previous paused-only disabling does not cover this path.

**Focused exact-source proof:** a separate tiny test package imports the untouched final native/controller libraries. Start the actual NativeSessionController microphone-only with injected quiet components, issue/record a real native typed request as draft basis, type a follow-up, invoke actual native microphone source-unavailable and use the same active-source session predicate as root. Then call the publicly enabled command path. It prints:

```text
SOURCE_LOSS authorityStillPresent=true microphoneActive=false beforeBasis=true
SOURCE_LOSS afterBasis=false draftKept=true
```

One failed original-basis-preservation assertion,0.109s. No issuance occurs. The probe demonstrates actual native source loss and exact command behavior; it does not instantiate real capture or click an actual UI. Reachability through final root's state Boolean is established by the reviewed straight-line Model/presentation/View code. Root independently confirmed this P2.

Durable inputs/logs: `typed-app-b431914-probes/source-loss/{Package.swift,SourceLossTests.swift,result.log}`; original runnable temporary package `/private/tmp/relay-review-typed-source-loss`. Command:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-typed-97-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-typed-97-module \
swift test --disable-sandbox --skip-update \
  --package-path /private/tmp/relay-review-typed-source-loss \
  --scratch-path /private/tmp/relay-review-typed-97-panel \
  --cache-path /private/tmp/relay-review-typed-97-cache --filter SourceLossTests
```

Root's stated narrow correction is snapshot eligibility for Send as new based on actual session/draft validity, command-side basis preservation on unavailable authority, Use latest using actual current-question eligibility, and removal of the duplicate UI activity Boolean. This review does not weaken final native issue/publication checks or require an idle assistant lifetime.

## Main integration verification

**All ten unchanged actual app tests passed, zero failures,5.238s** on exactb431: nine `StagedVisualRetirementTests` plus `TypedApplicationTests.testActualTypedSendHelpDraftBasisAndTranscriptLifecycle`. The same test on original131289 patch with pre72 backend failed four Help/card/basis assertions; all unchanged assertions are green after72. Nine held-image cases were green before and after that correction.

The ten prove actual Model/global ingress/forwarder/helper routes: typed Send and targeted Stop deny a held original before EOU release; positive original PNG upload remains one image POST; source/onset/Pause/End/Disable/failed-channel behaviors remain; Help returns a positive coding card; draft original-basis preservation, transcript Pause seal, fresh Resume, explicit new question and End clearing hold. Strong card assertions were not removed or relaxed. These are synthetic injected native components and the existing HTTPX MockTransport launcher; no external inference/account action occurs.

Exact command from frozen `spikes/macos-panel`:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-typed-97-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-typed-97-module \
RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python \
swift test --disable-sandbox --skip-update \
  --scratch-path /private/tmp/relay-review-typed-97-panel \
  --cache-path /private/tmp/relay-review-typed-97-cache \
  --filter 'StagedVisualRetirementTests|TypedApplicationTests'
```

Durable logs `typed-app-b431914-probes/app-10-green.log` and `app-10-original-help-red.log`; scratch/cache are reviewer-owned. `git diff --check HEAD^ HEAD` passes and final status is clean.

Source review confirms actual locked native issuance, owned cancellation registration before the same bounded global enqueue, denial/context retirement before any old optional callback release, fresh typed context/image capture, stale queued original denial, pre-panel exact-owned draft recovery, nonfatal stale authorization rejection and actual source/session checks. The composer observes the actual nested transcript; typed/model text is not promoted into transcript or personal memory. No further actionable issue found in this own delta.

## Limits

No full native/Python suites, visible UI, actual device/capture/ASR model, real consent revocation, private files/Keychain/account/network model inference were performed by this reviewer. Root's separate visible synthetic preview is not this reviewer's evidence. Idle/audio-unavailable Ask remains the declared later slice. No root/author/frozen source/index/HEAD edits, commits, pushes or new agent occurred; only independent snapshots, temporary public build/probe inputs and coordination evidence were written. Final runtime tests are green, but this report deliberately leaves the confirmed basis-action P2 open until the narrow successor is reviewed.
