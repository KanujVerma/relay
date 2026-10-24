# Saved-context app lifecycle join

Owner `/root/compose_context_controls`, GPT-6.1 Sol xhigh. Own branch `feature/saved-context-app-2026-10-23`, frozen base `bd99b0af13577177508b22a9648a4b0ff6c2b12a`, PR target `build/saved-context-app-foundation-2026-10-23`. Accepted profile coordinator/core352703e is already in the base. This lane owns only Model saved-context/profile lifecycle, My Context wrapper, focused joined tests and this lane note. Root owns concurrent typed Model integration/reconciliation. No profile core, store format, Python/provider, speech/capture/transport core, account or package changes.

The real app now has synchronous `openMyContext()` / `lockMyContext()` ports and observable lazy `contextUse`. My Context observes its actual snapshot and routes existing View actions through these ports. Appearance constructs inert objects only; explicit Open enables the one remembered Boolean, and Lock disables before await. Default fixture mode uses an ephemeral off preference and cannot explicitly open unless the test injects both preferences and a vault factory. Tests never consult standard preferences or the real profile/key.

`SharedProfileBinding.id` is the stable actual controller/binding lifetime, including initial lazy child launch. Required coordinator guards inspect the actual cached controller, current nonretired binding and permanently bound helper; the prelaunch helperIdentity is never treated as stable profile identity. Profile responses are rechecked against that actual binding/child after await. A nil-default read-only post-response observer can hold actual accepted receipts in tests; it cannot filter/mutate requests, responses or native events.

Normal Start preserves existing source/recording/speech/configuration checks, then restores only existing context before capture. It rechecks the actual Start/source/preference/binding/opened/not-busy state before admission. The injected fixture path uses the same restore gate before the actual native fixture start. Requested missing/unavailable restoration aborts with fixed recovery, and reachable Lock allows a later context-off Start. Disabled use skips profile IO. Native eligibility also blocks on actual profile/coordinator work.

Pause/End/helper retirement synchronously retire profile use and retain the remembered preference, then join actual context work with existing Start/capture/helper barriers. Existing staged screen retirement order stays intact. End retires the shared helper/cache; a later Start loads the existing vault into a fresh actual helper. An already closed idle workspace does not launch profile work merely for Stop. The AI-mode close check applies to actual opened/busy profile ownership; no account/auth behavior is added.

## First actual-helper checkpoint

Four new `SavedContextApplicationTests` use the actual stdio session helper, fake32-byte key, fake settings and fictional encrypted temporary vault. The API tests were red on absent Model ports before edits. They then passed4/4 in2.107s:

- inert offscreen workspace value/layout and opted-out fixture Start/End perform zero profile commands/key calls/vault creation;
- explicit Open approves one fictional self-owned source fact, End retires old controller/helper, and the next actual helper restores that exact fact before native session admission; saved encrypted bytes remain unchanged and no new key is created;
- missing requested vault aborts with zero native starts, profile commands/key calls/files; Lock permits an actual fixture session without creating the vault;
- explicit Lock while an accepted actual load_commit receipt is held disables use immediately and prevents late native Start; a subsequent context-off Start succeeds.

Log `/private/tmp/relay-saved-context-app-first-green.log`. Explicit interpreter `/private/tmp/relay-answers-venv/bin/python`; owned build scratch `/private/tmp/relay-saved-context-app-build`. Dependencies reuse their exact existing public pins/artifact; no model weights downloaded or loaded. Initial SwiftPM public-artifact fetch was denied by sandbox, then its existing reviewed artifact was copied locally. No private credentials obtained or Relay profile Keychain touched.

The affected application target collected43 tests:39passed,4explicit opt-in skips, zero failures, in6.911s (`/private/tmp/relay-saved-context-app-checkpoint-affected.log`). Skips are real public-model/offline-audio acceptance, actual bundled-runtime acceptance and two optional render exporters. All actual staged visual helper cases ran. `relay-panel-session` builds (`/private/tmp/relay-saved-context-app-checkpoint-product.log`). Local sandbox NSWorkspace registration/cleanup warnings are nonfatal; no real external content is read.

The exact test-only799151c compatibility patch is imported as a declared dependency: two model-owning presentation tests use async XCTest to avoid the independently reproduced Swift6.2 isolated-deinit runtime abort. Its original hosted red40044727949 and exact-source green40045630474 both used the same Intel/Xcode26.2 toolchain; it changes no assertions/runtime. Root may pick only this lane's feature commits when that patch is already assembled.

More focused End/replacement/AI/late-work negatives remain before final review. Actual microphone/process-tap permission/capture, signed aggregate product packaging and visible UI acceptance are not performed on the locked Mac. This synthetic joined proof is not a real interview/account/capture acceptance claim.
