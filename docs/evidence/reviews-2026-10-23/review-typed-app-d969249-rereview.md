# Final typed basis-eligibility correction: d969249

2026-10-23. Independent narrow source/UI re-review, GPT-6.1 Sol extra-high. **ACCEPTED at `d969249baf1c5fc67666c503be0a1a1d5db2a736`.** The source-loss P2 in `review-typed-app-b431914.md` is closed. Together with the separately accepted transcript3f/backend72 and actual b431 integration tests, the assigned typed source scope is accepted.

Fresh detached clone `/Users/kanuj/Documents/ChatGPT/relay/work/relay-review-typed-app-d969249`, clean before/after. Reviewed only own correction: four files32 additions/seven deletions, binary diff SHA-256 `1ad639ab9c36cd1d2f9041ec58ff3e41b7f14d6c2e201fe4723aa09168b62946`. No accepted core or root lifecycle re-audit.

The snapshot now supplies `canSendAsNew` from the actual current session and bounded/nonempty/single-line draft validity; ordinary Send adds its retained-basis gate. Send as new refreshes and checks that real eligibility before clearing the basis. Composer uses this value and actual current-question Help eligibility; the duplicate app-running Boolean is removed. The new shipped microphone-only source-loss regression reflects the original defect. No wire, model, publication or source authority is added.

The **unchanged independent actual-native source-loss test passes**, one test, zero failures,0.002s:

```text
SOURCE_LOSS authorityStillPresent=true microphoneActive=false beforeBasis=true
SOURCE_LOSS afterBasis=true draftKept=true
```

Originalb431 returned `afterBasis=false` and failed the same assertion. The test source is byte-identical; only Package.swift dependency paths point at the new immutable checkout. Actual NativeSessionController is microphone-only with injected quiet components; there is no OS capture or model load. New temporary package `/private/tmp/relay-review-typed-source-loss-d969`; durable manifest/test/log copies: `work/coordination-2026-10-23/typed-app-d969249-probes`.

Exact command:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-review-typed-97-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-review-typed-97-module \
swift test --disable-sandbox --skip-update \
  --package-path /private/tmp/relay-review-typed-source-loss-d969 \
  --scratch-path /private/tmp/relay-review-typed-97-panel \
  --cache-path /private/tmp/relay-review-typed-97-cache --filter SourceLossTests
```

The earlier independent b431 ten actual app cases remain attributed to that exact source: zero failures,5.238s, including positive typed Help/card and all nine held-image cases. They were not broadly repeated for this four-file eligibility correction. Root separately reports its nine controller cases plus actual lifecycle; that is owner evidence, not this reviewer's independent run. Source review confirms the UI parameter removal and new call sites agree.

No further actionable issue found. No real UI, microphone/capture/permissions/private files/Keychain/account/network inference, source/index/HEAD edits, commit/push or new agent. The current eligibility correction is source acceptance; root's already-built170,779,443-byte release artifact is still attributed to its frozen04fe/b431 source and does **not** contain d969 until rebuilt. This report makes no newer artifact or physical-device acceptance claim.
