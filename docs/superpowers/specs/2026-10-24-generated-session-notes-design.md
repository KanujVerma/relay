# AI notes from a saved transcript

2026-10-24. **Proposal only, implementation not approved.** Owner `/root/review_composition`, GPT-6.1 Sol xhigh. Isolated branch `feature/generated-session-notes-design-2026-10-24` at accepted base e846c00012c73762fa4a599729a5c70b87e532be. Corrected response preferences b270297 is root-accepted at the source/app boundary and stays frozen elsewhere. History file-owner lease d9d91b56185df57c03368cddcc3b38f8a30d23fb is now root-accepted at that boundary; the later account/stop-metadata join is still under review. All History APIs were inspected read-only at immutable772cec5/d9d91b5, without importing runtime here. [Primary-source/reuse evidence](../../research/GENERATED_SESSION_NOTES_REUSE.md).

## Recommendation and alternatives

Add one explicit Generate AI notes action to the unlocked History record. Generate a short typed summary, discussed decisions and possible next steps, each linked to saved source rows and exact supporting quotations. Store that derived document separately from the existing user note, in the same protected History vault. Use the existing configured protected OAuth stream, its completed-stream accumulator and one exclusive actual helper/worker. Never create audio events, reuse an old audio lease, retrieve Personal Brain facts or make a review/title/model-selection request.

The existing live answer-card route is a poor substitute: its question/basis and card schema do not represent saved-document scope, citations or a durable notes receipt. Encoding a summary in card detail would obscure provenance. A separate summarizer SDK/helper would duplicate account, cancellation and process ownership. The recommended narrow notes scope adds a genuine noncapture work identity, bounded source-transfer and typed result to the current host/transport, sharing its real worker and account stream. It does not replace the existing audio/assistant wire or model adapters.

Cluely's inspected client can fetch and edit a session summary, and its session-end action submits filtered transcript text. That does not reveal its server summarization, citations, retry or persistence policy. Relay's explicit transfer, local encrypted storage and source-grounded typed notes are Relay choices. No proprietary source/prompt/assets are copied.

## Product flow and disclosure

History retains Transcript, My notes and a distinct AI notes section. Manual text remains editable and independently saved; generation never overwrites it or the user title. On an eligible selected record show source scope and a Generate AI notes button beside this disclosure: **Sends the selected saved transcript to your configured ChatGPT plan.** No setup wizard, per-start model checkbox or speech-model choices. AI-off/unavailable uses the existing AI Settings route, preserving source selection and drafts; navigation alone performs no account work.

Default scope is All saved transcript for the complete admitted History record: up to 1,024 whole rows and 256 KiB of actual transcript UTF-8 text. The encoded transfer cap covers its worst JSON expansion and original identities, rather than imposing a smaller interview limit. Records marked Partial/Interrupted/Paused retain that warning: all saved text is not a claim that the entire conversation was recorded. If the actual configured provider rejects a complete input or cannot finish within its real stream budget, preserve the source/prior notes and offer an explicit Select excerpt action. A source violating the accepted History bounds is invalid; do not silently rescue it by taking a prefix. The user explicitly chooses a contiguous range of original rows, sees its count/range and clicks Generate for that excerpt. Never preselect a prefix and call it the session. A view page is not an excerpt grant. There is no automatic chunk summarization, map/reduce or hidden second generation.

Generated content is labelled AI-generated notes, with recorded full/excerpt/partial scope and View source actions. Possible next steps are suggestions or reported plans, not completed work. Source labels remain Microphone/Selected app audio; neither proves a person's identity, job or contribution. Citation structure and literal quotation checks improve inspectability, not semantic truth. No automatic promotion to Personal Brain, profile candidates, verified skills, calendar tasks, mail or external sharing.

During generation show Generating and Cancel; after provider completion show Saving until the actual encrypted receipt. Only then say Saved. Keep the prior saved AI document visible as the prior version while a replacement is pending. Replace AI notes is an explicit replacement action; failures leave its previous saved version and the manual draft intact. Generated text is initially read-only; Edit AI notes opens a separate text-field draft with original citations retained. Explicit Save uses the same text/aggregate bounds and record/note CAS, produces origin `generated_user_edited`, and preserves original generation/source metadata. It cannot silently create a new uncited generated section. It never relabels derived text as original transcript or verified manual evidence. Lock hides all private source/generated/edit drafts immediately, following existing History policy. Export distinguishes transcript, user note, AI-generated and user-edited AI notes.

Continuous cross-meeting Learning Memory remains a separate tracked foundational phase. History and derived notes may later be permitted inputs with original provenance, but this notes feature performs no automatic learning, embedding/indexing, feedback promotion or AI-as-ground-truth write.

No generation starts during capture, visual verification, another assistant/notes worker, history writer/export/retirement, or account mutation. An idle assistant conversation is closed and joined before the notes scope opens; it is not relabelled capture. Start/Resume/End/AI/account handoff retires notes synchronously and joins the original work before a new scope/helper is available. Mere workspace rendering, selection, opening history, transcription completion, End or restart never initiates inference. A failed request needs a new explicit Generate action.

## Source preparation and bounds

The history author confirms that selected detail is paged at64rows/64KiB. Its internal `HistoryStore.detail(id,all:true)` reads the complete bounded source (up to1024rows/256KiB). Add an owned source-read operation on the accepted history coordinator, not a getter that serializes `snapshot.selected`.

Proposed seams, with private constructors for source/permit/receipt:

```swift
@MainActor func prepareNotesSource(recordID: UUID, expectedRevision: Int64,
    selection: HistoryNotesSelection, intentID: UUID,
    isCurrent: @escaping @MainActor () -> Bool) async throws -> HistoryNotesSource
@MainActor func ownsNotesSource(_ original: HistoryNotesSource) -> Bool
@MainActor func commitGeneratedNotes(_ result: ValidatedGeneratedNotes,
    source: HistoryNotesSource, operationID: UUID) async throws -> HistoryNotesReceipt
@MainActor func retireNotesSource(_ original: HistoryNotesSource)
```

The actual accepted file-owner/storage lease, vault epoch, policy epoch, record ID/revision, expiry, ordered row identities/revisions and selection bind the source. Source preparation joins/uses the single real history flight, purges expiry before access, reads all rows, verifies the expected record and allowed scope, and emits one immutable canonical UTF-8 JSON byte buffer. Only those actual bytes and their SHA256 are transferred. No key, path, original native JSON envelope, user note, participant guess, résumé, screen image/OCR, guide catalog, prior generated note or other record is included. Response guides do not influence this fixed notes task in v1.

The source is a strict native-emitted JSON object. Keys are sorted, with no insignificant whitespace, no escaping of solidus `/`, required JSON string escaping and valid UTF-8. The helper hashes the exact bytes rather than recreating Swift serialization. `sourceDigest = lowerhex(SHA256(UTF8("relay.notes.source.v1\n") || payloadBytes))`.

| Source field | Exact type/domain |
| --- | --- |
| `schemaVersion` | integer1, never bool/float |
| `recordID` | canonical lowercase UUID string,36ASCII bytes |
| `recordRevision` | canonical positive decimal string1..Int64.max; reject new generation if it cannot safely advance for save |
| `selection` | exact object `kind,totalSavedRows,includedRows,firstRowID,lastRowID` |
| `recordState` | `paused`, `completed`, `partial` or `interrupted`; never actively `recording` |
| `gaps` | unique array of0..10fixed gap strings in declaration order below; completed requires empty |
| `rows` | ordered array of1..1024exact objects `id,revision,source,text`; IDs unique |

Selection `kind` is `full_saved_transcript` or `explicit_excerpt`; counts are integer1..1024, never bool/float; includedRows equals the rows array length and is no greater than totalSavedRows. `firstRowID`/`lastRowID` are the exact first/last included IDs. Full requires all actual store rows, not all loaded view rows, so both counts equal the complete read count. Excerpt means a user-selected contiguous inclusive range in the complete original store order; the native read verifies the endpoints/membership. A JSON selection object alone grants nothing. The native API is `HistoryNotesSelection.fullSavedTranscript` or `.excerpt(firstRowID:lastRowID:)`.

Row `id` is the exact HistoryFinal composite `lowercaseCaptureUUID:epoch:sourceCode:streamGeneration:segmentID`, where sourceCode is1or2 and the other three counters are canonical decimal1..UInt64.max. Its maximum is101ASCII bytes. Row `revision` is the actual canonical HistoryCounter string, exactly `"1"` in source schema1, matching the accepted original-final validator; future revision policy requires another explicit review. Row `source` is `microphone` for1 or `selected_app_audio` for2, consistent with that ID and actual retained source. Row `text` is the exact accepted nonblank string: at most1200Unicode scalars/4800UTF-8 bytes, no NUL, aggregate actual text at most262144bytes. No normalization, trimming, source relabelling or invented person identity. Store order is capture ordinal then the existing native row order, never a comparison of unrelated capture uptimes. Native memory also retains the original row revision/text proof and actual file/store/policy owner.

Gap strings are exactly `sourceUnavailable,sequenceGap,capacity,storageFailure,savingStopped,interrupted,captureFailure,sourceDeleted,invalidObservation,unfinishedSpeech`, inherited from HistoryGap. They describe missing/limited saved source, not ASR accuracy or inferred duration.

Proposed bounds, corrected from the initial smaller draft:

- One full or explicit-excerpt source buffer/transfer/generation per notes scope; 1,024whole rows/256KiB actual text, at most2MiB encoded source JSON. This covers the entire accepted History projection domain; no ordinary full-interview restriction at128rows/32KiB.
- Source transfer uses8KiB raw chunks, at most256chunks, original byte count and SHA256, written sequentially with one awaited whole-frame write at a time. The existing queue remains32frames/256KiB; a transfer cap is not queued memory. Chunk JSON uses unescaped solidus so the full8KiB base64 frame remains below16KiB.
- One5second staging deadline starts at source-begin, does not extend per chunk and only bounds unclaimed source; cancel its one timer on claim/retirement. Overall notes intent deadline30seconds; existing actual stream deadline/rate/total budgets remain, including default15second generation. No shared deadline mutation or unsupported model request parameter.
- Strict raw and re-encoded canonical model JSON at most8KiB, at most16items total: summary1..8, decisions0..4, nextSteps0..4. Each nonblank text at most768UTF-8 bytes; every item has1..3citations with original rowID and nonempty at most240UTF-8 byte exact quote. All individual/overall bounds apply together. Display nonprinting quote scalars visibly escaped; matching still uses original bytes.
- One persisted derived document per record, at most256KiB canonical payload including all1,024source membership proofs and provenance; only explicit replacement, through CAS. Existing8MiB/100record/soft-admission snapshot budget remains. Capacity failure preserves previous ciphertext/canonical notes; never evict unrelated records to fit.

[Bound calculation and fictional witnesses](../../evidence/2026-10-24-notes-bounds/README.md) include maximum UInt64 composite IDs and all fixed metadata. Source upper bound is **1,743,487bytes** (213chunks) under2MiB; ordinary text432,767bytes/53chunks and quote/backslash694,911bytes/85chunks. U+0001 is actually admitted by the original non-NUL text domain and expands sixfold in JSON, disproving768KiB as a universal cap. Persisted payload with8KiB output and1,024membership proofs is223,779bytes; conservative wider revision/model escaping allowance gives244,515bytes under256KiB. A full chunk frame body is11,179bytes (11,183including prefix). This is a small stdlib projection proof, not a native/model/latency test.

A deadline retires admission; it does not prove a held native disk call or protected refresh thread stopped. Availability stays blocked until actual receipt/join or applicable real helper reap. These are application resource bounds, not verified model context-window or entitlement claims. A provider refusal/unsupported route/context limit is a typed unavailable result, with no alternate paid model, implicit retry or prefix reduction. The bounds need maximum-size fictional fixtures before exposure.

## Native scope and helper protocol

Add a separate `NativeNotesSessionController` and native-owned notes operation/authority. It uses the current original-owner failure/retirement box pattern and actual helper generation, without source drivers, `NativeSessionEvent`, `CaptureContext`, recording consent or a microphone-active flag. One scope accepts one generation. Native stamping happens only after actual account readiness, complete owned source preparation and actual helper notes-open ready receipt, with original intent checks after every await. A changed draft/selection never implicitly submits a replacement.

Proposed exact wire field sets, all within existing16KiB frames:

| Kind | Exact fields beyond `schemaVersion:1,kind` |
| --- | --- |
| `notes_scope_request` | `scopeID,scopeEpoch,operationID,action` (`open`/`close`) |
| `notes_scope_response` | same scope/operation/action plus `status,quiesced,reasonCode` |
| `notes_source_begin` | `scopeID,scopeEpoch,requestID,requestSequence,transferID,recordID,recordRevision,selectionKind,rowCount,totalBytes,sourceDigest` |
| `notes_source_chunk` | `scopeID,scopeEpoch,requestID,transferID,index,data` (canonical base64) |
| `notes_source_end` | `scopeID,scopeEpoch,requestID,transferID,chunkCount,totalBytes,sourceDigest` |
| `notes_generate` | `scopeID,scopeEpoch,requestID,requestSequence,transferID,recordID,recordRevision,sourceDigest` |
| `notes_cancel` | `scopeID,scopeEpoch,requestID,requestSequence,transferID,recordID,recordRevision,sourceDigest,reasonCode` |
| `notes_result` | `scopeID,scopeEpoch,requestID,requestSequence,transferID,recordID,recordRevision,sourceDigest,resultRevision,status,reasonCode,notes` |

UUIDs are canonical lowercase; digests have64lowercase hex digits; recordRevision is canonical decimal1..Int64.max. UInt64 counters reject bool/float/overflow. Source is one transfer of1..1024rows/1..2097152encoded bytes and at most262144actual text bytes; chunks are indexed0..255 without holes, byte-identical duplicates are inert, changed duplicates fail. Exact byte/chunk count, hash and source schema are verified before claim. One scope has requestSequence1; these are independent notes counters, never fabricated audio counters.

Scope response status is `ready` (open, quiesced:null, reasonCode:`ok`), `closed` (close, quiesced:true, reasonCode:`ok`) or `unavailable` (quiesced:false, fixed reason). Notes result revision1 is `pending`, notes:null/reasonCode:`generating`; revision2 is exactly one of `completed` (validated notes, reasonCode:`ok`), `cancelled` (notes:null) or `unavailable` (notes:null). Fixed non-success reasons are `busy,stale,source_unavailable,source_expired,source_budget,inference_disabled,account_unavailable,request_unavailable,output_invalid,cancelled,transport_closed`; no raw provider exception/source text in errors. Schema/identity violations fail the transport rather than succeeding as unavailable. Cancel shares the original request waiter/terminal latch; it never creates a competing terminal after completion. Cancellation before admission tombstones its exact original identity and returns cancelled only after matching staged bytes/producer work clear, without admitting a generation.

Bound one actual notes scope, one source/worker/result cache and at most4live notes waiters (open/result/cancel/close). At most512data-free operation/transfer fingerprints are retained per helper. A transfer consumes one replay entry, not one per chunk: at most256chunk digests are slot-local to the one active transfer, cleared on close; completed transfer metadata keeps its whole-source digest. Closed-scope chunk replay is inert and cannot reconstruct a source. Exact duplicates within the current scope replay its one pending/terminal outcome without IO; close clears source/output/private prompt bytes and only keeps public control receipts/fingerprints. After close a late notes-result replay is inert, not a new terminal or a resurrected scope. Exhaustion rejects new operations, never evicts replay fences or increases queue bounds. Unknown fields and invalid null/status combinations fail closed. ScopeEpoch/requestSequence are independent native notes counters, never audio eventSequence. Scope open is unavailable while any audio/assistant scope, worker, cancel receipt or visual probe remains owned. Ready is emitted only on actual admission. Repeated identical original operations replay their one owned pending/terminal state without IO/generation. Changed UUID reuse, wrong scope/epoch/action and competing terminal receipts fail closed. Use the existing validate-before-removal continuation rules and finite request/replay ledgers; no unbounded source/response dictionaries.

A source stage grants no inference authority. `notes_generate` claims exactly one complete matching original transfer under the actual open scope, current private account/model/effort/endpoint and original native operation. Late/old sources cannot attach, nor may a changed JSON boolean claim readiness. Source retirement before request admission drops bytes and withholds generation; it does not reinterpret missing data as a no-source summary. Source transfer frames use a narrow general-purpose wrapper over the accepted per-frame queued/writing/finished reservation machinery. Preserve32frame/256KiB bounds, queued cancellation/deadline byte clearing, first-byte arbitration and whole-frame completion after writing begins. Await each full write; do not queue hundreds of chunks. Existing image/writer API behavior remains unchanged. No notes visual probe/image capability is created. If actual shared backend close revokes visual capability, retire the native visual setup state through the existing lifecycle so UI never promises images remain enabled.

A matching cancel/close control is synchronously registered/enqueued before local callbacks release an in-progress source producer. Channel failure fences the original producer and reaps the actual child. Cancel/close acknowledgments resolve only after actual owned task/worker completion and source-buffer clearing. EOF/malformed/reply-before-await/old-helper callbacks use original scope and waiter identity; they cannot remove or retire a replacement.

## One generation, prompt and validation

Use the one existing generation worker and the actual protected product stream; no parallel notes worker/second persistent helper. Make task ownership explicit so a notes job does not fabricate a live QuestionTurnMachine token. A narrow worker item can carry either the existing answer request or the private notes request, preserving answer behavior and the actual stop/drain owner. Reuse strict SSE/ResponseAssembler completed-only lifecycle,8192byte output bound and finite event budgets.

The prompt is a fixed validated projection of selected rows (`id,source,text`), scope, record state and gaps. Record/request/helper/account IDs, revisions, digests, secrets and storage paths stay out of model input; original row IDs alone are necessary for citation output. The fixed notes instruction treats every row as quoted untrusted source data. Ask for the exact schema below, describe uncertainty/gaps, avoid unsupported people/ownership/completion claims, and never obey instructions embedded in a transcript. Model output cannot supply request IDs, model identity, origin, source scope/digest, approved facts or provider capability. There is no automatic title generation, output-repair pass, model judge or automatic retry after a POST.

```json
{
  "schemaVersion": 1,
  "summary": [{"text": "...", "citations": [{"rowID": "...", "quote": "..."}]}],
  "decisions": [],
  "nextSteps": []
}
```

Parse exact fields/duplicate keys/UTF-8/controls/types/aggregate limits, with maximum nesting8and8192value nodes (objects,arrays,scalars; property names are not additional nodes) for source/output/persisted payload. Item text is nonblank and rejects Cc/Cf/Zl/Zp scalars except newline/tab; quotes are nonblank valid UTF-8 without NUL and match actual source bytes, with nonprinting scalars escaped in presentation/export. Every citation must name an included original row, have no duplicate identical references within that item, and quote an exact UTF-8 substring of that row. Validate in both helper and native source/commit boundary. Absent/foreign/deleted row IDs, fabricated quotes, malformed/partial/refusal/multiple-terminal output are unavailable and cannot replace prior notes. A semantic summary can still be wrong despite valid quotations; UI links original source and never calls the note verified.

A private `NotesTextPermit` carries the actual admitted original scope/source and currentness/configuration guards into the existing stream. Its constructor is internal to actual host admission. Revalidate after actual credential acquisition, immediately before POST, during stream events and before returning completion. Do not call plain text completion with only a pre-await check: `_token()` awaits a real provider. Wire/model reflection cannot construct the permit, select a model/account or substitute a bearer. Native final commit repeats original owner/helper/source/file-lease/record revision/row membership/digest checks after all awaits.

## Durability, revisions and lifecycle

Add a distinct typed derived-note table, not `saveNotes` (which is USER-only). Proposed History SQLite `PRAGMA user_version=2` preserves the exact three existing tables/index and adds exactly:

```sql
CREATE TABLE history_generated_note (record_id TEXT PRIMARY KEY REFERENCES history_record(id) ON DELETE CASCADE, payload BLOB NOT NULL CHECK(typeof(payload)='blob' AND length(payload)<=262144))
```

The protected History filename/header/key remain unchanged. Payload schema1 is a strict canonical JSON object with exactly the fields below, no unknown/duplicate fields, at most262144bytes. UUID/hash/counter encodings match source rules. All stored source IDs must belong to this record and follow its captured selection order; each ID/proof is unique.

| Persisted field | Exact type/domain |
| --- | --- |
| `schemaVersion` | integer1 |
| `noteID`, `recordID` | canonical lowercase UUIDs |
| `noteRevision`, `sourceRecordRevision`, `savedAtRecordRevision` | canonical positive decimal1..Int64.max; checked increment/CAS, captured source revision precedes its own saved revision |
| `selection` | exact source selection object/counts/endpoints |
| `sourceState`, `sourceGaps`, `sourceDigest` | exact captured source state/gaps/domain-separated hash |
| `sourceRows` |1..1024ordered exact objects `rowID,revision,textDigest`; ID <=101ASCII bytes; revision exactly `"1"` in schema1; textDigest is SHA256 of original row UTF-8,64lowercase hex |
| `origin` | `generated` or `generated_user_edited` |
| `modelID` | actual private configured model identifier, nonblank <=256UTF-8 bytes, no controls/format characters; never model-issued identity |
| `promptPolicy` | fixed `notes_source_v1` |
| `generation` | exact object `scopeID,scopeEpoch,operationID,requestID,requestSequence,transferID,completedAt`; four UUIDs; epoch canonical decimal1..UInt64.max; requestSequence canonical `"1"` |
| `editedAt` | null for generated; required UTC timestamp for generated_user_edited |
| `notes` | validated exact output object, canonical encoded length <=8192bytes |

Timestamps are exact24ASCII UTC `YYYY-MM-DDTHH:mm:ss.SSSZ`, valid calendar year0001..9999. `completedAt` is stamped from actual completed generation receipt; `editedAt` is a later actual user save receipt, never model text. Editing preserves original model/source/generation provenance and changes only validated item text; original references/quotes stay attached. No secrets, storage paths, full prompt or duplicate full transcript are persisted. Membership text digests allow surviving-row validation without retaining another transcript copy.

Deletion/expiry cascades derived notes; deleting/changing any included original row invalidates its dependent document, including an edited-generated version. Unrelated user notes/sources remain. A later source append/resume marks the older full-snapshot note as covering earlier saved text; it never silently expands scope.

Version1 is validated against its exact old schema before an in-memory known-schema migration. Do not execute arbitrary restored SQL or loosen exact schema validation. Persist version2 only on an explicit notes mutation through the actual leased encrypted commit; merely rendering/selecting an old record must not rewrite a vault. Unsupported future schemas fail closed with recovery. Existing profile/account/preferences purposes and keys do not change. Capacity, migration and old-version behavior require dedicated tests before implementation acceptance.

Persisted notes retain captured source state/gaps, ordered row revisions and row membership as well as the digest. After save, a later record revision never grants new authority to the note. Display/export its captured transcript scope and generation time; a resumed record with additional text marks the prior full-scope note as covering an earlier snapshot until explicit replacement. Title/manual-note edits do not erase generated notes; included-row removal/revision/text change invalidates their dependent source proof. This durable-source check is distinct from strict in-flight whole-record CAS. Reconstruct the digest using captured source metadata/revision and actual surviving original rows, rather than expecting current record revision to equal the pre-save revision.

Generated save checks original record CAS and immutable source, then uses the real history candidate transaction/encrypted receipt. The document records the captured source revision; its own commit advances record revision only through that exact owned receipt. Do not treat that self-commit as a foreign mutation, and do not rebase on any other title/manual/source revision. Foreign mutation retires the permit and requires a fresh explicit Generate.

| Event | Immediate fence | Actual joined outcome |
| --- | --- | --- |
| Cancel / close / Start / Resume / End | Retire original notes/source permit before producer release or scope callback; hide pending replacement, preserve prior saved note/drafts except existing Lock policy. | Join source write/worker/cancel+scope receipts. If bounded cleanup fails, reap the actual child before replacement. Capture remains truthfully off until its later genuine Start. |
| AI-off / account selection / sign-out | Same original helper writer/source/notes retirement before account mutation; no new public readiness flag. | Actual helper exit/reap and native profile/history flights complete before credential identity changes. Exclude CURRENT owned account preparation from its own helper-only retirement callback to avoid self-await. |
| Record/title/manual revision / expiry / source delete | Retire affected original source/result and fence new admission; do not silently summarize updated rows. | Join already-started work, then CAS mutation/deletion and dependent-note removal. Old completion cannot recreate the source or record. |
| History Lock / DeleteAll | Hide source/generated/editor state and retire permits synchronously before awaiting work. | Join original notes/source/export/storage operations, then existing close or actual deletion receipt. No replacement opens while old file-owner lease/flight remains. |
| Same-account protected token thread held after async cancellation | Original note permit remains denied, so late provider completion cannot POST/save/paint old work. | Scope task completion alone does not prove the account-global refresh thread stopped. Keep the existing honest boundary; account identity/mode/sign-out reaps the actual helper before mutation. |

The d9 HistoryOwnedSnapshotStorage begins exclusive access before any vault read and ends only after actual GRDB queues close. Notes use that same retained owner and single worker; a detached source read is not another owner. No replacement may begin while original notes IO/queue or close failure still owns it. Revalidate actual directory/file ownership through the accepted storage port before source read/commit; never infer ownership from path existence. The pending History account/stop-metadata join must be accepted before this implementation starts.

The history author reports the root-approved pending join contract: account/helper-only mutation does not close/open idle History, create records or change its preference. A paused retention permit may survive auth refresh, while actual Resume revalidates. Treat this as an integration prerequisite until that exact join is accepted. Require the same still-unlocked selection/policy epoch after account preparation; never implicitly reopen after explicit Lock.

The notes preparer has its own intent and joined cancellation outside capture startTask/assistant preparation. It invokes the existing prepareAccountForExplicitAction hook first; the account helper-only retirement excludes this CURRENT preparer. Then read the original source, close/join any idle old assistant scope, ensure the actual configured helper and open notes, rechecking intent/source/account after every await. An unrelated My Context/Profile Lock does not revoke this History-only source or cancel notes. If its real emergency cleanup actually retires/reaps the shared helper, notes retire with that original helper; no dependent late result can publish. History Lock always fences this private source and notes. No account identity/token/ASR readiness is inferred from a saved record.

Cancellation cannot recall an already-started model upload. A matching retirement processed before helper POST admission must prevent that POST; after admission it cancels remaining work and native ownership always vetoes a late save/paint. Test the held credential/stream schedules explicitly, without claiming provider-side deletion.

A cancelled generation/queued save leaves the prior note. If cancellation arrives after ciphertext writing already began, join and report the actual saved/not-saved receipt without painting the cancelled result; do not claim unchanged storage when a save finished. A later explicit Open reads the actual durable revision. A ciphertext write which already began may complete before cancellation is observed. Do not promise it never touched disk. Lock joins and keeps ciphertext encrypted; Delete/source delete joins then removes dependent notes before reporting Deleted. Exported user copies remain outside local retention. Export reads one complete validated revision and labels source scope and origin, escapes Markdown/JSON safely, and never adds arbitrary HTML execution or remote image loads.

No store/authority/owner lock may invoke a callback that acquires another session lock. Use synchronous short admission fences, release locks, then join the original operation. Reuse the accepted reserved-retirement pattern for helper failure and stale reused-child callbacks. No extra mutable global owner/account registry.

## Implementation checkpoints after approval

1. Accepted History source/lease dependency first; strict derived schema/migration and immutable source-read/CAS component with fake keys/temp vaults. Preserve manual notes and existing purposes. Held actual IO/Lock/Delete/expiry/source removal/self-commit receipt tests.
2. Native notes controller + strict bounded source/result parser/provider + shared worker/stream permit. Actual framed synthetic child/MockTransport, no account/model/private IO. Check one POST, pre/post-token retirement, strict replay/waiters, partial frames/full-write cancellation and actual close/reap.
3. Actual Model owner/preparation/lifecycle and History workspace actions. Account ready before source read/native issuance; explicit visible transfer/full-versus-excerpt; drafts/manual notes/source links; truthful saving and generated labels/export. Held Start/Lock/Delete/account/profile/helper callbacks and final encrypted receipt tests.
4. Freeze verified own commits for root independent review, then root actual window and rebuilt bundled-artifact gates. No hidden inference or device/account acceptance claim.

## Required proof and approval questions

The runtime feature is not approved by this proposal. Root has approved the complete-source/cap correction in principle, conditional on the exact proof/schema. Final approval must cover: complete1,024row/256KiB actual text with2MiB encoded-source and256KiB stored limits, retaining8KiB output; explicit excerpt range rather than multi-pass whole-session summarization; separate notes scope/permit/private stream guard and fixed schema2 migration; generated-user-edited origin; lifecycle reuse/transfer disclosure. The author owns the entire end-to-end feature after approval, with no runtime code written until then.

Tests must cover defaults/render/open/End/restart zero inference; full source across multiple view pages; exact excerpt and no automatic prefix; source record/revision/membership/digest conflicts; quotation membership without pretending semantic verification; one generation and all partial/malformed/refusal/unknown references; held actual token provider then source retirement zero POST; reentrant Model/private snapshot notification invoking Lock/Delete cannot restore old cached notes; held stream then delete zero save/paint; provider completion before held ciphertext receipt not Saved; source/record deletion and Lock actual joins; self-commit vs foreign revision; manual/newer edit preservation; old helper/notes callbacks vs replacement; Start/End/AI/account/profile and actual one-child ownership; encrypted migration/restore/export/retention/capacity and no Personal Brain promotion. No assertions should be weakened to fit existing stubs.
