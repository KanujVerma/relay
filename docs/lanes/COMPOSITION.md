# Context and controls composition lane

Branch `feature/context-controls-composition-2026-10-23`, isolated checkout `work/relay-build-composition`. Initial answer dependency `cd5286a50700b8040f9e9b03b65c8f960e98fb1c`. The controller explicitly owns global HANDOFF, contracts, status and CI; this lane changes none of those. Main merges remain separately authorized.

## Dependencies and actual reuse

Reviewed screen `e3fcfbe3d7f6caa87e2ba3d95f0cb012fc1781ca` and corrected controls `2fc2db5c767d8ef892d030487bd7a281f418e366` are imported by explicit ancestry. The answer frozen correction is pending; existing app/helper/router/UI seams remain untouched until that head is imported. Personal `eb98e41` has scoped review acceptance, while actual process-reaping native acceptance is still under investigation by its owner.

Actual invoked existing components: strict `panel_wire` JSON/framing checks, existing `ContextSnippet`, and `SupplementalScreenProvider` exact screen schema/admission. New Swift ordering/publication modules consume `RelayNativeSession.NativeSessionEvent`, `PresentationLease`, and `SessionPresentationAuthority`. No library core is copied or changed. Next composition imports native `a26181e`, final answer/profile corrections and controller CI ancestry explicitly.

ScreenKit/Vision adapters and tests are supplied by `RelayScreenContext`; [its notices](../../spikes/macos-context/THIRD_PARTY_NOTICES.md) retain exact Apple examples/API and license evidence. [Controls notices](../../spikes/macos-controls/THIRD_PARTY_NOTICES.md) identify MIT KeyboardShortcuts pin `772133d9dbe800fdac0473226822994c5c162c58` (Swift tools 6.2). Existing MCP/HTTPX/OpenAI source/test research remains in [upstream reuse](../research/UPSTREAM_REUSE.md). This lane adds no framework, image model, network route or source copy. Actual native app wiring remains pending at this checkpoint.

## Approved composition behavior

One bounded ordered pump may hold a remote EOU for at most 1.5 seconds. A newer onset/control cancels optional work and immediately forwards the original EOU without context before the later event. Original global sequence/session/request/epoch/generation is never restamped. Queue overflow retires, and late OS completion cannot send after retirement. Exactly one selected-text or OCR frame precedes EOU. The helper stages syntax only for at most 2 seconds; its actual validated current Request must supply the original native envelope before any provider ingestion. Late context cannot attach after generation starts.

Selected text has a separate strict wire schema, source application/PID/launch identity, consent UUID, capture time and observation UUID. It uses existing generic `screen_text` task kind with explicit `selected_accessibility_text` provenance, never `local_ocr` or biography authority. Selected text has deterministic priority over OCR. Actual source/provenance will appear in the app. OCR answers require one bounded re-observation followed by synchronous original native lease plus coordinator ownership checks before the panel's own atomic commit. The image route stays off.

Help is a separate manual request referencing an active authorized native session, fresh UUID/newer native lease and exact latest forwarded audio sequence anchor. It reruns only the current accepted verbatim question and semantic token; it never fabricates audio, ASR text/finality or timestamps. With no current question, the visible result is Ask a question first. Pause ends actual capture admission and clears ephemeral dialogue/task state; resume starts a fresh native session only after actual old ownership quiesces. Protected preparation and explicit source/shortcut consent may persist.

## Verified checkpoint 1

New disjoint Swift package: 8 synthetic tests passed, zero failures. They cover original event identity/order while capture is delayed, prompt newer-onset release, late uncooperative capture after retirement, overflow, deadline release, changed native lease/source ownership during awaited validation and one terminal observation. New Python staged-provider suite: 6 tests passed; reviewed screen provider suite: 20 passed. No real screen, AX selection, global shortcut, private source, Keychain, capture/model/account or network inference was exercised.

Swift command uses temporary cache/build roots with `CLANG_MODULE_CACHE_PATH`, `SWIFTPM_MODULECACHE_OVERRIDE`, `swift test --disable-sandbox --package-path spikes/macos-composition --cache-path /private/tmp/relay-composition-cache --scratch-path /private/tmp/relay-composition-build`. Existing pinned source and public binary artifact caches were copied read-only from the answer checkout into the temporary build root; no peer files changed. The first ordinary cache attempt was unwritable and the network artifact fetch unavailable. No upstream tests or real model operation are claimed.

Next action: import frozen answer corrections, then wire the reviewed production context/controls adapters into the actual single-helper app and test the joined path.

## Approved delegated native seam

The controller explicitly delegated only `NativeSessionController.issueManualHelp(expectedEventSequence:expectedLease:question:enqueue:)` plus nonpublicly constructed `NativeManualHelpRequest`. It uses the existing source-stamping NSRecursiveLock to compare actual native sequence/lease, issue a newer native lease/UUID/time and synchronously enqueue the manual binding before later audio can stamp/emit. It does not consume an audio event sequence. Stale queued audio rejects the request; throwing ingress retires actual authority/source admission. App eligibility and helper exact semantic question/token remain separate checks; a Boolean is not proof. No generation exception or other native library behavior is changed. This delegated seam requires explicit independent composition review.

Selected AX reads occur only on explicit Help after enablement, matching the reviewed consent UI. Automatic questions use optional selected-window OCR. The helper hook admits one frozen snippet before route selection; technical context bypasses reference matching, while personal output stays exact provider-backed facts and does not consume task context. A strict host-owned provenance field will identify actual task-context use so ignored OCR cannot veto a personal/reference answer.

## Verified checkpoint 2

Atomic native manual issuance passed 3 focused synthetic tests after the missing-type/method red run: original audio sequence stays contiguous, manual ingress precedes the next real onset, a stamped but unforwarded event rejects the stale anchor without changing the current lease, stale lease rejects, and throwing manual ingress retires native/source admission. The complete native-session package then passed 30 synthetic tests (7 capture/adapter and 23 native core/writer/manual), zero failures. The composition package remains 8 passing tests after using one typed audio/manual ingress. The staged Python provider now passes 7 tests plus the reviewed screen provider's 20, including future manual context staging without mutating the currently issued observation. No app/helper seams have changed at this checkpoint. The new host composition tests deliberately fail on the absent admission hook until frozen answer fixes can be imported.
