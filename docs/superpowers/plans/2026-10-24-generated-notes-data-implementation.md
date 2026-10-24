# Generated Notes Data Checkpoint Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, task by task. Root explicitly assigns this single owner; do not spawn agents.

**Goal:** Independently validate the approved notes source/output/provenance data without issuing authority, performing IO or changing the host.

**Architecture:** One pure Python module returns frozen data records/tuples from strict bounded JSON. It reuses existing strict_json and preserves exact source bytes for the domain-separated hash. Shape/integrity/citation validation is separate from future actual History read, native issuance, account configuration and final commit gates.

**Tech Stack:** Existing Python3.14 stdlib/dataclasses/hashlib/json/unicodedata and unittest. No dependency, model, environment, native build or runtime import.

**Spec:** Exact approved60539785fda6d213b74ea216caaed834fcf6960d, imported unchanged as declared documentation only: [design](../specs/2026-10-24-generated-session-notes-design.md), [bounds](../../evidence/2026-10-24-notes-bounds/README.md). Branch `feature/generated-session-notes-data-2026-10-24` starts at published runtime foundation0c87bae4c1d9c23662b262bf93608dc35901c8c4. DesignPR98 branch remains605.

## Global constraints

- DATA ONLY. No SessionHost/transport/native/controller/account/History/runtime import, source issuer/claim/currentness stub, timer/clock, inference, file/network IO, persistence or personal/learning promotion.
- Parsed/validated bytes are not evidence that a real record exists, that a declared full selection includes every actual row, or that a configured model/account exists. Future private owners enforce those claims.
- Source1,024rows/256KiB raw text/2MiB encoded JSON; exact eleven inherited gaps including captureEndUnknown; rowID101byte maximum with lossless UInt64 components; current final revision1. Preserve allowed source controls, exact whitespace/text and original bytes.
- Output<=8KiB raw and canonical, <=16items (summary1..8/decisions0..4/nextSteps0..4), text<=768bytes,1..3literal citations/item, quote<=240bytes. No fabricated metadata/model/personal authority in model output.
- Derived payload<=256KiB, strict fields/provenance/membership and original-byte hash; immutable data only. Full/excerpt/counter/null/status boundaries follow the spec, no fallback/truncation.
- Use existing `/private/tmp/relay-root-current-runtime/venv/bin/python`, PYTHONDONTWRITEBYTECODE. Pure tests <=10seconds, no subprocess/helper/model/converter/native child. Artifact owner retains heavy slot; no compiler/download/new cache/environment. Canonical LOCAL_RESOURCE_BUDGET applies to later phases too.

## File map and APIs

- Create `relay_spike/session_notes_data.py`: NotesDataError fixed safe code; frozen NotesSelectionData, NotesRowData, NotesSourceData, NotesCitationData, NotesItemData, NotesOutputData and NotesDocumentData. All collections tuples, input retained as immutable bytes. No authority properties/callbacks.
- Create `tests/test_session_notes_data.py`: only fictional in-memory projections/citations/provenance and bounded maximum fixtures.
- Create `docs/lanes/GENERATED_NOTES_DATA.md`; append own HANDOFF evidence. Do not alter runtime/import/package/default configuration.

```python
parse_source_payload(raw: bytes) -> NotesSourceData
parse_generated_notes(raw: bytes, source: NotesSourceData) -> NotesOutputData
parse_notes_document(raw: bytes, source: NotesSourceData) -> NotesDocumentData
```

SourceData fields expose record_id, record_revision, selection, record_state, gaps, rows, raw_bytes and source_digest. RowData exposes row_id/revision/source/text/text_digest. OutputData exposes tuple summary/decisions/next_steps and canonical_bytes. DocumentData exposes immutable validated document fields and canonical_bytes, not a save/currentness receipt. Parsing provenance requires its captured source data for exact row membership/digest/quotes; no implicit source read.

## Task1: strict source data

- [x] Write source API/domain tests first: full and explicit excerpt, exact preserved bytes/domain hash, immutable tuples, every missing/unknown/duplicate field, bool/float/overflow/noncanonical integers/UUIDs, all11gaps/unknown/duplicate gap, completed-with-gap, row/source/revision/identity consistency, missing endpoints/count mismatch, invalid Unicode/NUL and actual source scalar/UTF8/aggregate bounds.

```python
source = parse_source_payload(source_bytes)
self.assertEqual(source.raw_bytes, source_bytes)
self.assertEqual(source.source_digest, hashlib.sha256(b'relay.notes.source.v1\n'+source_bytes).hexdigest())
self.assertEqual(source.rows[0].text, original_text)
with self.assertRaises(NotesDataError):
    parse_source_payload(changed_source_with_unknown_gap)
```

- [x] Run the new test module red on missing API; preserve exact failure before implementation.
- [x] Implement strict data-only parsing. Reuse generated_answer.strict_json (duplicate/nonfinite/UTF8/depth protection); add depth8/8192value-node checks. Enforce exact field sets and types with safe codes, no raw values in errors. Use a source-specific nonblank predicate and allow admitted non-NUL controls; do not reuse general bounded_text which rejects those controls or strip source text.
- [x] Run source tests green within10seconds; no actual source/admission assertion. Freeze after output/provenance tasks form the independently reviewable component.

## Task2: strict output and literal references

- [x] Add red output tests: valid full/excerpt citations; unknown/missing/model-metadata fields; raw/canonical8KiB; item/group/text/quote limits; foreign/nonincluded row IDs; mismatching exact Unicode/whitespace quotation; duplicate citations within one item; source text preserved; malformed/nested/partial JSON; future schema and nonfinite values.

```python
notes = parse_generated_notes(output_bytes, source)
self.assertEqual(notes.summary[0].citations[0].row_id, source.rows[0].row_id)
with self.assertRaises(NotesDataError):
    parse_generated_notes(output_with_invented_quote, source)
```

- [x] Implement output DTOs/validator only. Source membership and UTF8 substring equality are structural support, never semantic truth. Item text rejects hidden controls except newline/tab; original quotes remain byte-exact and have bounded safe presentation responsibility later.
- [x] Run affected source/output cases green, with no host/worker/probe or model call.

## Task3: strict persisted provenance data

- [x] Add red document tests: exact256KiB envelope and fields, source record/revision/scope/gaps/digest/membership match, every row ID/revision/text digest, safe checked positive note/record revisions, generation UUID/counters/requestSequence1, fixed prompt policy, declared model syntax limit (not configuration proof), real-calendar24byte UTC form, generated/null edit versus edited/valid timestamp, strict embedded output/citations and unknown fields.

```python
document = parse_notes_document(document_bytes, source)
self.assertEqual(document.source_digest, source.source_digest)
with self.assertRaises(NotesDataError):
    parse_notes_document(document_with_changed_membership_digest, source)
```

- [x] Implement frozen data parsing/cross-field checks. Do not add a native receipt, issuer, save, provider, auth flag or currentness method. A well-formed declared model ID is still untrusted data. No implicit semantic approval.
- [x] Exercise full1,024row/256KiB text projection with maximum-width IDs and all11gaps, control6:1 expansion, source/output/document overflow and exact-membership variants. Reuse the approved small bound algorithm conceptually; avoid duplicating large fixture data on disk or repeatedly allocating maxima for every mutation.
- [x] Add explicit no-effects control around actual parser calls (fixture construction/import first): patch builtin open/socket/subprocess to fail if invoked; parsers must still work. Verify future authority fields such as authorized/claim/model-selection are not accepted.
- [x] Run only this bounded pure module with a10second SIGALRM/KeyboardInterrupt guard, then nearby strict-json unit cases only if changed code justifies them. Existing strict_json must remain unchanged.
- [x] Review diff/import graph, safe errors, immutability and exact spec coverage; update lane/HANDOFF with red/green/count/time/limits; commit/publish independent data checkpoint for root review. No runtime or native/store/Model integration before final History acceptance and heavy-slot allocation.

## Execution command once tests exist

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tests:. /private/tmp/relay-root-current-runtime/venv/bin/python - <<'PY'
import signal, unittest

def stop(_signum, _frame):
    raise KeyboardInterrupt('notes data test budget exceeded')

signal.signal(signal.SIGALRM, stop)
signal.setitimer(signal.ITIMER_REAL, 10)
try:
    suite = unittest.defaultTestLoader.loadTestsFromName('tests.test_session_notes_data')
    result = unittest.TextTestRunner(verbosity=2).run(suite)
finally:
    signal.setitimer(signal.ITIMER_REAL, 0)
raise SystemExit(not result.wasSuccessful())
PY
```

Only documentation has been imported so far. Root has now approved605 design and authorized this independent DATA/PARSER checkpoint. Subsequent source-read/store/native scope/transport/provider/Model/UI work requires its own accepted dependency checkpoint and reviewable plan; none is stubbed by this module. Continuous Learning Memory architecture/observed reply-followup learning remains root-owned and out of this checkpoint.

## Verified data checkpoint

All three data tasks are implemented. The API-first run failed on the absent module; the initial16cases passed0.137s after implementation. Separate new pre-decoder-budget and backwards-clock checks then failed on their original behavior, and passed after the narrow correction. Final20cases pass0.697s under the10second guard, including225deterministically enumerated Unicode/JSON-escaping pairs in two byte encodings, maximum1,024row/256KiB source, exact8KiB output and complete persisted membership. No PBT dependency was added.

Root explicitly clarified timestamp ordering: both UTC fields retain strict real-calendar syntax and origin nullability, but wall time can move backwards. A logically later edited document with an earlier UTC value is valid DATA; actual save/edit receipts must enforce logical revision/CAS ordering in the later store component. This interpretation does not alter the frozen605design branch.

[Data lane](../../lanes/GENERATED_NOTES_DATA.md) records implemented APIs, tested boundaries and limits. This component issues no grant and remains unconnected to the actual host, History, provider or app. Next is independent review of this exact checkpoint; actual History/store/native scopes still wait their accepted dependency and a separately authorized resource slot.
