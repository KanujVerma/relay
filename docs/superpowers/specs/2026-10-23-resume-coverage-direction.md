# Résumé and background coverage: research/design checkpoint

2026-10-23. `/root/compose_context_controls`, GPT-6.1 Sol xhigh. Read-only research in `work/relay-resume-coverage`, branch `research/resume-coverage-2026-10-23`, exact root `db768fdeebb7f084b8619b2eae54d8aabebe0065`. No implementation or schema edits. Model/UI/Vault/key namespace are outside this lane; account worker owns the key-purpose seam. Root approves interfaces before implementation. Current encrypted import/review/session reuse already exists and should be reused.

## Measured current gaps

`resume_candidates.extract_synthetic_candidates` is the legacy-named parser actually used by production `ProfilePreparation`. It accepts only action-like lines, at most64 candidates/600characters per line from30,000characters. A small fictional TXT probe produced:

| Section | Candidates | Lost information |
|---|---:|---|
| Education |0| institution, degree, dates, GPA |
| Experience |1| company, title, dates; even the “Reduced…” achievement |
| Projects |1| project title/date header |
| Technical skills |0| named language/database/tool lists |
| Certifications / summary |0 /0| declarative qualification/background text |
| Explicit I / Our team controls |1 /1| actor hints correctly self/team, still unverified |

After explicitly approving the Harbor Monitor project bullet, “What did you personally do on Harbor Monitor?” returns no_evidence; “What did you design in Python?” retrieves the same fact. Project-header association was lost. `personal_context.py` ranks flat lexical overlap plus optional source-wide project hint; a multi-project résumé has no entry-level context. Overview retrieves a bounded list, and `SessionHost._personal` displays only its first two facts. It cannot deliberately cover education/work/projects or distinguish a listed skill from demonstrated use. A reviewed fact over the180-byte personal-point budget causes honest abstention; broadening extraction must not weaken that global bound or truncate qualifiers.

Converters already preserve original/derived digests and exact located text. Native PDF uses Docling NativePdf line cells, with page locations but no semantic reading order/headings/tables. Current DOCX reads only body paragraphs and rejects tables, hyperlinks, secondary text relationships, drawings and unsupported XML instead of silently dropping content. Typical column/table/header résumé templates therefore remain unsupported. Historical converter docs' “future file-picker/storage” paragraph is stale relative to the actual native preparation app; do not mistake it for a missing current picker/vault/review flow.

## Recommended approach

Do not merely whitelist more action verbs. Add a bounded **unverified résumé structure** alongside existing exact candidate spans: section, entry boundary and exact source-located fields (institution/degree; employer/title; project; dates-as-written; listed skills; contribution). These are extraction suggestions, never verified facts. Preserve original text/hashes/locators; classification normalization must not rewrite the evidence. No embeddings, LLM extraction, OCR/layout model, new store or network default is needed for this first step.

Keep each contribution's exact atomic claim separate from its proposed entry context. A useful association such as “this bullet belongs to Cedar Analytics, June–August2023” must be visible and explicitly reviewed, not silently inferred from proximity. Recommended approval seam: optional v2 review context with bounded field spans, bound into the existing card fingerprint/revision; root's small DTO/View companion must show it and return its context acknowledgement with approval. Legacy cards/facts retain their existing path; an old client cannot blindly approve a context-dependent v2 card. Do not overload snippet with unlabelled concatenated text or pretend disjoint source fragments are one exact span.

Persist only approved associations in the same encrypted SQLite snapshot, with source/fact redaction and revision invalidation. No ProfileVault/key namespace change. Reject/revoke/replace must clear dependent context; copied bundles remain non-authority. Suggestions about matching an earlier résumé entry are review aids, not automatic merge/supersession. Existing explicit correction/replace gate remains.

Use intent-aware bounded selection over reviewed facts: education/qualification, employer/role/date, project, listed skills, actual tool use, individual contribution and overview. “Listed Python” does not prove professional Python use or proficiency. Individual-work questions require approved self evidence; team/teammate outcomes keep their labels. Dates remain as written: Expected2027 is not graduation; Present is not proof of today's employment; do not invent durations, awarded degrees or seniority. Role/job-description requirements remain task context, never biography.

Personal output remains host-owned and deterministic. Keep current contribution rendering. For new structured background, render only the exact approved field values and explicitly reviewed relationships under concise labels, with existing fact/source provenance and currentness checks. This is a narrow extension to the exact-personal-fact renderer, not permission for model-generated biography. Preserve card budgets; select a fitting reviewed unit or honestly withhold, never trim away a qualifier. A later long-fact detail design can be separately reviewed.

## Delivery alternatives and boundaries

1. **More line prefixes only:** small patch, but still loses education/entry associations and cannot answer ordinary résumé questions reliably. Not recommended as the claimed feature.
2. **Recommended:** source-located structure + visible context review + reviewed selection/rendering, first using TXT, single-column selectable PDF and plain-paragraph DOCX. This is a real useful coverage increment with explicit limits.
3. Full model/LLM résumé parsing adds weight/account/provenance problems without replacing review authority; not justified for this slice.

Do not relax converter rejection to claim template coverage. A separate second increment may use existing python-docx ordered paragraph/table traversal and Docling provenance boxes to support bounded, unambiguous table cells/columns, with exact nested locators and no silently omitted header disclaimer. Keep unsupported/ambiguous layouts explicit until that evidence is tested. No new dependency is proposed.

## Reuse inspected at immutable pins

- **Docling Slim2.142.0**, commit `6aaf87ebd99b8c7d3699d90f7aba372555d0140e`, MIT: existing `NativePdfPipeline`/options and upstream `test_native_pdf_pipeline.py`. Source states model-free native cells do not establish headings, tables or reading order; tests verify line cells, page/bbox provenance and page ordering. Reuse the existing invoked API, optionally retain its bbox knowledge; do not silently switch to Standard/layout/OCR pipeline. [Source](https://github.com/docling-project/docling/blob/6aaf87ebd99b8c7d3699d90f7aba372555d0140e/docling/pipeline/native_pdf_pipeline.py), [tests](https://github.com/docling-project/docling/blob/6aaf87ebd99b8c7d3699d90f7aba372555d0140e/tests/test_native_pdf_pipeline.py), [license](https://github.com/docling-project/docling/blob/6aaf87ebd99b8c7d3699d90f7aba372555d0140e/LICENSE).
- **python-docx1.2.0**, annotated tag dereferenced to `e45454602b53e8e572b179ccf1c91093ec9f4ed7`, MIT: `BlockItemContainer.iter_inner_content()` yields Paragraph/Table in document order. Its real fixture test checks paragraph/table/paragraph order; this is a useful later table traversal port, not proof that arbitrary headers/merges are safe. [Source](https://github.com/python-openxml/python-docx/blob/e45454602b53e8e572b179ccf1c91093ec9f4ed7/src/docx/blkcntnr.py), [tests](https://github.com/python-openxml/python-docx/blob/e45454602b53e8e572b179ccf1c91093ec9f4ed7/tests/test_blkcntnr.py), [license](https://github.com/python-openxml/python-docx/blob/e45454602b53e8e572b179ccf1c91093ec9f4ed7/LICENSE).
- **JSON Resume schema v1.0.0**, `7095651fbbb593d2c5dc2db3095412b170d74d2e`: taxonomy/reference only for work/education/projects/skills/date fields; no JS validator or source copied. Its LICENSE.md says MIT while package.json declares BSD-2-Clause, so record that inconsistency rather than falsely call its package unambiguously MIT. The permissive taxonomy is useful; a full schema dependency is unnecessary. [Schema](https://github.com/jsonresume/resume-schema/blob/7095651fbbb593d2c5dc2db3095412b170d74d2e/schema.json), [license](https://github.com/jsonresume/resume-schema/blob/7095651fbbb593d2c5dc2db3095412b170d74d2e/LICENSE.md), [package](https://github.com/jsonresume/resume-schema/blob/7095651fbbb593d2c5dc2db3095412b170d74d2e/package.json).

Existing optional document pins stay unchanged. Upstream code/tests were read; no new code copied, package installed, parser model downloaded or private file opened during research.

## Synthetic acceptance proposal

Generate fictional matching TXT/selectable PDF/simple DOCX with education (completed vs Expected), two employers/titles/date ranges, two projects, own vs team/teammate bullets, listed-vs-used skills (Python/SQL/C++/R), certification and duplicate headings. Exact original/derived hashes and every approved field locator must survive real converter→stage→review→snapshot→restore→provider→personal-host publication. Before review, nothing is retrievable as personal evidence. No direct DB approval shortcut.

Positive questions: education/degree/role/date/project overview; “what did you personally implement?”; “which tools did you actually use?” only when the source supports use. Negatives: other person's work, unknown proficiency, unawarded/expected degree, stale Present/duration inference, job requirements as experience, changed/revoked source, stale/forged context receipt, context mismatch, Unicode/duplicate spans, >bounds and too-long personal points. Table/column/header PDFs/DOCX are explicit unsupported/ambiguity cases in increment1; increment2 needs real nested-locator positives plus existing malicious relationship/omission negatives. No real account, uploads or user résumé.

## Separate approved query-classifier correction

Root observed “How does that queue work?” withheld personal_context_missing despite a technical basis. Exact trace: `_ATTRIBUTION` interprets capitalized How as `_NAMED_SUBJECT` plus does as `_HISTORY_ACTION`; What does/What did share this problem. Python/PostgreSQL process questions additionally match `does <ProperName> work/do` in `_HISTORY_REQUEST`.

Root approved a separate narrow query-only correction before résumé schema work: leading interrogative+aux is grammar; genuine personal/your/past/contribution/passive evidence requirements remain, generated-output attribution guard unchanged. Include technical proper-name positives and actual typed technical-basis SessionHost answer evidence. No names whitelist. Proposed present-process-vs-attribution tradeoff has been sent to root: How does Morgan implement remains personal; an ambiguous How does Morgan work may receive neutral generic process coaching, never permission to invent Morgan's history. Await that exact tradeoff response before implementation shape is frozen.

Resume-schema implementation remains unapproved. Needed root seams: backend structure/evidence metadata and migration ownership; required visible review-context DTO/View acknowledgement; bounded provider/host personal-field rendering contract; converter expansion as a separately tested increment. Model/UI/Vault/key-purpose ownership remains outside this worker.

## Controller decisions and current work

The controller approved the source-located structure/reviewed-association direction and intent-aware bounded personal rendering. The worker may own the backend and native ProfileController/DTO/ProfilePreparationView end to end, with actual converters/tests. Root retains SessionApplicationModel/outer app/account; account owns the Keychain purpose seam. Acknowledgement should ride the existing visible approve/actor action after entry context is displayed, with no extra per-fact confirmation by default. Before schema implementation, freeze exact bounded v2 card/receipt/review-command/migration/rendering contracts for root approval. The high-level direction is approved, while those exact schemas remain a separate checkpoint.

Query-only mechanism correction is approved separately. Present-tense mechanism questions may reach generic coaching/clarification even with an ambiguous proper name, without granting biographical authority. Actual you/your/résumé/past/team/passive and mixed-tail evidence guards remain, and generated-output attribution is unchanged. Include Python/PostgreSQL/React and broader implement/execute mechanism positives, historical/personal negatives and actual typed-basis model/unsupported-output tests; no names registry or technology whitelist. This supersedes the earlier pending Morgan-present-form tradeoff in the research text.

The query fix uses feature isolation fix/query-mechanism-grammar-2026-10-23 from exactdb768. Broader résumé implementation will use its own feature lane from build/resume-coverage-foundation-2026-10-23 at the same exactdb768, declaring the query correction as a dependency if needed. No schema coverage is claimed before implementation/review.
