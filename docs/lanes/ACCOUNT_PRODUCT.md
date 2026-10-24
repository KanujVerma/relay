# Protected account product join

Active incremental branch `feature/chatgpt-account-product-2026-10-23`, frozen PR base `build/account-product-foundation-2026-10-23` at3c2f1c16443884c481fe64776ead1b142464a312 (accepted native28d5948 plus canonical6eb1717 only). PR87/component branch remains frozen at28d5948. Storage728e929, control6bd40bd and native28d5948 were independently accepted at their respective boundaries. This product increment is a separate review gate.

## Implemented source checkpoint

`product_session.protected_answer_stream(model,input_fd=...,service_factory=...,client_factory=...)` requires a bounded host-selected model, consumes the exact private oauth_session first frame with raw descriptor IO, opens the actual encrypted selection/generation/scope and injects its token provider into the existing OAuthAnswerStream. It has no plaintext/default provider fallback. Injected HTTP clients are test ports; the production endpoint/stream/budget stays the existing public Responses route.

SessionHost's additive `--protected-account` mode requires OAuth and an explicit model. It constructs the protected stream before attaching asyncio to stdin. `run_stdio` independently refuses that mode when its provider injection is absent, so a broken factory cannot silently construct a development stream. Ordinary direct CLI behavior remains development-only. The packaged entry's exact argument parser rejects unprotected/abbreviated OAuth, duplicate flags and invalid modes before dispatch; account_bridge is the only added module, with no extra arguments. The frozen build spec includes actual account/product modules, never synthetic test launchers.

53 focused product-provider/entry/packaging/session/typed tests pass4.393s (`/private/tmp/relay-account-product-provider-final.log`). Includes actual source-entry child missing/wrong private bootstrap exiting with no raw output, exact adjacent command preservation and protected token source, refusal of missing injected provider, and actual fixture/no-inference reviewed-reference answers without any secret bootstrap. These are source/helper tests. New frozen artifact/Model/UI account exposure and held token/reap proof remain required.

## CI preparation

Separate commit87af54e adds actions/setup-python@v5/Python3.12 to contract CI and installs the existing approved HTTPX0.28.1, PyJWT2.15.1 and cryptography50.0.2 pins in both workflows. The native workflow now includes the macos-account trigger/package. Both YAML files parse and their exact pins/package loop were checked locally. No assertion/skip/timeout was weakened. Hosted CI for the final product head remains a separate required check.

## Remaining work

- Actual HelperTransport private bootstrap before all normal frames, using the current private AccountInferenceSelection and selected model.
- Actual Model/Settings join, simple connected-account/plan/actionable error copy, automatic saved-account restore on explicit Start/Send, one coalesced/current owned account-preparation task and joined Stop/End cancellation.
- Old session helper actual exit/reap before any account/AI-mode/sign-out mutation, including a held token thread after Pause. Profile approval/use preference must remain separate.
- Actual Model+MockTransport rotating-bearer and stale/no-POST cases; relocated newly built frozen runtime account/bootstrap/fixture/reference checks; final hosted CI and independent precise-head review.

Only generated keys/grants, public fixtures, mocked HTTP and owned temporary pipes/processes were used. No actual account/browser/Keychain, capture/permission, private content or paid/model network request was performed.
