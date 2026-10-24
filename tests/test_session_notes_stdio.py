"""Owned source helper with fictional framed commands; no account or network."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import unittest

from relay_spike.panel_wire import encode_frame
from relay_spike.session_notes_protocol import decode_result
from relay_spike.session_notes_data import parse_source_payload
from tests.test_session_notes_protocol import scope,transfer,chunk,end,generate
from tests.test_session_notes_data import source_value,row_id,encode


class NotesStdioTests(unittest.TestCase):
    def child(self,fixture):
        args=[sys.executable,'-m','relay_spike.session_host','--role','developer']
        if fixture:args.append('--fixture-model')
        process=subprocess.Popen(args,cwd=Path(__file__).resolve().parents[1],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
        def stop():
            if process.poll() is None:process.terminate()
            try:process.wait(timeout=3)
            except subprocess.TimeoutExpired:process.kill();process.wait(timeout=3)
            for pipe in (process.stdin,process.stdout):
                if pipe is not None:pipe.close()
        self.addCleanup(stop);return process
    def send(self,p,value):p.stdin.write(encode_frame(value));p.stdin.flush()
    def read(self,p):
        def exact(count):
            result=bytearray();deadline=time.monotonic()+5
            while len(result)<count:
                remaining=deadline-time.monotonic()
                if remaining<=0 or not select.select([p.stdout],[],[],remaining)[0]:self.fail('Owned fictional helper frame timed out')
                part=os.read(p.stdout.fileno(),count-len(result))
                if not part:self.fail('Owned fictional helper exited before its complete frame')
                result.extend(part)
            return bytes(result)
        count=int.from_bytes(exact(4),'big');self.assertGreater(count,0);self.assertLessEqual(count,16384)
        return json.loads(exact(count))
    def staged(self,p):
        opened=scope();self.send(p,opened);self.assertEqual(self.read(p)['status'],'ready')
        begin,raw,source=transfer(opened)
        for frame in (begin,chunk(begin,raw),end(begin)):self.send(p,frame)
        return opened,begin,source
    def test_actual_framed_fixture_notes_close_without_audio_or_private_bootstrap(self):
        p=self.child(True);opened,begin,source=self.staged(p);self.send(p,generate(begin))
        pending=self.read(p);terminal=self.read(p)
        self.assertEqual(pending['status'],'pending');self.assertEqual(terminal['status'],'completed')
        self.assertEqual(decode_result(terminal,source=source),terminal)
        self.send(p,generate(begin,'notes_cancel'));self.assertEqual(self.read(p),terminal)
        closing=scope('close',scopeID=opened['scopeID']);self.send(p,closing);reply=self.read(p)
        self.assertEqual(reply['operationID'],closing['operationID']);self.assertEqual(reply['status'],'closed');self.assertTrue(reply['quiesced'])
        p.stdin.close();self.assertEqual(p.wait(timeout=3),0)
    def test_actual_default_no_inference_refuses_notes_and_stays_responsive(self):
        p=self.child(False);opened,begin,_=self.staged(p);self.send(p,generate(begin))
        reply=self.read(p);self.assertEqual(reply['status'],'unavailable');self.assertEqual(reply['reasonCode'],'inference_disabled');self.assertIsNone(reply['notes'])
        closing=scope('close',scopeID=opened['scopeID']);self.send(p,closing);self.assertEqual(self.read(p)['status'],'closed')
        p.stdin.close();self.assertEqual(p.wait(timeout=3),0)
    def test_full_1024_row_control_source_crosses_actual_frames_without_prefixing(self):
        p=self.child(True);opened=scope();self.send(p,opened);self.assertEqual(self.read(p)['status'],'ready')
        value=source_value()
        value['rows']=[dict(id=row_id(i),revision='1',source='selected_app_audio',text='\x01'*256) for i in range(1,1025)]
        value['selection'].update(totalSavedRows=1024,includedRows=1024,lastRowID=row_id(1024))
        raw=encode(value);source=parse_source_payload(raw);begin=transfer(opened)[0]
        begin.update(rowCount=1024,totalBytes=len(raw),sourceDigest=source.source_digest)
        self.assertGreater(len(raw),1500000);self.send(p,begin)
        count=0
        for offset in range(0,len(raw),8192):self.send(p,chunk(begin,raw[offset:offset+8192],count));count+=1
        self.assertLessEqual(count,256);self.send(p,end(begin,count));self.send(p,generate(begin))
        self.assertEqual(self.read(p)['status'],'pending');completed=self.read(p)
        self.assertEqual(completed['status'],'completed');decode_result(completed,source=source)
        self.assertEqual(completed['sourceDigest'],source.source_digest)
        closing=scope('close',scopeID=opened['scopeID']);self.send(p,closing);self.assertTrue(self.read(p)['quiesced'])
        p.stdin.close();self.assertEqual(p.wait(timeout=3),0)


if __name__=='__main__':unittest.main()
