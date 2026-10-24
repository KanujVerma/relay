"""Unverified résumé structure. Exact slices, no model or ownership inference."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
import json
import re
import unicodedata
from uuid import uuid4

from .personal_brain import BrainError
from .generated_answer import strict_json

CLAIM_KINDS = frozenset(('contribution', 'education', 'employment', 'project',
                         'listed_skill', 'certification', 'summary'))
SECTIONS = frozenset(('education', 'experience', 'projects', 'skills',
                      'certifications', 'summary', 'other'))
FIELD_KINDS = frozenset(('section_heading', 'employer', 'title', 'institution',
                         'credential', 'project', 'date', 'category', 'issuer', 'gpa', 'status'))
_HEADINGS = {'work experience': 'experience', 'work history': 'experience',
             'technical skills': 'skills', 'technologies': 'skills',
             **{s: s for s in SECTIONS if s != 'other'}}
_DEGREE = re.compile(r'\b(?:b\.?s\.?c?\.?|m\.?s\.?c?\.?|bachelor|master|associate|ph\.?d|doctor|diploma)\b', re.I)
_BULLET = re.compile(r'^(?:[-*•]\s+|\d+[.)]\s+)')
_INSTRUCTION = re.compile(r'ignore (?:all |the |your )?(?:previous |prior )?instructions|(?:system|developer|assistant)\s*:|mark (?:all|every) (?:claim|fact|record)s? (?:as )?(?:approved|verified)|bypass (?:the )?(?:review|approval|verification|consent)', re.I)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False, allow_nan=False)


def digest(value):
    return sha256(canonical(value).encode('utf-8')).hexdigest()


def _text(value, characters, size):
    if (not isinstance(value, str) or not value.strip() or len(value) > characters or
            any(unicodedata.category(c) in ('Cc', 'Cf', 'Cs', 'Zl', 'Zp') for c in value)):
        raise BrainError('Invalid résumé text field.')
    if len(value.encode('utf-8')) > size:
        raise BrainError('Résumé text exceeds its byte budget.')


@dataclass(frozen=True)
class LocatedField:
    kind: str
    text: str
    sha256: str
    span_start: int
    span_end: int
    locator: str

    def validate(self):
        _text(self.text, 160, 512)
        if (self.kind not in FIELD_KINDS or type(self.span_start) is not int or
                type(self.span_end) is not int or not 0 <= self.span_start < self.span_end <= 30_000 or
                self.span_end-self.span_start != len(self.text) or
                self.sha256 != sha256(self.text.encode()).hexdigest() or
                not isinstance(self.locator, str) or len(self.locator) > 80 or
                re.fullmatch(r'(?:text:line|pdf:page|docx:paragraph):[1-9][0-9]*', self.locator) is None):
            raise BrainError('Invalid résumé source field.')


@dataclass(frozen=True)
class ResumeContext:
    section: str
    entry_id: str
    fields: tuple[LocatedField, ...]

    def validate(self):
        if (self.section not in SECTIONS or not isinstance(self.entry_id, str) or
                re.fullmatch(r'[0-9a-f]{32}', self.entry_id) is None or
                not isinstance(self.fields, tuple) or len(self.fields) > 6 or
                not all(isinstance(f, LocatedField) for f in self.fields) or
                len({f.kind for f in self.fields}) != len(self.fields)):
            raise BrainError('Invalid résumé entry context.')
        for field in self.fields:
            field.validate()


def decode_context(raw):
    try:
        value = strict_json(raw, max_bytes=12*1024)
        if not isinstance(value, dict) or set(value) != {'section', 'entry_id', 'fields'} or not isinstance(value['fields'], list):
            raise ValueError
        fields = []
        for field in value['fields']:
            if not isinstance(field, dict) or set(field) != {'kind', 'text', 'sha256', 'span_start', 'span_end', 'locator'}:
                raise ValueError
            fields.append(LocatedField(**field))
        result = ResumeContext(value['section'], value['entry_id'], tuple(fields))
        result.validate()
        if canonical(asdict(result)) != raw:
            raise ValueError
        return result
    except (ValueError, TypeError, KeyError):
        raise BrainError('Résumé context is unavailable.') from None


@dataclass(frozen=True)
class StructuredCandidate:
    claim_kind: str
    snippet: str
    span_start: int
    span_end: int
    actor_hint: str
    context: ResumeContext
    locator: str


@dataclass(frozen=True)
class StructuredExtraction:
    candidates: tuple[StructuredCandidate, ...]
    unclassified_lines: int
    codes: tuple[str, ...]

    def coverage(self):
        return {'version': 2, 'unclassified_lines': self.unclassified_lines, 'codes': list(self.codes)}


def extract_resume_structure(text, locator):
    """Return None for the legacy unsectioned path; suggestions never approve.

    `locator(start,end)` is the preparation owner's exact source-segment check.
    Header order is only a visible review suggestion, never a verified relation.
    """
    if not isinstance(text, str) or not text.strip() or len(text) > 30_000:
        raise BrainError('Invalid selected résumé text.')
    if not any(line.strip().rstrip(':').casefold() in _HEADINGS for line in text.splitlines()):
        return None
    candidates, codes, unclassified = [], set(), 0
    section, heading, entry, fields, pending = 'other', None, uuid4().hex, [], None

    def retire_pending():
        nonlocal pending, unclassified
        if pending is not None:
            pending = None; unclassified += 1; codes.add('ambiguous_entry')

    def located(kind, start, end):
        field = LocatedField(kind, text[start:end], sha256(text[start:end].encode()).hexdigest(),
                             start, end, locator(start, end))
        field.validate()
        return field

    def candidate(kind, start, end, context_fields):
        snippet = text[start:end]
        _text(snippet, 600, 2400)
        actor = 'unknown'
        if re.match(r'^(?:I\b|I\x27ve\b|I have\b)', snippet, re.I): actor = 'self'
        elif re.match(r'^(?:we\b|our team\b)', snippet, re.I): actor = 'team'
        elif re.match(r'^(?:my teammate|teammate|my cofounder|cofounder)\b', snippet, re.I): actor = 'teammate'
        selected = ([heading] if heading else []) + list(context_fields)
        selected = tuple(f for f in selected if (f.span_start, f.span_end) != (start, end))
        context = ResumeContext(section, entry, selected); context.validate()
        candidates.append(StructuredCandidate(kind, snippet, start, end, actor, context, locator(start, end)))
        if len(candidates) > 64: raise BrainError('Too many résumé review candidates.')

    offset = 0
    for raw in text.splitlines(keepends=True):
        line = raw.rstrip('\r\n'); leading = len(line)-len(line.lstrip())
        body = line.strip(); start = offset+leading; offset += len(raw)
        if not body:
            retire_pending()
            fields, pending, entry = [], None, uuid4().hex
            continue
        label = body.rstrip(':').casefold()
        if label in _HEADINGS:
            retire_pending()
            section = _HEADINGS[label]; heading = located('section_heading', start, start+len(body))
            fields, pending, entry = [], None, uuid4().hex
            continue
        bullet = _BULLET.match(body)
        if bullet:
            start += bullet.end(); body = body[bullet.end():].rstrip()
        if len(body) > 600 or _INSTRUCTION.search(body):
            retire_pending()
            fields, pending, entry = [], None, uuid4().hex
            unclassified += 1; codes.add('line_budget' if len(body) > 600 else 'unclassified_text')
            continue
        if section == 'other':
            # Contact/header lines outside recognized sections never become biography.
            if not re.search(r'@|https?://|\+?\d[\d ()-]{6,}', body):
                unclassified += 1; codes.add('unclassified_text')
            continue
        if bullet and section in ('experience', 'projects') or re.match(r'^(?:I\b|we\b|our team\b|my teammate\b|teammate\b)', body, re.I):
            retire_pending()
            candidate('contribution', start, start+len(body), fields)
            continue
        if section == 'skills':
            colon = body.find(':'); category = []
            value_start = start
            value = body
            if colon >= 0:
                category = [located('category', start, start+colon)]
                value = body[colon+1:]; value_start = start+colon+1
            entry = uuid4().hex
            for part in re.finditer(r'[^,;]+', value):
                piece = part.group(); trimmed = piece.strip()
                if not trimmed: continue
                begin = value_start+part.start()+len(piece)-len(piece.lstrip())
                candidate('listed_skill', begin, begin+len(trimmed), category)
            continue
        pieces = []
        for part in re.finditer(r'[^|]+', body):
            value = part.group(); trimmed = value.strip()
            begin = start+part.start()+len(value)-len(value.lstrip())
            pieces.append((trimmed, begin, begin+len(trimmed)))
        if any(len(p[0]) > 160 or len(p[0].encode()) > 512 for p in pieces) and section != 'summary':
            fields, pending, entry = [], None, uuid4().hex
            unclassified += 1; codes.add('ambiguous_entry'); continue
        if section == 'summary':
            entry = uuid4().hex; candidate('summary', start, start+len(body), []); continue
        if section in ('education', 'experience'):
            credential = section == 'education'
            if len(pieces) == 1 and not (credential and _DEGREE.search(body)):
                retire_pending()
                if re.search(r'[.!?;]', body):
                    fields, pending = [], None; unclassified += 1; codes.add('ambiguous_entry')
                else:
                    fields, pending = [], pieces[0]
                entry = uuid4().hex; continue
            if len(pieces) > 4:
                retire_pending()
                fields, pending, entry = [], None, uuid4().hex
                unclassified += 1; codes.add('ambiguous_entry'); continue
            entry = uuid4().hex
            if pending is not None:
                owner = pending; primary = pieces[0]; extras = pieces[1:]
            elif credential and _DEGREE.search(pieces[0][0]):
                owner = None; primary = pieces[0]; extras = pieces[1:]
            elif len(pieces) >= 2:
                owner, primary, extras = pieces[0], pieces[1], pieces[2:]
            else:
                fields, pending = [], None; unclassified += 1; codes.add('ambiguous_entry'); continue
            fields = [located('institution' if credential else 'employer', *owner[1:])] if owner else []
            fields.append(located('credential' if credential else 'title', *primary[1:]))
            for extra in extras:
                kind = 'gpa' if re.match(r'GPA\b', extra[0], re.I) else 'date'
                fields.append(located(kind, *extra[1:]))
            candidate('education' if credential else 'employment', primary[1], primary[2], fields)
            pending = None; continue
        if section == 'projects':
            if len(pieces) > 2 or (len(pieces) == 1 and re.search(r'[.!?;]', body)):
                fields, pending, entry = [], None, uuid4().hex
                unclassified += 1; codes.add('ambiguous_entry'); continue
            entry = uuid4().hex; fields = [located('project', *pieces[0][1:])]
            if len(pieces) == 2: fields.append(located('date', *pieces[1][1:]))
            candidate('project', pieces[0][1], pieces[0][2], fields); continue
        if section == 'certifications':
            entry = uuid4().hex; fields = []
            if len(pieces) > 3:
                unclassified += 1; codes.add('ambiguous_entry'); continue
            if len(pieces) > 1: fields.append(located('issuer', *pieces[1][1:]))
            if len(pieces) > 2: fields.append(located('status', *pieces[2][1:]))
            candidate('certification', pieces[0][1], pieces[0][2], fields)
    retire_pending()
    return StructuredExtraction(tuple(candidates), unclassified, tuple(sorted(codes)))
