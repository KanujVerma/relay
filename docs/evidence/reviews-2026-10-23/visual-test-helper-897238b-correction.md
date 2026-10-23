# Native argv correction for the synthetic visual helper

Frozen correction: `897238b459eb5e9dc682046295e50f0b6e06510f`, parent `fedc2e6cd87f37cc817926ddece1684916194b19`.
Branch: `test/visual-retirement-helper-2026-10-23`.
Own correction: one fixture file, 14 additions/2 deletions. Binary-diff SHA-256 against fedc2e6: `6c1e5e688d3db99894b345bba7ae1b76ec6523ed1031db997df55a2756b8aeb0`.

Root reproduced that the initial launcher did not accept the actual arguments appended by HelperTransport. The source at HelperTransport.swift:112 confirms the suffix. The initial five direct-launcher checks were insufficient native integration evidence; source fedc2e6 alone must not be used as the corrected native fixture.

The fixture now accepts only this optional exact tail after its mandatory test flag/log arguments:

```text
-m relay_spike.session_host --role analytics|epic [--fixture-model|--oauth]
```

The zero-mode tail is accepted as well. Wrong module, unknown role, conflicting mode flags, extra model/auth/runtime arguments and missing explicit synthetic flag/log are rejected before imports/log creation. The recognized mode never selects real authentication: the helper always receives the fixed synthetic token, synthetic model and HTTPX MockTransport. Direct launcher use without a suffix remains supported. Immediate completed responses remain; no hold was added.

Fresh verification: **8 bounded subprocess tests passed** under existing HTTPX0.28.1. Actual appended argv EOF passed across two roles and all three modes; framed verify/generated flow passed with both fixture and OAuth suffixes. Positive image request logging, pre-EOU retirement, disable OCR-only fallback, inert imports and exclusive temporary logging also passed. The new actual-tail tests were observed failing against fedc2e6 before this correction. `git diff --check` passed.

Command:

```sh
/private/tmp/relay-answers-venv/bin/python /private/tmp/relay-visual-test-helper-check.py <workspace>/work/relay-build-visual-test-helper/tests/support/visual_backend_helper.py
```

No production Python/Swift, existing tests, CI or global docs changed. No real account, credential, network/model, capture, AX or permission operation ran. Native owner received the corrected SHA; importing from a tree without the fixture requires both fedc2e6 and this correction, or taking the single exact file from this head. Native P1 fix and its cross-process callback regression acceptance remain separate.
