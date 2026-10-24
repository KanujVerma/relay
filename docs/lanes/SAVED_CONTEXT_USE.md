# Saved context use across sessions

Owner-assigned lane, GPT-6.1 Sol extra-high. Frozen base30fbf85f1f5572f50e738153c90e9e850fe56fcd. Isolated work/relay-saved-context-use, branch feature/saved-context-use-2026-10-23. Approved design: controller coordination saved-context-reopen-design-2026-10-23.md. Root owns actual SessionApplicationModel/adapter/Start/End/AI/typed hooks; this lane does not edit them, Package.swift, global docs or prior UI/review branches.

Plan: first publish tested existing-vault-only ProfileController open plus synchronous/idempotent beginClose API; then the preference/operation coordinator and minimal View Open/Lock overrides; finally actual synthetic helper restore/Lock/lifecycle tests and scoped review. Existing encrypted ProfileVault remains the only facts store. One settings Boolean remembers explicit use; no missing-vault auto-create, automatic approval or new auth/framework/wire.

Profile API foundation targets `openExistingProfile() async -> ProfileOpenOutcome` (opened/missing/unavailable/stale) and `beginClose() -> Task<ProfileCloseOutcome,Never>`, preserving `openProfile()` and `close()` behavior for existing callers. Coordinator/Model currentness uses required native binding/Start guards and owned operation IDs. Explicit Lock disables use before await; internal helper retirement preserves the preference; requested restore failure aborts that Start.

## Tested API foundation

The existing-only open and synchronous/idempotent close APIs are implemented. Initial tests failed on the absent APIs before production edits. Five new tests cover missing-vault zero key/backend/filesystem creation, synchronous visible/lifecycle retirement, repeat close sharing an actual held lock receipt, late load returning stale while real emergency cleanup is still held, and reentrant invalidation joining the same close. The callback-join check first failed with two invalidations, then passed after reserving the close owner before callbacks. MainActor client IO still begins only after the synchronous retirement method returns.

Full profile package29 tests passed, zero failures; log `/private/tmp/relay-saved-context-foundation-profile.log`. Existing24 tests include actual synthetic helper/approved-memory/lock-emergency/vault boundaries. The five new foundation cases use real ProfileController/ProfileClient/temporary encrypted vaults with fake keys and held command receipts. No real profile, Keychain/account/capture/private material or default settings were used.

The coordinator and View overrides below are implemented on top of this independently accepted foundation. The actual Model hook remains root-owned. These profile APIs alone do not restore context automatically in the app.

## Coordinator API checkpoint

The core coordinator and one Boolean settings adapter are now implemented, with injected preferences/native retirement in tests. Public API:

```swift
SessionContextUseCoordinator(preferences: any SessionContextUsePreferences,
                             onInvalidate: @escaping @MainActor () -> Void)
// Production convenience: init(onInvalidate:) uses the one UserDefaults Boolean.
ProfileUseTarget(controller: ProfileController, bindingID: UUID,
                 isCurrent: @escaping @MainActor () -> Bool)
func openFromUserAction(target: ProfileUseTarget)
func lockFromUserAction(target: ProfileUseTarget)
func restoreBeforeSession(target: ProfileUseTarget, startIntentID: UUID,
                          isStartCurrent: @escaping @MainActor () -> Bool) async -> SessionContextRestoreResult
func retireForHelperChange()
func waitForQuiescence() async
```

Observable snapshot fields are useInSessions/status/isBusy/message; computed isBusy reads actual operation ownership. Result is disabled/ready/missing/unavailable/stale/busy. Both native guards are mandatory. Root must recheck its Start/native admission after restore and join the coordinator with existing capture/helper barriers. An off preference never proves an old close has finished. A different target cannot inherit an old controller's ready state or start loading while old work retires.

Seven coordinator tests passed using real synthetic ProfileBridge children and fictional encrypted vaults. They cover default-off zero work, missing-vault no create and reachable opt-out, actual approved fictional fact restore in a fresh helper with unchanged encrypted bytes/no new key, explicit Lock retention, pre-registration Lock with zero helper/vault creation, Lock during ready delivery and serialized binding replacement. The last two were red before adding final returned-admission checks and the different-target retirement guard. Delayed cancellation is scoped to the owned operation UUID. Snapshot publication drains synchronous observer changes so a ready event cannot overwrite a nested Lock state.

The full profile package passed36 tests, zero failures, at this checkpoint (`/private/tmp/relay-context-coordinator-checkpoint-profile.log`). The foundational Controller code remains unchanged from accepted56f9558; new work is coordinator/preferences/tests only. A target binding must remain the actual stable profile/controller lifecycle through lazy child binding, with the caller's real current-binding guard; it must not be invented from a JSON field or restamped after completion.

## Final profile/UI-port candidate

The coordinator now checks each coalesced caller's own native binding/Start guard before joining and after awaiting the shared load. A caller cannot inherit another caller's currentness merely by presenting the same Start UUID. The original operation guard still governs the shared load. These checks were red when only the first caller's guard was consulted, then green with independent caller checks.

`ProfilePreparationView` preserves its existing initializer with optional additions:

```swift
init(controller: ProfileController, role: String? = nil,
     sessionUse: SessionContextUseSnapshot? = nil,
     onOpen: (@MainActor () -> Void)? = nil,
     onLock: (@MainActor () -> Void)? = nil)
```

The app wrapper must observe the actual coordinator and pass its current snapshot plus synchronous Open/Lock closures. `ProfilePreparationActions`, used directly by the View, routes those commands. The default standalone Lock calls `beginClose()` synchronously; default Open retains explicit create behavior. Lock stays reachable during controller/coordinator work and when remembered use is enabled but restoration is missing/unavailable. Import/review/Open content remains disabled during work. View construction and appearance perform no IO. Visible copy explains that Open enables saved context for future sessions and Lock turns that use off. Only actual `controller.opened` exposes the facts workspace.

Fifteen coordinator/action cases now use actual synthetic Python ProfileBridge children, real client/controller and encrypted fictional temporary vaults with fake keys/preferences. In addition to the seven checkpoint cases, they cover:

- cancellation while an actual `load_commit` response is held after helper acceptance, retaining busy ownership until that late delivery joins even after the original child has been reaped;
- revoked native Start or binding during load, rejecting/closing the original provider;
- explicit repeated Lock during a held load, synchronous preference retirement and no replacement-helper activity;
- corrupt-vault preservation, fixed error copy and zero key creation;
- each coalesced caller's guard at entry and after joining;
- an obsolete coalesced waiter's cancellation after ready publication, preserving the replacement ready use;
- the actual View action adapter's synchronous Open/Lock routing and opt-out availability after missing restoration.

The two action tests were red on the absent adapter, then green. As a mutation check, changing only the captured-operation cancellation to unscoped current-operation retirement made the obsolete-waiter regression fail with two assertions (opened state lost and closing instead of ready). The exact source was restored before final verification.

Final full profile verification: **44 tests passed, zero failures**, including all 15 new coordinator/action cases and five accepted foundation cases; `/private/tmp/relay-saved-context-final-profile.log`. The `relay-profile-prep` product also builds; `/private/tmp/relay-saved-context-final-product.log`. Test interpreter was explicitly `/private/tmp/relay-answers-venv/bin/python`; owned Swift caches stayed under `/private/tmp`. The only warnings concern the deprecated `--skip-update` flag and sandbox-disabled user-level SwiftPM caches. No real profile, standard preferences, private files, Keychain, account, capture or model operations were used.

Existing ProfileVault encryption/key policy, ProfileClient strict bridge/close semantics, source confirmation/revocation and current-fact provider are reused unchanged. This lane adds no dependency, framework, wire, second store or fact approval. The accepted foundation Controller source remains unchanged by the coordinator/View followup. The actual restored fictional fact is retrieved from the fresh helper's `current_claim` command after loading the same encrypted vault; saved bytes remain unchanged and only the existing key is read.

## Root integration and limits

Root owns actual Model/adapter creation, stable native profile-binding identity/currentness, Start/Resume/End/AI-mode hooks and joined publication/capture tests. A binding ID must remain stable through the first lazy helper launch; an initial helper UUID that rotates during binding is unsuitable. Guards must inspect actual current/retired native ownership. Root must join `waitForQuiescence()` and existing helper/capture barriers, then recheck its Start intent before capture. A requested result other than ready must abort Start with fixed recovery; disabled skips all profile IO only after prior owned work has joined. Internal retirement preserves preference, while explicit Lock disables it synchronously.

The package candidate is ready for scoped review, not a claim of delivered automatic app restoration. Actual app restore-before-first-question and End/AI replacement wiring are pending root's integration. The Mac stayed locked; visible UI acceptance and private-user operation were not performed. No user data/default preferences are used by tests.
