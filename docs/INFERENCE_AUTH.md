# ChatGPT subscription-backed inference protocol and feasibility gate

Official documentation reviewed 2026-10-22. **This documents a supported platform path, not successful access for the user's account.** No Relay OAuth authorization or actual AI inference has been observed.

## Official sources
- Overview: https://developers.openai.com/siwc/token-sharing-open-source
- Dynamic registration and sign-in: https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- Models and inference: https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- Preview limitations: https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- Token reference: https://developers.openai.com/siwc/token-sharing-open-source/token-reference
- Errors and recovery: https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery
- App-server alternative: https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server

## Verified platform behavior
- Open-source, locally hosted apps may request identity scopes plus optional ChatGPT plan inference permission; eligibility/limits depend on account and workspace.
- This sign-in is not access to ChatGPT Memory, ChatGPT conversations, existing connectors or a conventional API key.
- New client registration begins with client_id equal to dynamic_agent_client and agent_name_hint set to the actual app name Relay.
- Create a stable opaque ext_agent_host_id per host (UUID URN allowed), saved for reuse.
- Start a browser-based OAuth2 authorization code + PKCE S256 flow with fresh state, nonce and code_verifier. Authorize URL: https://auth.openai.com/api/accounts/authorize.
- Local callback must be http://127.0.0.1:PORT/auth/callback (same host, scheme, path across sign-ins; port may change). Start listener before browser.
- Request scopes: openid profile email offline_access resource.invoke chatgpt.tokens.use.direct. Resource: https://api.openai.com/v1.
- New-registration callback includes issued client_id (example prefix oaiapp_). Use that, not dynamic_agent_client, for code exchange at https://auth.openai.com/api/accounts/oauth/token with exact redirect_uri, code_verifier and resource.
- Validate state; reject OAuth error, mismatched callback client ID, invalid grant. Verify ID token JWKS signature, issuer, audience (issued client ID), expiration and nonce. Identity alone is not plan permission.
- Only infer if granted scopes include chatgpt.tokens.use.direct. Store/rotate access, ID and refresh tokens securely. CLI spike can use owner-only protected local credentials; shipping Mac app should use Keychain.
- List account-specific models via authorized GET https://api.openai.com/v1/models, parsing models array, display_name and slug.
- Stream inference via POST https://api.openai.com/v1/responses with Bearer OAuth access token, store=false, stream=true, input as array, top-level instructions when needed.
- Only a response.completed terminal event counts as success. response.failed, response.incomplete, network timeout and EOF before terminal event are failures; failures can occur after partial tokens.
- Preview excludes many standard API settings (temperature, max_output_tokens, previous_response_id over HTTP, conversation, background and more). Hosted file search, hosted MCP/Drive connectors and audio/transcription APIs are NOT supported on this route.
- Use local speech recognition and independently authorized file connectors. Model catalog presence is not proof that a specific inference call will succeed.
- Codex app-server is a supported alternative transport but adds local process/RPC complexity; keep it a potential fallback.

## Slice 01A implementation and remaining live proof
Python CLI code is now available in relay_spike/ with offline tests in tests/test_spike.py and steps in docs/RUN_LOCAL_SPIKE.md. **Only protocol code is implemented**; user account entitlement and end-to-end auth have not been verified.

The goal is a small text-only local OAuth/streaming proof with synthetic questions. No GUI, live audio, user files, API key fallback or external billable integration. Measure monotonic first-output-token and completed-response latency. Test offline errors with mocks and report truthfully that offline simulation is not a live account authorization.

## Error/limit handling
Consent denied or missing scope: no inference. Invalid_grant: discard code, reauthorize. Expired tokens: refresh per documented protocol or require explicit login. Usage-limit events (including subscription_sharing_usage_limit_exceeded and subscription_sharing_usage_unavailable): stop and explain account limit. Model unavailable: select from actual available list. Stream error/incomplete: never call partial output a validated answer. Network errors: no uncontrolled retries that duplicate inference.

## Must still validate on user's Mac
- Real browser consent and issued client registration.
- Cryptographically verified ID token and chatgpt.tokens.use.direct grant.
- Actual account model list and one successful response.completed.
- First useful and total response times; exact model and limits.
- Account suitability for recurring personal use, changes to preview terms.

## Security
Do not log callback codes, token fields, browser links containing identity hints, personal source text or credentials. Never use ChatGPT cookies or undocumented backend endpoints. Do not let a CLI fallback to separately charged API billing.

The experimental callback now checks loopback Host and OAuth state **before** consuming the callback, so unsolicited malformed requests cannot prematurely terminate the sign-in attempt. Before persisting credentials, token fields are type-checked and require a nonempty access token, Bearer token type and positive expiry. Offline negative tests cover both guards. This is preliminary hardening, **not** a substitute for an interactive security/entitlement test on the Mac.
