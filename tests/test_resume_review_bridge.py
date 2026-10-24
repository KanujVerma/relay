"""Actual framed stdio child; no external account, paths or capture."""
import base64
from hashlib import sha256
import json
from pathlib import Path
import struct
import subprocess
import sys
import threading
import unittest

from tests.test_resume_structure import RESUME


class ResumeReviewChildTests(unittest.TestCase):
    def test_context_receipt_legacy_rejection_and_actual_snapshot_reload(self):
        child = subprocess.Popen([sys.executable, '-m', 'relay_spike.profile_bridge'],
            cwd=Path(__file__).parents[1], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        watchdog = threading.Timer(8, child.kill); watchdog.start()
        def exact(count):
            result = bytearray()
            while len(result) < count:
                part = child.stdout.read(count-len(result))
                self.assertTrue(part, 'Synthetic profile helper ended before receipt')
                result.extend(part)
            return bytes(result)
        def command(value):
            data = json.dumps(value, ensure_ascii=False).encode()
            self.assertLessEqual(len(data), 16*1024)
            child.stdin.write(struct.pack('>I', len(data))+data); child.stdin.flush()
            size, = struct.unpack('>I', exact(4)); self.assertLessEqual(size, 16*1024)
            return json.loads(exact(size))
        def transfer(data):
            for offset in range(0, len(data), 4096):
                self.assertTrue(command({'command':'transfer_chunk', 'offset':offset,
                    'data':base64.b64encode(data[offset:offset+4096]).decode()})['ok'])
        try:
            self.assertTrue(command({'command':'new'})['ready'])
            data = RESUME.encode()
            self.assertTrue(command({'command':'select_begin', 'size':len(data), 'sha256':sha256(data).hexdigest(),
                'file_type':'txt', 'purpose':'resume', 'label':'Fictional résumé', 'role':'developer', 'project_hint':None})['ok'])
            transfer(data); state = command({'command':'select_commit'}); card = state['card']
            self.assertEqual(card.get('schema_version'), 2)
            self.assertEqual(card['review_context']['fields'][-1]['text'], 'GPA: 3.8/4.0')
            decision = {'command':'decide_v2', 'fact_id':card['fact_id'], 'fingerprint':card['card_fingerprint'],
                'card_version':2, 'context_sha256':card['context_sha256'], 'decision':'approve',
                'actor':'self', 'claim_key':'fiction.education', 'replaces_fact_id':None}
            old = {k:v for k,v in decision.items() if k not in ('card_version','context_sha256')}; old['command'] = 'decide'
            for wrong in (old, {**decision, 'context_sha256':'0'*64}, {**decision, 'authorized':True},
                          {k:v for k,v in decision.items() if k != 'context_sha256'}, {**decision, 'card_version':True}):
                self.assertEqual(command(wrong), {'ok':False, 'error':'profile_request_rejected'})
                self.assertEqual(command({'command':'state'})['card'], card)
            self.assertEqual(command(decision)['pending_count'], state['pending_count']-1)
            self.assertFalse(command(decision)['ok'])
            manifest = command({'command':'snapshot_begin'}); parts = []
            for offset in range(0, manifest['size'], 4096):
                parts.append(base64.b64decode(command({'command':'snapshot_chunk', 'offset':offset})['data']))
            snapshot = b''.join(parts); self.assertEqual(sha256(snapshot).hexdigest(), manifest['sha256'])
            self.assertTrue(command({'command':'snapshot_end'})['ok'])
            self.assertTrue(command({'command':'lock'})['locked'])
            self.assertTrue(command({'command':'load_begin', 'size':len(snapshot), 'sha256':sha256(snapshot).hexdigest()})['ok'])
            transfer(snapshot); self.assertTrue(command({'command':'load_commit'})['ready'])
            memories = command({'command':'memories', 'after':None, 'limit':8})
            self.assertEqual(memories['total_count'], 1)
            self.assertEqual(memories['memories'][0]['claim_text'], 'BSc Computing')
            self.assertEqual(command({'command':'sources'})['sources'][0]['resume_coverage']['version'], 2)
            child.stdin.close(); self.assertEqual(child.wait(timeout=3), 0)
            self.assertEqual(child.stderr.read(), b'')
        finally:
            watchdog.cancel()
            if child.poll() is None: child.kill(); child.wait(timeout=3)
            for stream in (child.stdin, child.stdout, child.stderr): stream.close()
