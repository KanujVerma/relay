"""Synthetic launcher invocation boundary used by the actual native port tests."""
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

FIXTURE=Path(__file__).parent/'support'/'account_backend_helper.py'

class AccountNativeFixtureTests(unittest.TestCase):
    def test_import_is_inert_and_requires_no_dependency_or_environment_secret(self):
        with patch('socket.socket',side_effect=AssertionError('import opened socket')),patch('os.open',side_effect=AssertionError('import opened file')):
            module=runpy.run_path(str(FIXTURE),run_name='account_test_import_only')
        self.assertTrue(callable(module['main']))

    def test_real_appended_account_module_tail_is_accepted_without_any_runtime_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'metadata.jsonl'
            result=subprocess.run([sys.executable,str(FIXTURE),'--synthetic-account-test','--log',str(log),'-m','relay_spike.account_bridge'],
                input=b'',capture_output=True,timeout=5)
            self.assertEqual(result.returncode,2);self.assertEqual(result.stdout+result.stderr,b'')
            self.assertEqual(log.read_bytes(),b'')
            self.assertEqual(log.stat().st_mode&0o777,0o600)

    def test_missing_synthetic_flag_or_unrelated_helper_tail_is_rejected_before_log_creation(self):
        with tempfile.TemporaryDirectory() as folder:
            log=Path(folder)/'metadata.jsonl'
            for arguments in (['--log',str(log)],['--synthetic-account-test','--log',str(log),'-m','relay_spike.session_host']):
                result=subprocess.run([sys.executable,str(FIXTURE),*arguments],input=b'',capture_output=True,timeout=5)
                self.assertEqual(result.returncode,2);self.assertFalse(log.exists())
