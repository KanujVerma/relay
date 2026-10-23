# Saved context use across sessions

Owner-assigned lane, GPT-6.1 Sol extra-high. Frozen base30fbf85f1f5572f50e738153c90e9e850fe56fcd. Isolated work/relay-saved-context-use, branch feature/saved-context-use-2026-10-23. Approved design: controller coordination saved-context-reopen-design-2026-10-23.md. Root owns actual SessionApplicationModel/adapter/Start/End/AI/typed hooks; this lane does not edit them, Package.swift, global docs or prior UI/review branches.

Plan: first publish tested existing-vault-only ProfileController open plus synchronous/idempotent beginClose API; then the preference/operation coordinator and minimal View Open/Lock overrides; finally actual synthetic helper restore/Lock/lifecycle tests and scoped review. Existing encrypted ProfileVault remains the only facts store. One settings Boolean remembers explicit use; no missing-vault auto-create, automatic approval or new auth/framework/wire.

Profile API foundation targets `openExistingProfile() async -> ProfileOpenOutcome` (opened/missing/unavailable/stale) and `beginClose() -> Task<ProfileCloseOutcome,Never>`, preserving `openProfile()` and `close()` behavior for existing callers. Coordinator/Model currentness uses required native binding/Start guards and owned operation IDs. Explicit Lock disables use before await; internal helper retirement preserves the preference; requested restore failure aborts that Start.

## Tested API foundation

The existing-only open and synchronous/idempotent close APIs are implemented. Initial tests failed on the absent APIs before production edits. Five new tests cover missing-vault zero key/backend/filesystem creation, synchronous visible/lifecycle retirement, repeat close sharing an actual held lock receipt, late load returning stale while real emergency cleanup is still held, and reentrant invalidation joining the same close. The callback-join check first failed with two invalidations, then passed after reserving the close owner before callbacks. MainActor client IO still begins only after the synchronous retirement method returns.

Full profile package29 tests passed, zero failures; log `/private/tmp/relay-saved-context-foundation-profile.log`. Existing24 tests include actual synthetic helper/approved-memory/lock-emergency/vault boundaries. The five new foundation cases use real ProfileController/ProfileClient/temporary encrypted vaults with fake keys and held command receipts. No real profile, Keychain/account/capture/private material or default settings were used.

Preference/coordinator/View overrides and root Model integration remain pending. This foundation alone does not restore context automatically in the app. Root may import the immutable API checkpoint as a declared dependency while retaining actual Model/adapter ownership.
