# Independent conversation lane review

Date: 2026-10-23. PR: https://github.com/KanujVerma/relay/pull/68.

Reviewed checkout: `<workspace>/work/relay-build-conversation`.
Immutable range: `a8f8359354f44e11be39e22a55422b2cef9f6c91..a26181ee068feb4ff1e0f3b965479df7fb07a797`.
The checkout was clean at the pinned head before review. The review covered the 25 added files / 2,159 added lines in manageable source, adapter/lifecycle, transport/package, tests and documentation passes. Only relevant existing capture/converter and pinned upstream VAD/ASR source was expanded for concerns. No source, index, HEAD or branch mutation, publication, full test rerun, capture, permission request, model artifact load/download, inference or private-data access occurred.

## Findings

**No actionable findings after actual source and test review.** No severity/correction item is being proposed. This verdict is scoped to the native conversation lane and the frozen requirements below; it does not certify real audio/model acceptance or the other lanes' independent implementations.

## Specification verdict

**Meets the reviewed native-lane contract at this head, with external acceptance still open.** The controlling reference was the integration checkout's `docs/BUILD_CONTRACT.md`, including the late-context and quiescent-ownership refinements, plus this lane's implementation plan and final builder report.

- **Independent provenance and complete closed activity:** `SourcePipeline.swift:83-119` validates source, generation, sequence, rate and bounded admission. `SourcePipeline.swift:187-243` retains packet spans and the actual closed sample interval. Its range association is explicit rather than counter matching. `SessionController.swift:145-161` allocates a separate ASR segment identity, emits the exact inner EOU shape, retains null confidence and mints request UUIDs only for remote EOU. `NativeCaptureSession.swift:153-173` owns separate converters/queues, and `FluidSessionAdapters.swift:24-42` consumes every chunk despite early EOU hints before one finish/reset.
- **Automatic host input and mic semantics:** `SessionController.swift:105-115` invalidates the presentation authority only for remote onset. Mic onset/final preserves the current remote lease and carries no request ID. The callback is a synchronous, throwing, globally ordered seam into bounded helper delivery. Python semantic authority and actual native panel painting belong to the answer/integration lanes; they are not reimplemented here.
- **Late A after B:** `SourcePipeline.swift:255-262` retains A's original activity lease. `SessionController.swift:157-161` serializes that original lease instead of retagging to the current onset. `SessionPresentationAuthority.swift:44-49` checks and commits under the same lock used for invalidation. The focused independent synthetic probe below verified that a valid late A remains available as its original event, does not replace B's lease, and cannot pass the current native display gate. Context-only treatment and inference suppression in Python remain the consumer's required responsibility.
- **Bounds and invalidation:** VAD input, activity retention, single-flight recognition and wire writer bounds are explicit. `SessionController.swift:68-82` closes authority before teardown awaits; `SessionController.swift:164-171` retires a failed source and advances remote authority before its control callback. `SessionEventWriter.swift:38-52,98-104` rejects overflow and invokes failure synchronously; pipe writes have a deadline. `NativeCaptureSession.swift:178-191` converts observed driver loss or transport failure into actual session teardown.
- **Quiescence before restart:** `NativeCaptureSession.swift:107-148` keeps restart closed while actual producer/drainer/model owners are outstanding. A deadline is represented as nonquiescent rather than successful shutdown. `SessionController.swift:95-101` and `SourcePipeline.swift:128-137,247-253` retain and join cancelled work. Owner drop also schedules producer/model teardown.

## Quality verdict

**Acceptable for integration of this scoped native slice; no blocking quality defect found.** The ownership and failure paths are reasonably small and explicit. Tests exercise the meaningful negative cases: sequence/rate/generation loss, backlog/activity limits, stale leases, cancellation, uncancellable ownership, owner drop, early EOU, independent overlap, failed/blocked pipes and fresh restart. Package defaults and CLI help are inert. Fixed diagnostics avoid printing arbitrary model/driver errors or transcripts. The documentation distinguishes compilation and fake-driven checks from measured real speech quality and latency.

Known conservative product limits are disclosed rather than hidden: one closed recognition per source, capture stops when a second closed activity arrives while recognition remains busy, 120-second activity and bounded text limits, explicit Stop/Start recovery, and added closure/recognition delay. Real target-Mac performance and recognition acceptance are needed to assess those policies in use.

## Evidence and limits

1. Inspected the final builder evidence and `/private/tmp/relay-session-final-tests.log`: the recorded run contains 7 capture/adapter tests and 20 core/writer tests, all passing. These are **builder-run results inspected by this reviewer**, not a fresh full-suite execution.
2. Read the actual pinned FluidAudio streaming VAD state machine and EOU adapter/manager seams to check the sample-index and early-EOU assumptions. The existing `ASRMonoConverter` uses the pinned stateless resampler; real boundary/quality effects remain within the explicitly pending audio/model acceptance, and no unvalidated quality finding is asserted from that alone.
3. Independently compiled the six exact-head `RelayNativeSession` source files in Swift 6 mode with an isolated temporary synthetic harness, linking the already-built audio queue dependency objects. Harness: `/private/tmp/relay-conversation-review-late-final-exact.swift`; executable: `/private/tmp/relay-conversation-review-late-final-exact`. The injected recognizer held A after closure, B then began, and A was released late. Assertions checked A's old lease and activity/input range, a remote request UUID, B remaining current and rejection of A at `withCurrentLease`. Exit 0, stdout: `PASS: late A retains original lease/range; B lease remains current; A cannot paint`.
4. The focused probe used synthetic samples and actor fakes only. It exercised the native freshness boundary, not Python inference, native pixel rendering, permissions, actual capture hardware, model weights or model quality. No full test rerun was performed.
5. This read-only review did not independently rerun packaging/signing or inspect GitHub CI. The builder's compilation/package evidence and native-to-Python nine-frame compatibility evidence remain separately attributed. Actual permission denial/revocation, device changes, overlap/echo, transcript quality, useful-answer latency, CPU/RSS and model-artifact provenance remain open external acceptance gates.

Next action: controller can incorporate this lane into the exact integration head and validate the combined synthetic transport/host/panel path. Real hardware/model use remains a separately authorized acceptance step.
