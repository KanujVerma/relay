# AI notes from a saved transcript

2026-10-24. **Proposal only, implementation not approved.** Owner `/root/review_composition`, GPT-6.1 Sol xhigh. Isolated branch `feature/generated-session-notes-design-2026-10-24` at accepted base e846c00012c73762fa4a599729a5c70b87e532be. Corrected response preferences b270297 is root-accepted at the source/app boundary and stays frozen elsewhere. History file-owner lease d9d91b56185df57c03368cddcc3b38f8a30d23fb is now root-accepted at that boundary; the later account/stop-metadata join is still under review. All History APIs were inspected read-only at immutable772cec5/d9d91b5, without importing runtime here. [Primary-source/reuse evidence](../../research/GENERATED_SESSION_NOTES_REUSE.md).

## Recommendation and alternatives

Add one explicit Generate AI notes action to the unlocked History record. Generate a short typed summary, discussed decisions and possible next steps, each linked to saved source rows and exact supporting quotations. Store that derived document separately from the existing user note, in the same protected History vault. Use the existing configured protected OAuth stream, its completed-stream accumulator and one exclusive actual helper/worker. Never create audio events, reuse an old audio lease, retrieve Personal Brain facts or make a review/title/model-selection request.

The existing live answer-card route is a poor substitute: its question/basis and card schema do not represent saved-document scope, citations or a durable notes receipt. Encoding a summary in card detail would obscure provenance. A separate summarizer SDK/helper would duplicate account, cancellation and process ownership. The recommended narrow notes scope adds a genuine noncapture work identity, bounded source-transfer and typed result to the current host/transport, sharing its real worker and account stream. It does not replace the existing audio/assistant wire or model adapters.

Cluely's inspected client can fetch and edit a session summary, and its session-end action submits filtered transcript text. That does not reveal its server summarization, citations, retry or persistence policy. Relay's explicit transfer, local encrypted storage and source-grounded typed notes are Relay choices. No proprietary source/prompt/assets are copied.

## Product flow and disclosure

History retains Transcript, My notes and a distinct AI notes section. Manual text remains editable and independently saved; generation never overwrites it or the user title. On an eligible selected record show source scope and a Generate AI notes button beside this disclosure: **Sends the selected saved transcript to your configured ChatGPT plan.** No setup wizard, per-start model checkbox or speech-model choices. AI-off/unavailable uses the existing AI Settings route, preserving source selection and drafts; navigation alone performs no account work.

Default scope is All saved transcript only when the entire immutable saved source fits the bounds below. Records marked Partial/Interrupted/Paused retain that warning: all saved text is not a claim that the entire conversation was recorded. For a larger record, say it is too long for one summary and offer Select excerpt. The user explicitly chooses a contiguous range of original rows, sees its count/range and clicks Generate for that excerpt. Never preselect a prefix and call it the session. A view page is not an excerpt grant. There is no automatic chunk summarization, map/reduce or hidden second generation.

Generated content is labelled AI-generated notes, with recorded full/excerpt/partial scope and View source actions. Possible next steps are suggestions or reported plans, not completed work. Source labels remain Microphone/Selected app audio; neither proves a person's identity, job or contribution. Citation structure and literal quotation checks improve inspectability, not semantic truth. No automatic promotion to Personal Brain, profile candidates, verified skills, calendar tasks, mail or external sharing.

During generation show Generating and Cancel; after provider completion show Saving until the actual encrypted receipt. Only then say Saved. Keep the prior saved AI document visible as the prior version while a replacement is pending. Replace AI notes is an explicit replacement action; failures leave its previous saved version and the manual draft intact. Generated text is initially read-only; Edit AI notes opens a separate text-field draft with original citations retained. Explicit Save uses the same text/aggregate bounds and record/note CAS, produces origin `generated_user_edited`, and preserves original generation/source metadata. It cannot silently create a new uncited generated section. It never relabels derived text as original transcript or verified manual evidence. Lock hides all private source/generated/edit drafts immediately, following existing History policy. Export distinguishes transcript, user note, AI-generated and user-edited AI notes.

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

The source payload has exact keys `schemaVersion,recordID,recordRevision,selection,recordState,gaps,rows`. `selection` has exact `kind,totalSavedRows,includedRows`, with kind `full_saved_transcript` or `explicit_excerpt`. Each row has exact `id,source,text`; source is `microphone` or `selected_app_audio`, and id is the original stable HistoryFinal identity. Rows preserve actual store order, including capture ordinal; do not order unrelated capture lifetimes by a common uptime or equate counters from distinct sources. Full scope requires every actual stored row, not just all loaded rows. Record revisions use canonical positive decimal strings, not floating point. `sourceDigest` is lowercase hex SHA256 of `UTF8("relay.notes.source.v1\n") || payloadBytes`; helper hashes those exact received bytes without recreating Swift JSON encoding. The source records stable row IDs plus original row revisions in native memory; the original row ID uniquely names its retained final. If any row revision/text changes, record CAS and digest ownership retire the source.

Proposed initial limits:

- One source buffer/transfer/generation per notes scope; at most128 whole rows and32KiB canonical source bytes. No text truncation or splitting an utterance to fit. Larger sources require an explicit fitting excerpt or remain unavailable.
- Source transfer uses8KiB raw chunks, at most4chunks, original total byte count and SHA256, and a5second staging expiry. A5second deadline bounds only unclaimed source staging, not provider completion. No source data survives close/EOF/retirement.
- Overall notes intent deadline30seconds; actual existing OAuth stream deadline/rate/total budgets still apply, including its default15second stream deadline. Do not mutate a shared stream's deadline or add unsupported request parameters to force larger output.
- Strict completed model JSON at most8KiB, at most16items total: summary1..8, decisions0..4, nextSteps0..4. Each text at most768UTF-8 bytes; every item has1..3citations, each with original rowID and a nonempty at most240byte quote. All individual and overall bounds apply together.
- One persisted derived document per record, at most32KiB including full source row-ID membership and provenance; it replaces only the prior derived document through revision CAS. The existing8MiB/100record History budget still applies. Capacity failure preserves the prior snapshot; no eviction of unrelated records to fit notes.

A deadline retires permission/admission; it does not prove a held native disk call or protected refresh thread stopped. Availability remains blocked until actual receipt/join or the applicable real helper reap completes. These are application resource bounds, not verified model context-window or entitlement claims. A provider refusal/unsupported route/context limit is a typed unavailable result, with no alternate paid model, implicit retry or prefix reduction. The bounds need maximum-size fictional fixtures before exposure.

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

UUIDs are canonical lowercase; digests have64lowercase hex digits; recordRevision is canonical decimal1..Int64.max. UInt64 counters reject bool/float/overflow. Source is one transfer of1..128rows/1..32768bytes; chunks are indexed0..3 without holes, byte-identical duplicates are inert, changed duplicates fail. Exact byte/chunk count, hash and source schema are verified before claim. One scope has requestSequence1; these are independent notes counters, never fabricated audio counters.

Scope response status is `ready` (open, quiesced:null, reasonCode:`ok`), `closed` (close, quiesced:true, reasonCode:`ok`) or `unavailable` (quiesced:false, fixed reason). Notes result revision1 is `pending`, notes:null/reasonCode:`generating`; revision2 is exactly one of `completed` (validated notes, reasonCode:`ok`), `cancelled` (notes:null) or `unavailable` (notes:null). Fixed non-success reasons are `busy,stale,source_unavailable,source_expired,source_budget,inference_disabled,account_unavailable,request_unavailable,output_invalid,cancelled,transport_closed`; no raw provider exception/source text in errors. Schema/identity violations fail the transport rather than succeeding as unavailable. Cancellation before admission tombstones its exact original identity and returns cancelled only after matching staged bytes/producer work clear, without admitting a generation.

Bound one actual notes scope, one source/worker/result cache and at most4live notes waiters (open/result/cancel/close). At most512data-free operation/transfer fingerprints are retained per helper. Exact duplicates within the current scope replay its one pending/terminal outcome without IO; close clears source/output/private prompt bytes and only keeps public control receipts/fingerprints. After close a late notes-result replay is inert, not a new terminal or a resurrected scope. Exhaustion rejects new operations, never evicts replay fences or increases queue bounds. Unknown fields and invalid null/status combinations fail closed. ScopeEpoch/requestSequence are independent native notes counters, never audio eventSequence. Scope open is unavailable while any audio/assistant scope, worker, cancel receipt or visual probe remains owned. Ready is emitted only on actual admission. Repeated identical original operations replay their one owned pending/terminal state without IO/generation. Changed UUID reuse, wrong scope/epoch/action and competing terminal receipts fail closed. Use the existing validate-before-removal continuation rules and finite request/replay ledgers; no unbounded source/response dictionaries.

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

Parse exact fields/duplicate keys/UTF-8/controls/types/aggregate limits. Every citation must name an included original row, have no duplicate identical references, and quote an exact UTF-8 substring of that row. Validate in both helper and native source/commit boundary. Absent/foreign/deleted row IDs, fabricated quotes, malformed/partial/refusal/multiple-terminal output are unavailable and cannot replace prior notes. A semantic summary can still be wrong despite valid quotations; UI links original source and never calls the note verified.

A private `NotesTextPermit` carries the actual admitted original scope/source and currentness/configuration guards into the existing stream. Its constructor is internal to actual host admission. Revalidate after actual credential acquisition, immediately before POST, during stream events and before returning completion. Do not call plain text completion with only a pre-await check: `_token()` awaits a real provider. Wire/model reflection cannot construct the permit, select a model/account or substitute a bearer. Native final commit repeats original owner/helper/source/file-lease/record revision/row membership/digest checks after all awaits.

## Durability, revisions and lifecycle

Add a distinct typed derived-note table/payload to the accepted history store, not `saveNotes` (which is the existing USER note). Proposed schemaVersion2 has one fixed derived-note table keyed by record ID, actual note ID/revision and a validated bounded payload. Payload contains captured sourceRecordRevision and rowIDs/digest/scope/gaps, actual model ID, original generation operation and completion time, origin `generated`/`generated_user_edited`, notes and edit time. No account secrets or prompt text are persisted. Deletion/expiry cascades derived notes; deleting any included source removes the dependent document, conservatively including an edited-generated version. Unrelated user note and other sources survive.

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

The notes preparer has its own intent and joined cancellation outside capture startTask/assistant preparation. It invokes the existing prepareAccountForExplicitAction hook first; the account helper-only retirement excludes this CURRENT preparer. Then read the original source, close/join any idle old assistant scope, ensure the actual configured helper and open notes, rechecking intent/source/account after every await. Profile Lock retires an in-progress notes preparation and its current scope without treating History as personal evidence; History Lock remains a separate stronger private-data close. No account identity/token/ASR readiness is inferred from a saved record.

Cancellation cannot recall an already-started model upload. A matching retirement processed before helper POST admission must prevent that POST; after admission it cancels remaining work and native ownership always vetoes a late save/paint. Test the held credential/stream schedules explicitly, without claiming provider-side deletion.

A ciphertext write which already began may complete before cancellation is observed. Do not promise it never touched disk. Lock joins and keeps ciphertext encrypted; Delete/source delete joins then removes dependent notes before reporting Deleted. Exported user copies remain outside local retention. Export reads one complete validated revision and labels source scope and origin, escapes Markdown/JSON safely, and never adds arbitrary HTML execution or remote image loads.

No store/authority/owner lock may invoke a callback that acquires another session lock. Use synchronous short admission fences, release locks, then join the original operation. Reuse the accepted reserved-retirement pattern for helper failure and stale reused-child callbacks. No extra mutable global owner/account registry.

## Implementation checkpoints after approval

1. Accepted History source/lease dependency first; strict derived schema/migration and immutable source-read/CAS component with fake keys/temp vaults. Preserve manual notes and existing purposes. Held actual IO/Lock/Delete/expiry/source removal/self-commit receipt tests.
2. Native notes controller + strict bounded source/result parser/provider + shared worker/stream permit. Actual framed synthetic child/MockTransport, no account/model/private IO. Check one POST, pre/post-token retirement, strict replay/waiters, partial frames/full-write cancellation and actual close/reap.
3. Actual Model owner/preparation/lifecycle and History workspace actions. Account ready before source read/native issuance; explicit visible transfer/full-versus-excerpt; drafts/manual notes/source links; truthful saving and generated labels/export. Held Start/Lock/Delete/account/profile/helper callbacks and final encrypted receipt tests.
4. Freeze verified own commits for root independent review, then root actual window and rebuilt bundled-artifact gates. No hidden inference or device/account acceptance claim.

## Required proof and approval questions

The runtime feature is not approved by this proposal. Root should approve/adjust: 32KiB/128row source and8KiB output/32KiB stored limits; explicit excerpt range rather than multi-pass whole-session summarization; separate notes scope/permit/private stream guard and fixed schema2 migration; generated-user-edited origin; lifecycle reuse/transfer disclosure. The author owns the entire end-to-end feature after approval, with no runtime code written until then.

Tests must cover defaults/render/open/End/restart zero inference; full source across multiple view pages; exact excerpt and no automatic prefix; source record/revision/membership/digest conflicts; quotation membership without pretending semantic verification; one generation and all partial/malformed/refusal/unknown references; held actual token provider then source retirement zero POST; held stream then delete zero save/paint; provider completion before held ciphertext receipt not Saved; source/record deletion and Lock actual joins; self-commit vs foreign revision; manual/newer edit preservation; old helper/notes callbacks vs replacement; Start/End/AI/account/profile and actual one-child ownership; encrypted migration/restore/export/retention/capacity and no Personal Brain promotion. No assertions should be weakened to fit existing stubs.
