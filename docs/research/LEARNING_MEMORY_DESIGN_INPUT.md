# Learning Memory: source-backed design input

Research date: 2026-10-24. **Proposal for architecture discussion, not an approved runtime contract.** No implementation, dependency adoption, account/model call or latency experiment was performed.

## Recommendation

Use Relay's existing protected local SQLite/snapshot and request infrastructure for a small evidence ledger. Reuse LangMem's distinction between interaction examples and response rules, and Graphiti's explicit source dependencies and time ranges. Do not add either framework to the live path now.

Keep two products distinct: immediate, ephemeral meeting continuity; and opt-in, source-linked learning for later style and preparation. History and generated notes alone do not implement learning. A generated suggestion never proves personal experience, skill, uptake or interview success.

## What Relay can currently establish

The inspected [bounded context](https://github.com/KanujVerma/relay/blob/b270297653f78201b56a7c5e57cc2efc322eef61/relay_spike/conversation_context.py#L33-L76) retains at most 12 raw utterances/6,000 UTF-8 bytes plus separately bounded mechanical task state. Its snapshot includes the last two microphone attempts and two remote feedback strings. It does not retain a source-identified suggestion/spoken-reply/follow-up chain across sessions. Those text labels cannot replace original native event identity.

The native transcript already validates source, session/epoch, sequence, stream generation, segment, activity and calibrated start/end timing. The separate History candidate exposes original validated observations and encrypted SQLite ownership; root must finish accepting that baseline before any learning migration. Reuse that producer, not a second ASR/capture pipeline or a model-generated transcript.

The current panel commits synchronously, and the Model drains reentrant publication before returning. A helper answer or intermediate snapshot alone is insufficient to say a suggestion remained available. A future native producer should issue its observation only after the final current card survives that drain.

## Observable chain and uncertainty

Propose a bounded interaction episode with immutable references:

| Record | Required evidence | Meaning |
|---|---|---|
| Suggestion available | Original request/session/epoch, card revision/hash, originating question refs, actual guide revision, native current-card commit time and known surface availability | Available through the app. Never proof of reading or attention. Hidden-window commits remain a separate state. |
| Spoken response | Original microphone final IDs, stream/activity identity and calibrated speech interval | Speech on that selected source. Not a verified person identity or biography. Typed requests stay separately labelled. |
| Remote continuation | Original selected-app-audio finals, timing and parent-task link | Continuation, clarification or explicit correction candidate. A follow-up is not automatically approval or failure. |
| Explicit feedback | User action/correction, exact target episode/card revision and requested scope | Highest-priority learning signal. It cannot silently retarget whichever card is newest. |

Join on the original native timeline, not asynchronous arrival order. If speech began before card availability, a later final cannot prove the card caused that speech. Overlap, echo, another local speaker, source changes, gaps, ASR uncertainty, multiple visible suggestions and delayed finals must yield ambiguity or exclusion. A newer request does not make old evidence current authority. Read-only episode continuity must not revive old native leases, source permissions, image bytes or model permits. Retired-before-publication and never-available cards are excluded.

Use a **signal vector**, not an uncalibrated success probability: temporal eligibility, distinctive phrase overlap, topic/structure match, competing-card count and source/gap flags. High lexical overlap can be labelled “possible uptake”; paraphrases may remain unknown. Record why a match was proposed and allow “not used” correction. Never turn similarity into “read,” “correct,” “liked,” “hired” or “personally implemented.”

For live continuity, retain a small episode projection alongside the existing task state: what Relay suggested, what was actually spoken, and the current clarification, each distinctly labelled. Keep a hard total prompt budget rather than adding an unbounded second transcript. A reasonable starting proposal is eight live episodes/32 KiB, with at most two compact relevant projections/2 KiB in one request; these limits need fixture validation. No extra classifier/model call belongs on the answer path. Eviction records an evidence gap; it must not silently relink an ambiguous answer to a newer question. Any projection still shares the existing 32 KiB whole-prompt limit and cannot displace the current explicit request or mandatory grounding.

## Cross-session application and deletion

For v1, require explicit Learning Memory consent and retained source history for persistence. History off still permits existing ephemeral session continuity. Store the episode/derivation references within the same owned protected ledger where feasible, so source deletion and dependent invalidation can be transactional; do not copy whole transcripts into another framework store.

Start with at most 100 retained episodes/1 MiB and 32 short derived style candidates, expiring no later than supporting source history (currently a proposed 30-day ceiling). Bounds and schema remain decisions for root. Default-off construction/status must create no file/key. No new model, embedding index, daemon or service is needed.

Separate technical/coding, recruiter/personal-presentation and other role scopes. A technical answer example must not become a recruiter biography. Prefer several eligible observations across meetings over one apparent uptake; count occurrences only within the user's permitted saved sessions. Explicit user preferences override inferred candidates, and current instructions override both.

Promote inspectable, reversible presentation/retrieval adjustments, not automatic edits to Relay's safety/biography policy or the user's saved guide. Example: “Lead with the answer, then one reason” is a style candidate; “user built Atlas” requires Personal Brain's separate confirmation. Future preparation can surface recurring topics and clarifications with their actual support count and uncertainty.

On source deletion/revocation/expiry, synchronously deny all dependent examples and derived rules, retire affected in-flight work, then delete/recompute using only surviving references. If recomputation fails, leave the derivative unavailable. Do not restore its prior text. Preserve a user-owned correction beyond source deletion only after a separate explicit save with clear retention; undo should not resurrect deleted source text.

The seams to agree are a native-issued available-card observation, the existing validated-final observer, a read-only request-scoped learning projection, and a background candidate/review store. None is model-supplied authority. A used projection needs host-built learning revision/support IDs for explanation and final currentness checks; it cannot rely on a model claiming that memory was used.

Use one owned, cancellable, debounced reflection task outside the critical path, preferably after a session. Only a separately enabled background-analysis policy may authorize one bounded call through the existing protected account/model factory and budget. No parallel unbounded optimizer loop, silent retries or API-key fallback. Recheck source/consent/learning revision after every await and before durable commit. Store observations and a short proposed adjustment, not inferred hidden reasoning. A disabled account/AI mode leaves deterministic evidence capture available under local consent but prevents reflection inference.

## Upstream comparison and actual reuse

| Primary source | Verified behavior and cost | Relay choice |
|---|---|---|
| [LangMem](https://github.com/langchain-ai/langmem/tree/48e3c11f5bb527282c7d5339c6a87a0b35abccfc), version0.0.30, [MIT](https://github.com/langchain-ai/langmem/blob/48e3c11f5bb527282c7d5339c6a87a0b35abccfc/LICENSE) | Episodic/procedural and delayed-reflection concepts. [Episode guide](https://github.com/langchain-ai/langmem/blob/48e3c11f5bb527282c7d5339c6a87a0b35abccfc/docs/docs/guides/extract_episodic_memories.md#L19-L47) infers success and agent reasoning; that evidentiary assumption is unsuitable here. Default gradient optimizer iterates; [prompt_memory](https://github.com/langchain-ai/langmem/blob/48e3c11f5bb527282c7d5339c6a87a0b35abccfc/src/langmem/prompts/stateless.py#L57-L115) offers one invocation. Adoption adds LangChain/LangGraph/Trustcall/provider SDKs. | Conceptual reuse only. Keep observable episodes, debouncing and one bounded proposed style update; reject automatic success/hidden-thought labels and core-prompt rewriting. |
| [Graphiti](https://github.com/getzep/graphiti/tree/8ce6d633bdcd3d178b3a47bc25b105dce106a754), version0.31.2, [Apache2.0](https://github.com/getzep/graphiti/blob/8ce6d633bdcd3d178b3a47bc25b105dce106a754/LICENSE) | [Entity edges](https://github.com/getzep/graphiti/blob/8ce6d633bdcd3d178b3a47bc25b105dce106a754/graphiti_core/edges.py#L263-L290) retain episode refs plus observation/validity/invalidation times. Full adoption adds graph drivers, LLM/embedding clients and extraction/search work. | Reuse source dependency and separate time concepts, not a graph server/framework. Host observations are facts about records; inferred truth is still uncertain. |
| Existing Relay | Protected snapshots, SQLite/GRDB transactions, immutable native observations, request ownership and protected one-call generation already exist. | Recommended implementation substrate after accepted History/notes contracts. No new package adopted. |

A concrete deletion mismatch matters: Graphiti's [remove_episode](https://github.com/getzep/graphiti/blob/8ce6d633bdcd3d178b3a47bc25b105dce106a754/graphiti_core/graphiti.py#L2174-L2245) rebuilds summaries, but its [failure test](https://github.com/getzep/graphiti/blob/8ce6d633bdcd3d178b3a47bc25b105dce106a754/tests/test_graphiti_mock.py#L845-L956) deliberately preserves the old summary, including deleted-source content, if rebuilding fails. Relay must use denial/unavailability instead. This is a source-observed upstream behavior, not a finding against current Relay.

Tests inspected, not executed: LangMem's empty/below-threshold cases assert zero calls and incremental-summary cases track summarized IDs; its general example runner is not an independent learning-quality benchmark. Graphiti's temporal tests distinguish a future deadline from an end of validity; request-scope tests prevent concurrent group routing from mutating shared identity. These inform Relay regression cases. [Exact source/blob/license ledger](LEARNING_MEMORY_SOURCE_LEDGER.json) has all inspected coordinates. **No code, prompts, assets or package was copied or installed.**

## Cluely workflow and latency evidence

The [existing REA investigation](CLUELY_DEEP_DIVE.md) selected39 client paths from shipped2.1.24, with explicit partial/truncated coverage. It establishes microphone/remote transcript state, manual/blank-help submission with context, streamed agent UI, modes/files and session-end/history transitions. It does not establish the server's memory loop, automatic trigger policy, outcome scoring, retention or latency. Current official [Cluely marketing](https://cluely.com/) was separately read by the controller on2026-10-24: continuous context and Assist via Cmd/CtrlEnter are product claims; the300ms claim concerns **transcription**, not end-to-end usable answers. This research did not independently refetch inaccessible older support pages or observe Cluely runtime.

No independent answer-latency benchmark is established by these sources. Relay's older owner-reported first-text/completion samples in [MODEL_STRATEGY](../MODEL_STRATEGY.md) are small, synthetic and not independently repeated. Neither those nor local fixture-test durations are comparable to a transcription marketing number.

A future permitted benchmark should report speech-end→final-ASR, admission/queue wait, request→first text, response.completed, QA and actual available-card time separately. Measure cold/warm, model/account configuration, prompt/memory sizes and cancellation/refusal rates. Publish p50/p95 only with adequate repeated samples and retain failures. Grade first *usable* advice on held-out technical and recruiter fixtures with blinded human/reference checks, not a first-token heuristic. Compare baseline versus learning on the same frozen session split; no future follow-up may leak into training/context before it occurred.

## Proposed acceptance sequence and open decisions

1. Ephemeral provenance capture and deterministic alignment: shown/hidden/stale cards, speech-before-card, overlap/echo, late/replayed/wrong-source finals, source switch/Pause/End and delayed targeted correction.
2. Opt-in protected persistence and deletion: inherited retention, capacity, exact source closure, lock/cancel/actual-close, deletion during reflection, failed recomputation, restart and reset/undo.
3. Later-session application with a visible “why this adjustment” trail; hold out whole sessions. Require no fabricated personal claims, no deleted-source retrieval, no worse correctness or stale-publication rate, and measured latency overhead before claiming improvement.

Root decisions remain: whether persistence requires History on, exact namespace/schema/bounds, who owns the availability receipt when the assistant surface is hidden, automatic tentative-rule activation versus review, and the explicit background-call budget. This report recommends defaults; implementation and architecture approval remain separate.
