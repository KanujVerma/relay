# Paced local ASR comparison, 2026-10-24

Exact source `667298504d2dbb78e0ed3033b43ed61bf3c916f0`, conditional pipeline
`18f982c672a1c4671203af86a1a2e659be6640e2`. One controlled real local-model
gate passed: one case / zero skips / 41.097 s; command exited 0 in 75.360 s.
The normal factory was still `closedSpan` during this measurement. Root reviewed
the source and exact local receipt independently before approving a separate
narrow factory activation. No automatic real-gate rerun occurred.

Canonical [sanitized measurements](2026-10-24-asr-prefix-benchmark.json) retain
every source observation, full synthetic recognized text and exact source
indices. No cache paths, local environment dump, raw audio or private content is
included. The unchanged fictional WAVE SHA is
`98f0000e24688c1e665bd90de70d99b378b661bb749b483aeeed90cd5b2be9c7`.
The AVAudioFile decode actually supplied **38,912 mono Float32 samples at 16 kHz
(2.432 s)**. A prior `afinfo` estimate was higher; actual decoded/delivered
counts govern this record. No trim, repeat, regeneration, playback or copied
input was used. Both modes add the same 8,000 leading / 32,000 trailing silence
samples and 448 final-packet zeros, providing 79,360 paced samples per source.

| Local native stage | Baseline | Safe prefix |
| --- | ---: | ---: |
| Median VAD closure event → ASR final | 135.629 ms | 40.602 ms |
| Median reported VAD audio boundary → ASR final | 1,234.379 ms | 1,137.351 ms |
| Input acknowledged before closure, each observation | 0 / 40,064 | 35,840 / 40,064 |
| Input still unacknowledged at closure | 40,064 | 4,224 |
| Process maximum RSS | 723,107,840 bytes | 701,988,864 bytes |

The observed closure-stage saving is **95.027 ms, about 70.1%**. Reported-boundary
latency improves by about 97 ms; endpointing remains the larger local component.
Acknowledgement means `accept` returned, not that every buffered encoder sample
had been computed. The backend's existing internal zero padding is unchanged.

Each mode ran in its own sequential process with exactly two existing ASR
managers, one declared native warm-up and two paced trials. Each trial had fresh
actual VAD states and native source indices. Models/cache integrity were checked
before load and after the gate; cold setup/warm-up/integrity are outside the
endpoint interval. Cache verification retained all 21 hashes / 225,301,695 bytes;
no model or dependency download, account, Keychain, hardware driver or cloud
inference was used. Process ASR-load observations differed (1,682 / 486 ms);
they are not a controlled cold-load speed comparison.

Both sources in both trials recognized exactly **“how would you handle an empty
python list”** from original range **[6,592, 46,656)**. No fallback, source loss,
gap, text/cutoff mismatch or memory increase occurred. The controlled >10%
median-reduction and <=256 MiB RSS-increase conditions passed. These are four
correlated observations per mode on one fictional question, not a p95 or broad
accuracy benchmark. This does not measure the helper, cloud model, actual app
publication, window paint, usefulness or real interview performance. Those
remaining [end-to-end gates](../lanes/RESPONSE_LATENCY.md) stay distinct.

## Following narrow activation

After the measured gate, root approved normal local-source assembly selecting
safe prefixes. Only the normal `NativeCaptureSession` assembly helper changes;
generic `SourceComponents` still defaults to `closedSpan`. Its original
composition fixture reached API red in 33.035 s, then the full macos-session
package passed 87 collected / 84 passed / three explicit model/download/benchmark
skips (8.154 s command). The no-model selection case drives the exact production
assembly helper, native controller and real adapter with a fake backend, proving
prefix input before closure and one exact final. The measured JSON remains
unchanged: it records the earlier exact-667 comparison, not an activation rerun.
Broader actual speech and full-app/account gates remain pending.
