"""Exact reviewed résumé selection/rendering, never generated biography."""
from dataclasses import dataclass
import re
import unicodedata

from .generated_answer import CardError, bounded_text
from .resume_structure import ResumeContext


@dataclass(frozen=True)
class ApprovedResumeContext:
    claim_kind: str
    context: ResumeContext


def selection_question(question):
    # Host-owned framing separates current typed intent from retained semantic
    # ancestry. This affects ranking only; personal admission still scans the
    # complete request and the original approved bundle remains the authority.
    current = re.match(r'^Current user question \(verbatim\): ([^\n]+)\nChosen earlier questions \(context only\):\n', question)
    if current and personal_intent(current[1]) != 'general': return current[1]
    return question


def personal_intent(question):
    text = question.casefold()
    if re.search(r'\b(?:proficien\w*|expert\w*|how many years|how long|currently|current employer|graduated|earned (?:a |your )?degree)\b', text):
        return 'unsupported'
    if re.search(r'\b(?:educat\w*|degree|gpa|university|college|school)\b', text): return 'education'
    if re.search(r'\b(?:certificat\w*|credential\w*|qualificat\w*)\b', text): return 'certification'
    if re.search(r'\b(?:employ\w*|job title|where.{0,30}work|your role at)\b', text): return 'employment'
    if re.search(r'\b(?:listed skills|skills|languages|technologies)\b', text): return 'listed_skill'
    if re.search(r'\b(?:personally|individual contribution|your contribution|what did you (?:do|build|implement|design|write))\b', text): return 'individual_contribution'
    if re.search(r'\b(?:actually use|did you use|have you used|tools did you)\b', text): return 'actual_tool_use'
    if re.search(r'tell me about yourself|walk me through your (?:resume|résumé|background)|(?:overview|summary) of your', text): return 'overview'
    if re.search(r'\bprojects?\b', text): return 'project'
    return 'general'


def eligible(fact, intent):
    structured = fact.resume_context
    if intent == 'unsupported': return structured is None and fact.actor == 'self'
    if intent in ('education', 'employment', 'listed_skill', 'certification', 'overview',
                  'individual_contribution', 'actual_tool_use') and fact.actor != 'self': return False
    if structured is None:
        return True  # Legacy exact claims retain their reviewed evidence path.
    kind = structured.claim_kind
    if intent in ('education', 'employment', 'listed_skill', 'certification'): return kind == intent
    if intent == 'individual_contribution': return kind == 'contribution'
    if intent == 'actual_tool_use':
        return kind == 'contribution' and re.search(r'\b(?:using|used|with|in)\b', fact.text, re.I) is not None
    if intent == 'project': return kind in ('project', 'contribution')
    return True


def context_words(context):
    return ' '.join(field.text for field in context.context.fields if field.kind != 'section_heading')


def normalize_entry(value):
    return ' '.join(unicodedata.normalize('NFKC', value).casefold().split())


def mentions_entry(question, name):
    # Names come only from reviewed entry fields, never a person/technology
    # registry. Lookup normalization does not rewrite stored source evidence.
    return re.search(r'(?<!\w)'+re.escape(normalize_entry(name))+r'(?!\w)', normalize_entry(question)) is not None


def resolve_entry_mentions(question, aliases):
    """Resolve maximal full-name occurrences; overlapping/equal owners abstain.

    A separate short-name occurrence remains valid in “Harbor and Harbor Labs”.
    An embedded Harbor inside Harbor Labs does not create a second target.
    """
    owners = {}
    for entry_id, name in aliases:
        owners.setdefault(normalize_entry(name), set()).add(entry_id)
    question = normalize_entry(question)
    matches = {(match.start(), match.end(), name) for name in owners
        for match in re.finditer(r'(?<!\w)'+re.escape(name)+r'(?!\w)', question)}
    maximal = [item for item in matches if not any(
        other[0] <= item[0] and item[1] <= other[1] and other[1]-other[0] > item[1]-item[0]
        for other in matches)]
    ambiguous = any(len(owners[item[2]]) > 1 for item in maximal)
    ambiguous |= any(left != right and left[0] < right[1] and right[0] < left[1]
                     for left in maximal for right in maximal)
    names = {item[2] for item in maximal}
    return {owner for name in names for owner in owners[name]}, names, ambiguous


def inferred_personal_presentation(question, adjustments, *, explicit_guide=False):
    """Fixed organization only; current wording/length choices always win."""
    if explicit_guide or re.search(r"\b(?:short(?:er)?|long(?:er)?|detail(?:ed)?|brief(?:ly)?|concise|quick(?:ly)?|steps?|bullets?|wording|phrase|tone|examples?|sentences?|paragraphs?|exactly|verbatim|only|overview|formal|informal|casual|star)\b",question,re.I):
        return None
    return next((value for value in adjustments if value in ('concise_lead','stepwise')),None)


def render_personal(bundle, *, presentation=None):
    """Choose complete fitting units, retaining every reviewed qualifier."""
    facts, points, kinds = [], [], set()
    labels = {'self': 'Your contribution', 'team': 'Team contribution', 'teammate': 'Teammate contribution'}
    background = {'education': 'Education', 'employment': 'Employment', 'project': 'Project',
                  'listed_skill': 'Listed skill', 'certification': 'Certification', 'summary': 'Background'}
    for fact in bundle.facts:
        if not eligible(fact, bundle.intent): continue
        context = fact.resume_context
        kind = context.claim_kind if context else 'contribution'
        if bundle.intent == 'overview' and kind in kinds: continue
        if kind == 'contribution': label = labels[fact.actor]
        else:
            label = background[kind]
            if fact.actor != 'self': label = ('Team ' if fact.actor == 'team' else 'Teammate ')+label.lower()
        values = [fact.text]
        if context:
            values.extend(field.text for field in context.context.fields if field.kind != 'section_heading')
        point = label+': '+'; '.join(values)
        try: bounded_text(point, 180)
        except CardError: continue
        facts.append(fact); points.append(point); kinds.add(kind)
        if len(points) == 2: break
    if not points: raise CardError('personal_detail_budget')
    lead = 'Start with these confirmed details.' if bundle.intent == 'overview' else 'Use these confirmed details; add only what you can personally support.'
    if presentation == 'concise_lead':
        lead=points[0];points=points[1:]
    elif presentation == 'stepwise':
        lead='First: '+points[0]
        points=[('Then: '+point) if len(('Then: '+point).encode())<=180 else point for point in points[1:]]
    return tuple(facts), {'lead': lead, 'points': points, 'detail': None}
