# Local macOS signing for protected storage

The stock offline builder's ad-hoc signatures establish artifact integrity for
synthetic tests. Normal native protected storage additionally requires a
legitimate Mac provisioning profile and an authorized main executable.
Data Protection Keychain access belongs to that main executable, including
calls made by imported libraries.
[Apple TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).

The owner-approved current Mac setup proved the distinction: an exact unique,
non-secret device-only Add failed with-34018 before proper signing, then passed
with0 and removed its own test item with0 afterward. No user credential item
was read, reset or deleted by the probe. [Sanitized result](evidence/2026-10-24-signing-and-cleanup-result.json).

## Obtain and validate signing authorization

Use an owner-authorized Apple development team, certificate and matching macOS
profile for `com.relay.session`. The ordinary Xcode automatic-signing workflow
can obtain the profile and register the Mac if needed; developer-account and
device-registration actions require the owner's specific authority. A paid
membership requirement is not assumed. Keep profile/device/certificate identity
details and raw signing logs local.

Validate the embedded profile's platform, expiration, team, app-identifier
pattern, allowed Keychain groups and signer against the intended identity.
Current local proof uses exactly one default group, derived from the profile's
`ApplicationIdentifierPrefix` and `com.relay.session`; this prefix need not be
guessed from a display name. The current obtained profile expires
2027-10-25T03:13:13Z. Renewal must preserve the intended identity/group and fixed
key purposes so existing encrypted data remains usable.

Never manufacture entitlement strings on an ad-hoc signature as an authority
substitute. The actual matching profile and signing identity must authorize
them. [Apple Keychain groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps).

## Apply to an already verified app

1. Check the resource budget and preserve one independently verified current
   app. Quit only the app being changed through its normal shutdown, joining
   its helper/control work. Preserve original unrelated prototypes.
2. Verify the new stock app's clean embedded source provenance, helper hash,
   native audit and current signatures. Its bundle identifier must match the
   authorized profile. Keep an exact before inventory.
3. Put the validated profile at `Contents/embedded.provisionprofile`. Prepare
   a minimal entitlement plist containing the authorized
   `com.apple.application-identifier`, `com.apple.developer.team-identifier` and
   the single intended `keychain-access-groups` entry. The normal app does not
   need a debug `get-task-allow` entitlement for this step.
4. Sign the outer app with the authorized identity, without recursively
   changing the frozen helper after its manifest was produced:

   ```sh
   codesign --force --sign "$RELAY_SIGNING_IDENTITY" \
     --entitlements "$RELAY_ENTITLEMENTS" "$RELAY_APP"
   codesign --verify --deep --strict "$RELAY_APP"
   codesign --verify --deep --strict \
     "$RELAY_APP/Contents/Helpers/RelayRuntime.app"
   ```

5. Recheck the signed entitlements against the profile, all native dependencies
   and preservation of the original witness. The main executable's whole-file
   hash changes during signing; compare its file-backed Mach-O sections to
   establish unchanged code/data. In the current proof only the main signature,
   outer CodeResources and new profile changed. The frozen helper and clean
   source provenance hashes stayed identical. All100native audits passed.
6. Relaunch that exact app path. Complete normal owner ChatGPT sign-in and plan
   approval. Account selection/AI-on alone does not prove a current nonempty
   model catalog or a usable native inference selection. Measure actual answers
   only after those gates work.

This is local development signing, not a notarized distribution or installer
claim. Build/profile/certificate failures must retain the current app and data;
storage is not weakened and no key reset or conventional API-key fallback is
part of recovery.

## Real-account XCTest hosting

Generic `xctest` does not gain Relay's Keychain access by importing its module
or pointing `bundleURL` at the packaged helper. Use standard application-hosted
tests: the source-equivalent Debug app has module `RelayPanelSession` and
`ENABLE_TESTABILITY=YES`; the test bundle uses `TEST_HOST` and
`BUNDLE_LOADER=$(TEST_HOST)` for that authorized main app. Its `Bundle.main` and
main executable must match the verified host, with the frozen helper/resources
staged before final signing. The ordinary app entry stays unchanged/idle and
has no process-level fixture or developer-Python flags.

Keep real acceptance opt-in and bounded. Test-owned models use inert non-account
controls and the real default account/preparer/protected factory. They do not
change stored Learning settings merely for setup. Close the ordinary setup app
before another account-control owner restores the connection. Debug-host timing
does not by itself measure the unchanged stock Release artifact.
