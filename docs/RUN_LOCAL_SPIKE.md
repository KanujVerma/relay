# Slice 01A: local ChatGPT OAuth and inference spike

This is a **small experimental CLI**, not the final macOS app. Authentication requires the actual user to approve Relay in their own browser. The spike does not accept an API key, cannot bill the regular API on its own, and does not access personal files or live audio. Subscription usage may count against ChatGPT plan usage/credits and may be unavailable on some accounts.

## Install on the user's Mac
1. Clone or pull the Relay GitHub repository.
2. From the repository root, run:
   - python3 -m venv .venv
   - source .venv/bin/activate
   - python3 -m pip install -r requirements-spike.txt
   - python3 -m unittest discover -s tests -v
3. Start browser-based sign-in: python3 -m relay_spike auth
4. Approve only if OpenAI shows the expected Relay identity/plan permissions. A local callback at 127.0.0.1 completes authorization.
5. List account models: python3 -m relay_spike models
6. Stream exactly one synthetic technical question: python3 -m relay_spike infer
7. If necessary, select a model: python3 -m relay_spike infer --model MODEL_SLUG
8. Delete local credentials: python3 -m relay_spike disconnect. Separately revoke Relay in ChatGPT Settings.

If the CLI says plan usage scope is missing, or a model/usage limit prevents completion, stop. Never add a paid API key or paste tokens into chat or an issue to work around entitlement.

## Security and storage
- Host identifier and issued OAuth credentials persist locally in owner-only files under ~/.config/relay. Credentials are never included in Git, PRs or CI.
- OAuth identity token is cryptographically checked against OpenAI JWKS using PyJWT with cryptographic signature validation, issuer, audience, nonce and expiration checks.
- Only scope-authorized access tokens can call the Responses API. No ChatGPT web session scraping.
- Local owner-only JSON is acceptable for a throwaway feasibility CLI, but the shipping SwiftUI app must migrate to Keychain, add proper logout/revoke and handle token rotation.
- No token or callback code is printed. Do not enable HTTP debug logging or submit browser callback URLs to GitHub.
- DO NOT run this against genuine interview transcript/user documents while repository remains public; the current test uses synthetic SQL text.

## Troubleshooting expired tokens / missing login dependencies
- After `git pull` and activating `.venv`, run `python3 -m pip install -r requirements-spike.txt`. This installs `PyJWT[crypto]`, needed to verify OpenAI's ID token. The new sign-in path will check this **before** opening the browser.
- On a subsequent `models`, `infer`, `benchmark --execute`, or `live-qa --execute`, `active_access_token()` renews an expiring session automatically when it has a valid `refresh_token`; it does not spend model usage just to refresh. Never paste any stored OAuth token or callback URL into an issue.
- If the server reports `invalid_grant` or another terminal refresh error, the spike removes unusable secrets but retains its issued OAuth registration and asks for browser reauthorization.
- Network and temporary server errors preserve the saved credential record rather than destroying it or retrying indefinitely.

**Known provider caveat (Oct 2026):** Multiple developers report occasional `invalid_grant` refresh failures even with correctly implemented Sign in with ChatGPT rotating tokens, see [upstream issue #5](https://github.com/openai/sign-in-with-chatgpt-devkit/issues/5). An automatic refresh attempt cannot guarantee success until this is resolved and tested on your account. Relay intentionally asks you to sign in again in this terminal case; it does not retry with other authentication/billing methods.

## Offline versus real testing
- CI can validate PKCE, callback state/client-ID rejection, credential modes/scope checks and SSE completion/error behavior without external requests.
- CI **cannot** prove live account entitlement, cryptographic verification against live OpenAI keys, model availability, usage limits or measured network latency. A successful local authorization and response.completed event are required.
- The command prints only the selected model slug, generated synthetic answer, first_text_ms, total_ms, and completed flag. Keep personal context out of these test invocations.
- The model is selected from the live GET /v1/models catalog. A catalog entry alone does not guarantee successful inference.

## Feasibility gate to report back
Record ONLY non-sensitive outcomes:
- OAuth sign-in and required scope granted or denied.
- Whether models were listed, and selected model slug (not token).
- One response.completed or sanitized failure category.
- Locally observed first_text_ms and total_ms if completed.
- Environment: macOS version and Python version. No account tokens, callback links, full access logs or private prompt data.

## Known deliberate limitations
- The issue #30 prototype attempts **one automatic rotating OAuth refresh** near expiry when the saved session includes a valid refresh grant (after updating Relay). A missing/revoked/30-day-expired refresh token still requires deliberate `python3 -m relay_spike auth`. CI does not contact OpenAI. Production Keychain, persistent multi-account selection and remote token revocation remain separate work.
- No live-audio, personal memory, agents, Google Drive or UI integration.
- No long conversation history, retry loop, model ranking or response QA yet.
- The upstream Sign in with ChatGPT feature is preview and account/workspace eligibility is not assumed.
- Live flow may need updates if OpenAI changes auth/discovery format; recheck official docs before use.

Source contract: docs/INFERENCE_AUTH.md. Next after proof: Slice 01B answer formatting/quality evaluation.
