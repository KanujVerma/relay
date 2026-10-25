# Independent My Context review

Reviewed 2026-10-23, GPT-6.1 Sol extra-high. Verdict: **one actionable P2 correction-path finding; narrow fix required before accepting this delta**. No other material findings in the reviewed scope.

Frozen candidate: `62a1f8540681ee8b1317018cdfcf8875329d9671`. Parent: `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`. Nine changed files,702 additions/154 deletions. Binary diff SHA256: `3c44039246e396fc7ba7d39aa718cd10ab567fe4028b540ebc9b176a7effe77d`.

Review checkout: `<workspace>/work/relay-review-context-62a1f85`, detached at the frozen head, clean after review. Candidate/peer/root source was not modified. No commits, pushes, agents, actual credentials, Keychain, private files, capture, OS permission or inference were used.

## Finding

**[P2] Preserve the selected saved claim key through correction.**

Location: `spikes/macos-profile/Sources/RelayProfile/ProfilePreparationView.swift:275`, with computed-key guard at28-33 and `ProfileReviewPresentation.swift:7-11`.

The existing storage contract accepts saved keys containing `_`, `:` and `-` (`personal_brain.py:457-462`). Clicking Correct this fact sets `topic` and `lookupKey` to the saved exact key and successfully looks up that original key. However, the view's computed `claimKey` runs the saved key through free-text topic normalization. For the valid key `atlas.component_v1`, it becomes `atlas.component.v1`. The `earlierFact` guard then hides the successfully looked-up original fact because `lookupKey != claimKey`.

Save to memory consequently sends the normalized different key and no replacement identity. It creates a second approved fact and leaves the selected old fact active, instead of performing the requested correction. This affects valid previously saved/helper-created keys using those separators; newly generated `reviewed.<digest>` keys happen not to trigger it. It does not bypass ownership approval, but it breaks the saved-memory correction flow and can retain contradictory approved facts under different keys.

Reproduction used the actual candidate `ProfileReviewPresentation.swift` compiled with a small synthetic Swift probe, then actual `ProfileBridge` selection/approval/current_claim/memories operations with fictional Atlas data. The probe mirrors the view's exact earlierFact predicate. Result:

```json
{
  "saved_key": "atlas.component_v1",
  "selected_correction_key": "atlas.component.v1",
  "actual_button_lookup_present": true,
  "earlier_fact_visible": false,
  "active_facts_after_ui_shaped_save": 2,
  "old_fact_still_active": true
}
```

Proof: `/private/tmp/relay-context-review-62a1f85/probes/correction-key.swift` and `correction-key-result.json`. This is source/pure-presentation/helper reproduction, not a claim of clicking the locked Mac UI.

Keep a selected saved-key identity separate from a newly typed topic, preserve that exact key for lookup/review, and clear the selection when the user edits the topic or the pending card changes. Add a regression that selects each valid separator form, shows the original fact, requires explicit replacement and leaves exactly the replacement active after Save. Do not loosen the inherited conflict/ownership checks.

## Confirmed preservation

- The default SHA256 key uses length-prefixed source/fact identifiers, not source text or guessed ownership. It is stable, bounded and separates the two identity boundaries.
- Normal approval still requires explicit self/team/teammate ownership. The helper's original displayed-card fingerprint, source consent, revision and conflict/replacement checks remain the authority; presentation defaults do not approve anything.
- `memories` reads the existing `verified_claims()` authority filter. Pending candidates and revoked/replaced facts are excluded; viewing does not call on_change, issue a retrieval bundle or retire a valid bundle.
- The endpoint enforces integer1..8 limits, rejects booleans and malformed cursors/unknown fields, returns complete claims within14KiB JSON and retains cursor continuity when byte limits reduce a page. The inherited framed pipe remains16KiB.
- Native list application checks ownership, order, duplicate IDs, counts and cursor metadata. Paging deduplicates accumulated rows. Mutation/revoke refreshes the read view; close clears it. Lifecycle guards prevent delayed source/memory/lookup responses from reopening or overwriting closed/fresh-controller state.
- Source labels and actor labels remain distinct. Team/teammate facts do not become claims about the user's individual work. Bound role and selected-file/review/vault/provider/capture boundaries were not changed.

## Verification

- Six new Python memory-browser tests: **6 passed**,0.020s, existing `/private/tmp/relay-answers-venv/bin/python`.
- Full scoped `spikes/macos-profile` package: **23 passed**, zero failures,6.531s test time after18.44s build. Actual synthetic helper persistence, paging/revoke, close/reopen, late response, emergency shutdown and process reaping tests ran. Own scratch/module caches were under `/private/tmp/relay-context-review-62a1f85`.
- Synthetic correction probe above reproduces the finding against the frozen source and real helper engine.
- `git diff --check` passed. Checkout HEAD and binary diff hash verified; working tree clean.

The complete own delta and lane contract were reviewed. Existing vault/BrainStore/provider/QA/capture implementations were treated as reviewed dependencies; no broad re-audit or unrelated full Python suite was run. No runtime UI appearance, real account, private-document conversion, actual Keychain or hardware acceptance is established by this review.
