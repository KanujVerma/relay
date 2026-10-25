"""Synthetic launcher acceptance; actual helper/permit/SSE, no external IO."""
import importlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from tests import test_session_notes_stdio as stdio_fixture
from tests.test_session_notes_protocol import scope,transfer,chunk,end,generate


class NotesBackendHelperTests(stdio_fixture.NotesStdioTests):
    def _fixture(self,held=False,response=False):
        folder=tempfile.TemporaryDirectory(prefix='relay-notes-fixture-');self.addCleanup(folder.cleanup)
        log=Path(folder.name)/'counts.jsonl';release=Path(folder.name)/'release'
        if not held:release.touch()
        root=Path(__file__).resolve().parents[1]
        args=[sys.executable,str(root/'tests/support/notes_backend_helper.py'),'--synthetic-notes-test',
            '--log',str(log),'--release',str(release)]
        if response:args.append('--hold-response')
        args.extend(['-m','relay_spike.session_host','--role','developer','--fixture-model'])
        p=subprocess.Popen(args,cwd=root,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
        def stop():
            release.touch(exist_ok=True)
            if p.poll() is None:p.terminate()
            try:p.wait(timeout=3)
            except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
            for pipe in (p.stdin,p.stdout):
                if pipe is not None:pipe.close()
        self.addCleanup(stop);return p,log,release
    def child(self,fixture):return self._fixture()[0] if fixture else super().child(False)
    def test_default_import_does_not_start_or_read_any_account(self):
        module=importlib.import_module('tests.support.notes_backend_helper')
        self.assertTrue(callable(module.main))
    def test_explicit_flag_and_exact_fixture_tail_are_required(self):
        root=Path(__file__).resolve().parents[1];launcher=root/'tests/support/notes_backend_helper.py'
        with tempfile.TemporaryDirectory(prefix='relay-notes-fixture-') as folder:
            log=Path(folder)/'counts.jsonl'
            flags=['--synthetic-notes-test','--log',str(log),'--release',str(Path(folder)/'release')]
            invalid=[[],flags+['--unknown'],flags+['-m','relay_spike.account_bridge'],
                flags+['-m','relay_spike.session_host','--role','developer','--oauth']]
            for tail in invalid:
                p=subprocess.run([sys.executable,str(launcher),*tail],cwd=root,input=b'',capture_output=True,timeout=3)
                self.assertEqual(p.returncode,2);self.assertEqual(p.stdout,b'');self.assertFalse(log.exists())
    def test_actual_read_transport_hold_has_no_model_post_before_release(self):
        p,log,release=self._fixture(held=True);opened=scope();self.send(p,opened);self.assertEqual(self.read(p)['status'],'ready')
        begin,raw,_=transfer(opened);self.send(p,begin)
        deadline=time.monotonic()+3
        while not log.exists() or 'staging_held' not in log.read_text():
            self.assertLess(time.monotonic(),deadline);time.sleep(.003)
        self.assertNotIn('model_post',log.read_text())
        self.send(p,chunk(begin,raw));self.send(p,end(begin));self.send(p,generate(begin));release.touch()
        self.assertEqual(self.read(p)['status'],'pending');self.assertEqual(self.read(p)['status'],'completed')
        self.send(p,scope('close',scopeID=opened['scopeID']));self.assertTrue(self.read(p)['quiesced'])
        entries=[json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual(sum(x['event']=='model_post' for x in entries),1)
        self.assertTrue(all(set(x)<= {'event','kind'} for x in entries))
        self.assertFalse(any('token' in key or 'prompt' in key or 'image' in key for x in entries for key in x))

    def test_actual_held_response_keeps_cancel_close_unjoined_until_release(self):
        import select
        p,log,release=self._fixture(held=True,response=True);opened,begin,_=self.staged(p)
        self.send(p,generate(begin));self.assertEqual(self.read(p)['status'],'pending')
        deadline=time.monotonic()+3
        while 'model_held' not in log.read_text():
            self.assertLess(time.monotonic(),deadline);time.sleep(.003)
        self.send(p,generate(begin,'notes_cancel'));self.send(p,scope('close',scopeID=opened['scopeID']))
        self.assertFalse(select.select([p.stdout],[],[],.03)[0])
        release.touch();self.assertEqual(self.read(p)['status'],'cancelled');self.assertEqual(self.read(p)['status'],'closed')
        self.assertIn('model_closed',log.read_text());self.assertEqual(log.read_text().count('model_post'),1)
