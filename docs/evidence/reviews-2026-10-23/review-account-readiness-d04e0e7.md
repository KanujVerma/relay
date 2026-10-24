# Explicit account readiness component

Exactd04e0e7647f189140ea9fce9c204a2656cbd1c58, PR91. Independent source review and clean detached work/relay-review-account-readiness-d04e0e7;20native tests pass3.984s. Accepted at unexposed component boundary, not actual app/product integration.

One original explicit Start/Send intent owns restore/select/catalog. Repeated same-intent preparation coalesces without replacing its original currentness predicate; competing intents fail. AI-off/current-selection paths are inert. Cancellation denies the original caller before awaiting actual account task/control cleanup; wrong-intent cancellation cannot retire it. A completed owner's captured private selection remains usable by its matching coalesced waiters without old cleanup clearing a replacement owner.

The full20case library gate includes three new readiness cases and17previous native account cases, including real mocked control child/exit. No real account/Keychain/browser, capture, private data or model request. This does not prove actual Model/helper retirement, a held product token thread or final frozen bundle. App wrappers must recheck original caller/Task cancellation after readiness and before issuance, and End must join readiness/control cleanup. Task.value alone is not caller cancellation propagation; this is an explicit remaining product gate.
