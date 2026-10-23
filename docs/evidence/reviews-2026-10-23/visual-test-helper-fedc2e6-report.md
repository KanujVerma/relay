# Synthetic actual-helper launcher checkpoint

Base: `e9e89cd87162e1dff9b8dd8c49f2d43e66835a79`.
Frozen commit: `fedc2e6cd87f37cc817926ddece1684916194b19`.
Branch: `test/visual-retirement-helper-2026-10-23`.
Checkout: `<workspace>/work/relay-build-visual-test-helper`.
Own delta: one new executable fixture, `tests/support/visual_backend_helper.py`, 98 lines. No production Python/Swift, existing tests, CI or global documentation changes; PR78 clone is untouched.
Binary-diff SHA-256: `54569555c4b8ef9f8a09be696f7bae2ef5a09070f29210f6444aa950465ea4d2`.

## Native interface

Use existing HTTPX0.28.1 interpreter `/private/tmp/relay-answers-venv/bin/python` with:

```text
pythonArguments = [absoluteScriptPath, "--synthetic-visual-test", "--log", newAbsoluteTemporaryJSONLPath]
```

The log path must not exist and its parent must already be in a temporary directory. The fixture creates it exclusively with owner-only permissions. Imports are inert; missing explicit flag/log rejects before running the helper. No optional response hold was added because the native owner had not requested one; immediate completed responses are the default.

Each HTTP attempt appends and flushes exactly `{"kind":<fixed kind>,"count":<per-kind count>}`. Kinds: `catalog`, `probe`, `image_question`, `text_question`. No credentials, authorization headers, prompts, image data, source text, account IDs or model output are logged. Recording happens before returning the response, so subsequent cancellation cannot hide an already attempted image POST.

The launcher invokes actual accepted `run_stdio` with a real `OAuthAnswerStream`, a fixed synthetic token/model, and HTTPX MockTransport. Only documented model/Responses routes are handled, entirely in memory. The probe really decodes the generated RGB pixels using existing tested `read_probe_pixels`; SSE completion and card content reuse existing `completed_wire` and `generated_card`. No new wire protocol or provider implementation is introduced.

## Verification

Existing `/private/tmp/relay-answers-venv/bin/python` reports HTTPX0.28.1. Five bounded actual subprocess checks passed:

1. Explicit verified setup followed by a valid staged PNG: log is catalog1/probe1/image_question1 and answer includes imageDigest.
2. Matching retirement before EOU: no image POST; one text question; no taskContext remains.
3. Image disable before EOU: no image POST; one text question with actual OCR-only provenance and no imageDigest.
4. Import is inert, including no HTTPX/auth import; missing flags/log refuse without creating the log.
5. Existing log is preserved and a non-temporary log target is rejected.

Verification command:

```sh
/private/tmp/relay-answers-venv/bin/python /private/tmp/relay-visual-test-helper-check.py <workspace>/work/relay-build-visual-test-helper/tests/support/visual_backend_helper.py
```

Observed `Ran 5 tests ... OK`. Tests first failed before the fixture existed, then passed with the launcher. `git diff --check` passed. No full production suite was rerun because this change is only the test fixture; native callback/order tests remain owned by the native implementer.

No actual account/credential access, external network/model call, listener, window capture, AX, Keychain, permissions, OS-private source or model download was used. All frames, bearer strings, pixels and responses were synthetic. The actual b880 native ordering defect is not claimed fixed by this fixture; native tests must feed their actual callback-produced frames and assert request metadata at this helper boundary.
