# Visual helper backend handoff

Branch `feature/visual-host-adapter-2026-10-23`, issue [#73](https://github.com/KanujVerma/relay/issues/73). Own incremental base is exactly `c20e1eb3287397caa15205e0c036afbc6e21deb7`, combining the clean visual primitive handoff with accepted answers `b33292f12dd8148fe41518acf514703a9d01d49f` and frozen composition `86d69e627c86ec17073c8bd57a9a2deb68c8356a`. PR #74 and its frozen foundation are unchanged. Root retains the later Swift-only composition fix independently.

## Implemented

[VISUAL_BACKEND.md](../VISUAL_BACKEND.md) owns the concrete helper wire, idle-only probe lifecycle, local PNG staging, original-observation adapter, model/publication flow and exact native consumer expectations. Root approved these APIs/wires before shared routing changes; the native owner confirmed the exact response/reason pairs and 35-second waiter budget.

One probe task remains independently cancellable and stdio-responsive. Its terminal emits only after task quiescence. Exact control replay never repeats IO; changed payload under a reused UUID fails closed. Default and fixture helpers remain inert for image inference. The same actual configured OAuth stream handles probe and normal answers, with existing request budgets and no fallback billing or second POST.

Image chunks stage locally through the existing public assembler, then bind to the actual issued current OCR observation at accepted request admission. Two screen-provider accessors are read-only. No legacy policy/fake account ID is used. Image permits require base native/token/permission checks, avoiding recursion; actual bearer continuity is rechecked before helper publication. Host-built optional imageDigest is the native pixel digest and exists only after actual image use. PNG bytes clear without destroying original publication ownership evidence. Unknown/incomplete images use one honest text request; failed image calls never retry automatically.

Matching pre-EOU retirement now clears staged text/image even without an active host request. Old retirement cannot clear newer staging. Disable cancels dependent image work while preserving unrelated personal/reference answers. A source-onset during a large partial transfer clears old staging before any model call. A completed image result cannot become text-only metadata after losing its permit. The demo-only case fixture uses workflow/users/problem/success points and no code; production policy files are untouched.

## Verification

Accepted-dependency baseline: **524 Python tests, 21 optional converter skips**, no failures. Focused backend suite: **30 passed**, including **six real helper subprocess tests** with injected HTTPX. Missing APIs, repeated completed transfer, early probe terminal, pre-EOU retirement, lost permit, mismatched transport credential read and model/publication boundaries were observed failing before their fixes. All images/tokens/sources are synthetic; no private user data, actual OAuth/account probe, capture, AX, permissions, model download or external inference was used.

Final full suite: **554 Python tests, 21 optional converter skips**, no failures. EVALS: **26 synthetic questions**; documentation: **20 required files/local links**; diff whitespace check passed. Existing HTTPError/SQLite ResourceWarnings and expected negative CLI messages remain; helper subprocesses exited with empty stderr. Tests used existing HTTPX0.28.1 without installing anything. Source/patch hash are recorded with the frozen source checkpoint and controller report.

No Swift, CI, root handoff/ADRs or global contract files were edited by this lane. Independent exact-head backend review, native consumer integration, hosted CI and real account/window acceptance remain separate. Root owns assembly and any main merge.

## Exact next action

Root reviews the single incremental backend commit against c20, preserving the accepted generated-answer and later native fixes. Native owner consumes the approved eight-field status protocol, ordered lazy image writes, complete-offer proof and optional imageDigest final gate on its separate Swift branch. Both must be joined and tested before claiming end-to-end app visual input. Image-only capture remains unsupported because the current screen observation requires OCR.
