# Automatic Response Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans inline, task by task. Root assigned one end-to-end author; do not spawn agents.

**Goal:** Keep General automatic and add real optional protected response guides with exact original-request ownership.

**Architecture:** Reuse accepted194 protected snapshots, current native/helper authority, one ordered transport and one generation worker. Native coordinator owns catalog/read/save receipt state; the app couples one immutable preference activation to a genuine request; the helper claims staged data only at actual native admission. Final publication composes preference ownership with original native and visual gates.

**Tech Stack:** Existing Swift/Foundation/Combine/CryptoKit/Security and Python stdlib/HTTPX mock tests. No new SDK, model or classifier call.

**Spec:** `docs/superpowers/specs/2026-10-23-response-preferences-design.md`, approved exact5e09548 plus explicit built-in Use may create first empty catalog/key.

## Global constraints

- Frozen base3e83; own clone/branch only. Default/fixture/render/typing/General perform zero storage/helper/model operations.
- Separate fixed responsePreferences protected purpose,32KiB catalog/eight guides/64-byte names/2048-byte guidance.
- One actual storage flight; original ID-scoped cancellation; actual IO joins before availability; committed receipt fences stale disk writes on restart.
- Eight staged offers, two-second expiry,512 replay/retirement entries; original actual native identity;32frames/256KiB writer unchanged.
- Preference text never supplies facts, permissions, account/model configuration or code-language authority. Original currentness and generation budget remain.
- No real Keychain/private files/account/capture/audio/model calls. Root owns actual UI/packaged window acceptance.

## Task1: protected native preference component

**Files:** import exact accepted194 source/test trio as dependency; new `macos-profile/Sources/RelayProfile/ResponsePreferences.swift`, `ResponsePreferencesCoordinator.swift`, `ResponsePreferencesJSON.swift`; narrow fixed-purpose enum/policy additions; tests `ResponsePreferencesTests.swift`.

**Interfaces:** `ResponsePreferencesCatalog` strict data; immutable privately constructed `ResponsePreferenceSnapshot`; `ResponsePreferencesReceiptStore` native committed-revision/enable port; `@MainActor ResponsePreferencesCoordinator` inert init, explicit open/save/use/delete/prepare, cancel and actual quiescence. `capture()` returns optional immutable snapshot; `owns(_:)` compares actual activation identity on MainActor. Existing protected snapshot signatures remain unchanged.

- [x] Import exact194 three runtime/test blobs and record source hashes, excluding its independent history docs/runtime.
- [x] Write failing fixed-purpose tests first: ciphertext file/header/key isolation, owner/nonrecursive directory checks, profile/history/account compatibility.
- [x] Run those tests red; add exhaustive responsePreferences cases and shared non-profile directory policy; run affected protected/profile tests green.
- [x] Write data/coordinator tests for strict duplicate/unknown/UTF8/size/schema domains; General zero operations; explicit Coding first Use; missing/corrupt remembered restore; held real synchronous save cancellation; stale successful disk receipt rejected after reconstruction; newer edits/old cancellation and actual busy joins.
- [x] Run red, implement strict bounded catalog, receipt and owned coordinator, then run affected tests green. Use actual temp encrypted vault + injected fixed keys and an NSCondition-held storage wrapper; no real Security calls.

```swift
let coordinator = ResponsePreferencesCoordinator(storage: fixtureVault, receipts: fixtureReceipts)
XCTAssertNil(coordinator.capture())
XCTAssertEqual(fixtureReceipts.reads, 0)
try await coordinator.useBuiltin(.coding)
XCTAssertNotNil(coordinator.capture())
let stored = try ResponsePreferencesCatalog.decode(fixtureVault.load())
XCTAssertEqual(stored.selected, "coding")
```

For a held save, select General while the actual `save` call is blocked, require busy and disabled receipt until release, then reconstruct against those disk bytes and prove stale selection cannot activate.

- [x] Freeze/push native component with exact tests/handoff and send immutable head to root/history owner before integration.

## Task2: strict helper claim and prompt use

**Files:** new `relay_spike/response_preferences.py`; narrow `session_host.py`, `generated_answer.py`, and exact native-retirement cleanup hook in `user_question.py`; new `tests/test_response_preferences.py`; native optional generated provenance decode in `SessionDecision.swift` and focused tests.

**Interfaces:** `HostResponsePreferences.stage(value)`, `retire(value)`, `claim(native)` returns privately owned use or nil; `owns(use,native)` leaf checks never recurse to base currentness; `close()` drops timer/data. `make_prompt(...,response_preferences=None)` adds only actual typed focus/guidance. Host-only optional generated provenance UUID records actual supplied activation. Native decoder accepts that one exact optional field alongside existing taskContext.

- [x] Write failing exact stage/retire/claim tests covering duplicate changed reuse, all identity counters, zero authority from stage, late attach, expiry/EOF and old retirement preserving new scope/revision.
- [x] Implement bounded provider/one owned expiry timer; wire actual native accepted-request claim and actual synchronous retirement before helper awaits.
- [x] Write captured-prompt/MockTransport tests proving one call, actual preference prompt, no personal/config authority, no default no-inference IO, held credential cancellation before POST, no retry after POST, local reviewed/personal answers omit use metadata.
- [x] Run red, add narrow currentness/prompt/use metadata; retain current output QA and32KiB prompt budget. Run affected host/user/context/visual tests only.

```python
host = SessionHost(complete=held_mock_completion)
host.handle_assistant_scope(original_open)
host.response_preferences.stage(original_offer)
await host.handle_user_question(original_native_question)
assert captured_prompt['response_preferences']['guidance'] == 'Prefer concise invariants.'
host.response_preferences.retire(original_scope_revision)
release.set()
await host.drain()
assert not any(row['disposition'] == 'answer' for row in emitted)
```

Use actual existing native question factory/framing test helpers and actual OAuthAnswerStream+HTTPX MockTransport for the token/POST schedule; never fabricate a token or infer account permission from guidance.

- [x] Freeze/push provider/parser checkpoint with exact source hashes/tests for independent review.

## Task3: actual app and Settings join

**Files:** new focused app `ResponsePreferencesBridge.swift` / `ResponsePreferencesSettingsView.swift`; narrow actual `SessionApplicationModel.swift`, `SessionSettingsView.swift`, current answer presentation/adapters if needed; actual app tests `ResponsePreferencesApplicationTests.swift` and held-context helper support.

**Interfaces:** Model owns lazy/injected coordinator plus per-original-owner preference-use records. Existing account preparation hook stays first; owned preference restore follows before native stamping. Actual ordered ingress freezes one activation before context await and sends its frame before original EOU/user request. Synchronous revision retirement enqueues control before releasing held work. The existing owner box, current request, native authority, profile/image validation and transport remain sole authorities.

- [x] Write failing actual Model tests: default typing inert, explicit idle Send/active capture fixture restore, failed/cancelled preparation preserving original draft/basis/new edits; built-in/custom Settings commands route real coordinator; no audio or account action from Save.
- [x] Join preparation using original intent/currentness after every await; never put account restore inside a self-owned startTask or replace its callback with preferences-only work.
- [x] Write failing actual held EOU/PNG tests: active guide change/General/delete retirement reaches accepted backend before actual envelope, zero old POST, genuine unchanged positive, unused personal/reference remains. Cover failed channel withholding EOU and old scope callback/retirement not clearing replacement.
- [x] Implement bridge and final MainActor use guard without another session lock in native commit; compose with actual async OCR/image validation and recheck synchronously afterward.
- [x] Add actual Responses Settings and quiet optional label, never mandatory chooser/upload/model selection. Editor has bounded validation, real Save/Use/Cancel/Delete busy/errors. General remains reachable while store unavailable.
- [x] Verify focused strict/native/store/helper/actual-app/held context and public synthetic end-to-end cases, then appropriate final build/affected gate once. Record exact skips/limits, update lane/handoff, freeze and request independent root review.

## Verification and publication

Use isolated Swift scratch/module caches and test Python `/private/tmp/relay-root-current-runtime/venv/bin/python` with `PYTHONDONTWRITEBYTECODE=1` / `PYTHONPATH=tests:.`. Public pinned caches may be copied to own temporary dirs only. Each test's red must fail on the intended behavior before its production change. Publish reviewable scoped commits/PR96 with exact component provenance; do not claim GUI, live usefulness, device/account or shipping artifact acceptance.

All author implementation/verification steps are complete for the source candidate. Independent root review, actual GUI and newly packaged artifact are downstream gates and remain unclaimed. Accepted e846/account and160/navigation were joined as declared dependencies after the partial Task3 checkpoint.
