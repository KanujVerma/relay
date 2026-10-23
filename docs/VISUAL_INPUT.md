# Verified optional image input

Issue [#73](https://github.com/KanujVerma/relay/issues/73). These are production Python ports with synthetic verification. The app/helper image staging adapter and visual setup UI are not connected by this patch. Images remain off in ordinary answers. Actual account acceptance, quality, latency, permission and real-window behavior are untested.

The controller-owned [primary research](https://github.com/KanujVerma/relay/blob/a18fb5d905b6298d04d981503eabe075ed3b332e/docs/research/VISUAL_INPUT.md) records official documentation, exact upstream source pins, licenses and the discovery gap. The documented ChatGPT-plan Responses route accepts images conditionally; neither catalog presence nor a cached/default Codex modality flag proves account/model acceptance. Relay uses an explicit synthetic check instead of an arbitrary Boolean. This is local verification policy, not an OpenAI entitlement guarantee.

## Explicit setup and grant continuity

Create `VisualInputController(clock=time.monotonic, receipt_lifetime=900)` without IO. Only an actual user setup action calls:

```python
consent = visual.begin_enable(stream.model)
receipt = await stream.verify_visual_input(
    visual, consent,
    is_current=actual_current_account_model_and_consent,
)
```

The required zero-argument callback must synchronously return literal `True` only for the original actual UI account/model/consent state. It cannot be supplied by screen JSON or replaced with an unconditional production lambda. Controller operations belong to the host's serial admission loop. `begin_enable` retires prior authority; it alone enables no image request. `disable()` immediately retires the capability and current permit and clears retained permit PNG bytes.

Verification reads the actual OAuth bearer through the existing auth provider, gets the documented selected-account `GET /v1/models` catalog, and checks one exact visible model slug. Catalog JSON is at most 1 MiB; error bodies are at most 64 KiB. It then sends exactly one generated in-memory RGB PNG to the existing `POST /v1/responses`, `store:false`, `stream:true`, with the same original bearer/model/configuration. No screenshot, real image input, tool, Files upload, extra dependency, API key, fallback or automatic retry is used. The six bar colors have a random order; the expected order is derived from pixels and absent from the prompt. Correct bounded output after a valid `response.completed` lifecycle issues the capability. Incorrect/refused/failed/incomplete/timeout output remains unverified. A lucky guess is possible; this check does not measure real-world visual accuracy.

The bearer is fingerprinted with an in-memory private keyed hash. It is not decoded into an account identity, exposed, serialized or logged. The receipt is private-issued and nonserializable, bound to that exact bearer, model, effort, Responses endpoint, consent and monotonic lifetime. The provider is re-read before the probe and after completion. Any bearer change, including a normal refresh, invalidates verification and requires another explicit setup check. Account switches must also synchronously retire host consent/admission. No separate account-setting read grants credential continuity.

## Trusted producer protocol

The future composition adapter supplies `VisualImagePort`:

```python
claim_for_request(original_request) -> VisualImageClaim | None
owns(claim, original_request) -> bool
release_bytes(claim) -> None
```

`VisualImageClaim(png, width, height, image_digest, owner)` copies a PNG into transient wipeable storage. `owner` is the original provider-issued observation carrying the original native request/session/epoch/presentation/source/selection/permission/capture/digest fences. `owns` must compare issued object identity and all actual current producer authority. The claim by itself grants no transport authority. `release_bytes` clears only image storage, preserving original observation identity for final validation; it must not retire the OCR/source observation merely to release PNGs.

The producer must continue using the existing strict bounded selected-window PNG assembler: PNG at most 2 MiB, each side at most 1920, original hashes/dimensions/request fences, ordered chunks and expiry, and the existing lazy queue backpressure. The new module reuses `screen_context._validate_png` unchanged from accepted screen head `e3fcfbe3d7f6caa87e2ba3d95f0cb012fc1781ca`. It adds no parser, image decompressor, capture or source authority. Current screen assembly requires a valid current OCR observation. Image-only capture is not implemented.

The production adapter uses public `ScreenImageAssembler` directly for bounded local staging. It then exposes the actual issued `ScreenObservation` only against the host's current admitted request. Legacy `ImageInputPolicy` and `SupplementalScreenProvider.image_input` remain offline/backcompat APIs and grant no authority on this new production route. No account ID is invented, and the private bearer fingerprint is never treated as a person/account identity. The verified capability plus request permit is the only network authority. Preserve the native canonical-pixels `imageDigest` separately from the permit's integrity hash of encoded PNG bytes. Assembly integration is outside this patch and still requires controller review. Unknown capability remains off.

## One attempt and publication

```python
permit = visual.prepare_attachment(
    receipt, request=original_native_binding,
    image_port=actual_selected_producer,
    is_current=actual_current_native_request,
)
text = await stream.complete(question, instructions, visual_attachment=permit)

if await stream.validate_visual_publication(permit):
    # Native then re-observes the original source within <=500ms,
    # requiringImageIdentity:true, and synchronously checks its lease/owns.
    # After that await, also require permit.validate_for_publication().
    ...
```

`complete` keeps its ordinary `str` return. Without a permit it remains the original text-only body. A valid permit adds exactly one standard `input_image` beside `input_text`; arbitrary image dictionaries cannot reach credentials or HTTP. Revalidation occurs after credential acquisition, immediately before sending, during SSE processing and after completed output with another actual bearer read. One permit cannot be sent twice. No failed image call silently triggers a second text request.

`permit.used_image` is a read-only historical completion fact owned by the local transport. Model output cannot supply it. Successful transport clears the claim's raw PNG bytes while retaining immutable original claim/owner/request/digest/issuer evidence. `permit.validate_for_publication()` stays usable after successful transport and checks the current receipt, actual original request callback and producer ownership. `await stream.validate_visual_publication(permit)` first re-reads actual bearer continuity and checks current transport configuration, without inference. The host must still use the bounded native pixel recheck, then synchronously check permit/native ownership and original lease at actual UI commit. OCR label equality cannot validate changed diagram edges.

Source/window/permission/request changes, disable, pause/end, cancellation and expiry must retire the permit and the existing answer task promptly. New permits retire older ones. Every exception/cancel path clears permit bytes. Stream failure diagnostics retain only a fixed local code, HTTP status when available, allowlisted provider code and parameter category. They never retain raw provider text, image payloads or credentials. Unsupported image/model capability revokes the capability; transient transport/503 failures do not prove no image support. A fresh Help action may initiate a separate ordinary answer, within existing admission and request budgets.

Python bytearray overwrite/release is best-effort memory hygiene, not a guarantee of erasing interpreter/HTTP copies or preventing already-sent provider work. No image/text is persisted by these ports.

## Reuse and verification scope

- Existing HTTPX **0.28.1**, BSD-3-Clause: actual AsyncClient invoked, same OAuth endpoint and no redirects/environment proxy use. Existing `SSEDecoder`, `ResponseAssembler`, total deadline, single-worker/request budgets and body builder are reused. No SDK/framework is added.
- Official OpenAI Python SDK at `56a55f243960e05e6268bb48ba6bf45299b8f90b`, Apache-2.0: its published Responses `input_text` + inline `input_image` example and request type informed the emitted standard protocol. No SDK executable code is copied or installed. Existing response accumulator provenance remains in its source module.
- Accepted Relay selected-screen provider/PNG validator is reused without changes. Apple capture/OCR framework notices remain in the screen package. Codex modality metadata was inspected as a rejected optimistic verification source; its parser/defaults are not adopted.
- Tests inject synthetic auth, HTTPX MockTransport, clock and a selected-image producer. The probe result oracle independently reads the generated RGB pixels. Existing actual localhost socket tests exercise completion/cancellation and HTTPX cleanup with fake credentials. Neither kind performs account inference or capture. The lane handoff records fresh exact counts and remaining composition/live acceptance gates.
