# Cluely UI and automatic setup implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace the developer-facing prototype with a Cluely-style normal session experience and automatically prepared speech assets.

**Architecture:** Keep the accepted native capture/conversation/helper/profile/context ports. Split native presentation from managed asset readiness through the exact public coordinator seam. Own files in isolated branches and join reviewed deltas; follow-on chat/history/account slices are explicit functional gaps.

**Tech Stack:** Swift6.2/macOS15.2+, SwiftUI/AppKit, existing pinned FluidAudio c79c4106, Foundation URLSession and CryptoKit, existing Python helper.

**Spec:** [Shared contract](../../CLUELY_PARITY_CONTRACT.md), [UI design](../specs/2026-10-23-cluely-ui-design.md), [automatic speech design](../specs/2026-10-23-automatic-speech-design.md).

## Global constraints

- Frozen foundation1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7. Preserve original native event/lease/order, request-bound context and actual quiescence.
- Normal Home/session has no model/detector folders or model-license checkbox. One Start prepares managed assets; init/fixtures perform no download/load/capture.
- Use the exact21-file225,301,695byte immutable manifest and source/license policy in the speech spec. No ambient account credential, mutable model listing or cloud fallback.
- Every enabled UI action uses a real port. No fabricated progress/transcript/history/account readiness. No private content or weights in Git/CI.
- All workers use GPT-6.1 Sol extra-high. Scoped commits/pushes are authorized; main merge remains separate.

## Task1: Managed assets and one Start

**Files:** SpeechAssetManifest.swift, SpeechAssetStore.swift, SpeechAssetDownloader.swift, SpeechSetupCoordinator.swift in macos-session/RelaySessionCapture; narrow NativeCaptureConfiguration managed initializer; SessionApplicationModel init/start/cancel/retirement integration; focused setup/app tests; model notices; lane handoff. Exact ownership is in the contract.

**Consumes:** Existing ASR/VAD loader layout, selected-source consent, native capture start/retire/join.

**Produces:** Public SpeechSetupCoordinator/Snapshot and internally issued PreparedSpeechAssets, plus model.speechSetup/start/cancelPreparation/retryPreparation.

- [ ] Add the fixed manifest/API foundation and negative synthetic tests for invalid cache/manifests, currentness/cancellation and no eager work. Verify failures establish the absent provisioning behavior.
- [ ] Implement streamed bounded downloads, owned staging/cache validation and atomic publication, finite retries and actual cancellation/join using the exact speech design. Preserve native inference/capture ports and reviewed model policy.
- [ ] Wire one current Start intent through preparation, actual model/capture start and existing teardown. Source/recording denial remains separate from model readiness. Advanced explicit roots cannot alter managed files.
- [ ] Run changed package/setup/app bridge checks with synthetic artifacts and injected transport. No repeated baseline model/capture audit. Build the product, record exact results/skips and publish scoped checkpoints.

```sh
RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python swift test --disable-sandbox --package-path spikes/macos-session
RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python swift test --disable-sandbox --package-path spikes/macos-panel --filter Setup
```

## Task2: Familiar native Home/live/Context/Settings

**Files:** App entry, SessionSettingsView, SessionWindowControls; new Home/live/toolbar/card/context/theme/settings/window-shell/presentation files; presentation/actual-action tests and UI lane handoff. Leave the shared model and profile/capture cores to their assigned owners.

**Consumes:** Existing SessionApplicationModel command/state ports, exact speechSetup snapshot seam, existing ProfilePreparationView.

**Produces:** A clean normal launch, compact live surface, separate Context/Settings access and functional current-answer actions.

- [ ] Split existing view/window presentation into the named components; retain a single real session model and bind only the live window to own-window actions. Use measured Cluely proportions as a familiar visual target with Relay assets.
- [ ] Move source/permission first-run tasks and technical overrides to appropriate setup/Settings. Observe real managed setup progress/recovery; preserve inert fixtures and actual stop availability.
- [ ] Keep current-question Help, current answer copy/detail, automatic replacements, context status and profile import/review/revoke working. Implement no decorative typed/history/mode controls before their ports exist.
- [ ] Verify command routing/state eligibility and build the actual SwiftUI app. Produce inert synthetic Home/live/paused/preparing/error visual artifacts for review without live account/capture actions. Record locked-Mac limitations honestly.
- [ ] Commit/push isolated own deltas and lane handoff. Declare imported automatic API dependency and exact own commits for independent review.

## Task3: My Context simplification

**Owner:** Controller, disjoint ProfilePreparationView and pure profile presentation file/tests. The existing approval/vault/lifecycle authority stays unchanged. The bounded read-only memories command/controller/browser refinement in the shared contract makes saved-memory correction usable without typed internal keys.

- [ ] Make Add résumé/project/job clear tasks. Move source fingerprints/spans/revision and correction-key tooling into Source details/Advanced review; preserve selected-file and explicit ownership/approval/reject/revoke actions.
- [ ] Generate a stable source/fact-bound default claim key when the user has not entered an advanced topic, without inventing ownership, changing claims or approving automatically. Keep explicit replacement lookup for advanced correction.
- [ ] Add the bounded active-approved-memory reader, native DTO/paging with lifecycle fencing and saved-fact selection for correction. Test rejected paging inputs, exact UTF8 byte bounds/no truncation, revocation/currentness and late response after lock.
- [ ] Verify identity/default-key/ownership eligibility and existing review command routing. Build profile and joined app; record only actual observed states.

## Task4: Review and join

- [ ] Compare exact own deltas against frozen parents and reproduce material findings. Return fixes to original owners, then narrow re-review.
- [ ] Join accepted source with clear dependency provenance. Run affected packages and one full meaningful synthetic integration/build gate, then publish HANDOFF/BUILD_STATUS and portable reviews.
- [ ] Continue through the full REA parity inventory: real typed requests/quick actions, transcript/activity/modes, history and account setup are subsequent end-to-end feature tasks. The first UI/setup delivery does not close the full owner goal.
