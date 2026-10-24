"""Synthetic-only launcher safety; actual app/model flow is tested natively."""
import base64
import json
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

FIXTURE=Path(__file__).parent/'support'/'account_product_helper.py'
TAIL=['-m','relay_spike.session_host','--role','developer','--oauth','--protected-account','--model','synthetic-model']

class AccountProductFixtureTests(unittest.TestCase):
    def test_import_is_inert(self):
        with patch('socket.socket',side_effect=AssertionError('import opened socket')),patch('os.open',side_effect=AssertionError('import opened file')):
            module=runpy.run_path(str(FIXTURE),run_name='synthetic_product_import_only')
        self.assertTrue(callable(module['main']))

    def test_actual_protected_helper_tail_reaches_private_bootstrap_without_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'metadata.jsonl'
            result=subprocess.run([sys.executable,str(FIXTURE),'--synthetic-product-account-test','--log',str(log),*TAIL],input=b'',capture_output=True,timeout=5)
            self.assertEqual(result.returncode,2);self.assertEqual(result.stdout+result.stderr,b'')
            self.assertEqual(log.read_bytes(),b'');self.assertEqual(log.stat().st_mode&0o777,0o600)

    def test_explicit_flag_and_exact_protected_mode_are_required_before_log_creation(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'metadata.jsonl'
            for arguments in (['--log',str(log),*TAIL],
                ['--synthetic-product-account-test','--log',str(log),'-m','relay_spike.account_bridge'],
                ['--synthetic-product-account-test','--log',str(log),*TAIL,'--fixture-model']):
                result=subprocess.run([sys.executable,str(FIXTURE),*arguments],input=b'',capture_output=True,timeout=5)
                self.assertEqual(result.returncode,2);self.assertFalse(log.exists())

    def test_nontemporary_bootstrap_is_rejected_before_any_account_store_access(self):
        bootstrap=dict(schemaVersion=1,kind='account_secret_bootstrap',purpose='oauth_session',
            key=base64.b64encode(bytes([42])*32).decode(),vaultDirectory='/not-an-owned-synthetic-test-directory/Accounts',
            registrationID=str(uuid.uuid4()),accountGeneration=str(uuid.uuid4()))
        body=json.dumps(bootstrap,separators=(',',':')).encode()
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'metadata.jsonl'
            result=subprocess.run([sys.executable,str(FIXTURE),'--synthetic-product-account-test','--log',str(log),*TAIL],
                input=struct.pack('>I',len(body))+body,capture_output=True,timeout=5)
            self.assertEqual(result.returncode,2);self.assertEqual(result.stdout+result.stderr,b'');self.assertEqual(log.read_bytes(),b'')
