# Source-linked Learning Memory Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. This owner is already delegated; no child agents. Steps use checkbox syntax.

**Goal:** Preserve useful current-meeting semantic continuity and apply tentative, inspectable and reversible source-backed wording/style/preparation adjustments to later requests.

**Architecture:** Native original-final and post-drain card observations feed a bounded local episode matcher. An opt-in schema3 extension of the existing encrypted History ledger owns retained examples/rules; a request-scoped bridge sends inert source projections to the existing one-call Python answer host.

**Tech Stack:** Swift6.2, existing GRDB/SQLite protected snapshot, Python standard library. No new packages/models/providers.

**Spec:** `docs/superpowers/specs/2026-10-24-learning-memory-design.md`

## Global constraints

- Existing History store/key/serialization owner; schema3 preserves v1/v2 and migrates only an explicit learning write.
- Eight ephemeral episodes/32KiB; sixteen continuity quotes/4KiB; two request projections/2KiB;100 retained episodes/1MiB;32 rules; source30-day ceiling.
- Explicit guide/current request override inferred wording; biography, skills, reading and outcomes gain no authority.
- One heavy job globally, existing two retained caches only, jobs2,180second external deadline, >=30GiB free and aggregateRelaytemp<=25GiB including reserve.
- Public repository contains fictional fixtures only. No actual account/Keychain/capture or paid/provider calls.

### Task1: Strict request projection and retirement

**Files:** `relay_spike/learning_memory.py`, `session_host.py`, `user_question.py`, `generated_answer.py`, `tests/test_learning_memory.py`.

**Interfaces:** `HostLearningMemory.stage(dict)->bool`, `.claim(native)`, `.prompt_for(request,has_explicit_guide:bool)->dict|None`, `.used_revision(request)->str|None`, `.retire(dict)`. Wire kind `learning_memory` includes exact native binding, `memoryRevision`, scope, continuity, adjustments, preparation, examples and supportIDs.

- [x] Red missing module/API, then strict exact-schema and real Host fixtures.
- [x] Implement source projection through unchanged one-answer factory; no provider/authority fields.
- [x] Verify retired used revision seals terminal and joins stubborn actual worker; explicit guide suppresses inferred tags/examples; personal/local-reference route unchanged.
- [x] Commit and publish e50e425;31 focused tests pass.

### Task2: Native source matcher and substantive continuity

**Files:** new `LearningMemoryModels.swift`, `LearningSessionMemory.swift`, `LearningMemoryTests.swift`.

**Interfaces:** `LearningSessionMemory.observe(ValidatedTranscriptObservation)`, `.available(binding:replacement:lead:points:guideRevision:visible:at:)`, `.projection(question:)->[LearningQuote]`, `.pause()`, `.end()`. `LearningEpisode` retains exact original question/microphone/remote finals and native availability identity. `LearningSignal` exposes temporal eligibility, overlap and ambiguity only.

- [x] Compile new real-source fixtures red; implement interval/source/gap/overlap matcher.
- [x] Preserve exact source-linked constraint/decision/unresolved-follow-up quotes beyond raw-ring eviction; bounded semantic relevance projection.
- [x] Verify hidden/pre-availability/overlap/gap/late finals never activate style, Pause retains read-only semantic context and End clears it. Root review added competing-card and unrelated-request negatives; all original red assertions now pass.
- [x] Commit and publish focused native green. Current successor13-case gate passes; independent acceptance remains separate.

### Task3: Protected schema3 and reversible deterministic derivation

**Files:** new `LearningLedger.swift`, `LearningMemoryCoordinator.swift`, dedicated tests; narrowly extend accepted Notes `HistoryStore.swift`/`SessionHistoryCoordinator.swift`.

**Interfaces:** `LearningArchive` episodes/rules; `LearningMutation.save(episode)`, `.suppress(ruleID)`, `.reset`; `HistoryStore.learningArchive()` and `.mutateLearning(_:admission:)` execute within sole serialized owned store. `LearningLedger` validates/copies/rebuilds against exact surviving finals in the same candidate.

- [ ] Import root-accepted frozen Notesv2 storage; test default-off no migration and candidate-only schema3 creation.
- [ ] Derive fixed tentative tags only after3 clean episodes/2 saved sessions in same scope, retain representative wording and dated unresolved prep with support IDs.
- [ ] Verify encrypted restart, exact source deletion/expiry rebuild, suppression persists across restart, reset/disable and held cancellation fail closed.
- [ ] Commit/publish storage green before Model/UI joins.

### Task4: Actual Model, request bridge and inspectable controls

**Files:** new app-only `LearningMemoryRequestBridge.swift`, `LearningMemorySettingsView.swift`; narrow `SessionApplicationModel.swift`, `SessionDecision.swift`, `SessionPanelController.swift`, `ConversationOwner.swift` and existing settings/answer surfaces.

**Interfaces:** one app-only observation after outer `panel.accept` returns outside the authority lock and after its Model publication drain, with original owner/binding/card replacement/question/card/guide+learning revision/monotonic time/actual attached-window visibility. `LearningMemoryRequestBridge.freeze/sendOffer/permits/retire/close` retains exact native request identity. Final `learningMemoryRevision` is separately decoded and rechecked before publication.

- [ ] Red actual Model reentrant retirement and hidden/attached surface fixtures before hook implementation.
- [ ] Wire validated original observer fan-out; preserve same logical meeting quotes across Pause, clear on End/source retirement; no native authority revival.
- [ ] Add explicit opt-in description including assistant suggestions/spoken examples, why/support/date, undo/reset/disable and current-answer adjustment explanation.
- [ ] Verify later-session actual request/advice differs with held-out correctness/biography/currentness regressions and no extra request; record local overhead separately from account/model latency.
- [ ] Publish exact source/test evidence and remaining controller-owned acceptance gates.
