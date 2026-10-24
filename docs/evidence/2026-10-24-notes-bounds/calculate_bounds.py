"""Small fictional projection calculation, not a runtime/native/model test.

stdlib only; allocates a few bounded JSON buffers, writes no source/private data.
Canonical JSON uses sorted keys, compact separators and unescaped solidus.
"""
import base64
import hashlib
import json
import math

U64 = 2**64 - 1
I64 = 2**63 - 1
COUNT, TEXT_BYTES, SOURCE_CAP, DERIVED_CAP = 1024, 256 * 1024, 2 * 1024 * 1024, 256 * 1024
UUID = 'ffffffff-ffff-4fff-bfff-ffffffffffff'
GAPS = ['sourceUnavailable','sequenceGap','capacity','storageFailure','savingStopped','interrupted','captureFailure','sourceDeleted','invalidObservation','unfinishedSpeech','captureEndUnknown']
def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
def row_id(index):
    return f'{UUID}:{U64}:2:{U64}:{U64-index}'
def source(text):
    rows = [dict(id=row_id(i), revision='1', source='selected_app_audio', text=text) for i in range(COUNT)]
    return dict(schemaVersion=1,recordID=UUID,recordRevision=str(I64-1),
        selection=dict(kind='full_saved_transcript',totalSavedRows=COUNT,includedRows=COUNT,firstRowID=rows[0]['id'],lastRowID=rows[-1]['id']),
        recordState='interrupted',gaps=GAPS,rows=rows)

assert len(row_id(0)) == 101 and len(set(row_id(i) for i in range(COUNT))) == COUNT
assert all(len(row_id(i)) == 101 for i in range(COUNT))
base = source(''); header = len(encoded(dict(base, rows=[])))
row_metadata = len(encoded(base['rows'][0]))
upper_source = header + COUNT * row_metadata + COUNT - 1 + 6 * TEXT_BYTES
results = {}
for name, text in [('ordinary','A'*256),('quote_backslash','"\\'*128),('control_u0001','\x01'*256),('astral','\U00010000'*64)]:
    value=source(text); data=encoded(value)
    assert sum(len(row['text'].encode()) for row in value['rows']) == TEXT_BYTES
    assert all(len(row['text']) <= 1200 and len(row['text'].encode()) <= 4800 and '\0' not in row['text'] for row in value['rows'])
    assert len(data) <= upper_source <= SOURCE_CAP
    results[name] = dict(raw_text_bytes=TEXT_BYTES,json_bytes=len(data),chunks=math.ceil(len(data)/8192))
assert results['control_u0001']['json_bytes'] == upper_source

# An exactly 8192-byte structurally valid result from an ordinary fictional source.
item=lambda:dict(text='A',citations=[dict(rowID=row_id(0),quote='A')])
notes=dict(schemaVersion=1,summary=[item() for _ in range(8)],decisions=[item() for _ in range(4)],nextSteps=[item() for _ in range(4)])
remaining=8192-len(encoded(notes))
for group in ['summary','decisions','nextSteps']:
    for entry in notes[group]:
        extra=min(767,remaining);entry['text']+='A'*extra;remaining-=extra
assert remaining == 0 and len(encoded(notes)) == 8192
ordinary=source('A'*256)
membership=[dict(rowID=row_id(i),revision='1',textDigest=hashlib.sha256(b'A'*256).hexdigest()) for i in range(COUNT)]
persisted=dict(schemaVersion=1,noteID=UUID,noteRevision=str(I64),recordID=UUID,sourceRecordRevision=str(I64-1),savedAtRecordRevision=str(I64),
    selection=ordinary['selection'],sourceState=ordinary['recordState'],sourceGaps=GAPS,
    sourceDigest=hashlib.sha256(b'relay.notes.source.v1\n'+encoded(ordinary)).hexdigest(),sourceRows=membership,
    origin='generated_user_edited',modelID='m'*256,promptPolicy='notes_source_v1',
    generation=dict(scopeID=UUID,scopeEpoch=str(U64),operationID=UUID,requestID=UUID,requestSequence='1',transferID=UUID,completedAt='9999-12-31T23:59:59.999Z'),
    editedAt='9999-12-31T23:59:59.999Z',notes=notes)
actual_derived=len(encoded(persisted))
# Conservative extra allowance: every row revision grows from1 to20digits,
# and every permitted modelID input byte expands to six JSON bytes.
upper_derived=actual_derived + COUNT*19 + 5*256
assert upper_derived <= DERIVED_CAP
chunk=dict(schemaVersion=1,kind='notes_source_chunk',scopeID=UUID,scopeEpoch=U64,requestID=UUID,transferID=UUID,index=255,data=base64.b64encode(b'\xff'*8192).decode())
chunk_body=len(encoded(chunk));assert chunk_body <= 16384
print(json.dumps(dict(rows=COUNT,max_composite_id_bytes=101,raw_text_bytes=TEXT_BYTES,
    header_bytes=header,empty_row_metadata_bytes=row_metadata,source_upper_bytes=upper_source,source_cap=SOURCE_CAP,
    source_upper_chunks=math.ceil(upper_source/8192),max_cap_chunks=256,fixtures=results,
    output_bytes=8192,derived_actual_bytes=actual_derived,derived_conservative_upper_bytes=upper_derived,derived_cap=DERIVED_CAP,
    full_chunk_frame_body_bytes=chunk_body,full_chunk_framed_bytes=chunk_body+4,
    queue_limit_frames=32,queue_limit_bytes=256*1024),sort_keys=True,indent=2))
