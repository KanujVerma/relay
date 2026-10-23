# Independent review: verified visual input, PR 74 / issue 73

Verdict: no reportable findings in the supplied six-file own patch. Recommendation: `merge` for this production-port slice, `human_review_required`. This is an advisory source-review result, not permission to merge and not a claim that the app's visual feature or actual account acceptance is complete.

## Exact scope

- Static checkout: `<workspace>/work/relay-review-visual-ad9f587`.
- Base: `819e4ae6b88aca4b2cd97c0f508af31c82207fae`.
- Head: `ad9f587cc83c7239865a0cf758fab185cccba72e`.
- Own patch: six files, 1049 insertions, 30 deletions. Aggregate PR dependency ancestry was excluded.
- Exact `git diff --binary <base> <head>` SHA-256: `ae3fa1ed274d1b992d9079ae8c8575a9e944ca8747a5c16f1ed4267c08198973`.
- Read the checkout AGENTS contract, docs/VISUAL_INPUT.md, docs/lanes/VISUAL.md, controller primary research at the integration checkout and its BUILD_CONTRACT visual section. Accepted peer libraries/auth core were considered only at changed boundaries, not re-audited.

## Findings

None. No source-visible correctness or authority defect was established in the supplied own patch.

## Evidence and scope verdict

The implementation separates explicit consent, capability and request authority. `begin_enable` grants no image transport. The setup method checks the current exact visible catalog slug, then makes one generated-image request with the same original bearer and existing Responses completion rules. Only correct bounded completed output yields the private in-memory receipt. The private keyed bearer fingerprint, configured model/effort/endpoint, consent and monotonic lifetime remain bound. Arbitrary JSON, caller booleans and legacy `ImageInputPolicy` do not grant authority in this transport.

The private permit binds the original request and trusted producer claim, validates the reused 2 MiB/1920 PNG bounds and encoded-byte hash, revalidates after token acquisition and immediately before the request, and sends once. Late source/credential/configuration failure vetoes completion or publication. `used_image` is a read-only transport-owned historical completion fact. Successful completion drops PNG storage and keeps original owner/request evidence for publication; cancellation, errors and retirement clear permit bytes. Sanitized provider errors retain fixed codes/allowlisted categories, with no automatic image/text retry or API-key fallback.

The existing SessionHost production caller still invokes the compatible text-only signature. The new producer adapter, local staging integration, setup UI and native canonical-pixel/lease publication check are separate declared composition work. Their absence is not reported as a defect in this assigned port slice. The interface requires actual host callbacks and original producer ownership, not unconditional production lambdas or invented account IDs.

## Validation and limitations

At this exact head, the focused visual suite ran with the existing `/private/tmp/relay-answers-venv/bin/python` and HTTPX 0.28.1: **23 tests passed in 0.119 seconds**. Tests used injected synthetic tokens, catalog, PNG producer, clock, SSE and HTTPX MockTransport. The tests observe actual emitted image/text bodies, independent probe pixels, completion, retirement, no resend and sanitized errors. The review checkout remained clean.

No full suite or baseline rerun was performed. No private credentials/files, external account/model requests, capture, OS permission prompts, socket tests, source/index/HEAD mutations, push or PR write occurred. Hosted CI, real-window/current-host composition and actual account/model acceptance/quality/latency were not independently verified. Primary research is accepted as the protocol authority; no new external entitlement guarantee is inferred.

Impact if this boundary were wrong is high because pixels could leave the device. The source/tests support low regression likelihood within this slice; regression protection is partial until composition/live gates exist. Reversion is easy and there is no persistent migration, though already-sent provider work cannot be recalled. This privileged boundary and public consumer API require human review.

## Validated structured assessment

```json
{
  "schemaVersion": 1,
  "patch": {
    "repository": "https://github.com/KanujVerma/relay",
    "sourceType": "commit_range",
    "base": "819e4ae6b88aca4b2cd97c0f508af31c82207fae",
    "head": "ad9f587cc83c7239865a0cf758fab185cccba72e",
    "changedFiles": [
      "docs/VISUAL_INPUT.md",
      "docs/lanes/VISUAL.md",
      "relay_spike/oauth_answer_stream.py",
      "relay_spike/stream.py",
      "relay_spike/visual_input.py",
      "tests/test_visual_input.py"
    ],
    "sha256": "ae3fa1ed274d1b992d9079ae8c8575a9e944ca8747a5c16f1ed4267c08198973"
  },
  "recommendation": "merge",
  "workflowLabel": "human_review_required",
  "impact": {
    "rating": "high",
    "rationale": "This introduces an authorization boundary for sending a selected-window PNG through an existing OAuth transport. A regression could disclose screen pixels. The default live host remains text-only."
  },
  "regressionLikelihood": {
    "rating": "low",
    "rationale": "Exact source tracing and the 23 passing synthetic exact-head tests support the stated port invariants. No source-visible defect was established within the supplied own patch."
  },
  "regressionProtection": {
    "rating": "partial",
    "rationale": "The exact-head visual tests exercise the controller and actual HTTPX 0.28.1 AsyncClient with MockTransport. Actual producer/native composition, UI and account/window acceptance are intentionally outside this patch and were not verified.",
    "exactHeadChecksPassed": true
  },
  "recoverability": {
    "rating": "easy",
    "rationale": "No persistence format, migration or dependency is added. Visual authority is memory-only and disable/revert can remove this optional path. Already-sent provider work cannot be recalled."
  },
  "confidence": {
    "rating": "high",
    "rationale": "The immutable six-file range, relevant production caller, primary contract, material authority boundaries and focused synthetic checks were examined. Confidence is restricted to this port slice."
  },
  "applicability": {
    "status": "confirmed",
    "rationale": "OAuthAnswerStream.complete is used by SessionHost's configured OAuth path at relay_spike/session_host.py:321-322. The optional visual ports have no app/helper producer consumer in this head; that absence is expressly the accepted composition boundary."
  },
  "statusQuoRisk": {
    "rating": "low",
    "rationale": "Leaving this patch out preserves the existing text-only flow and unavailable optional image input; it does not create a new screen egress path."
  },
  "autoMergeExclusions": [
    "privileged_boundary",
    "public_contract"
  ],
  "affectedRuntimeRoots": [
    "relay_spike/session_host.py:321-322 -> OAuthAnswerStream.complete (existing text-only caller)",
    "OAuthAnswerStream.verify_visual_input (explicit setup port)",
    "VisualInputController.prepare_attachment -> OAuthAnswerStream.complete(visual_attachment=permit) (future trusted composition consumer)",
    "OAuthAnswerStream.validate_visual_publication -> permit.validate_for_publication (future final publication consumer)"
  ],
  "importantCallers": [
    "relay_spike/session_host.py:293",
    "relay_spike/session_host.py:321-322",
    "tests/test_visual_input.py:107-115"
  ],
  "riskDrivers": [
    "Optional raw-image egress depends on correct host-provided ownership and current-request callbacks.",
    "The native canonical-pixel publication check and real staging adapter remain separate required composition work.",
    "Bearer fingerprint continuity deliberately invalidates receipts on refresh and can require explicit setup again."
  ],
  "protectiveFactors": [
    "Private in-memory identity receipts; arbitrary JSON and caller booleans do not grant new transport authority.",
    "Current catalog and exactly one correctly completed generated-image probe use the same original bearer.",
    "Permit revalidation after token await, before request, during SSE, after completion and before publication.",
    "Strict reused PNG structural, dimension and byte bounds; one image POST; no automatic retry or API-key fallback.",
    "Successful transport drops PNG storage while retaining publication evidence; cancellation/error/retirement reject publication.",
    "Provider diagnostics expose only fixed local codes plus bounded allowlisted categories."
  ],
  "materialBoundaries": [
    {
      "id": "consent-probe",
      "invariant": "Only explicit consent plus current catalog and one correct completed PNG probe grants capability.",
      "runtimeRoot": "OAuthAnswerStream.verify_visual_input; visual_input.py:188-239",
      "counterexample": "Missing, hidden, duplicate or malformed selected model; wrong or incomplete probe output; forged receipt. Patched parsing/identity/completion checks reject them without a retry.",
      "legitimateControl": "Explicit begin_enable consent plus private receipt identity and existing ResponseAssembler; tests/test_visual_input.py:117-197.",
      "result": "supported"
    },
    {
      "id": "credential-config",
      "invariant": "Receipt and permit use the same actual bearer, model, effort, endpoint, consent and monotonic lifetime.",
      "runtimeRoot": "visual_input.py:203-261; oauth_answer_stream.py:175-186,239-247,265-270",
      "counterexample": "Bearer rotates after catalog, before image send, or before publication; model/effort/endpoint changes or receipt expires. Fingerprint/config/lifetime checks retire authority.",
      "legitimateControl": "Private salted HMAC and exact config tuple; actual token reads before/after verification and for send/publication; tests/test_visual_input.py:148-157,219-242,281-287.",
      "result": "supported"
    },
    {
      "id": "original-image-owner",
      "invariant": "A permit binds the original actual request, producer observation and selected PNG.",
      "runtimeRoot": "visual_input.py:263-325",
      "counterexample": "Producer no longer owns the claim, request guard retires while awaiting auth, PNG bytes mutate, or consent retires during claim production. Ownership/current/receipt and hash checks reject the send.",
      "legitimateControl": "Required trusted VisualImagePort and current-request callback; claim object and original request retained; strict PNG bounds reuse; tests/test_visual_input.py:244-279,316-327.",
      "result": "supported"
    },
    {
      "id": "one-send-lifecycle",
      "invariant": "An image permit sends once and used_image records actual validated completion only.",
      "runtimeRoot": "visual_input.py:297-353; oauth_answer_stream.py:163-205",
      "counterexample": "Reuse after success, stream failure/incompletion, cancellation or source retirement. Reuse cannot POST; unsuccessful paths retire and drop PNG bytes; failed completion never sets used_image.",
      "legitimateControl": "Private _sent/_completed lifecycle and finally retirement; ResponseAssembler completion; tests/test_visual_input.py:199-217,289-314,329-361,376-395.",
      "result": "supported"
    },
    {
      "id": "publication",
      "invariant": "Successful send preserves publication proof while current credential/request/source authority remains required.",
      "runtimeRoot": "visual_input.py:330-353; oauth_answer_stream.py:256-276",
      "counterexample": "Successful completion followed by source, consent, expiry or bearer change. used_image remains a true historical fact, but synchronous/asynchronous publication validation rejects stale authority.",
      "legitimateControl": "Original claim/producer/request retained after byte release, final token/config check and synchronous ownership check; tests/test_visual_input.py:199-217,281-314. Native pixel recheck is an explicit later composition obligation.",
      "result": "supported"
    },
    {
      "id": "provider-errors",
      "invariant": "Provider failures expose sanitized bounded diagnostics without automatic retry or billing fallback.",
      "runtimeRoot": "oauth_answer_stream.py:18-48,124-161,189-205",
      "counterexample": "Unsupported-image response or top-level SSE error contains private text and bearer-like values. Only allowlisted code and parameter category survive; the image attempt is not repeated.",
      "legitimateControl": "Bounded strict JSON and allowlisted error projection; capability rejection retirement; tests/test_visual_input.py:329-361.",
      "result": "supported"
    },
    {
      "id": "text-compatibility",
      "invariant": "No permit preserves existing text-only call behavior and does not initiate visual setup.",
      "runtimeRoot": "oauth_answer_stream.py:163-188; stream.py:65-95; session_host.py:293,321-322",
      "counterexample": "Ordinary existing complete(question,instructions) call without consent. It produces one text POST, no catalog/probe/image request.",
      "legitimateControl": "Default visual_attachment=None and optional body extension; tests/test_visual_input.py:363-374.",
      "result": "supported"
    }
  ],
  "validation": [
    {
      "name": "Immutable range identity and own patch digest",
      "status": "passed",
      "protects": "HEAD ad9f587; supplied own base 819e4ae; six files, 1049 insertions/30 deletions; SHA-256 ae3fa1ed274d1b992d9079ae8c8575a9e944ca8747a5c16f1ed4267c08198973."
    },
    {
      "name": "Exact-head focused visual tests with existing HTTPX 0.28.1",
      "status": "passed",
      "protects": "23 tests in 0.119 seconds; synthetic bearer/catalog/PNG/SSE only; no actual account, capture, socket, external inference or permissions."
    },
    {
      "name": "Source and caller tracing",
      "status": "passed",
      "protects": "All six own files, reused completion/PNG boundaries and current SessionHost caller inspected. Static review checkout remained clean."
    },
    {
      "name": "Full suite and baseline reruns",
      "status": "skipped",
      "protects": "Excluded by review scope; no full-suite or redundant baseline run performed."
    },
    {
      "name": "App/producer/native pixel/UI/account acceptance",
      "status": "skipped",
      "protects": "Intentionally separate composition and live acceptance gates; no delivery or account entitlement claim made."
    }
  ],
  "unknowns": [
    {
      "summary": "Actual selected account/model acceptance, visual quality and latency are untested.",
      "decisionCritical": false
    },
    {
      "summary": "Final producer adapter, app/helper staging/UI and native canonical-pixel publication gate are not wired in this patch.",
      "decisionCritical": false
    },
    {
      "summary": "The host must supply actual ownership/current callbacks and promptly retire/cancel on source/account/consent/request lifecycle changes; this patch cannot establish future caller correctness.",
      "decisionCritical": false
    }
  ],
  "evidencePlan": []
}
```

