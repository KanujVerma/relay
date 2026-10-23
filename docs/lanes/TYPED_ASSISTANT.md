# Typed assistant foundation

Branch `feature/typed-assistant-2026-10-23`, frozen runtime base `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`. Owner: typed backend/native foundation. Implementation is in progress; app-model/UI integration remains root-owned and is not enabled by this checkpoint.

Approved contract: controller commit `5de9a3184a1e0fd5027e9832cd28d3c41a1cf246`, `docs/superpowers/specs/2026-10-23-typed-assistant-design.md` and its foundation plan. Retained draft basis is bounded same-session read-only context, not an old authority lease. Idle Ask is required follow-on work.

## Backend checkpoint

Strict user-question, deny-only retirement and cancellation decoding; explicit token issuance; pure bounded typed task projection; eight retained source/task contexts; bounded replay and actual target-task cancellation receipt use the existing SessionHost/QA/reference/personal/OAuth engine. No typed input becomes remote ASR, a speaker identity or personal evidence. Existing exact-current-question ManualHelp remains unchanged.

Nine new tests passed after a missing-module red run. Affected semantic/helper/reference checks:128 tests passed,1.523s, with pre-existing synthetic SQLite ResourceWarnings. Includes an actual no-network helper child receiving typed input before any remote final. The child EOF test establishes admission/pending output, not completed model streaming. Completed mocked OAuth, native ordering and app-hook proof remain in progress and are not claimed here.

## Native issuance checkpoint

Private native UserQuestion/AnswerCancel values now issue under the same controller lock, with a fresh actual lease/UUID and original native sequence anchor. Cancel targets the controller's actual issued request and carries original-target retirement data. Existing ManualHelp behavior remains unchanged. The new API first failed compilation because NativeUserQuestionRequest was absent; after implementation,6 targeted native UserQuestion/ManualHelp tests passed,0.009s after14.40s build, using an isolated copy-on-write baseline build cache with offline dependency resolution. No audio/model/permission action occurred. Forwarder/receipt/adapter integration is still in progress.

## Intended reuse

Actual runtime reuse is existing NativeSessionController/ordered ingress, ActiveTurns, ConversationContext correction grammar, SessionHost one-worker/newest-pending routing, Personal Brain authority, reference/card QA, HTTPX0.28.1/SSEDecoder/ResponseAssembler and verified image ports. No model/framework/dependency added.

Primary reference inspected: Vercel AI SDK commit `84d788027f44a87a489d14bb2aea194b284ac1d0`, Apache-2.0, [chat cancellation source](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.ts#L769) and [tests](https://github.com/vercel/ai/blob/84d788027f44a87a489d14bb2aea194b284ac1d0/packages/ai/src/ui/chat.test.ts#L1224). Reference only; no SDK source copied or invoked. No private data, credentials, capture, permissions, account/model network or weight downloads used.

## Next work

Native private issuance and exact cancel receipt; typed/cancel forwarder ports over a private queued-item wrapper, preserving existing SessionIngress/AppModel until root integration; injected draft and bounded actual-final transcript reducers; actual helper/HTTP mock and held-request ordering regressions. Root receives a concrete integration guide before UI controls are connected. No SessionApplicationModel, auth, profile/vault, UI view or provisioning/capture teardown edits belong to this lane.
