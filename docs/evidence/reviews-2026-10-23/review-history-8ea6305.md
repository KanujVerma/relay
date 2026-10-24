# History core independent acceptance, 2026-10-24

Exact accepted feature source: **8ea630550a088863295f459741d606c4e42b72c0**, [PR93](https://github.com/KanujVerma/relay/pull/93). Frozen dependency ref: `build/generated-notes-history-foundation-2026-10-24`. This accepts the History core/account/preferences composition through that ref, not future manual-draft editor work or real device/user acceptance. It is not yet joined into canonical PR71.

## Original findings and corrections

1. Same-epoch reentrant Delete/DeleteSource during published History state could restore the outer selected/list state. Original fixture failed three assertions. Correction **60dcf669c8a65133bcbc46c5b118ef3a3b7b1036** drains actual private state synchronously after publication.
2. A read-only History observer could trigger actual Model End during transcript EOU, after which the outer consume appended an old private row. Original fixture failed two assertions. Correction **5f09cbb1225d9438a279900a63bbeb327b6dd2fa** rechecks sealed state and original session/epoch/event high-water after the optional observer.
3. A real quiesced audio-error stop had an observed cleanup end but could be projected as completed text. Original fixture failed nine assertions across capture error, shutdown timeout and consent revocation; a strict contradictory-restore fixture failed once. Correction **8ea6305** retains the original validated reason, adds the fixed capture-failure gap for non-user-stop receipts and rejects contradictory persisted projections. Original event JSON, text and observed end survive; unknown cleanup end is not fabricated.

Root read the tiny production corrections, inspected original fixtures and independently reran actual native tests. No request/capture permission, native authority, timeout, admission bound or protected-account boundary was widened. Canonical JSON fixture construction was corrected where floating-point timestamp spellings had previously caused unrelated rejection; typed production validation was not weakened.

## Independent observations

| Exact source | Root command scope | Result |
| --- | --- | --- |
| b3672f1e5dfc7c61fa56b115cb99457190674db7 | Original coordinator/application/timing findings plus capture/evidence/store/transcript, joined account and guide/image cases | 93 collected, 92 passed, one opt-in rendering skip, zero failures. Panel/core 47 cases in 6.707 seconds; application 46 cases in 38.361 seconds. |
| 8ea630550a088863295f459741d606c4e42b72c0, detached clean author checkout | `HistoryErrorStopTests`, `HistoryErrorStopRestoreTests`, `HistoryCaptureEndTests`, `HistoryEvidenceValidationTests`, `HistoryRootReviewTests`, `HistoryStoreTests`, `SessionTranscriptTests` | 32 passed, zero failures/skips; selected tests 2.001 seconds. Whole existing-cache command 17.334 seconds. |

Replay uses Swift test with automatic resolution disabled, the two-job resource limit, one retained History scratch root and its module/cache/config/security paths, and the existing test Python. The root-owned command had a 180-second external deadline and preserved its actual exit code, zero. Fresh resource checks admitted a 1 GiB reserve below the 25 GiB temporary cap and above the 30 GiB free floor. No new model/archive/environment/cache copy was needed.

Portable replay from the exact source, substituting already populated paths:

```sh
RELAY_TEST_PYTHON="$EXISTING_PYTHON" CLANG_MODULE_CACHE_PATH="$EXISTING_MODULES" \
swift test --disable-sandbox --disable-automatic-resolution --skip-update --jobs 2 \
  --package-path spikes/macos-panel --scratch-path "$EXISTING_HISTORY_BUILD" \
  --cache-path "$EXISTING_CACHE" --config-path "$EXISTING_CONFIG" \
  --security-path "$EXISTING_SECURITY" \
  --filter '(HistoryErrorStopTests|HistoryErrorStopRestoreTests|HistoryCaptureEndTests|HistoryEvidenceValidationTests|HistoryRootReviewTests|HistoryStoreTests|SessionTranscriptTests)'
```

The original coordinator fixture SHA-256 is `4e3d71fddf864682e2bee6b6ebfa641807e2557ed60b0cb0e3e0fa4b74520a2c`; application fixture `c81e64c4e0aa86f1be4e1e08d07edb5808d22b305e54600d3a597388f4994854`; prior timing probe `e23f56394adf8cebdee7aa898edaf0136c182e5789e363daa6b6c0f843086c2e`. They remain in the feature source or the existing public timing evidence. Local raw logs are retained outside Git; no host paths, environment dump or private transcript are published here.

No real account, Keychain, screen/audio capture, private transcript, paid inference, UI usability or answer-latency benchmark was exercised. Complete History editor/product and Notes schema/generation gates remain separate.
