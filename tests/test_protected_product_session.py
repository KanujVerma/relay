"""Actual protected product factory and packaged entry, synthetic data only."""
from importlib.util import module_from_spec,spec_from_file_location
import base64
import asyncio
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid
from types import SimpleNamespace
from relay_spike import auth
from relay_spike.account_store import AccountCredentialStore,AccountStoreError
from relay_spike.account_bridge import AccountProtocolError
from relay_spike.panel_wire import encode_frame,FrameDecoder
from relay_spike.product_session import protected_answer_stream
from tests.test_account_store import grant

class ProtectedProductSessionTests(unittest.TestCase):
    def test_protected_stdio_cannot_construct_a_default_stream_when_provider_injection_is_missing(self):
        from relay_spike.session_host import run_stdio
        args=SimpleNamespace(oauth=True,protected_account=True,fixture_model=False,model='gpt-synthetic-first',role='developer')
        with (patch('relay_spike.oauth_answer_stream.OAuthAnswerStream',side_effect=AssertionError('default credential fallback')),
              patch.object(auth,'load_auth',side_effect=AssertionError('legacy credential read'))):
            self.assertEqual(asyncio.run(run_stdio(args)),2)

    def test_actual_factory_consumes_only_private_frame_then_uses_protected_provider(self):
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'Relay'/'Accounts';key=bytes(range(32));store=AccountCredentialStore(directory,key)
            host=store.initialize();record=grant(host,saved_at=time.time());identity=store.save_registration(record)
            generation=str(uuid.uuid4());store.select(identity,generation)
            bootstrap=dict(schemaVersion=1,kind='account_secret_bootstrap',purpose='oauth_session',key=base64.b64encode(key).decode(),
                vaultDirectory=str(directory),registrationID=identity,accountGeneration=generation)
            following=encode_frame(dict(kind='synthetic_next_command'))
            read,write=os.pipe()
            try:
                os.write(write,encode_frame(bootstrap)+following);os.close(write);write=None
                with patch.object(auth,'load_auth',side_effect=AssertionError('product fell through to development auth')):
                    stream=protected_answer_stream('gpt-synthetic-first',input_fd=read)
                    self.assertEqual(stream.model,'gpt-synthetic-first')
                    self.assertEqual(stream._token_provider(),record['access_token'])
                    self.assertEqual(os.read(read,16384),following)
            finally:
                os.close(read)
                if write is not None:os.close(write)

    def test_missing_bootstrap_and_wrong_model_never_touch_legacy_credentials_or_network(self):
        read,write=os.pipe();os.close(write)
        try:
            with patch.object(auth,'load_auth',side_effect=AssertionError('legacy read')),patch('socket.socket',side_effect=AssertionError('network')):
                with self.assertRaises(AccountProtocolError):protected_answer_stream('gpt-synthetic',input_fd=read)
                for model in ('', 'spaces are invalid', 'x'*129, 'hidden\u200bmodel', '--oauth'):
                    with self.subTest(model_length=len(model)),self.assertRaises(AccountProtocolError):protected_answer_stream(model,input_fd=read)
        finally:os.close(read)

class ProtectedProductEntryTests(unittest.TestCase):
    def setUp(self):
        path=Path(__file__).resolve().parents[1]/'packaging'/'relay_helper_entry.py'
        spec=spec_from_file_location('protected_product_entry_test',path);self.entry=module_from_spec(spec);spec.loader.exec_module(self.entry)

    def test_unprotected_or_abbreviated_product_oauth_never_dispatches_a_session_host(self):
        with patch('relay_spike.session_host.main') as host:
            for remaining in (['--oauth'],['--oa'],['--oauth','--protected-account'],['--protected-account','--model','gpt-synthetic'],
                ['--oauth','--protected-account','--model','gpt-synthetic','--oauth']):
                with self.subTest(remaining=remaining):self.assertEqual(self.entry.main(['-m','relay_spike.session_host',*remaining]),2)
            host.assert_not_called()

    def test_exact_protected_fixture_noinference_and_account_entrypoints_dispatch_only_their_actual_host(self):
        with patch('relay_spike.session_host.main',return_value=0) as host:
            for remaining in ([],['--role','developer'],['--fixture-model'],['--oauth','--protected-account','--model','gpt-synthetic-first']):
                self.assertEqual(self.entry.main(['-m','relay_spike.session_host',*remaining]),0)
            self.assertEqual(host.call_count,4)
        with patch('relay_spike.account_bridge.main',return_value=0) as account:
            self.assertEqual(self.entry.main(['-m','relay_spike.account_bridge']),0)
            self.assertEqual(self.entry.main(['-m','relay_spike.account_bridge','--oauth']),2)
            account.assert_called_once_with()

    def test_actual_packaged_entry_missing_or_wrong_first_private_frame_exits_without_any_fallback(self):
        entry=Path(__file__).resolve().parents[1]/'packaging'/'relay_helper_entry.py'
        from tests.test_session_host import start
        for payload in (b'',encode_frame(start())):
            result=subprocess.run([sys.executable,str(entry),'-m','relay_spike.session_host','--oauth','--protected-account','--model','gpt-synthetic-first'],
                input=payload,capture_output=True,timeout=5)
            self.assertEqual(result.returncode,2);self.assertEqual(result.stdout+result.stderr,b'')

    def test_actual_fixture_and_noinference_entry_keep_reviewed_reference_without_secret_bootstrap(self):
        from tests.test_session_host import start,speech,end,final
        root=Path(__file__).resolve().parents[1];entry=root/'packaging'/'relay_helper_entry.py'
        for mode in ([],['--fixture-model']):
            child=subprocess.Popen([sys.executable,str(entry),'-m','relay_spike.session_host','--role','analytics',*mode],
                cwd=root,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:
                child.stdin.write(b''.join(encode_frame(value) for value in [start(),speech(2),end(3),final(4,'What is the difference between WHERE and HAVING?')]))
                child.stdin.flush();decoder=FrameDecoder();terminal=None;deadline=time.monotonic()+5
                while terminal is None:
                    remaining=deadline-time.monotonic()
                    self.assertGreater(remaining,0)
                    self.assertTrue(select.select([child.stdout],[],[],remaining)[0])
                    chunk=os.read(child.stdout.fileno(),4096);self.assertTrue(chunk)
                    for response in decoder.feed(chunk):
                        if response['disposition']!='pending':terminal=response
                self.assertEqual(terminal['disposition'],'answer');self.assertEqual(terminal['answerKind'],'reviewed_reference')
                child.stdin.close();child.wait(timeout=5)
                self.assertEqual(child.returncode,0);self.assertEqual(child.stderr.read(),b'')
            finally:
                if child.poll() is None:child.kill();child.wait(timeout=5)
                for stream in (child.stdin,child.stdout,child.stderr):stream.close()
