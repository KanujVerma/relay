# Visual test environment correction: scoped controller review

Accepted `babb9798f50615a0db083006e6b8b92ac51c494a`, assembled as controller `951b06275d8762e5a16effb8225ca4f50f7a27dc`. This is test environment and lane evidence only; accepted c707 product runtime, helper fixture, assertions and timeouts are unchanged.

The complete own diff is three files,27 additions/6 deletions. The feature workflow gains the already established pinned HTTPX0.28.1 installation and synthetic Python-suite steps. Its existing `RELAY_TEST_PYTHON` export remains. The Swift test removes the machine-specific private temporary venv, selects an executable from explicit environment first or PATH, and uses correctly single-quoted shell arguments plus verbatim `"$@"`. An invalid explicit interpreter fails instead of silently selecting a different one. No model/capture/auth permission, changed regression expectation or skipped test is introduced.

The original feature CI40025482408/job120660473737 compiled Swift6.2.3 but lacked HTTPX, failing all seven new cases at verification before capture. Builder reproduced content-free child exit2 under an interpreter without HTTPX versus checking1/verified2 under the configured interpreter. Builder's seven focused cases and positive controls with a path containing spaces/apostrophes and PATH fallback passed, with a marker establishing the selected executable. Root reviewed the exact immutable diff and source equivalence.

The controller already had the dependency/Python workflow steps; cherry-pick preserved its additional requirements-file path trigger and made no workflow change. Only the test bootstrap and lane evidence differ from fully hosted-tested controller7685572. Exact runtime/fixture comparisons are empty.

Root fresh verification at951b062:

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/relay-final-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/relay-final-swift RELAY_TEST_PYTHON=/private/tmp/relay-answers-venv/bin/python swift test --disable-sandbox --disable-automatic-resolution --skip-update --package-path spikes/macos-panel --filter StagedVisualRetirementTests
```

Exit0, seven tests passed in3.012s with zero failures. Log: /private/tmp/relay-final-portable-fixture-tests.log. Expected restricted LaunchServices notification diagnostics did not fail tests. All runtime sources and the synthetic backend launcher are unchanged from hosted7685572, which passed176 native/Python558 with21 optional skips and final app compilation. A repeated full suite was unnecessary for this setup-only correction. New feature CI40028985057/job120672201072 was running after publication; do not claim its final verdict from earlier runtime evidence.

No actual account, private content, credential, OS permission/capture or external model operation occurred. The locked-Mac UI limitation remains separate.
