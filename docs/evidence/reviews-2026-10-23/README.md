# Independent review evidence, 2026-10-23

These are controller-published copies of the immutable local review reports. Workspace paths are normalized to `<workspace>` for portability; temporary harnesses/logs are supporting local evidence, not repository artifacts. Reviews are independent local agent work, not submitted GitHub approvals. Synthetic examples are fictional and contain no user biography or private material.

- [Conversation](conversation.md): a26181e accepted for scoped integration; external hardware/model acceptance remains open.
- [Personal round 1](personal-round1.md): d8bb0dc changes required. [Builder correction report](personal-fix-report.md): eb98e41, independent delta re-review [accepted](review-personal-eb98e41-rereview.md). A later full integration run found a [shutdown stall](profile-integration-stall.md); [shutdown re-review](review-personal-7ace412-shutdown.md) accepted correction7ace412 and the complete controller profile suite now passes.
- [Answers round 1](answers-round1.md): cd5286a changes required; [correction report](fix-answers-round1-report.md) at2e06c6d. [Scoped re-review](review-answers-2e06c6d-rereview.md) closed microphone/display/eviction reproductions and accepted the shared-helper seam, but found named-person attribution and correction-state follow-ups; [final correction report](fix-answers-round2-report.md) and [final scoped re-review](review-answers-b33292f-rereview.md) close both atb33292f.
- [Screen round 1](screen-round1.md): ec2ef25 one downscale-only finding. [Scoped re-review](screen-rereview.md): e3fcfbe addressed, no nearby regression found.
- [Controls round 1](review-controls-006b7bd-report.md): canceled-parent read finding; [scoped re-review](review-controls-2fc2db5-rereview.md) accepted correction2fc2db5.

Current accepted heads, hosted checks and remaining integration gates live in [BUILD_STATUS](../../BUILD_STATUS.md). A report's test totals are attributed to the reviewer or builder as stated; they do not establish live account, permissions, capture or product acceptance.

- [App composition first review](review-composition-86d69e6-report.md):86d69e6 changes required; [scoped correction re-review](review-composition-e45549a-rereview.md) accepted e45549a.
- [Visual service](review-visual-ad9f587-report.md):ad9f587 accepted within its exact six-file service scope; app/helper consumers and real account acceptance remain separate.

- [Prospective build routing review](review-hypothetical-a5827dc.md): sourcea5827dc accepted, final PR77 head62b30c4 has identical source/tests; [builder evidence](fix-hypothetical-routing-report.md) records48 focused tests and the original seven red failures.

- [Visual helper backend review](review-visual-host-1c2d8ef.md):1c2d8ef accepted;30 focused tests and an independent held-cleanup cancellation schedule pass. [Builder checkpoint](visual-host-1c2d8ef-report.md) records554 Python tests/21 optional skips and six synthetic helper subprocesses. Native consumer remains separate.

- [Native visual core checkpoint](review-visual-app-e896c2a.md):e896c2a changes required for one admitted-but-not-started write cancellation/deadline issue. Exact slow-reader reproductions sent a retired image before returning an error. [Queued-retirement re-review](review-visual-app-e01c34b-rereview.md) closed that original finding but found first-write EPIPE retirement; [final scoped re-review](review-visual-app-a227a13-rereview.md) accepted correctiona227a13. Final producer/UI acceptance is recorded below.

- [Native producer/UI first review](review-visual-app-b880fd5.md):b880fd5 changes required for one P1 pre-EOU staged-data retirement ordering issue. The actual callback-order/frame proof and accepted-backend MockTransport proof sent an old image before later onset. The original owner corrected it in c707; the next report records independent acceptance and closes this finding.

- [Final producer retirement re-review](review-visual-app-c707ef8-rereview.md): c707ef8 accepted; original P1 closed. Fourteen focused actual app/backend/control tests and original frame-order/backend reproductions pass. No stale image POST after retirement; unchanged image and OCR-only Disable controls pass. Root joined5ed2b50 passes panel64/composition17/Python558 with21 optional skips.
- Test-only launcher: [initial implementation](visual-test-helper-fedc2e6-report.md), [exact native argv correction](visual-test-helper-897238b-correction.md) and [default developer-role correction](visual-test-helper-5b03283-developer.md). Final5b03283 has no runtime authority/network path; nine builder subprocess checks and separate root native-argv verification passed.

- [Test setup correction](review-visual-test-setup-babb979.md): babb979 accepted and assembled as951b062. The feature branch gains the existing pinned mocked-helper dependency; configured-interpreter selection replaces a machine-specific temporary path. Root seven focused app tests pass; runtime/assertions/timeouts and root workflow are unchanged from hosted176-native/Python558 proof.

- [My Context candidate review](review-context-62a1f85.md): one P2 selected saved-key correction bug. [Narrow correction re-review](review-context-fe6aad7-rereview.md) accepts fe6aad7 and closes it with the original actual bridge proof: one active replacement, old fact inactive. Builder24 native/564 Python with21 optional skips; reviewer7 focused native pass. Accepted source is assembled at controller91cc199.

- [Native UI own-delta review](review-cluely-ui-a100cd9.md): owna100cd9 slice accepted, conditional on its automatic-speech dependency correction/re-review. Root10 independent actual/presentation action tests pass. Real visible UI acceptance remains open on the locked Mac.
- [Automatic speech original review](review-automatic-fbceb0c.md): one P2 obsolete-waiter cancellation can cancel a new prepare operation. Exact-source10/10 reproduction and positive control are preserved beside the report. All21 public asset hashes independently revalidated without download/model load. The [narrow correction re-review](review-automatic-5aa65cb-rereview.md) accepts5aa65cb: original unchanged probe and positive control remain checking10/10 each, six affected coordinator tests pass. The correction is assembled asafa1ac3; originalfbceb0c alone remains unaccepted.

- [Runtime Model hook review](review-product-runtime-hook-4d557a8.md): exact4d557a8 accepted, source-only independent review. Root26 affected native +3Python entry tests pass; full frozen/bundled runtime acceptance is separate.

- [Saved-context API foundation](review-saved-context-foundation-56f9558.md): accepted API56,5 independent boundary tests pass; later coordinator/View and actual app reopening remain separate.
- [Typed stale-original finding](review-typed-stale-original-c7a4a57.md): P2 expired typed frame blocked fresh Stop receipt; author correctionbe4fbef awaits final scoped root re-review with the rest of typed source.

## Typed and saved-context app continuation

- [review-typed-3f18299-rereview.md](review-typed-3f18299-rereview.md)
- [review-typed-72ed859-rereview.md](review-typed-72ed859-rereview.md)
- [review-typed-app-b431914.md](review-typed-app-b431914.md)
- [review-typed-app-d969249-rereview.md](review-typed-app-d969249-rereview.md)
- [review-saved-context-352703e-rereview.md](review-saved-context-352703e-rereview.md)
- [review-saved-context-app-2b73674.md](review-saved-context-app-2b73674.md)

These are local scoped independent reviews, not GitHub approval or a main merge. The b431 report preserves its original P2; d969 closes it. Joined root source db768fd independently passes129 panel/app cases collected,124pass/5opt-in skips.

- [Protected account storage/key checkpoint728](review-account-storage-728e929.md): accepted at storage boundary; actual account control/bootstrap/product UI remains separate.

- [Query mechanism/team-planning correction](review-query-f0fe9d0.md): accepted f0fe9d0, joined6eb1717;74focused/605full collected and18 packaged cases.

- [Standalone scope foundation369](review-idle-foundation-3698e28.md): accepted96Python+10native; actual transport/app follow.
- [Native account consumer28](review-account-native-28d5948.md): accepted17native+3launcher tests; full product consumer follows.
- [Résumé backendf353 first review](review-resume-backend-f353253.md): one P2 shared-name employer relevance finding, correction pending.

- [Idle transport/preparationdae](review-idle-preparation-dae0675.md): accepted34native, actual app next.
- [Résumé backendc043 re-review](review-resume-c043887-rereview.md): original shared-name and prefix P2 findings closed;64focused pass.
- [Résumé nativebd594](review-resume-native-bd59453.md): accepted5independent native cases, real format/join next.
