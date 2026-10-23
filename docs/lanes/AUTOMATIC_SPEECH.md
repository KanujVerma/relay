# Automatic speech setup lane

Owner-assigned scope: automatic managed speech assets plus the app's existing Start/cancel/retirement bridge. Frozen parent `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`; branch `feature/automatic-speech-setup-2026-10-23`. The controller owns global HANDOFF/contracts/status and independently reviews the final delta. UI source belongs to the separate Cluely UI lane.

API foundation `d3a0ca3bd4bf0f844880d9126f2352152554bd89` exposes the fixed manifest, public observable snapshot/coordinator, internal-construction `PreparedSpeechAssets` and inert injectable app seam. The UI imported that immutable checkpoint; the foundation alone deliberately reported preparation unavailable.

## Implemented behavior checkpoint

Start now checks explicit source/conversation choices, prepares verified managed assets, rechecks the same uncanceled intent and audio choices, then starts the existing helper/native capture path. Construction and fixture mode perform zero speech preparation. Normal managed setup requires no per-start model acknowledgment. Advanced nonempty roots select an explicit local override: both roots and its acknowledgment are required, and the managed cache is not touched. `--asr-models`, `--vad-model`, and `--acknowledge-local-model-licenses` remain explicit advanced inputs.

The store owns only its named immutable manifest entry and UUID staging under Application Support/Relay/Speech/v1. It rehashes all 21 files on reuse, checks lengths/paths/regular-file identity, refuses symlinks, and atomically promotes a fully validated staged tree. It requires 1 GiB free before a cold fetch, uses at most two concurrent files and a 900-second download budget. A filesystem lock serializes same-root preparations. User-specified model folders and shared FluidAudio caches are never changed.

The foreground downloader has at most three attempts per file, bounded transient backoff/Retry-After, HTTPS-only redirect handling, no credential/cookie storage and measured byte progress. No dynamic registry, ambient account credential, archive extraction or cloud fallback exists. Cancellation remains busy until the actual transfer/children and Start owner return; late progress/assets cannot publish readiness or begin capture. Pause/End synchronously invalidate Start intent and cancel preparation, then join it through the existing native/helper teardown barrier.

The fixed model pins, sizes, policies and upstream reuse are recorded in [managed speech notices](../research/MANAGED_SPEECH_NOTICES.md). No ASR/VAD runtime loader or compute policy changes are included.

## Verification at behavior checkpoint

TDD red evidence: absent setup APIs, store/downloader APIs and managed policy initially failed compilation; the old Start path then failed the new managed-preparation/cancellation app checks. Focused green: 16 capture-package setup/store/downloader tests, plus 4 actual app model tests. Tests use synthetic bytes, real filesystem hash validation, injected URLProtocol through actual URLSessionDownloadTask, held uncooperative preparation, and the existing actual fixture helper/session path. They cover inert construction/fixture, coalescing, delayed progress, actual cancel join, managed-vs-explicit policy, cache/offline/corrupt/short/symlink/storage, HTTP/body/byte/credential/retry bounds, pre-cancel/expired download and app consent/offline/late-cancel behavior.

Commands use `swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-session --filter 'SpeechSetupTests|SpeechAssetStoreTests|SpeechAssetDownloaderTests'` and panel `--filter AutomaticSpeechApplicationTests`, with private `/private/tmp/relay-auto-speech-*` scratch/cache roots. Exact logs are `/private/tmp/relay-auto-speech-managed-policy-green.log`, `/private/tmp/relay-auto-speech-start-red.log` and `/private/tmp/relay-auto-speech-start-green.log`. The fresh app scratch initially could not fetch the public Nemo binary due sandbox DNS; copying the already pinned public artifact from this lane's private cache enabled the build. No peer cache/source changed.

Remaining before final acceptance: broader affected app checks/product build, additional resource/cancel negative tests, independent scoped review and optional real public asset provisioning. No large weights have yet been fetched, and no real model load, audio/OS permission, private file, account/Keychain, inference or visible UI flow has been exercised. The Mac remains locked. Asset-ready is not recognizer/capture/account-ready.
