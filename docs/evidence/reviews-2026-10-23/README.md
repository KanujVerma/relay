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
