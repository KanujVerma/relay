# Optional local session history and notes

Status: controller-approved design with amendments, 2026-10-23. Original design checkpoint `e242746` used base `5575b184a081450308b88b622ec5fcb5eb81318a`; implementation starts from `ac70eb3b8526331b074cd5a9e24f0d775ecad4f9`. Publication of this document itself implements no storage. The accepted résumé and idle authority remain dependencies.

Approval amendment: all six seams below are approved for manual History/notes implementation. Fixed key service is `com.relay.history.v1`, account `local-history-aes256`; location `Application Support/Relay/History/history.relayvault`, authenticated header `RELAYHISTORY1\n`. The lane owns complete isolated Model/Home/Settings/lifecycle/package/key-purpose integration as well as store/coordinator/DTO/export/validated-final observation. It narrowly incorporates accepted account728's compatible `.profile/.chatGPTCredentials` enum, without importing unreviewed account app code. Controller independently reviews/reconciles and owns GUI verification. Generated notes still require a later exact contract and have no stub.

## Recommendation and approval decisions

Build a native, optional local History workspace. Reuse pinned MIT GRDB `DatabaseQueue` and backup for an in-memory SQLite ledger; persist only an authenticated encrypted whole snapshot through a narrowly factored Relay vault primitive. Keep History separate from Personal Brain and from the capture helper's lifetime. Default saving is off. Actual final audio transcript and user-written notes form the first independently reviewable deliverable. A second deliverable adds explicitly requested generated notes using the existing configured-plan inference path and a separate owned notes task. Do not show a working Generate button before that path exists.

The complete target is useful session list/detail, source-labelled transcript, editable title and notes, restart persistence, bounded expiry, delete/export and optional grounded generated notes. A saved record is not an active conversation: opening it never resumes recording or revives old question authority. Sending a new question based on history is a later explicit-context feature, not implied by the word Resume in a competitor menu.

Controller approval is requested for these exact seams and policies before implementation:

1. GRDB v7.11.1 at `b83108d10f42680d78f23fe4d4d80fc88dab3212`, using system SQLite, one private in-memory queue and one bounded candidate queue. No new runtime framework or Python database process. Add its MIT notice and a locked package resolution only when adopted.
2. A distinct History key purpose/file/header, and a small protected-snapshot primitive factored from `ProfileVault`. Controller/account owner owns that extraction and fixed key namespace. Existing profile bytes, purpose and authority stay compatible.
3. Explicit idle-only Enable; default off; remembered enabled sessions reopen an existing History vault before capture; missing/corrupt/unavailable storage aborts that save-enabled Start with reachable Turn saving off. Lock history turns saving off synchronously. Internal End/close can preserve the preference. No missing-vault auto-create on Start.
4. A narrow producer-issued validated transcript observation hook before ring eviction, plus controller-owned Start/Pause/Resume/End/failure hooks. It cannot alter, filter, restamp or block native event forwarding.
5. The bounds, 30-day expiry policy, deletion scope and pending-write rules below. Permission loss does not itself erase previously saved history.
6. Storage/UI first, generated notes as a separate accepted checkpoint. Its noncapture task/transfer contract must be frozen before helper edits. No model output or retained transcript authorizes Personal Brain facts.

## Current facts and product gap

`SessionTranscriptStore` already validates original final audio events against native session/epoch/sequence, closed activity, source/generation, input range and timing evidence. Its public ring contains at most 64 rows and 65,536 text bytes; row text is bounded to 1,200 Unicode scalars/4,800 UTF-8 bytes. It is transient. Pause seals admission and keeps rows; End clears them. Current-session consent revocation removes the affected source's transient rows, including after Pause. Replacement sessions remain fenced. Public rows do not separately retain the original epoch/global sequence. An End-time copy of this ring would lose earlier rows and can observe an already empty ring.

`SessionApplicationModel` already retires capture/answer/context admission synchronously, then joins real capture, event forwarding and helper work. Resume uses a fresh capture session. These are dependencies, not a request to redesign lifecycle. The History design needs its own finalization receipt after that actual join; a UI flag, timer or `stopped(quiesced:false)` cannot certify a completed record.

Relay already persists Personal Brain as encrypted native whole SQLite snapshots with injected key/file ports and explicit close ownership. The Python ledger is in memory. Putting history inside that ledger would mix approval domains and tie History to a helper which End actually reaps. Personal Brain retrieval must never silently discover a new history table or derived note.

Static Cluely 2.1.24 REA shows session list/detail, transcript, editable title/markdown summary, trash and share-text actions. It does not verify cloud retention, summary accuracy or share-link access controls. The existing [REA report](../../research/CLUELY_DEEP_DIVE.md) remains the source for that distinction. Relay's explicit local retention policy is a proposed Relay choice.

## User flow

Home gets a functional History destination. On first visit it says "Session history is off" and explains: save final transcript text and notes locally on this Mac; no audio or screen images; saved text may include both microphone and selected app audio; export creates a readable file. Only an explicit Enable action creates the empty store/key. Opening Home or constructing the model performs no file, key, helper, account or network work.

Open saved history reads only an existing vault and never turns saving on. If none exists, show the empty/off state with an explicit Enable action, not a fabricated history item. Enable opens existing storage if present; it creates only when the explicit action actually authorizes a new empty store.

When saving is enabled, Start follows current speech/source/recording-consent checks, then opens/validates the existing history and creates a pending record before capture. It must recheck the same Start intent and source consent after all awaits. Setup cancellation, a late Lock, source replacement or a failed history open prevents capture from starting. History permission is separate from recording permission. Fixtures use fake keys, a temporary vault and synthetic events.

The live surface adds a small actual saving state: Off, Saving locally, Saving stopped, or History unavailable. A failure never says Saved. It must not put storage diagnostics into the answer card. Turning saving off while live stops future retention without ending permitted assistance. Enabling while live is unavailable in v1; the user can enable before a new session, so there is no covert backfill from the transient ring.

History list: date groups, 56-point minimum rows, 40-point icon, 14-point medium title and 12-point secondary date/status, matching the measured hierarchy with Relay assets. List pages contain at most 20 records. Detail shows title, date, duration/known segments, Completed/Partial/Interrupted state, Transcript and Notes. Rows say Microphone or Selected app audio, optionally the actual selected application label/bundle captured at session start. They never infer Interviewer, Candidate or a person's identity. The original text remains selectable; no automatic content correction or generated speaker assignment.

Notes initially means an editable user note with an explicit Save and real persisted receipt. Show unsaved state until the encrypted commit completes. Export and Delete are real commands; omit cloud sharing, calendar and inert Generate/Resume controls. A save failure keeps the draft visible until Lock or explicit discard. Lock hides private rows and drafts immediately; v1 discards unsaved drafts after its clear warning rather than silently storing them elsewhere.

## Identity, content and bounded schema proposal

All content and private index metadata live inside one encrypted snapshot. Plain preferences contain only saving-enabled, policy version and retention choice, never a title, transcript, source label, timestamp list, notes, search index or count.

| Entity | Required identity and content |
| --- | --- |
| Logical history record | New local UUID; monotonically increasing record revision; UTC creation/start time; optional actual finalized end time; status; title origin (`default`/`user`); title; retention expiry; completeness/gap reasons. It is not a capture UUID or answer request. |
| Capture segment | Original capture UUID + UInt64 epoch, segment ordinal within the logical record, actual selected source configuration, wall/uptime anchor, first/last original event sequence, actual start/end or unknown end, completion reason. Pause/Resume creates another capture segment under the same logical record only through the actual Resume intent. |
| Audio final | Original capture/epoch/source code/stream generation/activity ID/segment ID/revision/global event sequence; original host-clock calibration and input interval; start/end/finalized/received/emitted uptime; exact accepted text. Uniqueness follows original capture/epoch/source/generation/ASR segment. An exact replay is idempotent; conflicting content under that identity rejects and marks a gap. |
| User notes | Record UUID/revision; exact bounded user text; origin `user`; edit time. No fact IDs or approval flags. |
| Derived notes, later | Separate note UUID/revision; record revision and exact source-row IDs/digest; model identity; actual generation receipt/time; origin `generated` or `generated_user_edited`; typed summary/actions with row references; explicit unavailable/partial state. No Personal Brain candidate or confirmed claim is created. |

UInt64 native counters/ticks must round-trip losslessly: use fixed 8-byte big-endian BLOBs in SQLite and canonical decimal strings in JSON export, not signed `Int64` casts or JavaScript floating-point numbers. Wall-clock values are timezone-qualified and labelled estimates if derived from an anchor; wall-clock changes cannot reorder original native events. Uptime from different capture/boot lifetimes is never compared as a common clock.

Proposed v1 bounds:

- 100 records, 8 MiB serialized snapshot, with a 7 MiB admission soft limit leaving finalization/deletion headroom. Reaching the bound stops new retention with a visible partial reason; it does not silently evict unexpired records.
- Per record: 1,024 final rows and 256 KiB transcript text, an 8 KiB user note and a 120-byte title. Retain each accepted row whole; never split/truncate an utterance to fit. A long session may be Partial with exact last retained watermark.
- Pending ingress: at most 128 observations and 256 KiB, with a separate reserved lifecycle/finalization slot. No unbounded task per utterance. A control fence retires admission synchronously even when the writer is busy; it never drops or changes original audio controls.
- Detail pages: 64 rows/64 KiB at a time, exact cursor/revision. Search initially scans only the bounded unlocked store; no external/Spotlight/plaintext full-text index or embeddings.
- Saving policy: 30 days from record creation, with an explicit earlier Delete. Purge expired records before exposing, exporting or generating from an unlocked store and commit the purge. Expiry cannot run while the app is quit or the key/store is unavailable; UI must say "Expired items are removed when History opens", not promise an always-running scheduler. Notes expire with their record. No default forever-retention option in the first slice.

These bounds are proposed tradeoffs for an 8 MiB whole-snapshot design, not measured capacity or universal long-meeting support. The limits apply together: 100 maximum-size sessions will not fit the overall byte bound. Before exposure, validate metadata overhead and finalization headroom using maximum-size fixtures. If those fixtures do not fit, lower admission bounds or raise an explicitly reviewed vault bound; never silently skip save failures. Typed-only assistant questions/answers are not retained in this first audio-session History slice; future explicit chat retention needs its own origin and lifetime, never fake audio rows.

Persisted schema validation checks the exact version/tables/columns, value bounds, foreign keys, source enum, UUIDs, counters and row ownership after authenticated decrypt. Reject unknown future versions and unsupported tables/triggers/views instead of executing untrusted schema or falling back to a disk database. Only compiled SQL and bound values are used. Deletion cascades through dependent derived notes, and no title/notes index escapes the vault.

## Storage architecture and commit ownership

Use GRDB `DatabaseQueue()` with its default private `:memory:` database, not `DatabasePool`, named shared memory, an empty filename or an arbitrary path. Set/verify foreign keys, `secure_delete=ON`, `temp_store=MEMORY`, memory journaling and defensive resource limits; extension loading and arbitrary SQL/ATTACH are not exposed. Serialize only within the queue's closure. Use copy-owning `sqlite3_serialize` rather than NOCOPY. Restore only into a fresh queue, with SQLite-owned bounded allocation, correct FREEONCLOSE error ownership, a memory-file size limit, GRDB schema/statement cache clear, integrity/schema checks and re-applied policies. This is a narrow bridge; GRDB owns queries, transactions, backups and serialized access.

Mutations use one native coordinator/worker owner. Back up canonical memory state into a bounded candidate queue, apply the whole transaction, enforce limits, serialize, encrypt and atomically publish ciphertext. Deletion/expiry instead builds the candidate from the fixed schema and remaining bounded rows, so deleted content/free-page payloads are not carried into the new snapshot and reclaimed capacity is usable. This is an in-memory rebuild, not a disk VACUUM/temp-file shortcut. Only then publish the new canonical queue/revision and a Saved receipt. If any step fails, close the candidate; previous ciphertext and canonical state stay authoritative. No plaintext SQLite file, WAL, rollback journal or temp spill is permitted. Snapshot copying adds CPU and transient memory cost; maximum-size save latency and peak memory must be measured before a production claim. Do not add more parallel writer queues to hide a slow commit.

Proposed protected domain: `history.relayvault`, authenticated header `RELAYHISTORY1\n`, distinct fixed History key purpose. The exact Keychain service/account constants remain controller/account-owner approval, not derived from an email/model/token. Reuse a reviewed generic protected-snapshot primitive and injectable fixed-purpose key provider; preserve profile's existing file/header/key behavior and public API. Constructor is inert. Existing-only load never creates a key or file. Only explicit first Enable may create; missing/corrupt existing data never triggers overwrite or key rotation. Directory/file ownership, permissions, hard-link/symlink defenses and ciphertext-only atomic replacement need the same or stronger negative coverage as the existing vault.

No promise of secure erase, same-user process isolation, swap exclusion or removal from filesystem snapshots/backups. In-memory plaintext is released at close, not claimed physically unrecoverable. Delete All commits an empty authenticated store, with actual success/failure receipt; it does not delete unrelated profile/account keys or invoke a credential-reset flow.

## Capture, saving, deletion and Lock are different controls

Every asynchronous command owns an immutable operation UUID plus vault epoch and policy/record revision. Public cancellation retires the current operation synchronously. Delayed cancellation/receipts affect only their original owner. All post-await publication checks include actual worker/controller busy state, not merely an opened flag. A replacement cannot start using a still-owned old queue.

| Action | Immediate native fence | Actual join / durable effect |
| --- | --- | --- |
| Capture permission/source unavailable | Existing capture/source admission and answer retirement remain unchanged. Mark the affected retained segment with the actual gap/reason. | Previously authorized saved history stays until its policy/delete action. Existing transient transcript purge remains unchanged. No new rows arrive from the lost source. No implication that history consent grants capture permission. |
| Stop saving | Retire History ingress permit before callbacks can enqueue more rows; clear unstarted history batches. Assistance can continue. | An atomic commit which already started may finish its authorized prefix; join that owner before reporting saving stopped. Existing committed records stay. This is not Delete or Lock. |
| Delete source text from this record | Invalidate row readers, export and derived-note permits for the exact record/capture/source scope; fence that source from further retention in this logical session; clear matching queued rows. | Join any started commit, then commit scoped removal of those rows, associated metadata and dependent derived notes. Unrelated source/record content remains. Only report Deleted after the final encrypted receipt. It does not revoke OS capture permission. |
| Delete record / Delete All | Tombstone exact record(s) in native admission before any pending writer/notes task can publish; hide affected private state immediately. | Join old writes/exports/notes, then actual encrypted deletion. A stale final callback cannot recreate the record. Failed deletion reports failure; never a false purge. Delete All also turns saving off. |
| Lock history | Hide rows/drafts synchronously; turn remembered saving off; invalidate all read/export/notes/admission permits before async cleanup. | Join any already-started owned write, then close actual queues and release plaintext/key material. Ciphertext remains. No open-after-Lock or old cleanup can reopen a replacement. My Context Lock remains separate. |
| Normal End / internal helper retirement | Stop History admission under the original logical record. No helper identity is reused as History identity. | Join actual capture/events, flush admitted rows and finalize status; helper reap does not erase History. History workspace may remain unlocked while open. Closing its owner joins storage and can preserve the enabled preference; no background capture is started. |

Permission withdrawal is intentionally not treated as retrospective erasure. The settings/detail recovery copy must offer the explicit Delete path. Conversely, a source-delete command is a true durable removal obligation, not merely an ephemeral row hide or a capture stop. Purge cannot return success from timeout. Lock/Delete can immediately veto visibility but must keep a retained cleanup owner until actual completion; show Closing/Deleting while unavailable rather than admit a replacement.

## Narrow producer and application API proposal

Add a default-nil read-only observation sink to the existing validated transcript store. It issues a non-publicly-constructible `ValidatedTranscriptObservation` after all existing checks and before ring eviction. Its final case carries the original `NativeSessionEvent` identity/evidence and accepted exact row; lifecycle cases identify the same original capture/source. It adds no validation bypass, event mutation, fake final or second sequence counter. History consumes only issued observations under its own native retention permit; a caller-supplied JSON `authorized` field cannot grant that permit.

An inert `SessionHistoryCoordinator` exposes observable state and commands:

```swift
// Proposed contracts, not implemented APIs.
openExisting() async throws
enableSaving() async throws             // idle, explicit creation only
stopSaving()                            // synchronous ingress fence, owned join
waitForQuiescence() async
lock()                                  // synchronous hide/preference/fence
beginSession(intent: sourceSnapshot:) async throws -> HistorySessionPermit
observe(_ issued: ValidatedTranscriptObservation) // bounded synchronous enqueue
pause(_ permit: HistorySessionPermit)
resume(_ permit: HistorySessionPermit, capture: OriginalCaptureIdentity)
finish(_ permit: HistorySessionPermit, completion: ActualSessionCompletion) async
list(cursor:) async throws -> HistoryPage
detail(recordID: cursor:) async throws -> HistoryDetailPage
saveNote(recordID: expectedRevision: text:) async throws
rename(recordID: expectedRevision: title:) async throws
deleteSource(recordID: expectedRevision: sourceScope:) async throws
delete(recordID: expectedRevision:) async throws
deleteAll() async throws
export(recordID: expectedRevision: format: destination:) async throws
```

`HistorySessionPermit` is privately issued, records the native owner/generation and cannot be deserialized. A read-only `canBegin` Boolean is presentation state, never Start authorization. `beginSession` returns only after actual restore/create-record commit and same-intent checks. Root's Model invokes it after speech/source checks and before capture; it rechecks source/Start/Lock state at the final start boundary. Finalization accepts only the original retained owner and genuine capture/event quiescence. Aborted Start removes an empty pending record or marks an actually begun segment partial, never inventing audio time.

Crash recovery opens records left Recording/Paused as Interrupted, preserves the last actual durable watermark and unknown end, and never fabricates a complete transcript. Final status is Completed only when actual End joins and every admitted row was durably flushed without gaps. Any source loss, queue/storage limit, missing segment or shutdown failure is Partial with a fixed reason. A valid late final can be retained under its original captured identity only while that segment's History admission remains open; it cannot publish an answer or reopen a finalized/tombstoned record.

## Export and derived notes

Export is an explicit save-panel action for the selected record/revision: Markdown for readable notes/transcript and versioned JSON for exact identities, source labels, times and gap state. Explain that the exported file is readable outside the encrypted store. Use an injected destination port, bounded output and ciphertext-independent atomic final-file publication; no default path, silent clipboard, public link or cloud upload. Lock/Delete/revision changes cancel a queued export before its file write. If final publication has already started, join it and truthfully report its outcome; an exported user-owned copy is not claimed erased by deleting History. No raw audio, screenshots, OCR/AX text or résumé/source files are exported.

Generated notes are a separate full-stack checkpoint after storage acceptance. User explicitly requests them from an unlocked saved record while inference is configured and the shared helper has no active capture answer/probe. The action explains that the selected transcript text is sent to the configured AI plan; locally encrypted storage does not mean generation is necessarily local. Start, helper/account/mode change, Lock, Delete or source deletion retire the notes permit synchronously and join real work before reuse. Reuse the actual OAuth/SSE/model path and current account gates; no new auth framework, API-key fallback or inference call during development.

A native-issued notes work permit binds record UUID/revision, exact included row IDs and text digest, vault/policy epoch, helper/model/configuration generation and deadline. It is not an old audio lease and never fabricates ASR activity. Bounded source transfer and strict response must carry the same original request; helper receives only selected source text necessary for the explicit notes request. No history-wide biography retrieval.

Use typed summary/action items with references to actual source-row IDs. Invalid/missing references, incomplete streams, cancellation and changed source revisions cannot save a note. Labels distinguish generated, edited-generated and user notes; generation is not source truth. A structural citation check cannot prove semantic correctness. Do not infer a person's identity, completed action, skill or personal ownership. Summary inputs exceeding the agreed note budget require a visible selected excerpt/partial scope, or remain unavailable; do not silently summarize a prefix as the whole session. The helper protocol, model token/input bounds and rich-text/export sanitizer require a separate exact contract review before coding. Until then, ship functional manual notes and no fake generated content.

## Ownership and meaningful acceptance

Proposed lane owns new History store/coordinator/DTO/export/presentation files and tests, plus the narrow validated-final observation hook after approval. Controller owns outer Home/Settings navigation, Model Start/retirement joins, package wiring, fixed key-purpose extraction/account coordination and final assembly. Notes helper/transport ownership is assigned separately after its wire contract. No broad Personal Brain/provider/schema change is needed for storing history.

Required storage/UI checkpoint fixtures:

1. Inert constructor/Home and Saving off cause zero file/key/helper/network actions; rejected Start/fixture defaults cannot persist. Explicit Enable creates only owned ciphertext with a fake key. Restart loads the real encrypted snapshot, not a parallel fake view model.
2. More than 64 actual synthetic native finals through the existing validator are retained up to History's own bound; wrong epoch/sequence/source/closed activity, stale replacements and conflicting replay are rejected. Text is exact and source-labelled. Typed requests never become invented audio transcript.
3. Pause/Resume groups distinct original capture IDs without reviving leases; End flushes only after held actual writer/events/capture joins. Crash/failed End/budget/source gaps produce Partial/Interrupted and unknown end correctly.
4. Ready-observer/held-write schedules exercise late Lock, replacement, cancellation before task registration, old-operation cancellation, failure after serialize and reentrant close. No completion succeeds while its real owner is busy. Native event forwarding remains unblocked and unchanged.
5. Hold a commit at before-start and during actual atomic replacement: Stop saving drops only unstarted batches; Lock hides immediately and joins; source/record/Delete All applies after any started commit and old completions cannot recreate deleted rows. Capture permission withdrawal changes capture/transient behavior but does not pretend to perform a durable delete.
6. 8 MiB/soft-limit/max-metadata boundaries, rollback, malformed/future/wrong-key/tampered snapshots, unsupported schema, unavailable serialization, SQLite FULL, symlink/hard-link/owner/mode rejection and actual candidate-close containment. Previous ciphertext survives failures; no plaintext SQLite/WAL/temp/index files.
7. Pagination/edit compare-and-swap, expiry before read/export with fake clock, no expiry while key unavailable, UTF-8/non-BMP text and UInt64.max round trips. Delete exact source keeps unrelated records; dependent derived-note fixtures are removed.
8. Real native save destination port exports selected exact revision; late Lock/Delete veto queued writes; output is correctly escaped, bounded and visibly plaintext. No real clipboard or user file selection in tests.
9. Actual Model/stdio fixture session through Save/End/restart/Open shows correct source text and user notes with fake key/temp directory; missing vault does not auto-create, Start cancellation/late Lock does not start capture. Product build and synthetic offscreen History states; visible hardware/private/account acceptance remains separate.

Notes checkpoint adds actual injected HTTPX completed-stream proof, unsupported citation/malformed/partial/cancel negatives, helper cleanup receipts, source deletion/Lock/Start race, no automatic biography promotion and clear generated-versus-user rendering. It must not depend on a live account or network model for CI.

## Alternatives, costs and limits

| Alternative | Benefit | Cost / decision |
| --- | --- | --- |
| GRDB private in-memory queue + encrypted snapshots | Reuses mature Swift query/transaction/concurrency/backup/close code and tests; survives helper retirement independently. | Recommended. New exact-pinned MIT package and a small audited C serialization bridge; whole-snapshot saves need bounded memory/latency proof. The [reuse evidence](../../research/SESSION_HISTORY_REUSE.md) includes an actual release probe. |
| Direct native SQLite3 + same encrypted snapshots | No Swift package; native SDK supplies serializer and backup. | Technically viable on this host, not rejected for style. Relay would own statement lifetimes, binding, queue confinement, transactions, schema caches, backup rollback and close/cancel behavior. GRDB removes substantial work that does not differentiate Relay. |
| Extend current Python BrainStore/helper | Reuses current Python SQLite and serialization. | Mixes verified personal facts with unverified session content unless separately isolated; End/helper/account replacement owns its lifetime; extra bulk pipe traffic and restart coordination. Prefer a distinct native History lifetime, not a second Python process. |
| GRDB disk SQLite / SwiftData / Core Data | Familiar durable queries and app tooling. | Plain persistent stores/journals/indexes do not meet the proposed encrypted-at-rest boundary. A new disk encryption strategy or SQLCipher is separate architecture, not a reason to silently weaken the boundary. SwiftData history reference was GPL-noticed, not adopted. |
| JSON encrypted record files | Small initial format, record-level writes. | Must implement indexing, migration, atomic multi-record deletion/notes references, ordering and transactional limits. Existing SQLite plus GRDB is a stronger reusable fit. |

The approval amendment above authorizes the bounded manual History implementation; each source/app checkpoint still receives independent review before assembly/exposure. Generated-note inference remains a separate contract. Long-session capacity, generated note quality, real OS/capture/account behavior and secure deletion beyond the current live encrypted file remain explicit limits.
