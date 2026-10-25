# Native default-role fixture correction

Frozen/published `5b03283fb62ef2bb8cd943238452223cdfa7865b`, parent `897238b459eb5e9dc682046295e50f0b6e06510f`, branch `test/visual-retirement-helper-2026-10-23`.

One fixture-file line now accepts the actual normal app default `developer`, alongside analytics/epic. SessionApplicationModel.swift:187 was checked: normal mode defaults to developer, fixture mode to analytics. The exact HelperTransport module/role/mode suffix and mandatory explicit synthetic flag/log remain validated. The recognized mode still cannot select actual authentication: every request uses the fixed synthetic token/model and HTTPX MockTransport. No runtime/default-role source changed.

The new developer argv tests failed against 897238b before the correction. Fresh result: **9 subprocess tests passed**, including EOF across all three supported roles and no/fixture/oauth mode suffixes, an actual developer+OAuth verify/generated flow, prior image/retirement/disable checks, inert imports and exclusive temporary logs. `git diff --check` passed. Immediate responses and the fixed kinds/counts log schema are unchanged.

Verification command:

```sh
/private/tmp/relay-answers-venv/bin/python /private/tmp/relay-visual-test-helper-check.py <workspace>/work/relay-build-visual-test-helper/tests/support/visual_backend_helper.py
```

Native owner already imported fedc2e6 and 897238b, so only this final one-line commit is needed there. No production Python/Swift, existing tests, CI or global docs changed. No real credential, account, model/network request, capture or OS permission was exercised. Native P1 correction/acceptance remains separate.
