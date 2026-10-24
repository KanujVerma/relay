# Résumé v2 review and personal-answer contract

2026-10-23. Controller-approved increment 1, including the amendments below.
Owner: `/root/compose_context_controls`, GPT-6.1 Sol xhigh.
Isolated branch `feature/resume-coverage-2026-10-23`, base
`db768fdeebb7f084b8619b2eae54d8aabebe0065` / frozen
`build/resume-coverage-foundation-2026-10-23`.

## Goal and first increment

Import typical education, employment, projects, listed skills, qualifications
and contributions; show exact source text and proposed entry associations;
let the existing visible ownership/Save action approve them; restore the same
encrypted profile and answer ordinary background questions from those
approved details. Extracted structure is unverified knowledge until that
action. It never independently establishes a user's skill or responsibility.

Increment 1 supports UTF-8 TXT, selectable single-column native PDF and simple
body-paragraph DOCX. Existing converter limits and rejection of unsupported
relationships/layout remain. Header/table/column support is a separate second
increment with real located fixtures. No network parser, OCR/layout model,
model biography, new dependency or second store is introduced.

The earlier research alternative of expanding action prefixes alone does not
recover entry relationships or background coverage. A source-located context
per exact atomic claim gives explicit approval and revocation boundaries
without imposing a full résumé schema/JS validator on the app.

## Exact source and extraction units

Every primary claim and context field is a separate exact contiguous slice of
the selected derived text. Offsets are zero-based Python Unicode-code-point
offsets, end exclusive. The original selected-byte digest and derived-text
digest retain their existing distinct meanings. New fields never concatenate
disjoint source fragments and claim that they form one source span.

Each slice must fit exactly one accepted converted segment; its locator is
`text:line:N`, `pdf:page:N` or `docx:paragraph:N` (positive N). Repeated equal
text on another line/paragraph remains a different span. The controller
independently validates wire bounds; the helper checks actual slice text,
digest, source consent, segment membership and revision.

The extractor recognizes section headings and bounded adjacent entry headers
as suggestions. A heading/blank entry boundary resets context. An ambiguous
header or unsupported line is not attached to the previous entry. Education
uses an exact credential claim with institution/date context; employment uses
an exact title claim with employer/date context; projects use an exact project
name plus separately staged contribution claims; skills split explicit lists
into exact skill-name slices; certifications/summary preserve exact statements.
Existing attributable contribution sentences remain exact claims. Unknown
ownership always requires the existing explicit actor choice, including when
the text came from a résumé. No name, chronology, seniority or proficiency is
inferred from a heading or filename.

Supported first-increment headers include `Name | Title | Dates`, a name line
followed by `Title | Dates`, project `Name | Dates`, and labelled skills lists.
Plain education/qualification statements are also reviewable without an
inferred institution association. Unclassified lines are counted and visibly
reported as partial extraction; contact details are excluded by policy. This
does not claim universal template recognition.

PDF line order is the existing converter's order, not proof of semantic
reading order. The first increment does not claim to detect every column
template. It proposes only bounded recognizable entry associations, displayed
as unverified context; missing/ambiguous entry boundaries produce partial
coverage with no guessed association. Arbitrary column reading order and new
geometry/nested locators require increment 2. This limitation must stay visible
in the handoff and file-import guidance.

## v2 review card, exact keys

Legacy cards retain their current wire representation. A structured card has
exactly these 15 keys:

```text
schema_version: 2
fact_id, source_id, source_sha256, snippet, snippet_sha256,
span_start, span_end, review_revision, actor_hint, card_fingerprint, locator,
claim_kind, review_context, context_sha256
```

Existing meanings are preserved. `claim_kind` is one of `contribution`,
`education`, `employment`, `project`, `listed_skill`, `certification`, `summary`.
It is a parser suggestion included in what the user approves. `actor_hint`
remains `unknown|self|team|teammate`; an explicit source actor cannot be silently
changed to a different one. Background/skill statements are not automatically
"self". `review_context` has exactly:

```text
section: education|experience|projects|skills|certifications|summary|other
entry_id: opaque 32-character lowercase hex identifier
fields: [LocatedField, ...]  # zero to six, ordered as displayed
```

Each `LocatedField` has exactly six keys:

```text
kind: section_heading|employer|title|institution|credential|project|date|category|issuer|gpa|status
text: exact slice
sha256: SHA256(text UTF-8), lowercase hex64
span_start, span_end: integer offsets
locator: the field's own location
```

Only fields relevant to the displayed claim are attached. Repeated kinds are
rejected; a field equal to the primary span is omitted. Fields from a different
source/revision/entry cannot be attached by a native caller. In the first
increment, corrected associations require reject/re-import or explicit new
text, rather than arbitrary JSON editing by the view/model.

Bounds: selected text 30,000 code points, 64 primary candidates, each primary
600 code points and 2,400 UTF-8 bytes; field text 160 code points and 512 UTF-8
bytes; field locators at most 80 ASCII bytes; context at most six fields.
Integers must be actual integers (never Boolean), within the selected-text
range; digests are lowercase hex64. Text disallows controls, format characters
and embedded line separators. The complete encoded card is at most 12 KiB and
the existing enclosing profile frame remains at most 16 KiB. Exceeding any
bound on a produced card/field rejects the import transaction before
source/candidate publication. An unparsed overlong line produces partial
coverage (`line_budget`) instead of a truncated claim.

`card_fingerprint` for v2 is SHA256 of canonical UTF-8 JSON containing all
displayed card identity/content fields except that fingerprint: sorted object
keys, compact separators, `ensure_ascii=False`, no nonfinite values. Thus it
binds kind, actor hint, primary evidence, ordered context, locators and review
revision. `context_sha256` is the same canonical hash of `review_context`,
issued by the helper on the card. Native code validates its format and returns
that displayed digest, rather than inventing a second cross-language JSON
canonicalization. The helper recomputes it from the actual current context at
approval. Legacy fingerprint computation remains unchanged.

## Review receipt and legacy fail-closed behavior

The native view shows section and all proposed context fields **above the
existing ownership/Save action**, with exact text selectable. These fields
cannot be hidden in a collapsed disclosure before Save. The Save action is
the context acknowledgement; there is no extra checkbox/click for every fact.
As today, this application interaction boundary does not attest that a person
read every character or resist arbitrary code inside the helper.

New v2 decisions use a distinct command with exactly these nine keys:

```text
command: decide_v2
fact_id, fingerprint, decision, actor, claim_key, replaces_fact_id,
card_version: 2
context_sha256
```

`decision` is `approve|reject`. `approve` uses the existing explicit
`self|team|teammate`, canonical claim key and optional exact replacement ID.
For `reject`, actor/key/replacement are JSON null. The context digest must
match the current displayed card for either decision. Unknown/missing keys,
stale/copy-modified card content, version mismatch or context mismatch reject
without mutation. `ProfileController.review/reject` retain their public
signatures and construct this command from the currently displayed v2 DTO.
Only the registered trusted gateway issues the existing opaque confirmation.

The old `decide` command must explicitly reject a v2 candidate, even if an old
Swift decoder ignored the extra card keys and sent its fingerprint. It cannot
approve or downgrade context-dependent content. Old v1 cards use old `decide`.
The new native decoder rejects unknown versions and invalid v2 fields before
showing approval controls. No parser/model-provided Boolean authorizes review.

## Same-store schema 3 and lifecycle

`BrainStore` advances SQLite `user_version` from 2 to 3 in an atomic migration,
after existing foreign-key checks. Add one table:

```text
candidate_resume_context(
  fact_id PRIMARY KEY REFERENCES candidate_fact(id),
  card_version INTEGER NOT NULL CHECK(card_version=2),
  claim_kind TEXT NOT NULL, context_json TEXT NOT NULL,
  context_sha256 TEXT NOT NULL,
  approved_context_sha256 TEXT NULL,
  confirmation_event_id TEXT NULL UNIQUE REFERENCES history_event(id)
)
```

The implementation adds enum/digest/paired-null constraints and validates
canonical JSON and exact field bounds before writes. `context_json` stores
only the bounded displayed fields, not the complete document body. Staging
writes this row with approval fields null in the same source/candidate
transaction. The registered review boundary verifies version/fingerprint/
context, confirms the existing atomic claim and sets matching approved digest
and the actual `fact_confirmed` event in **one transaction**. No direct legacy
`confirm_fact` call can approve a context-dependent candidate without this
matching review context. Rollback leaves neither partial approval nor partial
supersession.

Rejection, revocation, source invalidation and supersession delete the context
row in the same lifecycle transaction; source revocation also preserves the
existing source/body redaction rules. There is no separately live association
after its primary fact loses authority. Existing fact/source history remains
opaque and immutable. Replacing one fact does not implicitly replace another
entry or auto-approve shared context. Existing conflict-key rules are unchanged.

Old confirmed facts gain no inferred metadata and retain their v1 rendering.
Old pending facts remain v1; re-import is required to gain structured context.
New code migrates v1/v2 snapshots through the existing memory-only restore.
Older code rejects schema 3 rather than silently reopening a partial schema;
the original encrypted vault is preserved. No downgrade, new key, vault format
or account-purpose change is part of this feature. The 8 MiB snapshot bound,
32-source bound and actual protected save/Lock/restore semantics remain.

## Provider and deterministic publication

`ContextFact` gains an optional `resume_context` value (default null), privately
constructed from the approved matching context row. `ContextBundle` may append
an intent field with a backward-compatible default. `retrieve(question, role,
project_hint=None, budget=8)` and `validate_current(original_bundle)` signatures
stay unchanged. The original object identity, issuance window and full SQLite
revision checks protect both claim and context. Serialized copies are not
authority. A context row without a matching active approval/event is excluded.

Selection distinguishes education, employment, project, listed skills,
actual tool use, individual contribution, qualifications and overview. Exact
approved entry names participate in ranking. An individual-contribution query
selects only self contribution claims; team/teammate statements retain their
labels for broader project questions. A listed-skill card cannot establish
actual use/proficiency; a tool-use query needs the tool in a reviewed
contribution itself. Job excerpts, screen/OCR/AX, conversation and generated
suggestions never become biography.

The host renders approved values under fixed labels and separators. Contribution
text stays exact with existing Your/Team/Teammate contribution labels. New
background units include exact primary text plus reviewed non-heading fields,
in displayed order, with corresponding self/team/teammate labels. Headings
assist selection but are not asserted as personal facts. Every attached date
or qualification is retained in an emitted unit: Expected is never omitted,
Present never becomes proof of current employment, and a list never becomes
proficiency. There is no calculated tenure, graduation, seniority or generated
summary. A question requiring unsupported award/currentness/proficiency is
honestly withheld, rather than upgraded from adjacent fields.

Existing answer-wire/provenance/card schemas stay unchanged: no more than two
180-byte personal points, lead at most 280 bytes, the same fact IDs/source IDs/
actors/revisions and `host_exact_approved_facts` check. Each point represents
one primary fact and its approved context. No extra facts can hide behind a
single provenance entry. Choose fitting whole units; never truncate a claim or
drop a qualifier to fit. If none fits, retain `personal_detail_budget`. Overview
selects at most two complementary units and says “Start with these confirmed
details”; it does not claim comprehensive résumé coverage. Final original
bundle/native lease checks remain immediately before publication. Unrelated
technical answers keep their existing route.

## Partial extraction status and native presentation

`sources` rows gain optional `resume_coverage` with exact keys `version:2`,
`unclassified_lines` (0...30,000), `codes` (unique list, at most four, from
`unclassified_text|ambiguous_entry|line_budget|unsupported_layout`). It is
stored without raw unmatched text in a preparation-owned
`profile_resume_coverage(source_id PRIMARY KEY REFERENCES source(id), coverage_json TEXT NOT NULL)`
table, created transactionally alongside preparation metadata and deleted on
source revocation.
It is parser coverage, never a percentage of verified background. New native
code displays fixed partial-import guidance when codes are nonempty; old
clients may ignore it. Unsupported converters still reject the whole import
before staging; this object does not bypass converter safety.

The Memory list remains the existing paged approved-fact reader. It can show
the exact primary text; the approval/review surface shows all associations.
No automatic context workspace opening or Model startup change is needed.

## Owned files, dependencies and acceptance

Own new structured extraction/DTO helpers; narrow edits to `resume_candidates`,
`personal_brain`, `profile_preparation`, `profile_bridge`, `personal_context`,
the deterministic personal branch of `session_host`; native `ProfileController`,
`ProfilePreparationView`, pure presentation/DTO files and focused tests. Root
retains Model/outer app, account and Keychain/Vault purpose. No Package/CI/global
contract edits. Reuse existing native Docling and python-docx at recorded pins,
with no code copied or dependency added. The read-only research/pin report is
`work/coordination-2026-10-23/resume-coverage-design-2026-10-23.md`.

Required first-increment evidence uses matching fictional TXT/selectable PDF/
plain DOCX: two employers/projects, institution/credential/Expected date,
listed Python/SQL/C++/R versus actual use, self/team/teammate responsibility,
duplicate headings and repeated identical text. Execute actual converter →
stage → visible DTO/real review command → protected snapshot/restore → actual
provider/SessionHost card. Before approval, no personal evidence is returned.
Assert exact fields/spans/locators/hash survival and no invented skill/date.

Negatives: old `decide` on v2, stale/forged digest, dropped qualifier, cross-entry
or source fields, wrong actor, unknown keys/version, Unicode/duplicate spans,
transaction rollback, conflicting replacement, rejection/revoke/supersede
redaction, schema2 migration and old-schema rejection, copied/stale bundle,
too-long unit and all existing frame/snapshot budgets. Native command tests use
actual synthetic stdio helper with temp encrypted vault/fake key; no real
Keychain/private résumé/account/capture. PDF/DOCX tests invoke the actual pinned
converters offline and must not count dependency skips as format acceptance.

Increment 2 cannot claim table/column/header support until separately approved
nested/geometry locator design and real fixtures pass the same authority gates.

## Controller amendments at approval

- Native offset/length checks use `unicodeScalars`, which matches Python code
  points, never Swift grapheme count or UTF-16 offsets.
- Self-biographical education, employment and listed-skill requests require
  explicitly self-approved units. A role/date attached to a team contribution
  cannot prove the user's employment or proficiency. Team/teammate units appear
  only under their honest labels.
- Literal GPA, completed/Expected education, certification issuer/status and
  C++/R retrieval are required fictional fixtures; numbers remain as written.
- Re-import of an old v1 source creates a new selected source/v2 candidate set;
  already confirmed v1 authority is neither edited nor auto-replaced. Existing
  digest/span/claim-key and explicit replacement rules still apply.
- An unparsed long/ambiguous entry clears dependent associations and reports
  partial coverage. Produced invalid cards roll back. Long-unit and complex
  layout gaps remain explicit under the unchanged two-point publication bound.
