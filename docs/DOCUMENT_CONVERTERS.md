# Synthetic document converter evaluation

Issue #29 adds a bounded bytes-only evaluation of fabricated PDF and DOCX files. It feeds only validated, source-located native conversions into the existing unverified Personal Brain review gateway. It does not implement a file picker, read paths or URLs, persist whole documents, or prove a real user approved an import.

## Supported conversion paths

| Input and backend | Result | Source locator | Review behavior |
|---|---|---|---|
| Born-digital PDF, `native` | Docling NativePdf text cells, joined into canonical text | One-based PDF page per line segment | Eligible for candidate staging when every candidate span maps to exactly one segment |
| Plain-paragraph DOCX, `native` | `python-docx` top-level body paragraphs | One-based body paragraph ordinal; page is absent | Eligible for candidate staging when every candidate span maps to one paragraph |
| PDF/DOCX, `markitdown` | Flattened MarkItDown Markdown | None | `needs_review`; staging is rejected |
| DOCX, `docling` | Flattened Docling plain text from `SimplePipeline` | None | `needs_review`; staging is rejected |

Docling’s native PDF path is explicitly configured with `NativePdfFormatOption` and `NativePdfPipelineOptions(text_cell_unit=TextCellUnit.LINE)`. Its `TextItem.prov` supplies a page number for each text line. The path does not run layout, OCR, table, VLM, or picture models; it has no inferred reading order or table reconstruction. Scanned/image-only and blank PDFs have no selectable text and fail closed.

PDFium checks `FPDF_GetSecurityHandlerRevision` before either PDF converter runs. Any security handler is rejected, including an encrypted PDF that PDFium can open using an empty user password.

The DOCX native path reads `Document(BytesIO(data)).paragraphs`. It preserves duplicate paragraphs as distinct one-based locations and never invents page numbers. Before extraction, the adapter requires exactly one root `officeDocument` relationship targeting the canonical `word/document.xml` part, validates that the body contains only direct paragraphs and section properties, and checks each paragraph's source XML text projection against python-docx's returned text. Tables, block/inline wrappers, unsupported run content, drawings, objects, external relationships, embedded media, and non-empty headers, footers, comments, footnotes, or endnotes fail closed. **Additional fail-closed rule:** relationship types for headers, footers, comments, footnotes and endnotes are rejected even when the referenced XML part has an arbitrary filename, including noncanonical paths such as `word/context-qualifier-header.xml`. This is stricter than checking file prefixes and intentionally rejects even empty linked secondary parts until their provenance can be reconciled. It fixes the post-merge P2 finding on [PR #34](https://github.com/KanujVerma/relay/pull/34). No hidden header disclaimer can be silently dropped while its body text remains stageable. This prevents the chosen parser from silently omitting source text while the result remains stageable.

## Limits and provenance

The adapter rejects non-`bytes`, empty input, file types outside PDF/DOCX, backends outside `native`/`docling`/`markitdown`, input over 2 MiB, output over 30,000 Unicode characters, PDFs over 10 pages, DOCX archives over 256 entries or 8 MiB uncompressed, malformed archives, and unsupported DOCX structures. Failed results carry empty text and segments. Reasons are short codes and never include source text or vendor exception bodies.

Each located `TextSegment` contains its exact text, character start/end in canonical converted text, and exactly one source locator. Candidate spans are checked against the original canonical text and must fall wholly inside one unique segment. A process-local HMAC binds each `ConversionResult` to its fields; `stage_converted` rejects altered, incomplete, flattened, or otherwise unsealed results before writing. This detects accidental or object-level tampering within the adapter flow; it is not authentication against hostile Python code in the same process.

The existing `ReviewGateway` checksum continues to cover the canonical converted text, preserving B0 behavior. A backwards-compatible optional `raw_document_sha256` argument records the original byte digest in `source.external_ref` as `document-sha256:<digest>`. Candidate evidence retains the derived text digest and character offsets. Source creation, consent and candidate staging share one outer SQLite transaction; any failure rolls back all writes. Existing user approval remains separate and no facts are auto-confirmed. Source revocation clears both hashes and dependent snippets/evidence through the existing ledger behavior.

## Pinned dependencies and footprint

`requirements-documents.txt` pins `markitdown[pdf,docx]==0.1.9`, `docling-slim[format-pdf,format-docx]==2.142.0`, and `python-docx==1.2.0`, all MIT. MarkItDown requires Python `>=3.10,<3.15` and publishes a pure-Python wheel; its transitive PDF/Magika runtimes may use platform-specific wheels. Docling Slim requires Python `>=3.10,<4.0` and classifies macOS, Windows, and Linux with Python 3.10-3.14; Docling Parse publishes platform-specific native wheels. python-docx requires Python `>=3.9` and is OS-independent. The optional integration workflow uses Python 3.12 on Ubuntu. On the measured Apple M2 Pro environment, the resolved versions were MarkItDown 0.1.9, Docling Slim 2.142.0, Docling Core 2.104.0, Docling Parse 7.23.0, python-docx 1.2.0, pypdfium2 5.14.0, pdfminer.six 20260107, pdfplumber 0.11.10, Magika 1.0.3, and ONNX Runtime 1.31.0.

MarkItDown's package imports Magika, and constructing the generic `MarkItDown` object runs Magika's local ONNX classifier when it sniffs a stream, even if the extension is known. Relay instead calls MarkItDown's exported `PdfConverter` and `DocxConverter` with an in-memory `BytesIO` and explicit `StreamInfo`; it never constructs `MarkItDown` or calls `convert_uri`. A worker test makes the generic constructor raise if invoked while exercising the explicit converter. The package closure still includes Magika, ONNX Runtime, and Magika's bundled `model.onnx` file, so the complete dependency tree is not model-free. No separate HF layout/OCR/VLM weights are installed or fetched. The comparator sets `ORT_DISABLE_TELEMETRY=1` before importing MarkItDown/Magika and calls ONNX Runtime's Python `disable_telemetry_events()` API if available; the optional commands and CI also set the environment variable before Python starts. ONNX Runtime documents that the pre-initialization variable prevents its 1DS uploader, events, and persistent device identifier from being created; its Python API can suppress future events, but an initialization event may precede the API call. These controls do not remove ONNX Runtime or the bundled Magika file.

Docling Slim is installed with only the PDF and DOCX format extras, not `models-local`, `standard`, or `all`. Native PDF sets `enable_remote_services=False` and `allow_external_plugins=False`, and selects the model-free native pipeline explicitly. The standard Docling PDF pipeline is not used.

## Verification and measured results

Run the optional checks inside a task-local Python 3.12 environment:

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements-documents.txt
PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -S -m unittest discover -s tests -q
ORT_DISABLE_TELEMETRY=1 RELAY_DOCUMENT_INTEGRATION=1 .venv/bin/python -m unittest discover -s tests -p 'test_document_conversion*.py' -v
ORT_DISABLE_TELEMETRY=1 RELAY_DOCUMENT_INTEGRATION=1 .venv/bin/python -m unittest discover -s tests -p test_document_acceptance.py -v
ORT_DISABLE_TELEMETRY=1 .venv/bin/python EVALS/benchmark_documents.py
```

The benchmark verifies fixture hashes before conversion and prints no document text. On the controller-verified 16 GiB Apple M2 Pro, one cold and one warm run per isolated case recovered all expected literal claims. Native PDF and DOCX returned `converted` with exact locations; all three flattened comparators recovered text, returned `needs_review`, exposed no source locators, and could not be staged.

| Case | Claims recovered | Source locations | Cold / warm seconds | Per-case process peak RSS |
|---|---:|---|---:|---:|
| Native PDF, two pages | 3/3 | page numbers correct | 0.944 / 0.003 | 149 MiB |
| Native Unicode DOCX | 5/5 | paragraph numbers correct | 0.043 / 0.006 | 55 MiB |
| Native duplicate DOCX | 2/2 | separate paragraphs 2 and 3 | 0.043 / 0.006 | 55 MiB |
| MarkItDown PDF | 3/3 | unavailable | 0.421 / 0.006 | 122 MiB |
| MarkItDown DOCX | 5/5 | unavailable | 0.566 / 0.175 | 150 MiB |
| Docling DOCX | 5/5 | unavailable | 0.992 / 0.018 | 166 MiB |

Cold time includes lazy converter imports; warm time reuses Python module imports but constructs a new converter. Peak RSS is the process high-water mark across both runs. This is one small synthetic corpus and one host run, not a performance ranking or target-hardware guarantee.

The mandatory integration tests patch Python socket connect/name-resolution calls and use empty task-local HF/Torch/XDG cache directories with offline flags. No guarded Python socket attempt occurred. This is a test guard, not an OS sandbox; native extensions could use lower-level networking outside the patched Python methods. ONNX Runtime's own telemetry API/env setting is disabled before process startup. Do not claim hostile parser isolation or complete network security from the Python socket guard alone.

## Narrow follow-up

Before any real import, Relay still needs a genuine macOS file-selection/consent boundary, visible review UI with page/paragraph location, encrypted local storage, explicit rejection and revocation UX, and stronger isolation for native parsers. A real-file benchmark must be separately authorized and must never place private source bytes, extracted text, names, or paths in Git, CI, logs, or the benchmark report.

## Upstream sources

- [MarkItDown 0.1.9 package metadata](https://pypi.org/project/markitdown/0.1.9/), [package configuration](https://github.com/microsoft/markitdown/blob/v0.1.9/packages/markitdown/pyproject.toml), [generic API and Magika usage](https://github.com/microsoft/markitdown/blob/v0.1.9/packages/markitdown/src/markitdown/_markitdown.py), [PDF converter](https://github.com/microsoft/markitdown/blob/v0.1.9/packages/markitdown/src/markitdown/converters/_pdf_converter.py), [DOCX converter](https://github.com/microsoft/markitdown/blob/v0.1.9/packages/markitdown/src/markitdown/converters/_docx_converter.py).
- [Docling Slim 2.142.0 package and provenance](https://pypi.org/project/docling-slim/), [minimal extras](https://github.com/docling-project/docling/blob/main/packages/docling-slim/README.md), [model-free native PDF pipeline](https://github.com/docling-project/docling/blob/main/docling/pipeline/native_pdf_pipeline.py), [PDF and DOCX converter options](https://github.com/docling-project/docling/blob/main/docling/document_converter.py), [Word backend pagination behavior](https://github.com/docling-project/docling/blob/main/docling/backend/msword_backend.py).
- [python-docx 1.2.0](https://pypi.org/project/python-docx/1.2.0/) and [source repository](https://github.com/python-openxml/python-docx).
- [ONNX Runtime telemetry and disable options](https://github.com/microsoft/onnxruntime/blob/main/docs/Privacy.md), [Python telemetry API](https://onnxruntime.ai/docs/api/python/api_summary.html#telemetry-events).
