# Generated meeting notes presentation and editor review

Base: canonical f57a484, whose accepted runtime checkpoint is e5f00f0. This component adds presentation and an app-owned bounded wording draft only. It does not yet insert the section into History or issue generation/save permission.

## Behavior and ownership

The section presents summary, decisions, next steps, literal source citations and generate/stop/edit/regenerate/delete actions. Every callback carries the original displayed snapshot. The model must recheck its actual source, operation, record and note versions. `saveEdits` returns only after a matching real save acknowledgement; failure retains wording and says the save could not be confirmed, including indeterminate storage outcomes.

The draft survives view recreation. Reopening the same note after its saved version changes preserves the original draft and save version, with a visible warning. A different dirty target requires an explicit keep/discard choice. Matching Lock/Delete/expiry/source retirement clears private draft state; unrelated record notices preserve it. The later Model integration must own one draft, fan out actual denial notices and include it in History's navigation/discard guard.

Default generation uses the full saved transcript. An explicit excerpt picker takes only actual displayed `HistoryFinal` rows, captures the original snapshot and endpoints, and rejects reversed endpoints. It tells the user to load more transcript rows to extend the selection. Store remains responsible for original membership/currentness; there is no automatic prefix fallback. Source labels identify microphone or selected-app audio, not verified people. Citation display escapes unsafe formatting without changing the original reference passed to the model.

## Independent review and observed verification

Both speed and notes workers independently read the three presentation/editor/test files. Review found two concrete issues: a dirty same-note draft could not be reopened after revision advance, and a held old save returned success after its local editor had been replaced, allowing an old task to close the new sheet. The original held-callback fixture reproduced exactly one failed assertion on the old behavior (one case, 1.153 seconds). Earlier attempts stopped at compile errors and establish no behavior result.

The narrow acknowledgement correction checks original local binding after await, then checks that the published clear did not install a replacement editor. The unchanged held-replacement fixture passes. Additional cases cover reentrant replacement during clear, original-version reopening, failed-save wording retention, matching denial before held acknowledgement, unrelated denial and exact source quote escaping. Source re-review found no remaining blocking issue; two source-label/singular-copy corrections followed review.

The root combined native gate collected **28 cases, all passed, zero skips/failures**, in a 17.210-second command: 11 Notes DATA, four actual full-source store, five native wire and eight presentation/editor cases. It explicitly exported four fictional offscreen layouts (empty, ready, working, unavailable) and never ordered a window. Root visually inspected all four: no clipped controls or text in the tested layout. These are presentation fixtures, not full app/native helper/account acceptance. Final History insertion, citation navigation, actual edit/delete effects and full app gates remain pending.

Reproduce through the existing macOS panel package filters `GeneratedMeetingNotesPresentationTests|NativeNotesWireTests|HistoryNotesDataTests|HistoryNotesStoreSourceTests`. Set `RELAY_NOTES_RENDER_DIRECTORY` only to an owned synthetic export directory to include offscreen rendering; otherwise that one export test explicitly skips. Follow the shared resource budget and reuse retained caches. No credentials, recordings, model calls, dependencies or private files are used.
