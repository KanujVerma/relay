# Typed assistant foundation

Branch `feature/typed-assistant-2026-10-23`, frozen runtime base `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`, draft [PR83](https://github.com/KanujVerma/relay/pull/83), base branch `build/cluely-parity-foundation-2026-10-23`. Owner: typed backend/native foundation. The backend/native/transport/draft/transcript ports are implemented. Root-owned app-model/UI integration is not enabled by this branch. Exact consumer APIs and callback order are in [TYPED_ASSISTANT_INTEGRATION.md](TYPED_ASSISTANT_INTEGRATION.md).

Approved contract: controller commit `5de9a3184a1e0fd5027e9832cd28d3c41a1cf246`, `docs/superpowers/specs/2026-10-23-typed-assistant-design.md` and its foundation plan. Retained draft basis is bounded same-session read-only context, not an old authority lease. Idle/audio-unavailable Ask needs a separate noncapture lifetime and remains required follow-on work.

## Implemented ports

- Strict typed11-key, deny-only retirement7-key, cancellation9-key and actual completion10-key schemas; exact bounded UUID replay,512-operation ledger,8 cached latest responses and8 original task/question records. Typed text never becomes remote ASR, a speaker identity or personal evidence.
- Explicit fresh semantic issuance in the existing ActiveTurns, preserving actual audio replay/sequence watermarks. Each request carries its own pure bounded task projection; current microphone gaps survive retained-basis follow-ups. Current personal/source context is retrieved again, with existing personal/reference/card QA.
- One actual inference worker and newest pending request. Original-request denial precedes held-frame release. Cancellation captures and joins only its target task, including an uncooperative worker; no timeout supplies false quiescence. Retiring an active original request also releases its admitted screen observation/bytes through the existing provider port.
- Privately constructed native typed/cancel values issued under the same native source lock, fresh actual lease/UUID and original native sequence anchor. Typed issuance requires a live source. Existing ManualHelp remains unchanged.
- Explicit ordered forwarder ports and owned helper cancellation parser/waiter, with exact target/session/epoch/generation matching. Unknown or mismatched receipts fail the transport and resolve its actual waiter.
- Injected `TypedAssistantController`: local draft/revision, visible retained original basis, explicit new/latest actions, real Help and async Stop. Missing/evicted/cross-session basis preserves the draft. Late helper failure restores submitted text/basis only if the cleared revision remains untouched; newer edits survive. Late cancellation cannot clear replacement work.
- Ephemeral `SessionTranscriptStore`: associated native final schema/time/source checks, source labels Microphone / Selected app audio,64 whole rows /64KiB, bounded original activity association, whole-row eviction, pause sealing, End clearing, source-revocation purging and no late restoration. No persistence or memory promotion.

No `SessionApplicationModel`, `SessionIngress`, UI view, auth, profile/vault, model provisioning or capture teardown file was edited. The foundation compiles against the existing app but adds no enabled stub controls.

## Verification

All inputs and responses were synthetic. HTTPX0.28.1 came from the existing `/private/tmp/relay-answers-venv` interpreter. Swift dependencies used isolated copy-on-write baseline caches with offline resolution; no package/model installation, capture, permission, private account/credential or model network action occurred.

| Check | Result | Evidence boundary |
|---|---|---|
| Affected Python user/helper/semantic/context/reference suites |137 passed,1.632s | Actual SessionHost and no-network child; complete mocked OAuth additionally covered below |
| Native session package |27 passed,0.881s | Native source lock/sequence/issuance and existing lifecycle; includes last-source-loss rejection |
| Explicit and existing ordered forwarder suites |7 passed,0.013s | Original denial before held release, no reorder, bounded queue and optional-work deadline |
| New/affected panel foundation suites |20 passed,1.631s | Draft/controller, transcript, real transport receipt and actual helper/MockTransport proofs |
| `git diff --check` |Passed | Source hygiene only |

Tests began red for absent typed modules/native types/forwarding ports/receipt parser/draft/transcript reducers. Targeted behavior regressions also ran red before their fixes: old-target cancellation crossing a newer generation, lost current microphone gap in retained projection, last-source-loss typed issuance, missing-latest silently dropping basis, malformed transcript confidence/field sets, and original issued-screen cleanup. Independent review reproduced a denied original request expiring before helper admission; its fresh Cancel previously lost the receipt. The fix allows a fresh cancel of a known target at or ahead of helper presentation while rejecting a target older than the current presentation. Original2s request freshness is unchanged. That stale-original regression returns `already_finished` and zero model requests, while old-target/newer-request rejection and actual target-task join stay green.

Actual helper/transport proof uses `tests/support/visual_backend_helper.py`, which requires an explicit synthetic flag/temp log, injects real OAuthAnswerStream plus HTTPX MockTransport, inspects random probe pixels and never reads real credentials or opens an external connection. It establishes:

- Typed Ask before **any remote final**: personal question clarifies, reviewed reference uses no model, ordinary typed question completes the existing SSE path. Exactly one text POST, no probe or image POST.
- Unchanged original actual native VAD/ASR final with staged synthetic PNG: exactly one image POST, completed answer and canonical image-use provenance.
- Stop while the actual original audio EOU/PNG is held: original deny goes first, original EOU is released before later native onset, actual cancel receipt resolves, zero image/text POST. The test deliberately lets the child process released EOU before writing Cancel, so missing denial would produce a POST.
- Typed supersession of that held audio/PNG: zero old image POST, exactly one fresh text POST.
- Both microphone and selected-app transcript rows originate from the actual NativeSessionController using injected synthetic VAD/recognizers. Late, unassociated, malformed, duplicate and retired data cannot enter or restore the read view.
- Wrong target/session cancellation receipts resolve the actual pending waiter with error, without waiting for its15s deadline or losing ownership.

An additional red/green draft regression covers an owned context-unavailable terminal arriving after a newer current audio/question binding. It can recover only the exact submitted UUID/session/epoch/generation/anchor and untouched cleared revision; a mismatched anchor is ignored, newer edits and current response ownership are preserved. This local draft recovery grants no publication authority.

Final local logs: `/private/tmp/relay-typed-python-final2.log`, `/private/tmp/relay-typed-native-final.log`, `/private/tmp/relay-typed-forwarder-final.log`, `/private/tmp/relay-typed-panel-final5.log`. The five actual helper/native proofs also passed after the cancellation review fix,1.235s (`/private/tmp/relay-typed-helper-after-review-fix.log`). Unrelated full Python/native suites were not rerun in this bounded slice. Copied SwiftPM manifest caches emitted read-only cache warnings; all listed compilation/test commands completed successfully.

## Reuse and limits

Actual runtime reuse is existing NativeSessionController/ordered ingress, ActiveTurns, ConversationContext correction grammar, SessionHost one-worker routing, Personal Brain authority, reference/card QA, HTTPX0.28.1/SSEDecoder/ResponseAssembler and verified image ports. No model/framework/dependency was added. The committed PNG fixture is programmatically generated synthetic1x1 data, built with the existing screen-test utilities; no competitor asset/source is included.

Primary reference inspected: Vercel AI SDK commit `84d788027f44a87a489d14bb2aea194b284ac1d0`, Apache-2.0, [chat cancellation source](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.ts#L769) and [tests](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.test.ts#L1224). Reference only; no SDK source copied or invoked.

Root must independently review the final delta, wire actual app enum/receive/bind/commands through the same ordered queue, and run a joined app/helper held-EOU/PNG regression plus positive control before UI exposure. Current tests prove the foundation ports, not that future app callback join. Standalone idle Ask, broader modes/history and actual physical capture/account acceptance remain separate. Locked-Mac visible runtime acceptance is not claimed.

## Narrow semantic-basis review correction

Review of `0bbe896` reproduced personal q1 -> short basis follow-up q2 -> Help incorrectly reaching the general model. A second Ask based on q2 had the same issue. Retained basis now stores exact display text and the actual semantic request separately, plus a flat tuple of original supplied question contexts. Help uses the current stored semantic request with fresh token/retrieval; chained Ask renders that flat context once. No old bundle, lease, pixel or personal approval is retained. The rendered semantic context is bounded to6000 UTF-8 bytes, matching the existing dialogue text budget; overflow withholds via `user_request_context_unavailable` before provider/model work instead of dropping a personal ancestor. Toolbar Help for typed requests must use new `help_current`, while legacy ManualHelp remains audio compatibility behavior.

Four added regressions ran red before the correction: personal follow-up Help, technical follow-up semantic/task preservation, a second short personal Ask, and bounded ancestry exhaustion. They now pass within137 affected Python tests,1.632s (`/private/tmp/relay-typed-ancestry-green.log`); unchanged actual helper/native proofs passed5 tests,1.290s with the new Python runtime (`/private/tmp/relay-typed-helper-semantic-fix.log`). Existing stale-original Cancel, old-target/newer rejection, actual target join and draft recovery remain covered. No wire, native source, Model or UI file changed in this correction.

## Legacy Help caller compatibility

Root review of `b5aa2ae` found that accepted legacy audio Help was not retained in the typed read-only basis map. The visible Help UUID therefore could not be used for a typed follow-up. Accepted ManualHelp now captures the actual current task projection and enters the same8-record bounded map with its existing exact display/semantic question; it keeps the original legacy token/admission/equality/anchor contract. A new audio -> legacy Help -> typed follow-up regression failed red before the narrow correction. Rejected stale/mismatched Help remains unrecorded with zero extra work. Affected Python evidence and exact correction head are recorded in the scoped compatibility handoff.
