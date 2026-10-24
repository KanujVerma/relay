"""Fictional strict wire DATA. No native/source/account/model grant is issued."""
import base64
import copy
import hashlib
import json
import unittest
import uuid

from relay_spike.session_notes_protocol import (decode_scope_request,decode_scope_response,
    decode_source_begin,decode_source_chunk,decode_source_end,decode_generate,decode_cancel,decode_result)
from relay_spike.session_notes_data import parse_source_payload
from relay_spike.panel_wire import WireError
from tests.test_session_notes_data import source_value,output_value,encode


def scope(action='open',**changes):
    value=dict(schemaVersion=1,kind='notes_scope_request',scopeID=str(uuid.uuid4()),scopeEpoch=1,operationID=str(uuid.uuid4()),action=action)
    value.update(changes);return value

def transfer(opened=None,**changes):
    opened=opened or scope();raw=encode(source_value());source=parse_source_payload(raw)
    value=dict(schemaVersion=1,kind='notes_source_begin',scopeID=opened['scopeID'],scopeEpoch=opened['scopeEpoch'],
        requestID=str(uuid.uuid4()),requestSequence=1,transferID=str(uuid.uuid4()),recordID=source.record_id,
        recordRevision=str(source.record_revision),selectionKind=source.selection.kind,rowCount=len(source.rows),totalBytes=len(raw),sourceDigest=source.source_digest)
    value.update(changes);return value,raw,source

def chunk(begin,raw,index=0):
    return dict(schemaVersion=1,kind='notes_source_chunk',scopeID=begin['scopeID'],scopeEpoch=begin['scopeEpoch'],
        requestID=begin['requestID'],transferID=begin['transferID'],index=index,data=base64.b64encode(raw).decode())

def end(begin,count=1):
    return dict(schemaVersion=1,kind='notes_source_end',scopeID=begin['scopeID'],scopeEpoch=begin['scopeEpoch'],
        requestID=begin['requestID'],transferID=begin['transferID'],chunkCount=count,totalBytes=begin['totalBytes'],sourceDigest=begin['sourceDigest'])

def generate(begin,kind='notes_generate',**changes):
    value={key:begin[key] for key in ('schemaVersion','scopeID','scopeEpoch','requestID','requestSequence','transferID','recordID','recordRevision','sourceDigest')}
    value['kind']=kind
    if kind=='notes_cancel':value['reasonCode']='cancelled'
    value.update(changes);return value

def result(begin,status='pending',**changes):
    value=generate(begin);value.update(kind='notes_result',resultRevision=1 if status=='pending' else 2,status=status,
        reasonCode='generating' if status=='pending' else 'ok' if status=='completed' else 'cancelled' if status=='cancelled' else 'source_unavailable',
        notes=output_value() if status=='completed' else None)
    value.update(changes);return value


class NotesWireDataTests(unittest.TestCase):
    def messages(self):
        opened=scope();begin,raw,source=transfer(opened)
        return [(decode_scope_request,opened),(decode_source_begin,begin),(decode_source_chunk,chunk(begin,raw)),
            (decode_source_end,end(begin)),(decode_generate,generate(begin)),(decode_cancel,generate(begin,'notes_cancel'))]
    def test_every_command_has_exact_fields_without_serialized_authority(self):
        for decoder,value in self.messages():
            self.assertEqual(decoder(value),value)
            for field in value:
                bad=dict(value);del bad[field]
                with self.subTest(kind=value['kind'],missing=field),self.assertRaises(WireError):decoder(bad)
            for field in ('authorized','current','accountID','model','sourceReady'):
                with self.subTest(kind=value['kind'],extra=field),self.assertRaises(WireError):decoder({**value,field:True})
    def test_identity_and_counter_types_are_canonical(self):
        for decoder,value in self.messages():
            for field in ('scopeID','requestID','transferID','operationID','recordID'):
                if field not in value:continue
                for invalid in (None,'bad','AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'):
                    with self.subTest(kind=value['kind'],field=field),self.assertRaises(WireError):decoder({**value,field:invalid})
            for invalid in (True,1.0,'1',0,-1,2**64):
                with self.subTest(kind=value['kind'],epoch=invalid),self.assertRaises(WireError):decoder({**value,'scopeEpoch':invalid})
        begin,_,_=transfer()
        for invalid in ('0','01','+1','١',str(2**63),True):
            with self.assertRaises(WireError):decode_source_begin({**begin,'recordRevision':invalid})
        for invalid in (True,1.0,'1',0,2):
            with self.assertRaises(WireError):decode_generate({**generate(begin),'requestSequence':invalid})
    def test_source_and_chunk_bounds_do_not_increase_existing_frame_limits(self):
        begin,raw,_=transfer()
        for field,values in {'rowCount':[0,1025,True],'totalBytes':[0,2097153,True],'selectionKind':['page','prefix'],'sourceDigest':['0'*63,'A'*64]}.items():
            for invalid in values:
                with self.assertRaises(WireError):decode_source_begin({**begin,field:invalid})
        for count in (1,8192):self.assertEqual(decode_source_chunk(chunk(begin,b'x'*count))['index'],0)
        for data in (b'',b'x'*8193):
            with self.assertRaises(WireError):decode_source_chunk(chunk(begin,data))
        for invalid in (-1,256,True,1.0):
            with self.assertRaises(WireError):decode_source_chunk(chunk(begin,raw,index=invalid))
        for invalid in (' eA==','eA','eB==','***','é'):
            with self.assertRaises(WireError):decode_source_chunk({**chunk(begin,raw),'data':invalid})
        for invalid in (0,257,True,1.0):
            with self.assertRaises(WireError):decode_source_end(end(begin,invalid))
        body=json.dumps(chunk(begin,b'x'*8192),separators=(',',':')).encode()
        self.assertLessEqual(len(body)+4,16384)
    def test_control_status_null_and_reason_combinations_are_exact(self):
        opened=scope();reply={**opened,'kind':'notes_scope_response','status':'ready','quiesced':None,'reasonCode':'ok'}
        self.assertEqual(decode_scope_response(reply),reply)
        closed={**reply,'action':'close','status':'closed','quiesced':True}
        self.assertEqual(decode_scope_response(closed),closed)
        for bad in ({**reply,'quiesced':True},{**reply,'reasonCode':'busy'},{**closed,'quiesced':1},{**closed,'status':'ready'},
                    {**reply,'status':'unavailable','quiesced':False,'reasonCode':'raw provider message'}):
            with self.assertRaises(WireError):decode_scope_response(bad)
        self.assertEqual(decode_scope_response({**reply,'status':'unavailable','quiesced':False,'reasonCode':'busy'})['reasonCode'],'busy')
    def test_result_is_cited_data_only_and_all_noncompleted_notes_are_null(self):
        begin,_,source=transfer()
        for status in ('pending','completed','cancelled','unavailable'):
            value=result(begin,status);self.assertEqual(decode_result(value,source=source),value)
            for key in value:
                bad=copy.deepcopy(value);del bad[key]
                with self.assertRaises(WireError):decode_result(bad,source=source)
        for bad in (result(begin,'pending',resultRevision=2),result(begin,'completed',notes=None),result(begin,'cancelled',notes=output_value()),
                    result(begin,'completed',reasonCode='output_invalid'),result(begin,'unavailable',reasonCode='private content')):
            with self.assertRaises(WireError):decode_result(bad,source=source)
        bad=result(begin,'completed');bad['notes']['summary'][0]['citations'][0]['quote']='invented source words'
        with self.assertRaises(WireError):decode_result(bad,source=source)
        with self.assertRaises(WireError):decode_result(result(begin,'completed'))


if __name__=='__main__':unittest.main()
