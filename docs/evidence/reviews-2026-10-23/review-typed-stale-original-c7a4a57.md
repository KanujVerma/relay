# P2: cancelled expired typed frame loses its Stop receipt

Targetc7a4a57, UserQuestionCoordinator.cancel in relay_spike/user_question.py. Root confirmed in a clean detached review clone. Changes requested for this narrow defect; the original author confirmed the mechanism and owns its correction. This supersedes the preliminary no-finding state of the earlier core review checkpoint.

Valid ordering: host started at generation1; native issues typed question at2, then Stop at3. Deny-only retirement for2 is received before its held original frame. If that original question is older than its2s admission budget when delivered, question handling correctly rejects it without advancing host presentation. A fresh Cancel3 targeting the known retired question2 then fails `target_generation == h.presentation` because host is still1. No cancellation receipt is emitted, despite no target inference/worker. The native transport eventually reaches its15s pending cancellation timeout and fails/reaps the helper. The1.5s optional capture plus a2s per-frame write budget and bounded writer queue can outlast the original2s age budget; the freshly issued Stop must not require that expired original to have been admitted.

Control: identical order with a fresh original typed frame yields no inference but advances host presentation, so Cancel3 is accepted and emits answer_cancel_response with actual quiescence. Independent observed output:

```text
fresh original: original_admitted=false cancel_accepted=true helper_generation=3 native_cancel_generation=3 receipts=[answer_cancel_response] live=true
expired original: original_admitted=false cancel_accepted=false helper_generation=1 native_cancel_generation=3 receipts=[] live=true
```

Probe uses actual SessionHost and strict request decoders, tests.test_session_host.start and tests.test_user_question.question/retirement/cancel. Set original emittedUptimeNanoseconds to monotonic_ns()-2_100_000_000, send retirement, await handle_user_question, then construct fresh Cancel with presentationGeneration=original.presentationGeneration+1 (the real native progression, not helper.presentation+1). Drain actual host work and inspect receipts. No sleep, model call, asset, capture/account/private data or network is needed. Helper remains live and there is no target worker in the reproduction.

Required correction: fresh cancellation of a known pre-request/tombstoned target must finish even when helper has not advanced to that target generation; a target older than the helper's newer presentation must remain unable to cancel/advance it. Keep original question freshness, exact native generation step/anchor/identity, deny-only semantics and actual captured-worker join. Add expired-original/no-POST receipt proof and retain current old-target/newer-request negative. Do not broaden inference admission or fake quiescence.
