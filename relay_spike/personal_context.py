"""Read-only, bounded retrieval of reviewed personal evidence.

Model strings and serialized copies never issue authority. The publication
host must retain the original bundle and call validate_current immediately
before publishing. A fresh check cannot make arbitrary generated prose true.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
import re
from typing import Protocol

from .personal_brain import BrainError, BrainStore, _required
from .resume_structure import decode_context, digest
from .resume_personal import ApprovedResumeContext, context_words, eligible, mentions_entry, personal_intent, selection_question

MAX_FACTS = 16
MAX_CONTEXT_CHARS = 8_000
_STOP = frozenset("a an the i me my you your we our did do does have has had what how why when where who which can could would should tell about describe explain experience project projects built build work worked used use in on at to for of and or with is was are were it that this those these".split())


@dataclass(frozen=True)
class ContextEvidence:
    source_sha256: str
    snippet_sha256: str
    span_start: int
    span_end: int
    locator: str | None = None


@dataclass(frozen=True)
class ContextFact:
    fact_id: str
    source_id: str
    actor: str
    claim_key: str
    text: str
    evidence: ContextEvidence
    revision: int
    resume_context: ApprovedResumeContext | None = None


@dataclass(frozen=True)
class ContextBundle:
    facts: tuple[ContextFact, ...]
    role: str
    project_hint: str | None
    job_context: str | None
    status: str
    missing_fields: tuple[str, ...]
    revision: str
    intent: str = 'general'


class PersonalContextProvider(Protocol):
    def retrieve(self, question: str, role: str, project_hint: str | None = None,
                 budget: int = 8) -> ContextBundle: ...

    def validate_current(self, bundle: ContextBundle) -> bool: ...


def _terms(text: str) -> set[str]:
    return {term for term in re.findall(r"[\w+#]+", text.casefold())
            if (len(term) > 1 or term in {"c", "r"}) and term not in _STOP}


class BrainContextProvider:
    """Exact/term ranking in memory, with no FTS shadow tables or embeddings.

    Every ledger mutation conservatively expires every issued bundle. The
    bounded issuance window expires old bundles too; callers retrieve again.
    Store/host access must stay serialized on its owning thread.
    """

    def __init__(self, store: BrainStore) -> None:
        self._store = store
        self._issued: list[ContextBundle] = []

    def _revision(self) -> str:
        return sha256(self._store.db.serialize()).hexdigest()

    def _has_table(self, name: str) -> bool:
        return self._store.db.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
        ).fetchone() is not None

    def _source_meta(self, source_id: str) -> str:
        if not self._has_table("profile_source"):
            return ""
        row = self._store.db.execute(
            "SELECT label,role,project_hint FROM profile_source WHERE source_id=?", (source_id,)
        ).fetchone()
        return " ".join(value for value in row if value) if row else ""

    def _locator(self, fact_id: str) -> str | None:
        if not self._has_table("profile_locator"):
            return None
        row = self._store.db.execute(
            "SELECT locator FROM profile_locator WHERE fact_id=?", (fact_id,)
        ).fetchone()
        return row[0] if row else None

    def _job(self, role: str) -> str | None:
        if not self._has_table("profile_job_context"):
            return None
        rows = self._store.db.execute(
            "SELECT j.text FROM profile_job_context j JOIN source s ON s.id=j.source_id "
            "JOIN profile_source p ON p.source_id=j.source_id "
            "WHERE s.revoked_at IS NULL AND s.consent_scope='personal_brain' AND p.role=? "
            "AND j.text IS NOT NULL AND j.confirmed_at IS NOT NULL ORDER BY j.rowid DESC LIMIT 1", (role,)
        ).fetchone()
        return rows[0] if rows else None

    def retrieve(self, question: str, role: str, project_hint: str | None = None,
                 budget: int = 8) -> ContextBundle:
        question = _required(question, "question", limit=4_000)
        role = _required(role, "role", limit=160)
        if project_hint is not None:
            project_hint = _required(project_hint, "project hint", limit=200)
        if type(budget) is not int or not 1 <= budget <= MAX_FACTS:
            raise BrainError("Invalid context budget.")
        revision = self._revision()
        selection = selection_question(question)
        intent = personal_intent(selection)
        question_terms = _terms(selection)
        project_terms = _terms(project_hint or "")
        overview = re.fullmatch(
            r"(?:tell me about yourself|(?:please )?walk me through your (?:resume|résumé|background)|"
            r"(?:give me |an? )?(?:overview|summary) of your (?:experience|background|projects))\s*[.!?]*",
            question.casefold().strip()) is not None
        ranked: list[tuple[int, ContextFact]] = []
        named_entries, named_terms, identity_terms, named_aliases = set(), set(), set(), set()
        missing: set[str] = set()
        conflict = False
        for claim in self._store.verified_claims():
            row = self._store.db.execute(
                "SELECT e.*,s.checksum FROM candidate_evidence e "
                "JOIN source s ON s.id=e.source_id WHERE e.fact_id=?", (claim.fact_id,)
            ).fetchone()
            if row is None:
                missing.add("reviewed_source_spans")
                continue
            if (row["source_id"] != claim.source_id or row["source_sha256"] != row["checksum"]
                    or sha256(claim.claim_text.encode()).hexdigest() != row["snippet_sha256"]
                    or row["span_end"] - row["span_start"] != len(claim.claim_text)):
                missing.add("valid_source_evidence")
                continue
            structured = self._store.db.execute(
                'SELECT r.*,v.confirmation_event_id AS verified_event,h.action,h.fact_id AS event_fact '
                'FROM candidate_resume_context r LEFT JOIN verified_fact v ON v.fact_id=r.fact_id '
                'LEFT JOIN history_event h ON h.id=r.confirmation_event_id WHERE r.fact_id=?', (claim.fact_id,)).fetchone()
            resume = None
            if structured is not None:
                try:
                    context = decode_context(structured['context_json'])
                    if (structured['approved_context_sha256'] != structured['context_sha256'] or
                            digest(asdict(context)) != structured['context_sha256'] or
                            structured['confirmation_event_id'] != structured['verified_event'] or
                            structured['action'] != 'fact_confirmed' or structured['event_fact'] != claim.fact_id):
                        raise BrainError('Reviewed résumé context is unavailable.')
                    resume = ApprovedResumeContext(structured['claim_kind'], context)
                except BrainError:
                    missing.add('reviewed_entry_context'); continue
            evidence = ContextEvidence(row['source_sha256'], row['snippet_sha256'],
                                       row['span_start'], row['span_end'], self._locator(claim.fact_id))
            fact = ContextFact(claim.fact_id, claim.source_id, claim.actor, claim.claim_key,
                               claim.claim_text, evidence, row['review_revision'], resume)
            if resume:
                anchor_kinds = {'employer','project'}
                if intent == 'education': anchor_kinds = {'institution'}
                elif intent == 'employment': anchor_kinds = {'employer'}
                elif intent == 'certification': anchor_kinds = {'issuer'}
                elif intent == 'listed_skill': anchor_kinds = set()
                elif intent == 'actual_tool_use' and not re.search(r'\b(?:at|on|from)\b', selection, re.I): anchor_kinds = set()
                for field in resume.context.fields:
                    if field.kind not in anchor_kinds: continue
                    identity_terms.update(_terms(field.text))
                    if mentions_entry(selection, field.text):
                        named_entries.add(resume.context.entry_id); named_terms.update(_terms(field.text))
                        named_aliases.add(field.text)
            if not eligible(fact, intent): continue
            haystack = _terms(claim.claim_text + ' ' + claim.claim_key + ' ' +
                              self._source_meta(claim.source_id) + (' '+context_words(resume) if resume else ''))
            if project_terms and not project_terms.intersection(haystack):
                continue
            overlap = len(question_terms.intersection(haystack))
            if resume and intent == 'listed_skill':
                focus = question_terms - {'listed','skills','skill','languages','language',
                                          'technologies','list','listed'}
                if focus and not focus.intersection(_terms(fact.text)): continue
            if not overlap and not project_terms and not overview and not (resume and intent != 'general'):
                continue
            # A pending alternative under an existing canonical key is an
            # unresolved contradiction, never a second approved claim.
            pending = self._store.db.execute(
                "SELECT c.claim_text FROM candidate_fact c JOIN source s ON s.id=c.source_id "
                "WHERE c.state='candidate' AND c.claim_key=? AND s.revoked_at IS NULL "
                "AND s.consent_scope='personal_brain'", (claim.claim_key,)
            ).fetchall()
            if any(r[0] and r[0].strip().casefold() != claim.claim_text.strip().casefold()
                   for r in pending):
                conflict = True
                missing.add("resolve_conflicting_facts")
                continue
            score = overlap * 10 + len(project_terms.intersection(haystack)) * 20
            score += len(_terms(role).intersection(haystack))
            ranked.append((score, fact))
        if named_entries:
            ranked = [(score, fact) for score, fact in ranked if
                (fact.resume_context is not None and fact.resume_context.context.entry_id in named_entries) or
                (fact.resume_context is None and any(mentions_entry(fact.text, name) for name in named_aliases))]
        elif re.search(r'\b(?:at|on|from)\b', selection, re.I) and question_terms.intersection(identity_terms):
            # A partial/shared entry token is ambiguous; it is not permission
            # to include every employer/project sharing that token.
            ranked = [(score, fact) for score, fact in ranked if fact.resume_context is None]
        if intent in ('individual_contribution', 'actual_tool_use'):
            focus = question_terms - named_terms - {'personally','individual','contribution','implement',
                'implemented','design','designed','write','wrote','actually','tools','tool'}
            def has_focus(fact):
                if fact.resume_context is None: return True
                target = _terms(fact.text)
                if intent != 'actual_tool_use': target.update(_terms(context_words(fact.resume_context)))
                return focus.issubset(target)
            ranked = [(score, fact) for score, fact in ranked if has_focus(fact)]
        ranked.sort(key=lambda pair: (-pair[0], pair[1].claim_key, pair[1].fact_id))
        selected: list[ContextFact] = []
        size = 0
        job = self._job(role)
        size += len(job or "")
        for _, fact in ranked:
            if len(selected) == budget:
                break
            field_size = sum(len(field.text) for field in fact.resume_context.context.fields) if fact.resume_context else 0
            unit_size = len(fact.text)+field_size
            if size + unit_size <= MAX_CONTEXT_CHARS:
                selected.append(fact)
                size += unit_size
        status = "ready"
        if conflict:
            status = "conflict"
        elif not selected:
            revoked = self._store.db.execute(
                "SELECT 1 FROM history_event WHERE action IN ('source_revoked','fact_revoked') LIMIT 1"
            ).fetchone()
            status = "revoked" if revoked and not self._store.verified_claims() else "no_evidence"
        if not selected:
            missing.add("verified_personal_facts")
        if job is None:
            missing.add("job_context")
        bundle = ContextBundle(tuple(selected), role, project_hint, job, status,
                               tuple(sorted(missing)), revision, intent)
        self._issued.append(bundle)
        del self._issued[:-32]
        return bundle

    def validate_current(self, bundle: ContextBundle) -> bool:
        if not any(bundle is issued for issued in self._issued):
            return False
        try:
            return bundle.revision == self._revision()
        except Exception:
            return False
