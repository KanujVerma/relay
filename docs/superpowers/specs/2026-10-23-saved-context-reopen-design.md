# Saved My Context across sessions: brief design proposal

2026-10-23. Native/profile lane, GPT-6.1 Sol extra-high. Base: canonical accepted root `30fbf85f1f5572f50e738153c90e9e850fe56fcd` (runtime `a4789b5`), including Context `fe6aad7`, UI `a100cd9` and automatic speech `5aa65cb`. Controller approved the existing-only restore, remembered explicit use, Start-aborts-on-requested-restore-failure policy, synchronous owned close prefix and minimal view action overrides. Implementation is active in PR84; actual Model/adapter integration stays root-owned. Old UI/review branches stay frozen.

## Recommended behavior

Reuse the existing encrypted ProfileVault, actual ProfileController/ProfileClient and permanently bound shared-helper port. Add one remembered settings Boolean, **use saved context in sessions**, default false. It stores no facts, source text, key, identity or account data. This is a use preference, not profile readiness or new approval authority.

Explicit **Open My Context** enables that preference synchronously and begins the existing explicit open/create flow. Show a short explanation that Open enables saved context in later sessions until Lock. If opening fails, report unavailable; the preference can still be turned off with Lock without a successful decrypt. Merely constructing/opening the workspace window does nothing.

Explicit **Lock** synchronously disables the preference, retires the preference/operation generation and existing personal display/request admission, then owns actual profile close/cleanup. Keep Lock reachable while opening/restoring and when use is enabled but the controller is currently closed. End, Pause/helper replacement and AI-mode teardown retire the current operation/provider normally but preserve the user's preference. Only explicit Open re-enables after Lock.

At the next authorized Start/Resume, after speech/source checks but before capture/questions, root asks the current profile target to reopen **only an existing** encrypted vault. A missing vault returns missing without key creation, `new`, snapshot save or helper load. A valid vault loads through the current helper and existing source/approved-fact semantics. Already-open context in the same actual binding is reused. A new helper never inherits an old controller's ready state.

Recommended failure policy: when remembered use is enabled, missing/corrupt/denied/unavailable restoration aborts this Start with a fixed message. The user can Open My Context to recover or Lock it and retry without personal context. Do not silently start while implying that requested saved context loaded. Preference disabled bypasses all vault/key/profile work. No automatic import, fact approval or second personal store.

## Narrow ports and ownership

The following are proposed interfaces, not frozen source signatures:

```swift
// Existing actual controller; automatic use never creates a vault.
func openExistingProfile() async -> ProfileOpenOutcome
// Outcome: opened / missing / unavailable / stale; actual opened state remains authoritative.

@MainActor final class SessionContextUseCoordinator: ObservableObject {
    var useInSessions: Bool { get }       // injected settings preference
    var snapshot: SessionContextUseSnapshot { get }
    func openFromUserAction(target: ProfileUseTarget)
    func lockFromUserAction(target: ProfileUseTarget)
    func restoreBeforeSession(target: ProfileUseTarget,
                              startIntentID: UUID,
                              isStartCurrent: @MainActor () -> Bool) async -> SessionContextRestoreResult
    func retireForHelperChange()         // preserves preference
    func waitForQuiescence() async
}
```

`ProfileUseTarget` contains the actual current controller, native helper/profile binding ID and a required synchronous `isCurrent` guard supplied by root from real model ownership. Restoration separately requires the actual native Start-current guard; a caller UUID alone proves nothing. Each operation captures its own UUID, the use-consent generation, binding and Start intent. Recheck them after awaits and immediately before reporting ready; delayed cancellation targets only its owned UUID. No default always-true guard.

One owned open/restore/close operation remains busy until actual underlying work returns. Same-intent calls may coalesce; a different intent/binding cannot reuse old authority or start before old cleanup. A controller busy with import/review/close is never treated as ready; root blocks Start until that actual operation finishes. Lock, cancelled Start, End and helper changes retire the old operation before any await. A late load is closed against its original controller/old bound port and cannot mark a replacement ready. Root keeps actual Start blocked until the same-intent restore outcome and its real capture/helper barriers permit admission. Disabling use on an already closed idle controller must not launch a helper merely to send Lock.

**Requested small close seam:** factor the existing ProfileController.close synchronous prefix into `beginClose()` returning its owned close task, with `close()` awaiting that same task. It immediately rotates lifecycle, clears visible facts, invokes existing onInvalidate and sets busy before task scheduling. This avoids a Task-only UI Lock leaving an old open result visible until the task runs. Preserve existing ProfileClient lock acknowledgment/emergency shutdown; no new wire/client/store framework. Root supplies the synchronous personal admission retirement and joins the result in its actual model hook.

ProfilePreparationView gains optional synchronous Open/Lock action closures and the use-enabled state. Defaults preserve the standalone demo. Root's app wrapper passes real coordinator actions; move the existing busy disable onto import/review content so Lock remains available during restore. No layout rewrite or new mode/account/transcript behavior.

Proposed lane files: new coordinator/preference types and tests in macos-profile; minimal ProfileController existing-only open and close-prefix reuse; minimal ProfilePreparationView action overrides/Lock availability; lane handoff. No ProfileVault format, ProfileClient wire, Python provider or package/dependency changes. Root owns SessionApplicationModel, adapter creation/actual binding guards, Start/End/AI hooks, typed admission and joined app tests.

## Focused acceptance

- Default disabled construction/Start: no vault/key/helper command or file creation. Explicit Open enables; internal close/replacement preserves preference; explicit Lock disables before any await and stays disabled across a new coordinator.
- Existing-only open: missing vault performs zero `new`/save/key-create calls. Corrupt/denied data is preserved and yields a fixed unavailable state. No reset/delete or plaintext persistence.
- With fictional data/fake keys and the actual synthetic helper: approve one source fact, close old helper, restore a fresh helper from the same vault and retrieve only the same currently approved/source-valid fact. No transcript or generated text becomes a fact.
- Hold a load/close response: Lock/cancel/helper replacement fences late ready/state, new Start stays unavailable until actual join, and an obsolete callback cannot cancel/reopen a replacement. Test original-bound-port ownership and failed-lock emergency retirement.
- View action routing: Open/Lock use the override ports; Lock remains reachable during restore/unavailable state. No clipboard/file picker/real Keychain/account/capture action in tests.
- Root joined proof: current authorized Start restores before capture/first question; disabled/locked skips restoration; failure cannot display unsupported personal claims; normal End/AI helper replacement loads the actual saved facts into the next actual helper. Core coordinator alone is not product delivery until this hook is joined.

## Controller approval recorded

Approved as stated. The lane starts from frozen build/saved-context-use-foundation-2026-10-23 at30fbf85. API foundation56f9558 is published with29 profile tests pass; coordinator/View and actual root app hooks remain incomplete. Missing/corrupt/denied restoration must never create a vault or silently imply personal context is ready. Explicit reachable Lock/use-off permits a subsequent session without personal context.
