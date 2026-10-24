# Transcript sealed-purge correction: 3f18299

2026-10-23. Independent narrow re-review, GPT-6.1 Sol extra-high. **ACCEPTED at `3f18299e09e9cf6cc9fc522b17562f550d6bddcf`; original transcript P2 closed.** This does not accept the separate pending Help-after-denial fix or root Model/UI integration.

Fresh detached clone: `/Users/kanuj/Documents/ChatGPT/relay/work/relay-review-typed-3f18299`, clean before/after. Original `97b3671` clone and report remain frozen. Reviewed only parent97b ->3f: four files,56 additions/five deletions; binary diff SHA-256 `5913384f2ce3d221825fe7a87beb3ac2fa76a121f61f7ef93f9c86873449fe1b`. Production change is limited to the transcript store. Docs and two focused tests describe original-scope retirement while sealed.

The store now verifies original session/epoch and monotonic event sequence before its sealed branch. While sealed, ordinary events can only advance that replay fence; exact consent-revocation removal can purge the affected source and mark it unavailable. It preserves the paused phase and seal. No late final can add rows, and old-session/epoch events cannot clear replacement rows. Existing live row/schema/time/budget behavior is unchanged.

The **unchanged independent probe** now prints:

```text
paused=false rows=1 microphoneRows=0 phase=listening
paused=true rows=1 microphoneRows=0 phase=paused
```

Original97b printed two rows/one microphone row in the paused schedule. Probe source and portable compiler wrapper remain byte-for-byte unchanged under `typed-97b3671-probes`. Command:

```sh
bash work/coordination-2026-10-23/typed-97b3671-probes/run-probe.sh \
  /Users/kanuj/Documents/ChatGPT/relay/work/relay-review-typed-3f18299 \
  /private/tmp/relay-review-typed-3f-purge-proof
```

**22 affected native cases passed, zero failures,2.062 seconds**: `TypedAssistantTests|SessionTranscriptTests|TypedAudioHelperTests|AnswerCancellationTests`. This includes the two new paused-original/wrong-scope/replay/late-final/replacement cases, plus the five actual injected-native/helper held-EOU/PNG and completed-SSE proofs. Only focused suites ran; no broad suite expansion. Exact command, from corrected `spikes/macos-panel`:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-typed-97-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-typed-97-module \
RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python \
swift test --disable-sandbox --skip-update \
  --scratch-path /private/tmp/relay-review-typed-97-panel \
  --cache-path /private/tmp/relay-review-typed-97-cache \
  --filter 'TypedAssistantTests|SessionTranscriptTests|TypedAudioHelperTests|AnswerCancellationTests'
```

The scratch/cache directories are reviewer-owned; original-head logs were preserved before reuse. Durable result logs are `work/coordination-2026-10-23/typed-3f18299-probes/{native-22.log,unchanged-probe.log}`. The standalone purge probe constructs synthetic DTOs; actual OS consent and UI were not exercised. Actual helper tests use generated/synthetic input and HTTPX MockTransport, never real credentials or network inference.

No new actionable issue found in this correction. No root/author/source/index/HEAD edit, commit, push, real capture/permissions/Keychain/private files/account/model work or new agent occurred. This report accepts the denial-only purge fix, while the separately reported root Help-after-denial failure and pending app join remain distinct review gates.
