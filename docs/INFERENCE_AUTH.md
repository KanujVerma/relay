# ChatGPT subscription-backed inference protocol and feasibility gate

Official documentation reviewed 2026-10-22. **A successful local user-reported ChatGPT-plan OAuth authorization and synthetic streamed inference was observed in terminal output on 2026-10-22.** It establishes feasibility for the tested account/sample, not unlimited usage or production robustness.

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
Python CLI code is now available in relay_spike/ with offline tests in tests/test_spike.py and steps in docs/RUN_LOCAL_SPIKE.md. **Protocol code was implemented and the user supplied a successful local OAuth and gpt-6.1-sol stream.** This remains a user-reported single-run test, not an independent repeated or security-audited deployment.

The goal is a small text-only local OAuth/streaming proof with synthetic questions. No GUI, live audio, user files, API key fallback or external billable integration. Measure monotonic first-output-token and completed-response latency. Test offline errors with mocks and report truthfully that offline simulation is not a live account authorization.

## Error/limit handling
Consent denied or missing scope: no inference. Invalid_grant: discard code, reauthorize. Expired tokens: refresh per documented protocol or require explicit login. Usage-limit events (including subscription_sharing_usage_limit_exceeded and subscription_sharing_usage_unavailable): stop and explain account limit. Model unavailable: select from actual available list. Stream error/incomplete: never call partial output a validated answer. Network errors: no uncontrolled retries that duplicate inference.

## Successful local user-reported gate (2026-10-22)
- Browser sign-in and plan scope verified, eight model slugs listed (including gpt-6-luna, gpt-6.1-sol and gpt-6-astra).
- Synthetic SQL WHERE/HAVING question completed via gpt-6.1-sol, first text **2640 ms**, total **8306 ms**, **906** output characters, completed=true.
- No ordinary API key supported in the experimental CLI. Usage still counts against plan entitlement; do not assert unlimited access.

## Still worth testing for production
- Repeatability across restarts, expired sessions, token rotation and revocation.
- Account-specific quotas/rate limits and model changes.
- Broader repeated comparative latency/correctness on harder concise prompts for Luna versus Sol. The initial 2026-10-22 three-case paired benchmark is recorded in [MODEL_STRATEGY.md](MODEL_STRATEGY.md).
- Account suitability for recurring personal use, changes to preview terms.

## Security
Do not log callback codes, token fields, browser links containing identity hints, personal source text or credentials. Never use ChatGPT cookies or undocumented backend endpoints. Do not let a CLI fallback to separately charged API billing.

The experimental callback now checks loopback Host and OAuth state **before** consuming the callback, so unsolicited malformed requests cannot prematurely terminate the sign-in attempt. Before persisting credentials, token fields are type-checked and require a nonempty access token, Bearer token type and positive expiry. Offline negative tests cover both guards. This is preliminary hardening, **not** a substitute for an interactive security/entitlement test on the Mac.

## Optional reasoning effort: locally validated for Low and Medium

As of 2026-10-22, the standard Responses API documents `reasoning.effort`; GPT-6 Luna and GPT-6.1 Sol each default to Medium, and Sol 6.1 rejects None/Minimal. The Sign in with ChatGPT preview restrictions explicitly prohibit several request fields, **but do not name `reasoning` in that prohibited list**. On 2026-10-22 the owner then completed four explicit Low/Medium requests on Luna and Sol 6.1 using the ChatGPT-plan OAuth preview, each returning a matching server-reported reasoning effort. This is account-specific compatibility evidence, not a guarantee for other accounts, effort levels or future preview changes.

Relay passes a validated top-level `reasoning: {"effort": "low"}` only with an explicit CLI flag; the default omits it. That user-reported four-request test establishes **acceptance** of the specific Low and Medium overrides; it does **not** establish a consistent latency or correctness improvement. One response per model/effort on D02 is too small to compare speed, and first nonempty output is not a measured first useful talking point. Do not infer effective effort from the requested value when the server does not report one. No retry should add a paid API key, unsupported pro-mode option, or extra usage without the user's approval.

Official sources: https://developers.openai.com/api/docs/guides/reasoning and https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations.
