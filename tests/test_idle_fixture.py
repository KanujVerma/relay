"""The optional native lifecycle fixture is inert and explicitly gated."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class IdleFixtureGateTests(unittest.TestCase):
    def test_import_does_not_start_or_write_anything(self):
        result=subprocess.run([sys.executable,'-c','import tests.support.idle_backend_helper'],
                              capture_output=True,timeout=5)
        self.assertEqual(result.returncode,0)
        self.assertEqual(result.stdout,b'');self.assertEqual(result.stderr,b'')

    def test_missing_explicit_flag_rejects_before_creating_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            log=Path(directory)/'log';release=Path(directory)/'release'
            result=subprocess.run([sys.executable,'tests/support/idle_backend_helper.py','--log',str(log),
                                   '--release',str(release),'-m','relay_spike.session_host','--role','analytics'],
                                  capture_output=True,timeout=5)
            self.assertEqual(result.returncode,2);self.assertFalse(log.exists());self.assertFalse(release.exists())

    def test_wrong_native_module_or_role_rejects_before_artifact_creation(self):
        for tail in (['-m','relay_spike.account_bridge','--role','analytics'],
                     ['-m','relay_spike.session_host','--role','invented'],
                     ['-m','relay_spike.session_host','--role','analytics','--api-key']):
            with self.subTest(tail=tail),tempfile.TemporaryDirectory() as directory:
                log=Path(directory)/'log';release=Path(directory)/'release'
                result=subprocess.run([sys.executable,'tests/support/idle_backend_helper.py','--synthetic-idle-test',
                    '--log',str(log),'--release',str(release),*tail],capture_output=True,timeout=5)
                self.assertEqual(result.returncode,2);self.assertFalse(log.exists());self.assertFalse(release.exists())

    def test_existing_artifact_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            log=Path(directory)/'log';release=Path(directory)/'release';release.write_bytes(b'synthetic-existing')
            result=subprocess.run([sys.executable,'tests/support/idle_backend_helper.py','--synthetic-idle-test',
                '--log',str(log),'--release',str(release),'-m','relay_spike.session_host','--role','analytics'],
                capture_output=True,timeout=5)
            self.assertEqual(result.returncode,2);self.assertFalse(log.exists())
            self.assertEqual(release.read_bytes(),b'synthetic-existing')
