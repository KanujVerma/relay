# Finish live response speed, Learning Memory and meeting notes

User-approved objective, 2026-10-24: dedicate parallel GPT-6.1 Sol extra-high workers to reducing response time, finishing Learning Memory and finishing AI meeting notes. Continue through end-to-end verification and keep verified progress/handoff on GitHub. Main merge remains separate. A component, validator, plan or synthetic timing is not the complete product.

## Owners and integration

- Speed: `/root/reduce_response_latency`, isolated `work/relay-preferences-product-gate`, branch `feature/response-latency-2026-10-24`.
- Learning Memory: `/root/finish_learning_memory`, isolated `work/relay-session-history`, branch `feature/learning-memory-2026-10-24`.
- Meeting notes: `/root/research_visual_inputs`, reassigned to `work/relay-generated-session-notes`; the former notes worker is no longer live. Native Notes starts from frozen accepted History8ea plus accepted DATA24, then freezes storage early for Memory.
- Controller: independent source review, existing History manual-draft completion, source integration, final app/benchmark/UI gates and public continuation. Reuse existing isolated review checkout; no extra clone/cache/environment.

All three owners retain GPT-6.1 Sol xhigh. Shared source changes are coordinated before implementation. Notes owns schema2 and source/CAS storage first; Learning adds strict known schema3 after the accepted storage foundation. The controller joins exact reviewed commits. One actual after-publication-drain Model observation will serve Memory availability and descriptive latency timing; neither consumer can grant native request authority.

## Approved behavior and architectural choices

- Ordinary use remains Start then natural conversation with automatic suggestions. Normal setup has no speech-model/detector chooser. Preserve supported account/permission/current-source boundaries and no paid API-key fallback.
- User explicitly approved automatic tentative wording/length adjustments with visible why and undo. Explicit guides/current request take precedence. New personal facts still require confirmation.
- Learning observes actual available suggestion, original microphone reply and remote continuation, with calibrated timing/source identities and ambiguity. It also preserves source-linked constraints and unresolved follow-ups beyond the raw recent-dialogue window, including read-only continuity across Pause in the same logical meeting. No reading, proficiency, correctness or interview-success inference from display/phrase overlap.
- Learning is separately enabled, inspectable and removable. It reuses protected local History storage, expiry and exact source deletion. No extra provider call belongs on the live answer path; initial reflection is deterministic. Examples and suggestions do not become confirmed biography.
- Meeting notes use complete bounded saved source, with explicit excerpts only when selected; not the current transcript page or a silent prefix. Output carries literal original-source citations. Separate manual notes, generated/edited notes and confirmed personal knowledge.
- The first performance checkpoint retains a lazy helper-owned client and content-free timings, preserving response.completed and all final guards. A short complete initial card and deferred optional detail are performance work to evaluate, not permission to publish incomplete/stale output or omit required question parts.
- Proposed product targets from speech end: first visible answer under1second median, first useful point within2seconds median, concise full card in3–4seconds median and first useful point within4seconds for95%. These are not achieved promises. Actual targets must be evaluated with answer correctness and missed/stale/cancelled requests, not success-only timing.
- No new memory framework, graph server, embedding model or second local database. Reuse relevant pinned primary-source patterns and existing dependencies; record any actual copied code/license separately. Follow LOCAL_RESOURCE_BUDGET: one heavy job globally, jobs2, two retained caches,30GiBfree floor and25GiBRelaytemporary cap including reserve. No automatic downloads or destructive cleanup.

## Evidence ledger and remaining acceptance

- [x] Reconcile live agents/branches and preserve stopped worker commits. Canonical starts at88af720. Root independently accepts History82e after34focused native passes/zero skips and source review; publishes PR93 exact82e.
- [x] Independently verify and join first transport timing/lifetime checkpoint a8fb232 and strict Learning request-projection checkpoint e50e425. Local joins are24dfeaf/f6f2fa9; root full combined Python gate collected773:741passed/32optional skips, zero failures in9.049seconds. The independent source review and gate accept these component deltas, not the full features.
- [x] Complete bounded manual History draft editor: window recreation/failure preserves draft, original CAS, actual saved receipt, newer edits during Save, synchronous Lock/Delete/expiry clearing, no stale restoration, no unsaved plaintext persistence. Source463 peer review clean; eight new actualModel tests pass, and joined72-case gate passes71withoneopt-in render skip. Final visible/bundled acceptance remains a separate item below.
- [ ] Speed: actual product-stage timing from original calibrated speech end through ASR, helper admission, inference, validation and current post-drain card availability. Keep bounded content-free failed/cancelled samples. Measure representative warm/cold paths; evaluate compact complete output and other justified improvements against unchanged quality fixtures.
- [ ] Notes: strict native DATA parity, full original-source issuance, exact candidate-only v1→v2 migration, actual protected save/CAS outcome and unknown-write reconciliation; then existing protected one-call generation, typed cited output, source-bound saving, History UI/read/edit/regenerate/delete and stock bundled-helper acceptance.
- [ ] Learning: native availability/final matching, long-session continuity, protected opt-in episodes/examples/rules, schema3/retention/deletion, undo/reset/disable, later-session application and explanation UI. Prove actual later advice change without weakening biography/technical guards, and exact-source invalidation during held work.
- [ ] Integrate all accepted source with account, guide, screen, Pause/Resume/End/Lock and cancellation ownership. Run appropriate combined native/Python/contract gates; preserve original failure reproductions and publish exact sources/results.
- [ ] Build one final self-contained app with already verified inputs and serial resource budget; verify signatures, relocation, actual visible synthetic UX, no repository/system-Python fallback, lifecycle and real source-dependent paths.
- [ ] Run authorized actual-account/device acceptance where configured: real speech-end-to-readable-card latency, technical/personal/case/follow-up usefulness and false/missed/stale suggestions, screen/memory on/off and warm/cold conditions. Report failures and uncertainty. No fixture runtime or vendor transcription marketing substitutes for this gate.
- [ ] Update GitHub PRs, canonical HANDOFF/BUILD_STATUS, exact documentation mirror and continuation with full requirements audit. Only mark the persistent goal complete when all requested end-to-end features and material gates are actually evidenced.

## Current review and coordination rulings

1. Reuse existing isolated checkouts and two build roots to avoid repeating the disk incident. Cost if wrong: less independent compiler-cache isolation, compensated by frozen source and independent test observations.
2. The controller finishes the bounded manual editor while the three workers own the requested feature lanes. Cost if wrong: this small controller patch still requires peer review and actual app tests before acceptance.
3. Notes schema2 precedes Learning schema3, while independent parsers/matching/wire/UI can proceed in parallel. Cost if wrong: shared integration may need revision, so freeze the storage component early instead of waiting for all Notes UI.
4. Connection-reuse benchmark savings are only milliseconds and cannot establish the seconds-level speed target. Keep the measurement and continue on actual stage timing/output policy.
5. The stock product builder now defaults to two compiler jobs, matching the resource policy; no new dependency/work environment is introduced. The remaining bundle build and relocation are still required.

Resume pointer: this plan plus the top override in HANDOFF.md, live Git and exact worker reports. Completed steps remain completed after compaction; never restart a live job merely because an observation timed out.

## Component checkpoint after source foundation

Protected Notes backend7429/bfa/82099 and native DATA/snapshotdf767 are joined, with original real-thread cancellation and changed-grant regressions closed. Root independently passes128affected Python cases and later89focused cases. Notes presentation/editor source e165ab3 passes28native cases without skips, including four fictional offscreen exports; two independent source reviews and original held-save failure precede correction. History insertion and actual generation/save effects remain pending.

Learning foundation5ae9d8d is source-reviewed and composed with these components: full combined Python823collected/791passed/32optional skips, zero failures,10.228seconds. Root inspected the actual author90-case native log and exact hashes. Ruling: defer a second standalone native foundation replay to the coherent actual-Model/combined gate, so owners can implement their observed missing interfaces without repeating a cache-changing compile for every inert component. Cost if wrong: final integration may expose a native interaction later; the complete native/application replay remains required before end-to-end acceptance. No feature completion checkbox changes.

Root coherent component replay now completed earlier than the planned final Model gate because the new Settings UI and production speech regression required the same compile. Exact native193collected/191passed/two explicit skips in124.150seconds; complete Python833collected/801passed/32optional skips in11.483seconds, zero failures. Real public WAVE→normal production VAD/ASR→owned helper→answer reducer passes once with unchanged assertions and input hash. No account, physical capture, actual window usefulness or model-quality improvement claim. Actual Model/History feature connections and final app/bundle/latency gates remain required; no full-feature checkbox is marked complete.
