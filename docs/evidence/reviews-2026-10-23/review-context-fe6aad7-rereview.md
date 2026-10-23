# My Context correction re-review

2026-10-23, GPT-6.1 Sol extra-high. **Accepted. The original P2 is resolved; no new actionable finding in this narrow delta.**

Frozen head: `fe6aad710b0109a964f823af42e8f89d440be90a`. Parent: `62a1f8540681ee8b1317018cdfcf8875329d9671`. Four files,86 additions/14 deletions. Binary diff SHA256: `937b74db3c06a1f1515aecd8f572a37b64647754da7b96aa996be2ab1d8ac5a3`.

The clean detached review checkout was advanced from the prior frozen review using only the local candidate repository. The complete four-file own correction was read. No candidate/root/peer source edits, commits, pushes or additional agents. Typed design remains frozen as requested.

## Original finding and correction

The original review is [review-context-62a1f85.md](review-context-62a1f85.md). A valid saved key such as `atlas.component_v1` was normalized to `atlas.component.v1` after selection. The original lookup succeeded, but key mismatch hid the returned fact; Save created another active fact without replacement.

The new selectedCorrection value retains the exact saved ProfileMemoryFact. The computed key returns its stored claimKey verbatim, independently of free-text topic normalization. Lookup metadata must match that exact key, and the returned fact ID must match the selected fact ID. Approval requires both a matched existing fact and explicit replacement confirmation whenever selection exists. Missing/failed/stale selected lookup cannot fall back to creating a fresh key.

Selecting a saved fact no longer writes topic, avoiding a delayed free-topic onChange that could clear the selection. The topic observer is inactive while selection exists; Clear selection and pending-card change explicitly retire selection/confirmation. The original free-topic normalizer and source/fact default hash remain unchanged. Original helper fingerprint, actor, conflict/replacement, source, reader, vault and authority code was not changed by this correction.

## Reproduced evidence

Recompiled the candidate's actual ProfileReviewPresentation.swift with the original synthetic correction shape, then used actual ProfileBridge select/approve/current_claim/memories operations. The same saved-key example now yields:

```json
{
  "saved_key": "atlas.component_v1",
  "selected_correction_key": "atlas.component_v1",
  "actual_button_lookup_present": true,
  "earlier_fact_visible": true,
  "missing_match_can_approve": false,
  "unconfirmed_can_approve": false,
  "confirmed_can_approve": true,
  "active_facts_after_ui_shaped_save": 1,
  "old_fact_still_active": false
}
```

Proof files: `/private/tmp/relay-context-review-62a1f85/probes/correction-key-fixed.swift`, `correction-key-fixed-result.json`. Original red proof files are retained alongside them.

The new actual-helper regression independently exercises underscore, colon/hyphen and backend case-canonicalized keys, preserving the exact selected ledger key and leaving only the replacement active. Existing free-topic normalization/default-key and approval tests remain in the focused run.

## Checks and limits

- Focused ProfileReviewPresentationTests: **7 tests passed, zero failures,1.199s**, after4.70s incremental build. Log: `/private/tmp/relay-context-review-62a1f85/rereview-native.log`.
- Original synthetic bridge/presentation reproduction: green above, including missing-match and missing-confirmation negatives.
- `git diff --check` passed; exact head/diff hash verified; review checkout clean.
- Python runtime, reader, native controller/vault and capture are unchanged, so the broader suites were not repeated. Prior six Python reader tests and23 native tests were independently passed at62a; this re-review covers only the correction.

All data and keys were injected synthetic fixtures. No real private file, Keychain item, account, capture, permission, external model or network inference was used. The Mac remained locked; this is source/presentation/helper evidence, not visible UI acceptance.
