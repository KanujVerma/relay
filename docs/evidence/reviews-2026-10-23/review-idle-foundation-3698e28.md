# Standalone assistant foundation review

Exact3698e28cb7503ca679b9cfde4764d40abe8eea61, PR89, independently reviewed in clean detached work/relay-review-idle-3698e28. Accepted at native/helper scope boundary. No integration-app exposure, GitHub approval or main merge.

NativeAssistantSessionController issues a separate noncapture lifetime with owned open/close tickets and fresh typed/cancel leases. Opening cannot issue until its matching receipt. Close withdraws display authority synchronously before enqueue, and replacement cannot begin before actual completion. Invalid/stale text, basis and enqueue-failure controls preserve or retire authority as required. Its reused lease identity field does not describe capture.

Helper accepts a strict nine-key assistant namespace and bounded replay ledger. It starts the existing explicit-question machine with its synthetic audio bridge stopped; no capture authorization/EOU is fabricated. Capture and assistant cannot replace each other while live or closing. Closing fences inference and actually joins request/probe/cancel owners. A captured original CancelACK is delivered before ScopeCloseACK even after answer publication permission retires. The narrow user cancellation change does not restore answer authority and rejects a different session.

Independent96Python pass3.598s: assistant, typed question, actual Host, visual backend and original native EOU controls. Ten native scope/typed cases pass0.008s. Includes actual stdio open→reviewed reference→close with no capture frame; held worker/probe cleanup; strict/replay/budget negatives; real OAuthAnswerStream with a held token-provider thread and mocked HTTP. Old retired work makes zero POST/publication, while the new current question proceeds after release.

Scope quiescence covers its asynchronous inference/probe/cancel owners. It explicitly does not claim that an account-global to_thread token refresh ended. Account/mode/identity changes still require actual helper exit/reap. Transport receipt matching, optional owned readiness and actual Model/Home/live lifecycle/UI remain the worker's next independently reviewable increment. The initial review command named a nonexistent manual-help test module and failed test discovery; the corrected explicit96case command above is the passing result. No assertion or runtime guard was weakened.

No real capture, permission, account/Keychain, model request, private source or speech model was used. Review scratch/modules were root-owned, author source remained unchanged.
