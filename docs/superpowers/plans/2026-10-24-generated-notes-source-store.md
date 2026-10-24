# Generated Notes Source and Store Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, one independently reviewed checkpoint at a time. Root assigns this owner; do not spawn agents. This document authorizes no execution before the dependency/resource gates below.

**Goal:** Issue a real immutable source from the already-unlocked History owner and save separately typed derived notes through actual encrypted revision/CAS receipts.

**Architecture:** Extend the existing HistoryStore and single coordinator I/O flight. A private store-issued read proof becomes an original coordinator-owned source, separate from parsed DATA and from future inference authority. Schema2 is a known candidate-only migration on explicit Notes mutation; actual storage completion and cleanup/publication have distinct outcomes.

**Tech Stack:** Existing Swift/Foundation/CryptoKit, strict native JSON, pinned GRDB/SQLite and protected History storage. No dependency, SDK, model, auth, key purpose, helper or capture framework change.

**Spec:** Approved60539785fda6d213b74ea216caaed834fcf6960d [Notes design](../specs/2026-10-24-generated-session-notes-design.md), with root's wall-clock clarification in [accepted DATA checkpoint](../../lanes/GENERATED_NOTES_DATA.md). Pure Python DATA24b528578d45224d36468429d95a0c1f57930e0d is independently accepted/published in PR100. DesignPR98 remains frozen605.

## Execution and ownership gates

- PLAN ONLY now. Root has accepted/published the final error/stop foundation8ea630550a088863295f459741d606c4e42b72c0, ref build/generated-notes-history-foundation-2026-10-24. This plan inspected frozen b3672f1e5dfc7c61fa56b115cb99457190674db7 and the exact8ea successor delta; neither runtime is imported here. Execution still waits root's approval of this component plan and resource slot. Start a new implementation branch at accepted8ea; declare DATA24 as a dependency if not already present. Do not import later History editor commits.
- Root retains the heavy slot; no compiler/test/cache/environment/download/helper child in this planning pass. Later native execution requires the controller-assigned retained build root, at most two compiler jobs and the canonical LOCAL_RESOURCE_BUDGET. Do not regenerate historical caches. Root publishes frozen refs; worker does not retry the known CLI DNS failure.
- Preserve605/24 named refs and source. Do not edit History author's pending UI draft/error projection, account/OAuth, protected purpose/key/header, app Model, current capture or response preferences. This component owns only the files below after authorization.
- This is local source/storage functionality only. No provider POST/worker/scope/protocol/Settings/History UI or export-format addition here. Native source/receipt values issue no audio, recording, account, personal, learning or inference authority.
- Do not commit raw local logs, machine paths, environment inventories, process metadata or observed wall-clock receipts. Tests use fictional generated native observations and fixture-only encryption keys. Public evidence is sanitized commands/counts/source hashes.

## Frozen code observations that constrain the change

| b367 file | Actual behavior and consequence |
| --- | --- |
| HistoryStore.swift:46 | One candidate backs up the canonical queue, validates/encodes/bounds it, checks admission, saves, then swaps queues and closes the old queue. A real save may precede a close error. |
| HistoryStore.swift:99 | Warm open compares actual decrypted bytes to canonical queue encoding. Eagerly migrating the canonical queue without a matching save breaks that check and lets ordinary writes persist migration. |
| HistoryStore.swift:60 | Removal builds a fresh fixed schema and copies retained rows. Schema2 copy must preserve unaffected derived rows and exclude only deleted/dependent source. |
| HistoryStore.swift:268 | detail(all:true) reads complete rows in capture ordinal/native row order; ordinary detail is64rows/64KiB. Never serialize the selected page as full source. |
| HistoryStore.swift:311 | Restored schema is exact DDL/index/user_version plus bounded canonical original evidence. Accept only exact known v1/v2; do not execute restored SQL as migration. |
| SessionHistoryCoordinator.swift:96 | run owns the detached actual task and joins it before releasing flight; published snapshot is a drained read view. No replacement or ready return during a reentrant actual flight. |
| SessionHistoryCoordinator.swift:288 | Lock/off retires gates before joining old writer/flight/exclusive/export and closing. Notes must join this same lifetime. |
| HistoryVaultStorage.swift:64 | Existing-only access cannot create a store/lock/key; retained owner checks fixed directory/descriptor identities. Access ends only after actual queues close. |

The accepted8ea successor keeps original error-stop evidence even when audio cleanup quiesced, retains captureFailure and requires it during restore; captureEndUnknown remains the eleventh fixed gap, displayed as Audio end time unavailable. Notes must preserve those actual record states/gaps, never reinterpret a quiesced error as a completed transcript. Other source/CAS/lease mechanisms above remain unchanged in that delta.

## Exact component interfaces

Pure native DATA counterparts follow the already accepted605/24 field/type/byte rules. Their public parsers may return data; their constructors/parsers never return the owned source or a save receipt:

```swift
public enum HistoryNotesData {
    public static func source(_ raw: Data) throws -> HistoryNotesSourceData
    public static func output(_ raw: Data,
        source: HistoryNotesSourceData) throws -> HistoryNotesOutputData
    public static func document(_ raw: Data,
        source: HistoryNotesSourceData) throws -> HistoryNotesDocumentData
}
public enum HistoryNotesSelection: Sendable, Equatable {
    case fullSavedTranscript
    case excerpt(firstRowID: String, lastRowID: String)
}
```

The three DATA structs mirror the605tables and immutable Python fields: canonical counter strings/UUIDs/hashes, exact original source bytes, fixed selection/gaps, ordered row proofs and bounded canonical output/document bytes. Native JSON preflight has nesting8/8192value-node limits before recursive allocation. Quotes remain byte-exact, including admitted nonprinting scalars; presentation escaping is a later UI/export responsibility. No clock read is used for DATA validation.

The source-read API is an actual storage operation, not a source-shaped JSON initializer:

```swift
@MainActor
public func prepareNotesSource(recordID: UUID, expectedRevision: Int64,
    selection: HistoryNotesSelection, intentID: UUID,
    isCurrent: @escaping @MainActor () -> Bool,
    onRetired: @escaping @MainActor (HistoryNotesSource) -> Void
) async throws -> HistoryNotesSource

@MainActor public func ownsNotesSource(_ original: HistoryNotesSource) -> Bool
@MainActor public func retireNotesSource(_ original: HistoryNotesSource)
```

`HistoryNotesSource` is a final reference with no public initializer. It exposes immutable validated source DATA only. Its internal constructor requires `HistoryNotesStoreRead`, whose initializer is private to the actual store-read file. The read proof retains the original store identity, actual record/revision/expiry and complete selected row proofs. The coordinator additionally retains original object identity, workspace/policy/selection epoch, intent and the existing thread-safe HistoryAdmission gate. A private pointer is the current source; no UUID lookup or parsed DTO can reconstruct ownership. The immutable onRetired callback belongs to this original source/intent and runs once on MainActor after denial, outside every lock. It is the later owner integration seam, not a helper command or inference permit in this component.

`ownsNotesSource` is a synchronous private ownership view, not filesystem IO or a claim that disk can never change. Actual retained file/directory ownership and canonical bytes are revalidated through the existing storage port on source read and every commit. Do not acquire the store's blocking lock from MainActor to implement this read view.

The store operations stay internal to RelaySessionPanel. App/public DATA cannot mint a generation receipt:

```swift
func readNotesSource(_ id: UUID, expectedRevision: Int64,
    selection: HistoryNotesSelection, intentID: UUID,
    admission: @Sendable () -> Bool) throws -> HistoryNotesStoreRead

func saveGeneratedNotes(_ output: HistoryNotesOutputData,
    provenance: HistoryNotesGenerationData, modelID: String,
    source: HistoryNotesStoreRead, operationID: UUID,
    admission: @Sendable () -> Bool) throws -> HistoryNotesCommitOutcome

func editGeneratedNotes(_ id: UUID, expectedRecordRevision: Int64,
    noteID: UUID, expectedNoteRevision: Int64,
    texts: HistoryNotesEditedTexts, operationID: UUID,
    admission: @Sendable () -> Bool) throws -> HistoryNotesCommitOutcome
```

The store-issued read retains the original intentID; source intent, operationID and provenance.operationID must match. Its single local commit state moves available → committing → consumed under the existing store lock, including a failed attempt. An explicit retry requires a newly issued source; no unbounded replay registry or automatic retry is added. Denial itself is a synchronous gate change and never waits on that store lock from MainActor.

Generated save accepts output and declared generation/model DATA only; it constructs noteID, noteRevision, saved revision, source membership/digest and origin internally from the actual original read and canonical store. It cannot accept a caller-selected persisted document as a receipt. Declared provenance/model DATA still does not prove any provider/configuration; the future actual scope owner must supply/check those original facts before exposing a public app commit.

`HistoryNotesEditedTexts` has exactly summary/decisions/nextSteps text arrays. Counts/order must match the stored note; only text changes, references/generation/source/model/policy remain identical. `HistoryNotesCommitOutcome` contains the actual privately constructed encrypted-save receipt and `cleanupComplete: Bool`. Receipt fields are original operationID, recordID, noteID, sourceRecordRevision, savedAtRecordRevision and noteRevision. It exists only after storage.save returns; it is never constructed from source/output DATA. Errors before storage completion produce no receipt. If ciphertext saved but old queue close fails, return that actual saved outcome with cleanupComplete=false, retain failed old queue ownership and make the coordinator unavailable/busy until its genuine close/recovery. Never label the save unchanged or paint a cancelled result. Do not broaden existing append/edit error semantics or invoke an external callback under the store lock.

An error thrown by storage.save is not proof of unchanged disk: the existing vault writes atomically before its final permission-setting step. A throwing post-write fixture must produce an indeterminate/unavailable result with no positive receipt, preserve original ownership and require actual owned reopen to reconcile durable state. Never retry/overwrite from cached plaintext or promise unchanged bytes after that result. A known before-write failure can assert unchanged ciphertext in its dedicated test.

Own-save revision handling is distinct from foreign mutation. Captured source DATA/revision remain immutable; register only the actual returned receipt on the same still-current source/operation after the await. Its exact checked saved revision is the one allowed self-advance for a later final publication gate, not permission to rebase onto another title/source/note mutation. A cancelled/stale source may retain its actual IO outcome for reconciliation but acquires no publication ownership from it. This component adds no public app publication entrypoint.

This checkpoint deliberately does not expose a public generated-result commit entrypoint to the app. Future actual notes-scope/model completion integration must verify its original scope/helper/account/result, revalidate the same source and then call the internal save operation. Native storage tests may supply validated fictional output/provenance DATA alongside an actual store-issued source; that proves persistence/CAS only and never pretends a model completed.

## Files

- Create Sources/RelaySessionPanel/HistoryNotesData.swift: native immutable DATA schema/parser/hash/citation/provenance rules; no IO/issuer.
- Create Sources/RelaySessionPanel/HistoryNotesSource.swift: original source reference and private read-proof wrapping, immutable retirement callback.
- Create Sources/RelaySessionPanel/HistoryNotesStore.swift: actual complete source read, known-schema migration and typed derived save/edit/restore/source reconstruction. Use an extension with only the narrow store internals it needs; do not expose canonical DatabaseQueue publicly.
- Modify Sources/RelaySessionPanel/HistoryStore.swift: exact v1/v2 schema dispatch, internal full-detail helper, bounded candidate commit outcome, retained-row copy/deletion integration. Keep one store lock/canonical queue/candidate and the existing original-row validation.
- Modify Sources/RelaySessionPanel/SessionHistoryCoordinator.swift: source preparation reservation/owned gate, one-flight integration, synchronous retirement prefixes and real joins. Share HistoryAdmission internally without making it public; no second mutable global authority registry.
- Create Tests/RelaySessionPanelTests/HistoryNotesDataTests.swift, HistoryNotesSourceTests.swift, HistoryNotesStoreTests.swift and HistoryNotesFixtures.swift. All paths above are under spikes/macos-panel.
- Modify only necessary existing History tests to assert v1 compatibility and source-deletion preservation; do not weaken expected original native evidence or change existing fixtures to make a new failure disappear.
- Update docs/lanes/GENERATED_NOTES_DATA.md and HANDOFF with sanitized exact verification. The accepted source/protocol/limits specification remains605 plus the documented clock clarification.

## Task1: native DATA parity and actual source projection

- [ ] Add API-first native DATA tests with the same605domain: exact bytes/hash, UInt64.max composite IDs, eleven gaps, source controls, full/excerpt consistency, output literal references, persisted membership, backwards-clock provenance and depth/node/raw limits. Expected initial red is missing native APIs. No History/vault/model is used for these DATA-only cases.
- [ ] Implement the three strict parsers and immutable DTOs. Use sorted keys/no whitespace/no solidus escaping for emitted native source JSON, but hash the exact original source buffer; never recreate a Python encoding as authority. Original parsed input is not required to prove an actual record exists.
- [ ] Add actual store source-read tests using existing HistoryTestEvents through SessionTranscriptStore.onHistoryObservation and real encrypted fixture storage. A128row fixture must have a64row selected view but the issued full source must contain128actual original IDs/texts in store order. Excerpt endpoints select a contiguous inclusive range from that complete array, not from its page; wrong/missing/reversed endpoints reject rather than widening or prefixing.
- [ ] Implement readNotesSource in the existing store lock/queue. Validate the retained owner/canonical storage using existing-only warm-open semantics; purge expiry; require exact expected record revision, non-recording state and capacity for a checked save increment; atomically read complete original rows/proofs in capture ordinal/native row order. Extract a private database detail helper rather than recursively entering public detail while the store lock is held. No title/user note/original event JSON/participant/app identifier/prior derived note enters source payload.
- [ ] Test1,024rows/256KiB actual text/max-width IDs/all11gaps under2MiB source without a page or prefix cap; zero rows, active recording, expired/deleted record, record-revision overflow, invalid original evidence and changed owner fail closed. Existing-only missing/locked History must do zero create/key/lock work, even if an explicit Generate intent exists.
- [ ] Run only DATA/source focused cases in the assigned retained build root after the execution gate; verify red/green then freeze a native-DATA/source-read checkpoint for independent review.

Actual source fixture setup uses the existing validator, not a stored-row initializer:

```swift
let transcript = SessionTranscriptStore()
var observations: [ValidatedTranscriptObservation] = []
transcript.onHistoryObservation = { observations.append($0) }
var events = HistoryTestEvents()
events.start(transcript)
for index in 1...128 {
    events.final(UInt64(index), text: "Fictional row \(index)", into: transcript)
}
events.stop(into: transcript)
// Persist the resulting observations via HistoryStore.append, then finish.
// Assertions compare read source IDs/text with those actual admitted rows.
```

## Task2: owned coordinator source and synchronous retirement

- [ ] Add failing coordinator tests for default/render/selection zero new IO; selected-page versus full source; same intent/read coalescing only if the original target/revision/selection match; cancelled/edited/replaced intent; held read followed by Lock/off/Delete/sourceDelete; ready-publication reentry which starts another actual flight; old retirement callback after replacement. A replacement never becomes ready while the original actual source read/cleanup remains outstanding.
- [ ] Reserve the original notes preparation before publishing/awaiting. Require actual opened store/ready selection, same selected record/revision and no existing writer/export/exclusive/retirement. A genuine paused retention owner is permitted only after its actual History writer is quiescent; active recording cannot prepare. Saving preference need not be enabled to read an explicitly unlocked prior record. Never call openExisting/enableSaving implicitly.
- [ ] Issue HistoryNotesSource only from the completed store read after original intent, workspace/selection epoch, cancellation, actual flight/busy and record checks. Recheck after synchronous snapshot publication. Cache only the original current source pointer and immutable captured fields; no second public readiness or wire boolean can install it.
- [ ] Retirement order is gate denial, clear matching current source, then original onRetired callback outside all locks, then join the actual old read/commit. Lock/off/DeleteAll/close/Start/Resume/End and affected record/title/manual/source mutations retire synchronously before any await or producer release. Paging the same unchanged record does not reinterpret or expand an already-issued source. Reentrant old callbacks cannot clear a replacement.
- [ ] Extend isBusy/waitForQuiescence for actual notes read/commit/retirement reservations, not for a remote model thread that this component does not own. New source issuance remains blocked until those actual operations settle. Existing deletion/exclusive flows join their captured old notes work; never await the current retirement task from itself.
- [ ] For ordinary title/manual-note CAS, preserve the original expected revision after notes retirement/join. If an already-started notes commit advanced it, return stale and keep the editor draft; do not silently rebase. Existing explicit delete/source-delete semantics may retain their already-approved current-revision behavior after joining.
- [ ] Run held-gate/reentry/old-owner controls plus the affected existing History ownership/coordinator cases once; freeze the exact owned-source checkpoint for independent review. No public app or provider integration yet.

## Task3: exact schema2, derived CAS and genuine persistence outcome

The only added DDL is fixed and authored by Relay:

```sql
CREATE TABLE history_generated_note (record_id TEXT PRIMARY KEY REFERENCES history_record(id) ON DELETE CASCADE, payload BLOB NOT NULL CHECK(typeof(payload)='blob' AND length(payload)<=262144))
```

- [ ] Test exact v1 restore/ordinary render/warm-open/ordinary edit remains v1 and byte-compatible absent its existing expiry/repair work. Unknown version/DDL/index/trigger/extra column rejects. v2 restore validates the complete fixed original schema plus this one table and every bounded document against actual surviving original rows; no restored SQL is executed as a migration.
- [ ] First explicit generated save builds the bounded candidate, validates v1, creates the known table and sets user_version2 on the candidate only. Normal open/list/source read does not mutate canonical schema; existing non-notes writes to v1 do not accidentally migrate it. Later v2 backup/retained-row copy/removal preserves the fixed derived table.
- [ ] Add real encrypted restart/CAS tests before implementation: captured source read, local fictional validated output/provenance DATA, exact successful source-record and note revision increments, actual storage receipt, no plaintext marker, fresh restore retains separate manual/generated data. Duplicate/reused operation, mismatched source object/store/intent, stale record/note revision, changed row/quote/digest, record removal, expiry and capacity reject without replacing prior canonical/ciphertext.
- [ ] Implement native final save validation under the store's serialized candidate transaction: same original store-issued source, same record revision and ordered included original row/revision/text proof, current admission and expiry. Construct and strictly validate the native document/caps from that proof plus validated output/provenance. Stamp savedAtRecordRevision from the checked actual record increment; never accept a caller-selected save revision as a receipt. Generate noteID/noteRevision1 for first save, preserve noteID and checked-increment noteRevision only for explicit replacement. No silently expanded source or auto-create of a missing record/vault.
- [ ] Return the real encrypted-save receipt only after storage.save completed. Test before-save failure, held actual save plus cancellation/Lock, thrown-after-write indeterminate result, positive-save/old-queue-close failure, receipt delivered during retirement and later fresh reopen. A started save may finish: retain its actual outcome, veto cancelled paint, and join cleanup. No timer or Task.done stands in for queue/file-owner completion. Only an actual original returned receipt permits its own revision advance; foreign/reentrant changes still veto.
- [ ] Restore reconstructs the captured source from actual surviving included rows plus persisted captured metadata/revision/selection; verify exact source digest, membership/order/text digests and citations. savedAtRecordRevision is no greater than actual current record revision, while sourceRecordRevision precedes its own saved revision. A later append or title/manual edit can preserve an older valid note; it is never treated as covering added rows. A changed/deleted included row invalidates the dependent note. No citation or note is promoted to biography/learning.
- [ ] Implement user-edit CAS separately: exact expected record/note ID/revision, same source/generation/model/policy/citations/group shape, only bounded text arrays changed, origin becomes generated_user_edited, actual new note/record revisions and valid observed UTC. Update savedAtRecordRevision to this actual document write while preserving captured sourceRecordRevision and original generation. Backwards wall clock remains valid; logical save receipts own ordering. No new inference or hidden citation rewrite.
- [ ] Update retained-row/source-delete/record-delete/expiry/DeleteAll candidate copy: retain every unrelated note and manual field; remove a derived row only when its record or one of its included source rows is removed/changed. Source delete outside an explicit excerpt may preserve that excerpt's valid document. Do not drop all derived notes because copyRows creates a fresh database.
- [ ] Test8MiB hard/7MiB existing soft admission and256KiB document cap, full1,024membership case, old prior-note preservation on failure, no unrelated eviction, v1 compatibility, v2 encrypted restart and close/lease recovery. Freeze the exact storage checkpoint for independent review.

## Verification and handoff boundaries

Focused future native filters are HistoryNotesDataTests, HistoryNotesSourceTests, HistoryNotesStoreTests plus materially affected HistoryStoreTests/HistoryCoordinatorTests/HistoryOwnershipTests/HistoryEvidenceValidationTests. Execution is serial in the controller-assigned retained root; no new independent build cache. Record red/green/exact head and counts, not a full-suite or real-user claim. Test fixture keys/public fictional rows only; no OS recording, real account/OAuth/Keychain/model call or helper is needed for this component.

Before claiming the component accepted: review its exact diff against the supplied accepted History foundation, test the real owned source, CAS/save/cancel/close schedules, and request independent root review. No source read, schema migration, authority, save or grant is implemented by this planning commit. Future notes scope/transport/provider/account/app/UI integration remains a separate checkpoint with actual one-worker/post-token/current-source and cleanup proofs. The current helper/response/capture/account policies remain unchanged.
