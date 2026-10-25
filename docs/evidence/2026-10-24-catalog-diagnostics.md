# Content-free catalog diagnostics

Base: `7bd1eaa8a5e701bb2a9ac17e0c886dd67acb6f40`. This diagnostic-only component preserves the existing catalog parser, 64 KiB response/strict-JSON limit, 256 raw-row and 32 visible-row limits, server order, complete native frame bound, normal clients, provider selection and errors. It changes no model/account permission or retry behavior.

One explicit catalog attempt may atomically replace `catalog-diagnostic.json` inside its existing validated Accounts directory. The file is at most 1,024 bytes, mode0600, with no history. It reuses existing owner-only directory and atomic replacement checks; symlinks/hardlinks and unsafe existing files are not adopted. Neither module import nor service/collector construction performs storage IO. A failed diagnostic writer cannot replace the catalog's successful result, existing error or cancellation. The Accounts store has no child allowlist and its metadata remains unchanged by this separate file.

The exact fixed schema contains only:

- `schemaVersion`, fixed `outcome`, `httpStatus`.
- `bytesAtStop`, numeric `declaredContentLength` or null.
- `modelsPresent`, `rawModelCount`, `visibleModelCount`, nullable before successful decoding.
- `monotonicNanoseconds`, recorded for checking freshness.

No headers, token/key/fingerprint, identity, URL, model name, raw body, prompt/source text or exception message is serialized. The content-length field is only the parsed bounded nonnegative numeric declaration. `bytesAtStop` counts response bytes delivered by HTTPX's decoded byte iterator before this reader stops; it does not claim full-body or on-wire length. Counts describe the decoded raw list and rows marked visible, even when later field/count validation rejects it.

Fixed outcomes distinguish valid/empty-visible catalogs; body, HTTP, JSON/object/models shape and row/field bounds; token failure, transport failure, timeout and cancellation. Cancellation remains cancellation even when it interrupts cleanup after an earlier body rejection. A valid service diagnostic does not prove downstream bridge frame fit, current native selection, model capability or entitlement. Diagnostics never authorize account use or inference.

Verification used only synthetic temp encrypted stores and HTTPX MockTransport. The original API-first red was the absent diagnostic module. An additional original red reproduced a stale body-limit label when cancellation interrupted error cleanup; its diagnostic-only correction now preserves cancellation and the observed byte count. Final **45 tests passed, zero skips/failures,2.162s**, covering10 new diagnostic cases plus35 existing OAuth/control/protected-product regressions.

The tests exercise exact65,536-byte acceptance and65,537-byte rejection; partial body stop versus a longer declared length; HTTP/JSON/empty/hidden/invalid/oversized shapes; token-secret/raw-body/model-name sentinel absence; latest-only0600 writing; inert construction; unsafe leaf refusal; missing-directory no-create; and writer failure preserving success/error/cancellation. Existing generated RSA/JWKS, refresh, complete-frame, private-bootstrap/factory and source-entry controls remain green. No real account, browser, Keychain, external network/model, native build, capture, dependency/model download or new environment was used.

Root must review this source before any frozen-helper rebuild. A later separately authorized single catalog-readiness action can identify the actual failure category from a fresh record. No speculative budget increase, parser relaxation, account-selection change, model retry or successful live diagnosis is claimed here.

## Independent review: owned writer and existing-only replacement

The original a784 source is preserved. Independent review identified synchronous strong filesystem flushes blocking the asyncio control loop, and a second directory-preparation call that could recreate a removed Accounts root. The original three-case regression batch produced two behavior failures plus the missing existing-only API error before correction.

Diagnostics now await the existing owned off-loop thread pattern. Status/cancel dispatch stays responsive while the actual writer is held; cancellation cannot acknowledge completion until that worker really returns. Cancellation during the writer gets at most one bounded, also joined correction of the same latest record to cancelled. There is no unjoined background write, history, new scope claim or arbitrary timeout that declares the thread gone. The unchanged15s HTTP deadline does not claim to bound filesystem cleanup.

Atomic replacement gains only the optional create_parent flag, defaultTrue for every existing caller. Diagnostics passFalse, so removal after initial validation cannot cause telemetry to recreate the root. Existing credential creation/rotation semantics are unchanged.

The unchanged original regressions now pass. The actual AccountBridge test holds the writer, receives status=busy and cancel=pending while held, observes no premature terminal, then releases and joins the real worker before exactly one cancelled terminal for each owned request. The root-removal interleaving leaves the root absent and the legitimate catalog result unchanged. Explicit default-caller creation, safe-file, cancellation, schema/content and credential durability controls remain enabled.

Final affected verification: **91 synthetic tests passed, zero skips/failures,3.319s**:13 diagnostic cases plus OAuth/control/factory, encrypted account-store and mocked legacy-refresh/default-storage regressions. Existing mocked HTTPError fixture ResourceWarnings remain. Docs/diff validation passes. No native/live account, Keychain, external network/model/capture, build, copy or dependency operation occurred.

Root independently reviewed both changes and imported them as d6681c9/47b05a7. Its complete Python suite then collected858tests:826passed,32optional skips,zero failures in12.655seconds. Existing SQLite ResourceWarnings remain. Documentation/local-link validation also passes. This accepts source compatibility/privacy/lifecycle controls; the fresh frozen-helper build and one normal catalog-readiness diagnostic action still follow. No catalog limit/parser/model policy change or live question retry is included.
