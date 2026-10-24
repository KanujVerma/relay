"""Opt-in actual frozen helper tests. Only synthetic encrypted grants are used.

The deliberately expired grant has no offline_access/refresh token, so even a
novel-request negative cannot make an HTTP request. No real account is opened.
"""
import base64
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time
import unittest
import uuid
from relay_spike import auth
from relay_spike.account_store import AccountCredentialStore
from relay_spike.panel_wire import encode_frame, FrameDecoder
from tests.test_account_store import grant
from tests.test_session_host import start, speech, end, final

@unittest.skipUnless(os.environ.get('RELAY_ACCOUNT_BUNDLED_HELPER'), 'Explicit newly built relocated account helper artifact required')
class BundledAccountProductTests(unittest.TestCase):
    def setUp(self):
        self.helper=Path(os.environ['RELAY_ACCOUNT_BUNDLED_HELPER']).resolve()
        self.assertTrue(self.helper.is_file())
        self.folder=tempfile.TemporaryDirectory();self.addCleanup(self.folder.cleanup)
        self.directory=Path(self.folder.name)/'Relay'/'Accounts';self.key=bytes(range(32))
        self.store=AccountCredentialStore(self.directory,self.key);host=self.store.initialize()
        record=grant(host,saved_at=1,refresh_token=None,scopes=[s for s in auth.SCOPE.split() if s!='offline_access'])
        self.identity=self.store.save_registration(record);self.generation=str(uuid.uuid4());self.store.select(self.identity,self.generation)
        self.environment=dict(PATH='/usr/bin:/bin',HOME=self.folder.name,TMPDIR=self.folder.name,HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1')

    def bootstrap(self,purpose='oauth_session'):
        return dict(schemaVersion=1,kind='account_secret_bootstrap',purpose=purpose,key=base64.b64encode(self.key).decode(),
            vaultDirectory=str(self.directory),registrationID=self.identity if purpose=='oauth_session' else None,
            accountGeneration=self.generation)

    def child(self,arguments):
        child=subprocess.Popen([str(self.helper),'-m',*arguments],cwd='/',env=self.environment,
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        def close():
            if child.poll() is None:child.kill();child.wait(timeout=5)
            for stream in (child.stdin,child.stdout,child.stderr):stream.close()
        self.addCleanup(close);return child

    def terminal(self,child,frames,kind=None):
        child.stdin.write(b''.join(encode_frame(value) for value in frames));child.stdin.flush()
        decoder=FrameDecoder();deadline=time.monotonic()+5
        while True:
            remaining=deadline-time.monotonic();self.assertGreater(remaining,0)
            self.assertTrue(select.select([child.stdout],[],[],remaining)[0])
            chunk=os.read(child.stdout.fileno(),4096);self.assertTrue(chunk)
            for row in decoder.feed(chunk):
                if kind is not None and row.get('kind')==kind:return row
                if kind is None and row.get('disposition') not in (None,'pending'):return row

    def finish(self,child):
        child.stdin.close();child.wait(timeout=5)
        self.assertEqual(child.returncode,0);self.assertEqual(child.stderr.read(),b'')

    def test_private_first_frame_plus_adjacent_actual_native_frames_produce_reviewed_reference(self):
        child=self.child(['relay_spike.session_host','--role','analytics','--oauth','--protected-account','--model','synthetic-model'])
        row=self.terminal(child,[self.bootstrap(),start(),speech(2),end(3),final(4,'What is the difference between WHERE and HAVING?')])
        self.assertEqual(row['answerKind'],'reviewed_reference');self.assertEqual(row['disposition'],'answer');self.finish(child)

    def test_protected_personal_request_stays_withheld_and_novel_request_has_no_usable_token(self):
        for question,reason in [('What did you personally do on your Atlas project?','personal_context_missing'),('Explain event loops.','answer_unavailable')]:
            child=self.child(['relay_spike.session_host','--oauth','--protected-account','--model','synthetic-model'])
            row=self.terminal(child,[self.bootstrap(),start(),speech(2),end(3),final(4,question)])
            self.assertNotEqual(row['disposition'],'answer');self.assertEqual(row['reasonCode'],reason);self.finish(child)

    def test_actual_account_control_private_bootstrap_then_status_uses_encrypted_registry(self):
        child=self.child(['relay_spike.account_bridge'])
        request=dict(schemaVersion=1,kind='account_request',requestID=str(uuid.uuid4()),action='status',payload={})
        row=self.terminal(child,[self.bootstrap('account_control'),request],kind='account_response')
        self.assertEqual(row['action'],'status');self.assertEqual(row['requestID'],request['requestID'])
        self.assertEqual(row['snapshot']['activeRegistrationID'],self.identity);self.finish(child)

    def test_missing_wrong_purpose_key_and_generation_fail_without_legacy_fallback(self):
        invalid=[]
        for field,value in [('purpose','account_control'),('key',base64.b64encode(bytes([99])*32).decode()),('accountGeneration',str(uuid.uuid4()))]:
            payload=self.bootstrap();payload[field]=value;invalid.append(encode_frame(payload))
        for payload in [b'',encode_frame(start()),*invalid]:
            child=self.child(['relay_spike.session_host','--oauth','--protected-account','--model','synthetic-model'])
            output,errors=child.communicate(payload,timeout=5)
            self.assertEqual(child.returncode,2);self.assertEqual(output+errors,b'')

    def test_fixture_and_no_inference_reference_modes_do_not_consume_any_private_frame(self):
        for mode in ([],['--fixture-model']):
            child=self.child(['relay_spike.session_host','--role','analytics',*mode])
            row=self.terminal(child,[start(),speech(2),end(3),final(4,'What is the difference between WHERE and HAVING?')])
            self.assertEqual(row['answerKind'],'reviewed_reference');self.finish(child)
