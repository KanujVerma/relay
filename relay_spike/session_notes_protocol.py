"""Strict notes wire DATA only. Decoding never issues an owned scope/permit."""
import base64
import binascii
import json
import re

from .panel_wire import exact,u64,uuid_string,WireError
from .session_notes_data import NotesSourceData,parse_generated_notes,NotesDataError

REASONS=frozenset(('busy','stale','source_unavailable','source_expired','source_budget',
    'inference_disabled','account_unavailable','request_unavailable','output_invalid','cancelled','transport_closed'))
SCOPE=('scopeID','scopeEpoch','operationID','action')
REQUEST=('scopeID','scopeEpoch','requestID','requestSequence','transferID','recordID','recordRevision','sourceDigest')


def _bad():raise WireError('notes_protocol')

def _base(value,kind,fields):
    if type(value) is not dict:_bad()
    exact(value,('schemaVersion','kind',*fields))
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!=kind:_bad()
    _uuid(value['scopeID']);u64(value['scopeEpoch'],True)

def _uuid(value):
    if type(value) is not str or value!=uuid_string(value):_bad()

def _digest(value):
    if type(value) is not str or re.fullmatch('[0-9a-f]{64}',value) is None:_bad()

def _revision(value):
    if type(value) is not str or not 1<=len(value)<=19 or re.fullmatch('[1-9][0-9]*',value) is None or int(value)>2**63-1:_bad()

def _bounded(value,low,high):
    if type(value) is not int or not low<=value<=high:_bad()

def _request(value):
    for key in ('requestID','transferID','recordID'):_uuid(value[key])
    if type(value['requestSequence']) is not int or value['requestSequence']!=1:_bad()
    _revision(value['recordRevision']);_digest(value['sourceDigest'])

def decode_scope_request(value):
    _base(value,'notes_scope_request',SCOPE);_uuid(value['operationID'])
    if value['action'] not in ('open','close'):_bad()
    return dict(value)

def decode_scope_response(value):
    _base(value,'notes_scope_response',(*SCOPE,'status','quiesced','reasonCode'));_uuid(value['operationID'])
    status,action,quiesced,reason=(value[k] for k in ('status','action','quiesced','reasonCode'))
    if action not in ('open','close'):_bad()
    valid=(status=='ready' and action=='open' and quiesced is None and reason=='ok'
        or status=='closed' and action=='close' and quiesced is True and reason=='ok'
        or status=='unavailable' and quiesced is False and type(reason) is str and reason in REASONS)
    if not valid:_bad()
    return dict(value)

def decode_source_begin(value):
    _base(value,'notes_source_begin',(*REQUEST,'selectionKind','rowCount','totalBytes'));_request(value)
    if value['selectionKind'] not in ('full_saved_transcript','explicit_excerpt'):_bad()
    _bounded(value['rowCount'],1,1024);_bounded(value['totalBytes'],1,2097152)
    return dict(value)

def decode_source_chunk(value):
    _base(value,'notes_source_chunk',('scopeID','scopeEpoch','requestID','transferID','index','data'))
    _uuid(value['requestID']);_uuid(value['transferID']);_bounded(value['index'],0,255)
    encoded=value['data']
    if type(encoded) is not str or not 4<=len(encoded)<=10924 or not encoded.isascii():_bad()
    try:raw=base64.b64decode(encoded,validate=True)
    except (binascii.Error,ValueError):raise WireError('notes_protocol') from None
    if not 1<=len(raw)<=8192 or base64.b64encode(raw).decode()!=encoded:_bad()
    return dict(value)

def decode_source_end(value):
    _base(value,'notes_source_end',('scopeID','scopeEpoch','requestID','transferID','chunkCount','totalBytes','sourceDigest'))
    _uuid(value['requestID']);_uuid(value['transferID']);_digest(value['sourceDigest'])
    _bounded(value['chunkCount'],1,256);_bounded(value['totalBytes'],1,2097152)
    return dict(value)

def decode_generate(value):
    _base(value,'notes_generate',REQUEST);_request(value);return dict(value)

def decode_cancel(value):
    _base(value,'notes_cancel',(*REQUEST,'reasonCode'));_request(value)
    if type(value['reasonCode']) is not str or value['reasonCode'] not in REASONS:_bad()
    return dict(value)

def decode_result(value,*,source=None):
    _base(value,'notes_result',(*REQUEST,'resultRevision','status','reasonCode','notes'));_request(value)
    if type(value['resultRevision']) is not int:_bad()
    status,revision,reason,notes=(value[k] for k in ('status','resultRevision','reasonCode','notes'))
    if status=='pending':
        if revision!=1 or reason!='generating' or notes is not None:_bad()
    elif status=='completed':
        if revision!=2 or reason!='ok' or type(notes) is not dict or type(source) is not NotesSourceData:_bad()
        if (value['recordID']!=source.record_id or value['recordRevision']!=str(source.record_revision)
            or value['sourceDigest']!=source.source_digest):_bad()
        try:parse_generated_notes(json.dumps(notes,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode(),source)
        except (NotesDataError,ValueError,UnicodeError,TypeError):raise WireError('notes_protocol') from None
    elif status in ('cancelled','unavailable'):
        if revision!=2 or notes is not None or type(reason) is not str or reason not in REASONS:_bad()
        if status=='cancelled' and reason!='cancelled':_bad()
    else:_bad()
    return dict(value)
