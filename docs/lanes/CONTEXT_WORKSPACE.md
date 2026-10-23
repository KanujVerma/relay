# My Context workspace candidate

2026-10-23. Controller-built lane from frozen1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7 on feature/context-workspace-2026-10-23. Scoped candidate awaiting independent review; no main merge or live private-file/Keychain/UI acceptance.

## Behavior

My Context now centers Add résumé / Add context, a plain-language review card and saved memory. The normal review requires explicit ownership and Save to memory, without manually typing an internal fact topic. A stable source/fact-bound SHA-256 key supplies the default; optional existing-topic normalization and explicit replacement remain for correction. Fingerprints, source spans/revisions and detailed correction options are disclosures. No model/speech configuration is added here.

The real saved-memory browser reads existing active, user-confirmed, fully consented claims through the same profile helper. It labels self/team/teammate distinctly, lists exact source-backed text and source label, and lets a pending statement select a remembered fact for actual existing-fact lookup and explicit replacement confirmation. Source count and reviewed-fact count remain separate. Revoke refreshes both; lock clears memory state. Viewing a list never confirms candidates or changes provider authority.

The read-only `memories` command accepts after:null-or-opaque-cursor and integer limit1..8, rejects boolean/invalid limits/unknown fields, and returns at most8 facts/14KiB JSON with total_count/next_after. UTF8 claims are never truncated. Cursor order is stable by fact ID. The native decoder validates ownership/order/IDs/count/cursor before applying, and lifecycle checks reject lists arriving after close/replacement. The inherited profile pipe retains its16KiB frame bound.

No new database, encryption, importer, semantic fact extractor, provider or package dependency. Existing BrainStore.verified_claims, ProfilePreparation/Bridge/Client, whole-vault CryptoKit persistence, source/fingerprint review and actual helper shutdown/reaping are reused. Native ProfilePreparationView retains the public initializer, while its minimum width drops from740 to480 to fit the assigned workspace. No unrelated capture/model/image/helper publication changes.

## Verification

- New presentation tests first failed because the presentation API was absent. Initial four tests then passed, including actual helper approve/save/lock/reopen with no manually typed topic.
- New memory reader tests failed on the absent command. After fixing synthetic fixture attribution/line bounds, the endpoint passes active-only/currentness, ownership, bounded complete pagination, UTF8 response budget, malformed input, replacement and pending-candidate exclusion cases.
- Native memory tests first failed because controller memory/paging state did not exist. After implementation, full macos-profile passes23 tests, zero failures,6.402s, including actual helper persistence/paging/revoke and held source/memory responses across close/fresh reopen. Decoder malformed-ownership/order/count/cursor cases pass. Existing failed-lock/emergency shutdown, late mutation/lookup, vault and actual-process reaping tests remain passing.
- Full Python:564 tests,21 optional converter skips, zero failures,3.459s. Initial sandboxed run had two existing local-socket tests denied bind; the scoped retry with loopback available passed. No actual external provider/account call occurred.
- git diff --check passes. SwiftUI profile view compiles in the native package. Final app integration and visible/rendered workspace review remain separate; no current live UI claim is made.

Logs: /private/tmp/relay-context-review-red.log, relay-context-review-green.log, relay-memory-browser-red.log, relay-memory-native-red.log, relay-memory-native-green.log, relay-context-profile-full.log, relay-context-python-full.log and relay-context-python-full-retry.log. These support portable results; raw temporary caches/artifacts do not belong in Git.

## Remaining product work

The full Cluely-style shell and automatic speech preparation are other owned branches. Account onboarding, typed requests/transcript/history and modes remain separate parity work. Protected context persists between launches, but fresh-helper automatic reopening/use still requires a distinct app startup hook with clear user intent/lock behavior; this lane does not claim that hook is already delivered. Optional real PDF/DOCX conversion dependencies remain skipped. No actual personal document, Keychain, OS permission, capture or external model request was used; all fixtures are fictional.
