# Offline public-model speech acceptance

On2026-10-23, controller verified the accepted automatic5aa source with the existing public225,301,695-byte cache. This is an opt-in local model test, not ordinary CI, actual microphone/process-tap capture or an interview/account operation. Source parent is controller30fbf85 (runtimea4789b5). No production model/capture implementation changes were required.

The test loads **two independent actual Silero VAD and Parakeet EOU ASR instances** using the normal local adapters and allowDownloadfalse. Input is a generated fictional English question, “How would you handle an empty Python list?” Both VAD instances detect a start and end with equal boundary kinds; both ASR instances run concurrently and recognize the Python/list anchors. The full pinned cache is revalidated after CoreML execution, ensuring load has not invalidated its required files. No capture driver, helper/model provider, Keychain, screen, private file or network inference is used.

Final test: **1 passed,zero failures,7.837s**. Native processed input38,912 mono Float32 samples at16kHz (2.432s). Sequential initialization of the two VAD/ASR pairs took6,700ms. The remaining938ms includes both VAD passes, parallel ASR, assertion work and post-load225MB cache revalidation; it is **not** measured live first-answer or isolated ASR latency. Maximum RSS of this test process was1,297,268,736bytes (about1.21GiB). This does not establish whole-app memory under actual capture, sustained overlapping speech, long-session resource use or the future packaged runtime.

An earlier run before the post-load cache assertion also passed (6.933s,6,331ms load,427ms processing span,1,303,789,568-byte process max RSS). The final repeat was justified by the added cache-integrity check, not repeated to select a faster result. Both are one short synthetic fixture, not an accuracy benchmark. English punctuation/capitalization and live conversation quality remain separate.

## Reproduction

Use the accepted pinned manifest and prepare its public cache explicitly as described in the automatic lane. Generate a file without playback:

```sh
/usr/bin/say -v Samantha -r155 --file-format=WAVE --data-format=LEF32@16000 \
  -o /private/tmp/relay-synthetic-technical-question.wav \
  'How would you handle an empty Python list?'
```

The first sandboxed speech export produced an empty file and a denied sandbox extension; it was rejected as input. A scoped file-only TTS retry using the installed voice succeeded. No audio played or recorded. Validate nonempty mono16kHz Float32 input before testing; the test rejects missing/oversized/silent data.

```sh
RELAY_RUN_OFFLINE_MANAGED_SPEECH=1 \
RELAY_OFFLINE_SPEECH_CACHE=/path/to/verified-public-cache \
RELAY_OFFLINE_SYNTHETIC_AUDIO=/private/tmp/relay-synthetic-technical-question.wav \
swift test --disable-sandbox --skip-update --package-path spikes/macos-session \
  --filter OfflineManagedSpeechSmokeTests
```

Use owned writable temporary Swift module/scratch caches where required by the environment. A180-second outer deadline bounded compilation/test execution. Ordinary test runs omit these three environment variables and skip before any cache inspection/model load. No audio or model artifact is committed. Final logs also contain CoreML sandbox-extension warnings, but both models load, actual inference assertions pass and the cache remains valid. No lock/permission bypass or visible UI action was involved.
