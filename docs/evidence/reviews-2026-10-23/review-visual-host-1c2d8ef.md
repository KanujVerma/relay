# Independent Python visual-consumer review

**Specification verdict: accepted for this scoped backend patch. Quality verdict: accepted; no actionable P findings established.** This is a source-review recommendation, not merge authorization, a joined native-app verdict, or real account/capture acceptance.

## Immutable scope

- Checkout: `<workspace>/work/relay-review-visual-host-1c2d8ef`.
- Base: `c20e1eb3287397caa15205e0c036afbc6e21deb7`.
- Head: `1c2d8ef2ce5d6207fd74f126845ebab48024537c`, detached and clean at start and finish.
- Own delta: eight files,1019 additions/26 deletions. `git diff --binary <base>..<head>` SHA-256 independently matched `b3b057b24e42706db495d2f097aea0e6f595240b801210ffe779c1b86f85a36b`.

Read current AGENTS, `docs/VISUAL_BACKEND.md`, `docs/lanes/VISUAL_HOST.md`, controller-canonical BUILD_CONTRACT visual-consumer requirements, accepted `ad9f587` service review, and root visual research. Reviewed the complete own delta once, then traced only necessary accepted permit/transport/assembler seams and ran focused checks. Accepted Swift composition corrections at `e45549a`, the separate native consumer, settled answer policy/auth core, and the root-owned prospective build-request grammar change were outside this patch and were not re-audited.

## Findings

None. No concrete source-visible authority, lifecycle, staging or publication defect was reproduced in this exact own patch.

## Evidence supporting acceptance

`visual_host.py` implements the strict four-field request/eight-field reply boundary, a512-entry exact-payload replay ledger, and one cancellable async probe. Duplicate operations replay their cached pending/final state without IO; a reused UUID with a different payload rejects the channel and cannot create a competing terminal. Verify checks actual idle host/worker/probe state. Default and fixture modes cannot probe. Stream admission checks the actual configured `OAuthAnswerStream.complete` binding and exact stream/model/effort/endpoint; no wire Boolean, account label or serialized receipt grants capability. Probe terminal publication occurs in the actual task's done callback, including cancellation before its coroutine starts.

`SupplementalContextProvider` stages one bounded OCR observation plus the existing PNG assembler before EOU. Staged bytes grant no host request authority. Actual current `Request.native` admission consumes the text, obtains the screen provider's original issued observation, matches assembled identity, and creates a claim owned by that exact object. The read-only screen accessors enforce current fences and original observation identity. Selected Accessibility text admits no image. Matching pre-EOU retirement clears staged OCR/PNG without an active answer; old retirement preserves independently fenced newer staging. Onset/stop/disable clear the appropriate staged bytes and original source ownership.

`SessionHost._generate` uses the existing one-active/newest-pending worker and generation deadline. Base current-request callbacks remain independent of permit validation, so the permit-to-provider checks do not recurse through `_current`. Unknown/incomplete image proof takes one text path before POST; a failed image POST produces no automatic text retry. Image publication awaits actual bearer/configuration validation through the accepted stream, then synchronously checks original permit/base ownership before the normal host result gate. Lost image proof cannot downgrade an image-derived answer into text metadata. Host-only optional `taskContext.imageDigest` comes from the original native canonical pixel identity and only actual transport-owned image completion; AX/text results omit it. Disable cancels dependent image work while leaving unrelated personal/reference results admitted.

The tiny case-study fixture response and test import correction are declared and limited to synthetic behavior/import resolution. No production auth core or generated-answer policy change appears in the delta.

## Fresh reviewer verification

All commands ran in the immutable checkout above, using the existing HTTPX0.28.1 environment. No dependency was installed.

```sh
PYTHONDONTWRITEBYTECODE=1 /private/tmp/relay-answers-venv/bin/python -m unittest tests.test_visual_host_backend
```

Observed exit0: **30 focused tests passed in1.210s**, zero failures/skips. This includes six real helper subprocesses with inherited framed pipes and HTTPX MockTransport, plus staging/original-owner checks, exact replay/no competing terminal, idle/default behavior, cleanup ordering, one image generation, text/AX/incomplete-image fallback, pre-EOU retirement, source-onset retirement, token/config/consent publication veto, lost permit, no automatic second POST, and the declared case fixture. The subprocesses used synthetic tokens/catalog/PNGs/SSE only; no actual account/network model call occurred.

An additional reviewer schedule deliberately held the probe HTTP cleanup open after cancellation. It uses the production host and configured OAuth stream with the existing synthetic MockTransport fixture. Harness: `/private/tmp/relay-review-visual-host-1c2d8ef-probe.py`.

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /private/tmp/relay-answers-venv/bin/python /private/tmp/relay-review-visual-host-1c2d8ef-probe.py
```

Observed exit0:

```text
held cleanup: drain_done=False terminal_count=0 stream_active=True
released cleanup: drain_done=True terminal_statuses=['cancelled'] stream_active=False calls=['GET', 'POST']
```

This independently confirms close/drain does not certify quiescence or emit the probe terminal while owned cleanup remains active, and no extra model request is introduced by cancellation.

Exact identity and whitespace verification:

```sh
git status -sb
git rev-parse HEAD
git diff --check c20e1eb3287397caa15205e0c036afbc6e21deb7..1c2d8ef2ce5d6207fd74f126845ebab48024537c
```

The checkout remained clean at the exact reviewed hash; diff whitespace checks passed. The binary patch digest was computed directly from `git diff --binary` bytes with SHA-256 and matched the supplied value.

## Limits and integration boundary

No full Python/native suite was rerun; the builder's554 tests/21 optional converter skips remain builder evidence. No source/index/HEAD mutation, commit, push, PR write or subagent occurred. No real screen/audio capture, permission prompt, Accessibility selection, global key, pasteboard, private source, Keychain, credentials/account service, model download/inference or socket test was used. MockTransport does not establish real account support, visual quality or latency.

This patch is the Python consumer only. Native lazy bounded image production, status-waiter ownership, complete-offer proof and canonical pixel/lease publication enforcement belong to the parallel native consumer and require joined-head verification. The current source pipeline still requires valid OCR; image-only capture is outside this slice. The old Swift composition source in this base is not reaccepted here; root must retain the separately accepted `e45549a` corrections during assembly.
