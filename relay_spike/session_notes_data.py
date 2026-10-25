"""Pure bounded notes DATA validation. No record, source or inference authority.

A parsed projection cannot prove an actual record exists or is complete/current.
Only future owned native readers/admission/receipts may establish those facts.
"""
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import re
import unicodedata
import uuid
from .generated_answer import strict_json, CardError

SOURCE_BYTES=2*1024*1024
TEXT_BYTES=256*1024
DOCUMENT_BYTES=256*1024
OUTPUT_BYTES=8192
U64=2**64-1
I64=2**63-1
GAPS=('sourceUnavailable','sequenceGap','capacity','storageFailure','savingStopped','interrupted','captureFailure','sourceDeleted','invalidObservation','unfinishedSpeech','captureEndUnknown')
STATES=('paused','completed','partial','interrupted')
_SOURCE_SPACE=frozenset('\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')

class NotesDataError(ValueError):
    """Only fixed redacted parser codes; never source/provider diagnostics."""

@dataclass(frozen=True,slots=True,repr=False)
class NotesSelectionData:
    kind:str
    total_saved_rows:int
    included_rows:int
    first_row_id:str
    last_row_id:str

@dataclass(frozen=True,slots=True,repr=False)
class NotesRowData:
    row_id:str
    revision:int
    source:str
    text:str
    text_digest:str

@dataclass(frozen=True,slots=True,repr=False)
class NotesSourceData:
    record_id:str
    record_revision:int
    selection:NotesSelectionData
    record_state:str
    gaps:tuple[str,...]
    rows:tuple[NotesRowData,...]
    raw_bytes:bytes
    source_digest:str

@dataclass(frozen=True,slots=True,repr=False)
class NotesCitationData:
    row_id:str
    quote:str

@dataclass(frozen=True,slots=True,repr=False)
class NotesItemData:
    text:str
    citations:tuple[NotesCitationData,...]

@dataclass(frozen=True,slots=True,repr=False)
class NotesOutputData:
    summary:tuple[NotesItemData,...]
    decisions:tuple[NotesItemData,...]
    next_steps:tuple[NotesItemData,...]
    canonical_bytes:bytes

@dataclass(frozen=True,slots=True,repr=False)
class NotesRowProofData:
    row_id:str
    revision:int
    text_digest:str

@dataclass(frozen=True,slots=True,repr=False)
class NotesGenerationData:
    scope_id:str
    scope_epoch:int
    operation_id:str
    request_id:str
    request_sequence:int
    transfer_id:str
    completed_at:str

@dataclass(frozen=True,slots=True,repr=False)
class NotesDocumentData:
    note_id:str
    note_revision:int
    record_id:str
    source_record_revision:int
    saved_at_record_revision:int
    selection:NotesSelectionData
    source_state:str
    source_gaps:tuple[str,...]
    source_digest:str
    source_rows:tuple[NotesRowProofData,...]
    origin:str
    model_id:str
    prompt_policy:str
    generation:NotesGenerationData
    edited_at:str|None
    notes:NotesOutputData
    canonical_bytes:bytes


def _bad(code='invalid_data'):
    raise NotesDataError(code)

def _json_structure(raw):
    """Bound value allocation before decoding; syntax is still strict_json's job."""
    index=depth=nodes=0;length=len(raw);space=b' \t\r\n'
    while index<length:
        token=raw[index]
        if token in space or token in b',:':
            index+=1;continue
        if token in b'}]':
            depth-=1
            if depth<0:_bad('invalid_json')
            index+=1;continue
        if token==34:
            index+=1
            while index<length and raw[index]!=34:
                index+=2 if raw[index]==92 else 1
            if index>=length:_bad('invalid_json')
            index+=1;following=index
            while following<length and raw[following] in space:following+=1
            if following<length and raw[following]==58:continue
        elif token in b'{[':
            index+=1
        else:
            while index<length and raw[index] not in b' \t\r\n,:{}[]"':index+=1
        nodes+=1
        if depth+1>8 or nodes>8192:_bad('json_structure_budget')
        if token in b'{[':depth+=1

def _json(raw,limit):
    if type(raw) is not bytes or not 0<len(raw)<=limit:_bad('json_budget')
    _json_structure(raw)
    try:value=strict_json(raw,max_bytes=limit)
    except CardError:raise NotesDataError('invalid_json') from None
    pending=[(value,1)];nodes=0
    while pending:
        node,depth=pending.pop();nodes+=1
        if depth>8 or nodes>8192:_bad('json_structure_budget')
        if type(node) is dict:pending.extend((v,depth+1) for v in node.values())
        elif type(node) is list:pending.extend((v,depth+1) for v in node)
    return value

def _exact(value,keys):
    if type(value) is not dict or set(value)!=set(keys):_bad('field_set')
    return value

def _schema(v):
    if type(v) is not int or v!=1:_bad('schema_version')

def _integer(v,low,high):
    if type(v) is not int or not low<=v<=high:_bad('counter')
    return v

def _decimal(v,maximum=U64):
    if type(v) is not str or not 1<=len(v)<=20 or not re.fullmatch('[1-9][0-9]*',v):_bad('counter')
    result=int(v)
    if result>maximum:_bad('counter')
    return result

def _uuid(v):
    if type(v) is not str or len(v)!=36:_bad('uuid')
    try:canonical=str(uuid.UUID(v))
    except ValueError:raise NotesDataError('uuid') from None
    if v!=canonical:_bad('uuid')
    return v

def _hash(v):
    if type(v) is not str or re.fullmatch('[0-9a-f]{64}',v) is None:_bad('digest')
    return v

def _utf8(v,limit):
    if type(v) is not str:_bad('text')
    try:data=v.encode('utf-8')
    except UnicodeError:raise NotesDataError('unicode') from None
    if len(data)>limit:_bad('text_budget')
    return data

def _nonblank(v):return any(c not in _SOURCE_SPACE for c in v)

def _text(v,limit,*,quoted=False,code=False):
    data=_utf8(v,limit)
    if not data or not _nonblank(v) or '\0' in v:_bad('text')
    if not quoted and any(unicodedata.category(c) in ('Cc','Cf','Cs','Zl','Zp') and not (code and c in '\n\t') for c in v):_bad('text_control')
    return v

def _row_id(v):
    if type(v) is not str or not 1<=len(v)<=101:_bad('row_id')
    parts=v.split(':')
    if len(parts)!=5:_bad('row_id')
    _uuid(parts[0]);_decimal(parts[1]);_decimal(parts[3]);_decimal(parts[4])
    if parts[2] not in ('1','2'):_bad('row_id')
    return v,parts[2]

def _gaps(v,state):
    if type(v) is not list or len(v)>len(GAPS) or any(type(g) is not str or g not in GAPS for g in v):_bad('gap')
    if len(set(v))!=len(v) or tuple(v)!=tuple(g for g in GAPS if g in v):_bad('gap')
    if state not in STATES or state=='completed' and v:_bad('record_state')
    return tuple(v)

def _selection(v,ids):
    _exact(v,('kind','totalSavedRows','includedRows','firstRowID','lastRowID'))
    kind=v['kind']
    if kind not in ('full_saved_transcript','explicit_excerpt'):_bad('selection')
    total=_integer(v['totalSavedRows'],1,1024);included=_integer(v['includedRows'],1,total)
    if included!=len(ids) or v['firstRowID']!=ids[0] or v['lastRowID']!=ids[-1]:_bad('selection')
    if kind=='full_saved_transcript' and total!=included:_bad('selection')
    return NotesSelectionData(kind,total,included,ids[0],ids[-1])

def _canonical(value,limit):
    try:data=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
    except (UnicodeError,ValueError,TypeError):raise NotesDataError('invalid_json') from None
    if len(data)>limit:_bad('json_budget')
    return data

def parse_source_payload(raw:bytes)->NotesSourceData:
    value=_exact(_json(raw,SOURCE_BYTES),('schemaVersion','recordID','recordRevision','selection','recordState','gaps','rows'))
    _schema(value['schemaVersion']);record=_uuid(value['recordID']);revision=_decimal(value['recordRevision'],I64)
    state=value['recordState']
    if type(state) is not str:_bad('record_state')
    gaps=_gaps(value['gaps'],state);rows=value['rows']
    if type(rows) is not list or not 1<=len(rows)<=1024:_bad('rows')
    result=[];known=set();size=0
    for row in rows:
        _exact(row,('id','revision','source','text'));identity,code=_row_id(row['id'])
        if identity in known:_bad('row_duplicate')
        known.add(identity)
        if row['revision']!='1' or type(row['revision']) is not str:_bad('row_revision')
        source='microphone' if code=='1' else 'selected_app_audio'
        if row['source']!=source:_bad('row_source')
        text=row['text'];data=_utf8(text,4800)
        if not data or len(text)>1200 or '\0' in text or not _nonblank(text):_bad('source_text')
        size+=len(data)
        if size>TEXT_BYTES:_bad('source_text_budget')
        result.append(NotesRowData(identity,1,source,text,hashlib.sha256(data).hexdigest()))
    ids=tuple(r.row_id for r in result);selection=_selection(value['selection'],ids)
    digest=hashlib.sha256(b'relay.notes.source.v1\n'+raw).hexdigest()
    return NotesSourceData(record,revision,selection,state,gaps,tuple(result),raw,digest)

def _notes(value,source):
    if type(source) is not NotesSourceData:_bad('source_data_required')
    _exact(value,('schemaVersion','summary','decisions','nextSteps'));_schema(value['schemaVersion'])
    by_id={row.row_id:row for row in source.rows};groups=[];total=0
    for name,minimum,maximum in [('summary',1,8),('decisions',0,4),('nextSteps',0,4)]:
        group=value[name]
        if type(group) is not list or not minimum<=len(group)<=maximum:_bad('items')
        total+=len(group);items=[]
        for item in group:
            _exact(item,('text','citations'));text=_text(item['text'],768,code=True);references=item['citations']
            if type(references) is not list or not 1<=len(references)<=3:_bad('citations')
            citations=[];seen=set()
            for citation in references:
                _exact(citation,('rowID','quote'));identity=citation['rowID']
                if type(identity) is not str or identity not in by_id:_bad('citation_row')
                quote=_text(citation['quote'],240,quoted=True)
                if quote.encode() not in by_id[identity].text.encode():_bad('citation_quote')
                key=(identity,quote)
                if key in seen:_bad('citation_duplicate')
                seen.add(key);citations.append(NotesCitationData(identity,quote))
            items.append(NotesItemData(text,tuple(citations)))
        groups.append(tuple(items))
    if total>16:_bad('items')
    return NotesOutputData(*groups,_canonical(value,OUTPUT_BYTES))

def parse_generated_notes(raw:bytes,source:NotesSourceData)->NotesOutputData:
    return _notes(_json(raw,OUTPUT_BYTES),source)

def _timestamp(v):
    if type(v) is not str or re.fullmatch('[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z',v) is None:_bad('timestamp')
    try:datetime(int(v[:4]),int(v[5:7]),int(v[8:10]),int(v[11:13]),int(v[14:16]),int(v[17:19]),int(v[20:23])*1000)
    except ValueError:raise NotesDataError('timestamp') from None
    return v

def parse_notes_document(raw:bytes,source:NotesSourceData)->NotesDocumentData:
    if type(source) is not NotesSourceData:_bad('source_data_required')
    value=_exact(_json(raw,DOCUMENT_BYTES),('schemaVersion','noteID','noteRevision','recordID','sourceRecordRevision','savedAtRecordRevision','selection','sourceState','sourceGaps','sourceDigest','sourceRows','origin','modelID','promptPolicy','generation','editedAt','notes'))
    _schema(value['schemaVersion']);note_id=_uuid(value['noteID']);note_revision=_decimal(value['noteRevision'],I64)
    record=_uuid(value['recordID']);revision=_decimal(value['sourceRecordRevision'],I64);saved=_decimal(value['savedAtRecordRevision'],I64)
    if record!=source.record_id or revision!=source.record_revision or saved<=revision:_bad('source_revision')
    if value['sourceState']!=source.record_state or _gaps(value['sourceGaps'],value['sourceState'])!=source.gaps:_bad('source_state')
    if _hash(value['sourceDigest'])!=source.source_digest:_bad('source_digest')
    selection=_selection(value['selection'],tuple(r.row_id for r in source.rows))
    if selection!=source.selection:_bad('source_selection')
    members=value['sourceRows']
    if type(members) is not list or len(members)!=len(source.rows):_bad('source_membership')
    proofs=[]
    for member,row in zip(members,source.rows):
        _exact(member,('rowID','revision','textDigest'))
        if member['rowID']!=row.row_id or member['revision']!='1' or _hash(member['textDigest'])!=row.text_digest:_bad('source_membership')
        proofs.append(NotesRowProofData(row.row_id,1,row.text_digest))
    origin=value['origin']
    if origin not in ('generated','generated_user_edited'):_bad('origin')
    model=_text(value['modelID'],256)
    if value['promptPolicy']!='notes_source_v1':_bad('prompt_policy')
    g=_exact(value['generation'],('scopeID','scopeEpoch','operationID','requestID','requestSequence','transferID','completedAt'))
    scope=_uuid(g['scopeID']);epoch=_decimal(g['scopeEpoch']);operation=_uuid(g['operationID']);request=_uuid(g['requestID']);transfer=_uuid(g['transferID'])
    if g['requestSequence']!='1' or type(g['requestSequence']) is not str:_bad('request_sequence')
    completed=_timestamp(g['completedAt']);edited=value['editedAt']
    if origin=='generated':
        if edited is not None:_bad('edited_at')
    else:
        edited=_timestamp(edited)
    generation=NotesGenerationData(scope,epoch,operation,request,1,transfer,completed)
    notes=_notes(value['notes'],source)
    return NotesDocumentData(note_id,note_revision,record,revision,saved,selection,source.record_state,source.gaps,source.source_digest,tuple(proofs),origin,model,'notes_source_v1',generation,edited,notes,_canonical(value,DOCUMENT_BYTES))
