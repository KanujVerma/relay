"""Fictional in-memory DATA only; no record/account/admission is issued."""
import copy
import dataclasses
import hashlib
import itertools
import json
import socket
import subprocess
import unittest
from unittest.mock import patch

from relay_spike.session_notes_data import NotesDataError, parse_source_payload, parse_generated_notes, parse_notes_document

RECORD='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
CAPTURE='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
OTHER='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
U64=2**64-1
GAPS=('sourceUnavailable','sequenceGap','capacity','storageFailure','savingStopped','interrupted','captureFailure','sourceDeleted','invalidObservation','unfinishedSpeech','captureEndUnknown')
def encode(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
def row_id(i=1):return f'{CAPTURE}:1:2:1:{i}'
def source_value():
    row=dict(id=row_id(),revision='1',source='selected_app_audio',text='  A stable original quote.\n')
    return dict(schemaVersion=1,recordID=RECORD,recordRevision='7',selection=dict(kind='full_saved_transcript',totalSavedRows=1,includedRows=1,firstRowID=row['id'],lastRowID=row['id']),recordState='completed',gaps=[],rows=[row])
def output_value():return dict(schemaVersion=1,summary=[dict(text='The discussion used a queue.',citations=[dict(rowID=row_id(),quote='original quote')])],decisions=[],nextSteps=[])
def document_value(source,output=None):
    return dict(schemaVersion=1,noteID=OTHER,noteRevision='1',recordID=RECORD,sourceRecordRevision='7',savedAtRecordRevision='8',
        selection=source['selection'],sourceState=source['recordState'],sourceGaps=source['gaps'],sourceDigest=hashlib.sha256(b'relay.notes.source.v1\n'+encode(source)).hexdigest(),
        sourceRows=[dict(rowID=r['id'],revision=r['revision'],textDigest=hashlib.sha256(r['text'].encode()).hexdigest()) for r in source['rows']],
        origin='generated',modelID='declared-data-not-a-configured-model',promptPolicy='notes_source_v1',
        generation=dict(scopeID=RECORD,scopeEpoch='1',operationID=OTHER,requestID=CAPTURE,requestSequence='1',transferID=OTHER,completedAt='2026-10-24T09:00:00.000Z'),
        editedAt=None,notes=output or output_value())

class NotesSourceDataTests(unittest.TestCase):
    def parse(self,value):return parse_source_payload(encode(value))
    def test_exact_bytes_digest_and_immutable_data_not_authority(self):
        value=source_value();raw=encode(value);data=parse_source_payload(raw)
        self.assertEqual(data.raw_bytes,raw);self.assertEqual(data.source_digest,hashlib.sha256(b'relay.notes.source.v1\n'+raw).hexdigest())
        self.assertEqual(data.rows[0].text,value['rows'][0]['text']);self.assertIsInstance(data.rows,tuple)
        with self.assertRaises(dataclasses.FrozenInstanceError):data.rows[0].text='changed'
        value['rows'][0]['text']='later external mutation';self.assertNotEqual(data.rows[0].text,value['rows'][0]['text'])
        self.assertFalse(hasattr(data,'claim'));self.assertFalse(hasattr(data,'authorized'))
    def test_eleven_inherited_gaps_and_completed_consistency(self):
        v=source_value();v.update(recordState='partial',gaps=list(GAPS));data=self.parse(v)
        self.assertEqual(data.gaps,GAPS)
        for gaps in [['futureGap'],[GAPS[0],GAPS[0]],list(reversed(GAPS))]:
            bad=copy.deepcopy(v);bad['gaps']=gaps
            with self.assertRaises(NotesDataError):self.parse(bad)
        v['recordState']='completed'
        with self.assertRaises(NotesDataError):self.parse(v)
    def test_full_and_explicit_excerpt_are_data_consistency_not_completeness_grants(self):
        v=source_value();v['rows'].append({**v['rows'][0],'id':row_id(9)})
        v['selection'].update(kind='explicit_excerpt',totalSavedRows=9,includedRows=2,lastRowID=row_id(9))
        self.assertEqual(self.parse(v).selection.included_rows,2)
        for change in [dict(kind='full_saved_transcript'),dict(includedRows=1),dict(firstRowID=row_id(2)),dict(lastRowID=row_id(2)),dict(totalSavedRows=1)]:
            bad=copy.deepcopy(v);bad['selection'].update(change)
            with self.assertRaises(NotesDataError):self.parse(bad)
    def test_exact_fields_and_no_authority_configuration(self):
        v=source_value()
        for key in v:
            bad=copy.deepcopy(v);del bad[key]
            with self.subTest(missing=key),self.assertRaises(NotesDataError):self.parse(bad)
        for key in ['authorized','model','accountID','current','capturePermission']:
            with self.subTest(extra=key),self.assertRaises(NotesDataError):self.parse({**v,key:True})
        for path in ['selection','row']:
            bad=copy.deepcopy(v);target=bad['selection'] if path=='selection' else bad['rows'][0];target['extra']=True
            with self.assertRaises(NotesDataError):self.parse(bad)
            keys=v['selection'] if path=='selection' else v['rows'][0]
            for key in keys:
                bad=copy.deepcopy(v);target=bad['selection'] if path=='selection' else bad['rows'][0];del target[key]
                with self.subTest(path=path,missing=key),self.assertRaises(NotesDataError):self.parse(bad)
    def test_uuid_counter_source_revision_and_type_domains(self):
        v=source_value()
        for key,bad_value in [('schemaVersion',True),('schemaVersion',1.0),('recordID',RECORD.upper()),('recordRevision','01'),('recordRevision',str(2**63)),('recordRevision',True),('recordState','recording'),('rows',{})]:
            with self.subTest(field=key,value=bad_value),self.assertRaises(NotesDataError):self.parse({**v,key:bad_value})
        for counter in ['0','01','+1','-1',str(2**64),'١']:
            bad=copy.deepcopy(v);bad['rows'][0]['id']=f'{CAPTURE}:{counter}:2:1:1';bad['selection'].update(firstRowID=bad['rows'][0]['id'],lastRowID=bad['rows'][0]['id'])
            with self.subTest(counter=counter),self.assertRaises(NotesDataError):self.parse(bad)
        for row_change in [dict(source='microphone'),dict(revision='2'),dict(revision=1),dict(id='bad'),dict(text=None)]:
            bad=copy.deepcopy(v);bad['rows'][0].update(row_change)
            with self.assertRaises(NotesDataError):self.parse(bad)
        for counter in [True,1.0,0,1025]:
            bad=copy.deepcopy(v);bad['selection']['includedRows']=counter
            with self.assertRaises(NotesDataError):self.parse(bad)
    def test_source_controls_are_preserved_while_nul_empty_unicode_limits_reject(self):
        v=source_value()
        for text in ['\x01','\x1c','quote"\\\n original','é'*1200,'\U00010000'*1200]:
            v['rows'][0]['text']=text;self.assertEqual(self.parse(v).rows[0].text,text)
        for text in ['', ' \t\n', '\0text','x'*1201]:
            v['rows'][0]['text']=text
            with self.assertRaises(NotesDataError):self.parse(v)
        v['rows'][0]['text']='\ud800'
        with self.assertRaises(NotesDataError):parse_source_payload(json.dumps(v,ensure_ascii=True).encode())
    def test_structure_budget_rejects_before_json_decoder_allocation(self):
        for raw in [b'['*9+b'0'+b']'*9,b'['+b'0,'*8192+b'0]']:
            with patch('relay_spike.session_notes_data.strict_json',side_effect=AssertionError('decoder must not run')):
                with self.assertRaises(NotesDataError):parse_source_payload(raw)
    def test_strict_json_duplicates_nonfinite_nesting_nodes_and_raw_budget(self):
        raw=encode(source_value())
        for bad in [b'{"schemaVersion":1,"schemaVersion":1}',b'{"x":NaN}',b'['*9+b'0'+b']'*9,b'\xff',b' '*2097153]:
            with self.assertRaises(NotesDataError):parse_source_payload(bad)
        for bad in [raw.decode(),bytearray(raw),None]:
            with self.assertRaises(NotesDataError):parse_source_payload(bad)
    def test_full_maximum_width_projection_and_aggregate_limits(self):
        v=source_value();v.update(recordState='interrupted',gaps=list(GAPS))
        v['rows']=[dict(id=f'{CAPTURE}:{U64}:2:{U64}:{U64-i}',revision='1',source='selected_app_audio',text='\x01'*256) for i in range(1024)]
        v['selection'].update(totalSavedRows=1024,includedRows=1024,firstRowID=v['rows'][0]['id'],lastRowID=v['rows'][-1]['id'])
        raw=encode(v);self.assertGreater(len(raw),768*1024);self.assertLessEqual(len(raw),2*1024*1024)
        data=parse_source_payload(raw);self.assertEqual(len(data.rows),1024);self.assertEqual(sum(len(r.text.encode()) for r in data.rows),256*1024)
        too_many=copy.deepcopy(v);too_many['rows'].append({**v['rows'][0],'id':row_id(2000)})
        with self.assertRaises(NotesDataError):self.parse(too_many)
        v['rows'][0]['text']+='x'
        with self.assertRaises(NotesDataError):self.parse(v)
        v['rows'][0]['text']='x';v['rows'][1]['id']=v['rows'][0]['id']
        with self.assertRaises(NotesDataError):self.parse(v)

    def test_unicode_and_json_encoding_roundtrips_keep_original_bytes_and_literals(self):
        alphabet=('A','"','\\','[',']','{','}',':','\t','\n','\x01','\x1c','é','\u0301','\U00010000')
        for pair in itertools.product(alphabet,repeat=2):
            text='x'+''.join(pair);v=source_value();v['rows'][0]['text']=text
            raws=(encode(v),json.dumps(v,ensure_ascii=True,indent=1).encode())
            sources=tuple(parse_source_payload(raw) for raw in raws)
            self.assertEqual(sources[0].rows,sources[1].rows)
            self.assertNotEqual(sources[0].source_digest,sources[1].source_digest)
            output=output_value();output['summary'][0]['citations'][0]['quote']=text
            for raw,source in zip(raws,sources):
                self.assertEqual(source.raw_bytes,raw);self.assertEqual(source.rows[0].text.encode(),text.encode())
                parsed=parse_generated_notes(encode(output),source)
                self.assertEqual(parsed,parse_generated_notes(parsed.canonical_bytes,source))
                self.assertEqual(parsed.summary[0].citations[0].quote,text)

class NotesOutputDataTests(unittest.TestCase):
    def setUp(self):self.source=parse_source_payload(encode(source_value()))
    def parse(self,v):return parse_generated_notes(encode(v),self.source)
    def test_valid_frozen_literals_and_no_model_metadata(self):
        data=self.parse(output_value());self.assertEqual(data.summary[0].citations[0].row_id,row_id())
        self.assertIsInstance(data.summary,tuple);self.assertEqual(data.canonical_bytes,encode(output_value()))
        for key in ['modelID','sourceDigest','personal_fact_ids','origin','authorized','requestID']:
            with self.assertRaises(NotesDataError):self.parse({**output_value(),key:True})
    def test_schema_item_citation_and_semantic_claim_limits(self):
        v=output_value()
        for path in ('root','item','citation'):
            original=v if path=='root' else v['summary'][0] if path=='item' else v['summary'][0]['citations'][0]
            for key in (*original,'extra'):
                bad=copy.deepcopy(v);target=bad if path=='root' else bad['summary'][0] if path=='item' else bad['summary'][0]['citations'][0]
                if key=='extra':target[key]=True
                else:del target[key]
                with self.subTest(path=path,field=key),self.assertRaises(NotesDataError):self.parse(bad)
        for changes in [dict(schemaVersion=True),dict(schemaVersion=2),dict(summary=[]),dict(summary=[output_value()['summary'][0]]*9),dict(nextSteps=[output_value()['summary'][0]]*5)]:
            with self.assertRaises(NotesDataError):self.parse({**output_value(),**changes})
        for item in [dict(text='',citations=[]),dict(text='A',citations=[]),dict(text='x'*769,citations=output_value()['summary'][0]['citations']),dict(text='hidden\u202e',citations=output_value()['summary'][0]['citations'])]:
            v=output_value();v['summary']=[item]
            with self.assertRaises(NotesDataError):self.parse(v)
    def test_exact_citation_membership_quote_duplicates_and_no_normalization(self):
        for citation in [dict(rowID=row_id(9),quote='original'),dict(rowID=row_id(),quote='not in source'),dict(rowID=row_id(),quote=''),dict(rowID=row_id(),quote='x'*241),dict(rowID=row_id(),quote='original',extra=1)]:
            v=output_value();v['summary'][0]['citations']=[citation]
            with self.assertRaises(NotesDataError):self.parse(v)
        v=output_value();v['summary'][0]['citations']*=2
        with self.assertRaises(NotesDataError):self.parse(v)
        sv=source_value();sv['rows'][0]['text']='Cafe\u0301  space'
        self.source=parse_source_payload(encode(sv));v=output_value();v['summary'][0]['citations'][0]['quote']='Café'
        with self.assertRaises(NotesDataError):self.parse(v)
        v['summary'][0]['citations'][0]['quote']='Cafe\u0301  space';self.parse(v)
    def test_raw_canonical_budget_and_safe_errors(self):
        with self.assertRaises(NotesDataError):parse_generated_notes(b' '*8193,self.source)
        with self.assertRaises(NotesDataError):parse_generated_notes(b'{"schemaVersion":1',self.source)
        marker='FICTIONAL_PRIVATE_MARKER';v=output_value();v['unknown']=marker
        with self.assertRaises(NotesDataError) as caught:self.parse(v)
        self.assertNotIn(marker,str(caught.exception))

class NotesDocumentDataTests(unittest.TestCase):
    def setUp(self):self.value=source_value();self.source=parse_source_payload(encode(self.value))
    def parse(self,v):return parse_notes_document(encode(v),self.source)
    def test_valid_provenance_is_data_not_configured_account_or_saved_receipt(self):
        v=document_value(self.value);data=self.parse(v)
        self.assertEqual(data.source_digest,self.source.source_digest);self.assertEqual(data.canonical_bytes,encode(v))
        self.assertEqual(data.model_id,'declared-data-not-a-configured-model');self.assertFalse(hasattr(data,'saved'))
        v['origin']='generated_user_edited';v['editedAt']='2026-10-24T09:00:01.000Z';self.parse(v)
    def test_exact_fields_membership_source_and_revision(self):
        v=document_value(self.value)
        for key in v:
            bad=copy.deepcopy(v);del bad[key]
            with self.subTest(missing=key),self.assertRaises(NotesDataError):self.parse(bad)
        for changes in [dict(recordID=OTHER),dict(sourceRecordRevision='8'),dict(savedAtRecordRevision='7'),dict(noteRevision='0'),dict(sourceDigest='f'*64),dict(sourceGaps=['captureEndUnknown']),dict(origin='user'),dict(promptPolicy='other'),dict(modelID='x'*257),dict(modelID='hidden\n'),dict(authorized=True)]:
            with self.subTest(changes=changes),self.assertRaises(NotesDataError):self.parse({**v,**changes})
        for changes in [dict(rowID=row_id(2)),dict(revision='2'),dict(textDigest='f'*64),dict(extra=1)]:
            bad=copy.deepcopy(v);bad['sourceRows'][0].update(changes)
            with self.assertRaises(NotesDataError):self.parse(bad)
        for path in ('selection','generation','sourceRows'):
            original=v[path][0] if path=='sourceRows' else v[path]
            for key in original:
                bad=copy.deepcopy(v);target=bad[path][0] if path=='sourceRows' else bad[path];del target[key]
                with self.subTest(path=path,missing=key),self.assertRaises(NotesDataError):self.parse(bad)
        bad=copy.deepcopy(v);bad['notes']['summary'][0]['citations'][0]['quote']='invented quotation'
        with self.assertRaises(NotesDataError):self.parse(bad)
    def test_generation_timestamp_types_and_edit_origin(self):
        v=document_value(self.value)
        for change in [dict(scopeEpoch=True),dict(scopeEpoch='01'),dict(scopeEpoch=str(2**64)),dict(requestSequence='2'),dict(scopeID='bad'),dict(completedAt='2026-02-30T00:00:00.000Z'),dict(completedAt='2026-10-24T09:00:00Z'),dict(extra=True)]:
            bad=copy.deepcopy(v);bad['generation'].update(change)
            with self.assertRaises(NotesDataError):self.parse(bad)
        for change in [dict(editedAt='2026-10-24T09:00:01.000Z'),dict(origin='generated_user_edited')]:
            with self.assertRaises(NotesDataError):self.parse({**v,**change})
        with self.assertRaises(NotesDataError):parse_notes_document(b' '*262145,self.source)
    def test_backwards_wall_clock_is_valid_data_and_does_not_replace_logical_revision(self):
        v=document_value(self.value);v.update(origin='generated_user_edited',editedAt='2026-10-24T08:00:00.000Z',noteRevision='2',savedAtRecordRevision='9')
        data=self.parse(v)
        self.assertEqual(data.edited_at,'2026-10-24T08:00:00.000Z');self.assertEqual(data.note_revision,2)
        v['savedAtRecordRevision']='7'
        with self.assertRaises(NotesDataError):self.parse(v)
    def test_full_record_provenance_and_exact_maximum_output_fit_without_narrowing(self):
        sv=source_value();sv.update(recordState='interrupted',gaps=list(GAPS),recordRevision=str(2**63-2))
        sv['rows']=[dict(id=f'{CAPTURE}:{U64}:2:{U64}:{U64-i}',revision='1',source='selected_app_audio',text='\x01'*256) for i in range(1024)]
        sv['selection'].update(totalSavedRows=1024,includedRows=1024,firstRowID=sv['rows'][0]['id'],lastRowID=sv['rows'][-1]['id'])
        source=parse_source_payload(encode(sv));output=dict(schemaVersion=1,summary=[],decisions=[],nextSteps=[])
        for group,count in [('summary',8),('decisions',4),('nextSteps',4)]:
            output[group]=[dict(text='x',citations=[dict(rowID=sv['rows'][0]['id'],quote='\x01')]) for _ in range(count)]
        remaining=8192-len(encode(output))
        for item in itertools.chain(output['summary'],output['decisions'],output['nextSteps']):
            added=min(remaining,767);item['text']+='x'*added;remaining-=added
        self.assertEqual(remaining,0);self.assertEqual(len(encode(output)),8192)
        self.assertEqual(len(parse_generated_notes(encode(output),source).canonical_bytes),8192)
        v=document_value(sv,output);v.update(sourceRecordRevision=sv['recordRevision'],savedAtRecordRevision=str(2**63-1),modelID='x'*256)
        v['generation']['scopeEpoch']=str(U64)
        data=parse_notes_document(encode(v),source)
        self.assertEqual(len(data.source_rows),1024);self.assertLessEqual(len(data.canonical_bytes),256*1024)
        self.assertEqual(data,parse_notes_document(data.canonical_bytes,source))
        output['summary'][0]['text']+='x'
        with self.assertRaises(NotesDataError):parse_generated_notes(encode(output),source)
        for change in [dict(sourceRows=v['sourceRows'][:-1]),dict(sourceRows=list(reversed(v['sourceRows']))),dict(sourceDigest=source.source_digest.upper())]:
            with self.assertRaises(NotesDataError):parse_notes_document(encode({**v,**change}),source)
    def test_actual_calls_have_no_file_socket_subprocess_effects(self):
        raw=encode(document_value(self.value));source_raw=encode(self.value);output_raw=encode(output_value())
        def denied(*_,**__):raise AssertionError('data parser attempted IO')
        with patch('builtins.open',denied),patch.object(socket,'socket',denied),patch.object(subprocess,'Popen',denied):
            source=parse_source_payload(source_raw);parse_generated_notes(output_raw,source);parse_notes_document(raw,source)

if __name__=='__main__':unittest.main()
