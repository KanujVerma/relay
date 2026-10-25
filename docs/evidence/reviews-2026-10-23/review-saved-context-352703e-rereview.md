# Saved-context final busy-admission correction: 352703e

2026-10-23. Independent narrow re-review, GPT-6.1 Sol extra-high. **ACCEPTED at exact `352703e06a3960b517a22b5032e5c48e610ddc4b`.** The original P2 is closed; no new actionable finding in this correction. This accepts the scoped coordinator/library candidate, not the pending actual app integration.

## Immutable scope

Original report: `work/coordination-2026-10-23/review-saved-context-5b96fed.md`. New separate detached review clone: `/Users/kanuj/Documents/ChatGPT/relay/work/relay-review-saved-context-352703e`, clean before/after. Original frozen `5b96fed` clone remains unchanged and clean.

Reviewed only `5b96fed3bc071114e6acf4913d21ce12589a27d8..352703e06a3960b517a22b5032e5c48e610ddc4b`: three files, 37 additions/one deletion. Binary diff SHA-256: `9a268449b1e62deb5c158eb1f971e1d576630bcc9dbe2ceab552016ddc93f5a4`.

The only production change adds `!target.controller.busy` to the final synchronous `admitted(...)` predicate in `SessionContextUseCoordinator.swift:152`. Required preference/operation/controller/binding/Start checks remain. Tests add actual held `current_claim` and `select_begin` schedules at ready publication, including readiness retry only after the held work joins. Lane docs attribute old full-suite evidence to its original head. No accepted foundation, wire, client, vault, Python/provider, View, capture or Model source changed.

## Independent focused evidence

All **16 affected coordinator/action tests passed**, zero failures, **3.524 seconds**, using actual synthetic Python helper children, fake keys/preferences and fictional encrypted temporary vaults. The new regression also verifies a fresh same-binding restore becomes ready after the actual busy operation returns. Existing Lock, cancellation/coalescing, stale binding/Start and original-close ownership cases remain green.

Reused the original reviewer probes **without changing their injected test methods**. The portable runner verifies production source identity while copying inputs to independent temporary packages; it writes nothing into the supplied checkout.

| Exact-source schedule | Original 5b96fed | Corrected 352703e |
| --- | --- | --- |
| Ready observer starts actual lookup; hold accepted `current_claim` response | ready while controller busy, 10/10 | stale while controller busy, 10/10 |
| Ready observer starts actual edit; hold accepted `select_begin` response | ready while controller busy, 10/10 | stale while controller busy, 10/10 |
| No queued profile operation | ready and not busy, 10/10 | ready and not busy, 10/10 |

Corrected lookup probe: one test passed, **1.391 seconds**. Corrected mutation/control probes: two tests passed, **3.034 seconds**. These are the same actual-ready-notification/high-priority-work/background-waiter schedules that demonstrated the original defect, with no fabricated controller flags, helper responses or native envelopes.

## Exact commands and durable evidence

Run from the corrected clone's `spikes/macos-profile` directory:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-saved-context-352-review-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-saved-context-352-review-module-cache \
RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python \
swift test --disable-sandbox \
  --scratch-path /private/tmp/relay-saved-context-352-review-build \
  --cache-path /private/tmp/relay-saved-context-352-review-cache \
  --filter SessionContextUseTests
```

Run the unchanged reviewer probes from the Relay workspace, choosing fresh output directories:

```sh
python3 work/coordination-2026-10-23/saved-context-5b96fed-probes/reproduce.py \
  work/relay-review-saved-context-352703e \
  /private/tmp/relay-saved-context-352-review-mutation-control \
  --expected-head 352703e06a3960b517a22b5032e5c48e610ddc4b

python3 work/coordination-2026-10-23/saved-context-5b96fed-probes/reproduce.py \
  work/relay-review-saved-context-352703e \
  /private/tmp/relay-saved-context-352-review-lookup --mode lookup \
  --expected-head 352703e06a3960b517a22b5032e5c48e610ddc4b
```

Durable corrected-head logs, command receipts and production source hashes: `work/coordination-2026-10-23/saved-context-352703e-probes`. Original reproduction sources/logs remain beside the original report. Each corrected command exited zero. Final Git checks confirm both detached heads and empty porcelain status; the correction's changed paths are only the coordinator, its test file and lane documentation.

## Limits

This is a one-predicate correction re-review plus the necessary affected tests and unchanged independent probes. No full profile/native/Python suite or settled dependency re-audit was repeated. No actual app Start/Resume/End integration, UI, Keychain/default preferences, private files, account, capture, OS permissions or model/network inference was exercised. Root still owns native app wiring and final post-restore controller/coordinator busy/current-target/Start guards. Source/index/HEADs in author/root/frozen checkouts were not edited; only separate clones, temporary probe/build inputs and coordination evidence were written. No commit, push or additional agent was used.
