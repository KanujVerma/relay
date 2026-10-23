# Automatic speech setup lane

Branch `feature/automatic-speech-setup-2026-10-23`, isolated clone `work/relay-cluely-automatic-speech`, base `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`. Root owns shared contracts/assembly, UI owner owns views/Settings/window shell. This lane owns managed speech assets/coordinator, narrow capture policy initializer and app-model startup/cancellation bridge. No event/lease/controller, Python, profile, image or capture-teardown refactor.

## API/manifest foundation checkpoint

The fixed21-file manifest pins the existing Parakeet EOU120M320ms and Silero unified256ms v6.2.1 dependencies to immutable revisions and SHA-256,225,301,695bytes total. `SpeechSetupCoordinator` exposes the frozen stage/progress/recovery/busy API, coalesces one owned operation and keeps cancelled work busy until it actually returns. `PreparedSpeechAssets` construction is internal; it represents verified dependencies/policy, never recording, microphone or account permission.

This checkpoint is deliberately partial. The default preparation port currently returns a truthful unavailable error and performs no network/model work; managed store/downloader and automatic Start are the next implementation step. The existing model start path has not yet switched to managed assets. UI may compile against this immutable API dependency but must not claim automatic provisioning is delivered from this checkpoint alone.

`model.speechSetup` is inert and injectable; existing `start()`, new `cancelPreparation()` and `retryPreparation()` are the stable adapter names. Advanced `asrFolder`/`vadFolder`/explicit local-model policy inputs remain for controlled overrides; they do not belong in normal Home/session flow. Root/UI do not edit this model file concurrently.

Foundation tests were first red on absent types/API. Three focused native tests pass for inert construction, one shared preparation, actual cancellation join/late-result rejection and pinned manifest/path/hash validation. The actual app fixture/API test also passed: injected setup remains untouched during model construction, fixture start and actual helper shutdown. No speech model or OS capture was invoked. Logs: `/private/tmp/relay-auto-speech-foundation-{red,green}.log` and `/private/tmp/relay-auto-speech-model-api-{red,green}.log`. Swift6 rejected a nested mutable weak capture during the first implementation compile; an immutable MainActor progress callback resolves that isolation error without weakening generation checks. Restricted LaunchServices notices in the app test did not cause a test failure. Diff whitespace check passed.

Next: implement streamed bounded public downloads and an owned atomic cache with full21-file validation, wire managed Start/cancel/join and add negative store/transport/app tests. No large weights, ASR model load, capture, OS permission, private source or account operation has occurred.
