# Visual input in the Python helper

This composes the reviewed [visual authority port](VISUAL_INPUT.md) into the existing helper. Native controls and image production belong to the separate app lane. The native account/window/permission acceptance gates remain unperformed. No capture or real model request runs at default launch or in these tests.

## Configured transport and explicit control

`SessionHost(..., visual_transport=stream)` accepts the actual configured `OAuthAnswerStream`, with `complete=stream.complete`. `--oauth` creates one such stream for both answers and the explicit probe. Normal/default/fixture modes have no visual transport and cannot read credentials or verify images. A mismatched fixture completion function is rejected before credential access. `run_stdio(args, oauth_stream=...)` is a Python dependency-injection port for synthetic tests, not an additional CLI, environment or billing option.

The inherited native channel sends exactly four fields:

```json
{"schemaVersion":1,"kind":"visual_input_request","requestID":"<native UUID>","action":"verify"}
```

Actions are `verify`, `disable`, and `status`. No model, account, permission Boolean, receipt or fingerprint is accepted from JSON. Responses contain exactly `schemaVersion`, `kind:"visual_input_response"`, `requestID`, `action`, `resultRevision`, `status`, `reasonCode`, and `model`. Model is the actual configured OAuth slug or null. Status describes the last local check, not an account entitlement; `status` never reads credentials or makes a network request.

| Action | Revision / status | Reason |
| --- | --- | --- |
| verify starts | 1 / checking | checking |
| verify succeeds | 2 / verified | probe_verified |
| verify fails its check | 2 / unverified | probe_unverified |
| verify task is cancelled | 2 / cancelled | probe_cancelled |
| disable | 2 / disabled | user_disabled |
| status | 2 / any nonchecking last-check state | current_status |
| verify without configured OAuth completion | 2 / unavailable | inference_disabled |
| verify during a live session | 2 / busy | session_active |
| verify before answer work quiesces | 2 / busy | answer_in_progress |
| verify or status while a probe exists | 2 / busy | probe_in_progress |

Verification is idle-only. It creates one cancellable task and returns immediately to the stdio reader. The checking response is revision 1; the task's done callback emits exactly one terminal revision 2 after actual task cleanup/quiescence. This includes cancellation before the coroutine starts. The native waiter allows 35 seconds for a transport deadline of at most 30 seconds plus bounded pipe slack. A session start cancels an unfinished idle probe. A completed capability can carry into that session; stop/disable revokes it. Answers wait for any cancelled probe to finish cleanup before using the same OAuth stream and its existing budget.

A 512-entry ledger stores the exact original four-field request and latest response. Exact duplicate UUID/payload replays that response without IO. A changed payload under the same UUID rejects the protocol and revokes visual authority. Cached status is never a capability object. Model/grant/consent changes are rechecked at actual image use and publication by the existing private receipt and actual bearer fingerprint rules.

## Local image staging and original ownership

Native sends one strict `screen_context` OCR frame, then optional existing `screen_image_begin/chunk/end` frames, then the original EOU/manual request. `SupplementalContextProvider.stage_image` reuses public `ScreenImageAssembler` directly. It permits one matching local transfer, at most 2 MiB, a two-second staging/assembly deadline and the existing chunk/hash/PNG bounds. Replacement, wrong order/identity or malformed frames clear assembly and reject the frame. These bytes have no inference authority. Legacy `ImageInputPolicy` and invented account IDs are not used.

At actual current host request admission, text is consumed first. The screen provider's two read-only accessors, `current_observation(native)` and `owns_observation(observation,native)`, expose/check the original issued object under its existing lock. Only `assembler.completed(original_observation)` can supply the image claim. `claim.owner` is that original object with original native request/session/source/revision/capture/digest fences. It is never a recreated observation or serialized authority.

Selected Accessibility text takes priority and admits no image. Missing/unverified/incomplete/expired image data falls back before POST to one ordinary text request, with accurate OCR/selected-text provenance. In particular, a cancelled partial image transfer followed by the original EOU still permits valid OCR text. A matching `supplemental_context_retired` clears staged text and PNGs before EOU even when `host.active` is null. Late old retirement preserves an independently fenced newer stage. Current retirement clears the original issued source and dependent answer before callbacks.

## Model call and final publication

The host creates one private request permit immediately before generation, using its base `supplemental_request_current` check of actual native object, token, session/sequence/presentation, permission and personal-source state. This callback is independent of supplemental/image validation, preventing recursion through `SessionHost._current`. The existing one-active/newest-pending answer worker remains the only normal generation worker.

The same configured `complete` receives that permit, making exactly one Responses POST with one inline PNG. A failed image call never silently makes a second text POST. After completed output, the helper awaits actual-bearer `validate_visual_publication`, then checks current host/producer/permit state. Lost image proof withholds the answer; it cannot downgrade an image-derived result to text metadata. Error/abstain terminals contain no image-derived card. Disabling images cancels only image-dependent work, preserving unrelated personal/reference answers.

Host-built `provenance.taskContext` keeps exactly its three existing keys: `provenance`, `source`, and `capturedUptimeNanoseconds`. It adds only `imageDigest` when the actual current permit reports `used_image`. That value is the original native canonical-pixels digest, distinct from SHA-256 of encoded PNG bytes. Model output cannot supply it.

Native independently requires matching original three-field context, original pixel digest, a complete image offered for that original request, a bounded `requiringImageIdentity:true` source recheck, then synchronous original lease/ownership checks at atomic panel commit. An absent image digest permits honest text fallback even if an image was offered. Raw PNG bytes clear after the request while original owner/permit evidence remains valid for publication, as defined by the unchanged reviewed authority port.

## Reuse and measured boundary

This adds `visual_host.py` and narrow Python composition changes; it reuses `VisualInputController`, private receipts/permits, HTTPX0.28.1, existing SSE/Responses assembly, `ScreenImageAssembler`, PNG validation, context admission and the existing model worker. No SDK, framework, dependency, capture implementation or auth framework is added. [Primary research and source pins](https://github.com/KanujVerma/relay/blob/a18fb5d905b6298d04d981503eabe075ed3b332e/docs/research/VISUAL_INPUT.md) retain upstream licenses and actual-reuse evidence.

Synthetic tests exercise actual helper subprocesses with HTTPX MockTransport, including responsive cancellation, replay, selected-text priority, incomplete images, source retirement, publication changes and no extra POST. Existing loopback socket tests remain separate from account inference. Current capture still requires a valid OCR observation; image-only capture is not implemented. The small case-study fixture response now uses workflow/problem/success talking points without code, preserving its explicit synthetic assumption. Production generated-answer policy is unchanged by this patch.
