# Issue 29: frozen document conversion acceptance contract

Authorized by the owner on 2026-10-22: define acceptance, execute a Luna XHigh worker loop, preserve tests and Relay scope, review before merging.

## Outcome
Evaluate real, pinned MarkItDown and Docling on fabricated PDF/DOCX bytes. Add one bounded local conversion adapter feeding the existing unverified Personal Brain review lifecycle with honest source locations. This is a synthetic feasibility slice, not production import or native user authentication.

## Fixed interface
`relay_spike.document_conversion.convert_document(data, *, file_type, backend="native")` accepts bytes only, `file_type` pdf/docx, and backend native/docling/markitdown. It returns an immutable result with `status`, `reason`, `backend`, `document_sha256`, `text_sha256`, `text`, `segments`. Statuses: converted, needs_review, unsupported, invalid, unavailable. Failed/unsupported/unavailable results have empty text and segments; needs_review can carry comparator text but no invented locations.

Each immutable segment has `text`, `start`, `end` (Unicode character offsets into canonical result text), and one-based `page` or `paragraph` with the other None. A segment's text must exactly equal text[start:end]. Every character in a candidate must be traceable to its source segment. Original-byte SHA256 and derived UTF-8 text SHA256 are distinct.

`stage_converted(result, gateway, *, observed_at, capability)` returns `(source_id, cards)`. Only a complete, validated converted result can enter the existing gateway. It must retain the original-byte digest as source.external_ref = `document-sha256:<digest>`, retain source.checksum/evidence hashes over canonical text, and create only unverified candidates. Add only the backwards-compatible optional `raw_document_sha256` keyword to ReviewGateway.select_source for this metadata; do not change the SQLite schema or existing approval authority. Validate the digest before writes. Invalid/tampered/incomplete results fail closed. Source selection and staging are one transaction, so failure leaves no partially selected source.

## Supported paths and honest limitations
- native PDF: explicit model-free Docling NativePdf pipeline; simple born-digital PDF line/page provenance, no OCR, ML layout, VLM, table inference or model downloads.
- native DOCX: pinned python-docx provides top-level paragraph ordinals; page is None. Reject unsupported tables/embedded or externally linked content rather than silently drop it. A synthetic plain-paragraph fixture is the supported minimum.
- Docling DOCX and MarkItDown PDF/DOCX: actually execute the pinned libraries as comparators. Their flattened output lacks source locators, so return needs_review without fabricated page/paragraph data and refuse staging. No runtime fallback that silently broadens capabilities.

## Pinned dependencies, reviewed before adoption
markitdown[pdf,docx]==0.1.9; docling-slim[format-pdf,format-docx]==2.142.0; python-docx==1.2.0. All MIT. Use Python 3.12 for the optional converter environment. Record source URLs, licenses, resolved versions and platform requirements. No models-local/standard/all extras, inference provider, OCR weights, plugins or service endpoints.

## Mandatory checks
A1. All existing tests and EVALS validators are unchanged and pass. Controller-owned tests/test_document_acceptance.py, tests/fixtures/documents/** and this spec are frozen. Worker may add new tests but cannot edit, skip, remove, weaken or replace these checks. A necessary contract correction must be raised to the controller with evidence before any edit.
A2. The eight fabricated fixtures and manifest hashes remain byte-identical. The two-page PDF's three literal claims map to expected pages. Unicode DOCX's five claims map to expected paragraph ordinals. Duplicate DOCX preserves two separate locations. No expected text/locations are computed by production code.
A3. Actual native PDF and DOCX conversions succeed on the fixed supported fixtures. Every required claim has an exact source segment and correct original-byte digest. Arbitrary source changes produce different original-byte digests even if extracted text is the same.
A4. Actual MarkItDown PDF/DOCX and Docling DOCX return the expected literal claims, report missing provenance as needs_review, and cannot be staged. Dependency absence is unavailable; it must never masquerade as a successful benchmark. The mandatory integration run must have zero skipped tests and all pinned packages installed.
A5. Corrupt PDF/DOCX, encrypted PDF and blank/image-only PDF fail safely with no staged facts. Empty/nonbytes/path/URL inputs, unsupported file types/backends, input >2 MiB, output >30,000 chars, PDF >10 pages, and hostile DOCX archives (uncompressed >8 MiB, >256 entries, external relationships) fail closed. Conversion runs on bytes/BytesIO only. No raw exception bodies/source text in errors or benchmark output.
A6. Block outgoing socket connections/name lookup throughout import and conversion in the mandatory integration run. No downloads, remote fetch, OAuth, model request, real private source or audio access. Use task-local package/model cache directories so prior user caches cannot supply hidden weights; native paths must run without weights. Record exact limits of the network guard, do not claim hostile native-parser sandboxing.
A7. Staging requires the existing host capability. Zero verified facts before explicit approval. Existing actor ownership, stale source/card, canonical conflict and revoke/redaction behavior continue to hold. Revocation clears original-byte digest metadata as well as evidence. Fake/partial/comparator results cannot create a source or candidate.
A8. A synthetic benchmark executes both pinned converters for PDF and DOCX, reports status/content recovery/source-location support, wall time and process peak RSS with OS-aware units. Record observed host/versions, cold versus warm scope and all unavailable cases. No unmeasured speed claims or arbitrary performance success threshold. Correctness/provenance gates precede efficiency comparisons.
A9. New optional integration CI installs narrow pinned requirements, runs existing checks plus mandatory no-skip frozen acceptance, and never downloads model weights or uses private data. Keep existing lightweight offline CI unchanged.
A10. Independent code/spec review and exact-head GitHub CI must pass before merge. The worker cannot push, create/merge PRs, approve itself, or choose new issues. The controller owns those actions under the user's authorization.

## Scope and loop
One issue, branch and PR. Allowed production additions: document_conversion.py and small document backend/benchmark helper modules if needed; one backwards-compatible gateway metadata keyword; optional requirements/workflow and focused docs. No OAuth/audio/QA/runtime memory redesign, cloud connector, native UI or generic agent framework.

Initial worker followed by at most three repair rounds before controller diagnosis/escalation. Completion means all mandatory checks and reviews pass. An iteration cap does not turn a failure into success. Preserve evidence in the SDD ledger, including commands, return codes, dependency limitations and each revision.
