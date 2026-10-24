# Automatic response preferences

Owner `/root/review_composition`, GPT-6.1 Sol xhigh. Isolated branch `feature/response-preferences-2026-10-23`, frozen base3e83f8e0157b7496674ece71ad3ded0f397b818f; draft PR96. Root approved exact5e09548 design plus explicit Coding/Feature Use may create first empty protected catalog/key. General and default rendering/typing/preparation never create protected storage. The author owns the full Settings/Model/helper/store feature; current checkpoint is only storage-purpose foundation.

Dependency77359c3 imports exactly three source/test blobs from root-accepted194be02bcde8fcc34b009a6bb9f6c15db938dd31, preserving profile/chatGPTCredentials/history. It imports no history ledger, app, account runtime or independent history docs.

New fixed responsePreferences purpose uses `Relay/ResponsePreferences/preferences.relayvault`, authenticated `RELAYPREFERENCES1\n`, key service `com.relay.response-preferences.v1`, account `local-response-preferences-aes256`. Exhaustive file/header/service/account switches preserve all three original purposes. History and response preferences share existing owned nonrecursive sibling-directory policy; profile retains its legacy facade/default.

Three new tests first fail at missing enum API, then unsafe-parent/missing-ancestry policy fails five assertions with the new purpose incorrectly following the profile branch. Applying the non-profile directory policy yields13affected storage cases passing0.055s (new3 + original protected5 + profile5). Tests use owned temporary directories, actual encrypted files and injected synthetic keys/Security clients. No actual Keychain, account/private files or model/capture work. `git diff --check` passes. Initial test command had an incorrect relative destination and omitted isolated module cache variables; corrected command below produced the recorded red/green without global cache changes.

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-response-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-response-module-cache RELAY_TEST_PYTHON=/private/tmp/relay-root-current-runtime/venv/bin/python swift test --disable-sandbox --scratch-path /private/tmp/relay-response-profile-build --cache-path /private/tmp/relay-response-spm-cache --filter 'ResponsePreferenceVaultTests|ProtectedSnapshotTests|ProfileVaultTests'
```

Run in `spikes/macos-profile`. Logs `/private/tmp/relay-response-purpose-api-red.log`, `relay-response-purpose-policy-red.log`, `relay-response-purpose-green.log`. Catalog/coordinator/request/prompt/UI are not implemented at this checkpoint. Next: strict catalog and owned actual storage receipt tests, including canceled successful disk writes and existing-only restart fences.
