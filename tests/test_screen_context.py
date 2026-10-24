"""Synthetic screen port tests. No capture, account credentials or network."""
import copy
import json
import unittest
from types import SimpleNamespace
from relay_spike.screen_context import SupplementalScreenProvider

REQUEST = dict(captureSessionID='11111111-1111-1111-1111-111111111111', sessionEpoch=1,
               presentationGeneration=2, requestID='22222222-2222-2222-2222-222222222222')
SOURCE = dict(windowID=11, bundleID='example.editor', processID=123, label='Editor window 11')
FRAME = dict(schemaVersion=1, kind='screen_context', **REQUEST, source=SOURCE,
             selectionRevision=1, permissionRevision=1, capturedUptimeNanoseconds=90,
             contentDigest='a'*64, imageDigest='b'*64, text='def solve(items):\n    return len(items)', provenance='local_ocr')

def wire(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()

class ScreenContextProviderTests(unittest.TestCase):
    def setUp(self):
        self.now = 100
        self.changes = 0
        self.provider = SupplementalScreenProvider(now_ns=lambda: self.now, on_invalidation=self.changed, snippet_factory=SimpleNamespace)
    def changed(self):
        self.changes += 1
    def test_valid_snapshot_issues_original_request_bound_ocr(self):
        self.assertTrue(self.provider.ingest(wire(FRAME), REQUEST))
        snippet = self.provider(REQUEST)
        self.assertEqual(snippet.text, 'def solve(items):\n    return len(items)')
        self.assertEqual(snippet.provenance, 'local_ocr')
        self.assertEqual(snippet.captured_uptime_ns, 90)
        self.assertTrue(self.provider.validate_current(snippet, REQUEST))
    def test_equal_but_unissued_snippet_does_not_authorize(self):
        self.assertTrue(self.provider.ingest(wire(FRAME), REQUEST))
        snippet = self.provider(REQUEST)
        self.assertFalse(self.provider.validate_current(copy.copy(snippet), REQUEST))
    def test_stale_or_different_epoch_request_cannot_reuse(self):
        self.assertTrue(self.provider.ingest(wire(FRAME), REQUEST))
        snippet = self.provider(REQUEST)
        for key, value in [('sessionEpoch', 2), ('presentationGeneration', 3), ('requestID', '33333333-3333-3333-3333-333333333333')]:
            self.assertIsNone(self.provider(dict(REQUEST, **{key:value})))
        self.now = 10_000_000_091
        self.assertFalse(self.provider.validate_current(snippet, REQUEST))
    def test_revoke_clears_before_callback_and_replay_cannot_restore(self):
        self.assertTrue(self.provider.ingest(wire(FRAME), REQUEST))
        prior = self.provider(REQUEST)
        self.provider.invalidate()
        self.assertIsNone(self.provider(REQUEST))
        self.assertFalse(self.provider.validate_current(prior, REQUEST))
        self.assertFalse(self.provider.ingest(wire(FRAME), REQUEST))
        self.assertEqual(self.changes, 1)
        updated = dict(FRAME, selectionRevision=2, permissionRevision=2, capturedUptimeNanoseconds=95)
        self.assertTrue(self.provider.ingest(wire(updated), REQUEST))
    def test_duplicate_unknown_boolean_counter_future_or_oversized_fails(self):
        bad = [wire(dict(FRAME, extra=True)), wire(dict(FRAME, sessionEpoch=True)),
               wire(dict(FRAME, capturedUptimeNanoseconds=101)), wire(dict(FRAME, text='x'*8193)),
               wire(dict(FRAME, source=dict(SOURCE, windowID=2**32))),
               wire(dict(FRAME, source=dict(SOURCE, processID=True))),
               wire(dict(FRAME, provenance='user_paste')),
               wire(FRAME)[:-1] + b',"kind":"screen_context"}']
        for payload in bad:
            with self.subTest(payload=payload[:50]):
                self.assertFalse(self.provider.ingest(payload, REQUEST))
                self.assertIsNone(self.provider(REQUEST))
    def test_old_completion_does_not_clear_new_context(self):
        self.assertTrue(self.provider.ingest(wire(FRAME), REQUEST))
        new_request = dict(REQUEST, presentationGeneration=3, requestID='33333333-3333-3333-3333-333333333333')
        updated = dict(FRAME, **new_request, capturedUptimeNanoseconds=95)
        self.assertTrue(self.provider.ingest(wire(updated), new_request))
        issued = self.provider(new_request)
        self.assertFalse(self.provider.ingest(wire(FRAME), new_request))
        self.assertIs(self.provider(new_request), issued)

import base64
import hashlib
import struct
import zlib
from relay_spike.screen_context import ImageInputPolicy

def png(width=1, height=1):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\0\0\0\0\xff')) + chunk(b'IEND', b''))

POLICY = ImageInputPolicy(model='synthetic-image-model', account_id='synthetic-account', model_supports_images=True, user_enabled=True)
TRANSFER = '44444444-4444-4444-4444-444444444444'

def image_frames(data=None):
    data = png() if data is None else data
    common = {k: copy.deepcopy(FRAME[k]) for k in ('captureSessionID','sessionEpoch','presentationGeneration','requestID',
              'source','selectionRevision','permissionRevision','capturedUptimeNanoseconds','contentDigest','imageDigest')}
    common.update(schemaVersion=1, transferID=TRANSFER)
    chunks = [data[i:i+6144] for i in range(0, len(data), 6144)]
    begin = dict(common, kind='screen_image_begin', mimeType='image/png', width=1, height=1,
                 totalBytes=len(data), chunkCount=len(chunks), sha256=hashlib.sha256(data).hexdigest())
    return [begin] + [dict(common, kind='screen_image_chunk', index=i, data=base64.b64encode(part).decode())
                      for i,part in enumerate(chunks)] + [dict(common, kind='screen_image_end')]

class ImageContextPortTests(unittest.TestCase):
    def setUp(self):
        self.now = 100
        self.provider = SupplementalScreenProvider(now_ns=lambda: self.now, snippet_factory=SimpleNamespace)
        self.assertTrue(self.provider.ingest(wire(FRAME), REQUEST))
    def ingest(self, frame, policy=POLICY, native=REQUEST):
        return self.provider.ingest_image(wire(frame), native, policy=policy, model='synthetic-image-model', account_id='synthetic-account')
    def result(self, policy=POLICY, native=REQUEST):
        return self.provider.image_input(native, policy=policy, model='synthetic-image-model', account_id='synthetic-account')
    def test_completed_png_builds_bounded_official_input_part_offline(self):
        frames = image_frames()
        for frame in frames:
            self.assertTrue(self.ingest(frame))
        part = self.result()
        self.assertEqual(part['type'], 'input_image')
        self.assertEqual(part['detail'], 'high')
        self.assertEqual(part['image_url'], 'data:image/png;base64,' + base64.b64encode(png()).decode())
    def test_unknown_model_or_user_disabled_never_admits_image(self):
        for policy in [ImageInputPolicy(), ImageInputPolicy(model='synthetic-image-model', account_id='synthetic-account', model_supports_images=True)]:
            self.assertFalse(self.ingest(image_frames()[0], policy))
            self.assertIsNone(self.result(policy))
        for frame in image_frames(): self.assertTrue(self.ingest(frame))
        wrong = ImageInputPolicy(model='different-model', account_id='synthetic-account', model_supports_images=True, user_enabled=True)
        self.assertIsNone(self.result(wrong))
    def test_one_byte_over_cap_boolean_counter_and_oversized_chunk_fail(self):
        begin, chunk, end = image_frames()
        for bad in [dict(begin,totalBytes=2*1024*1024+1), dict(begin,chunkCount=True), dict(begin,width=1921), dict(begin,totalBytes=1,chunkCount=2)]:
            self.assertFalse(self.ingest(bad))
            self.assertIsNone(self.result())
        self.assertTrue(self.ingest(begin))
        self.assertFalse(self.ingest(dict(chunk,data=base64.b64encode(b'x'*6145).decode())))
        self.assertFalse(self.ingest(end))
    def test_duplicate_out_of_order_and_index_gap_retire_transfer(self):
        for bad_index in [True,1,2,-1]:
            begin,chunk,end=image_frames()
            self.assertTrue(self.ingest(begin))
            self.assertFalse(self.ingest(dict(chunk,index=bad_index)))
            self.assertFalse(self.ingest(end))
        begin,chunk,end=image_frames()
        self.assertTrue(self.ingest(begin)); self.assertTrue(self.ingest(chunk))
        self.assertFalse(self.ingest(chunk)); self.assertFalse(self.ingest(end))
    def test_mixed_transfer_source_session_or_revision_fails(self):
        begin,chunk,end=image_frames()
        for update in [dict(transferID='55555555-5555-5555-5555-555555555555'),dict(sessionEpoch=2),
                       dict(source=dict(SOURCE,windowID=12)),dict(selectionRevision=2),dict(imageDigest='c'*64)]:
            self.assertTrue(self.ingest(begin))
            self.assertFalse(self.ingest(dict(chunk,**update)))
            self.assertFalse(self.ingest(end))
    def test_hash_mismatch_expiry_and_revoke_prevent_use(self):
        begin,chunk,end=image_frames()
        self.assertTrue(self.ingest(dict(begin,sha256='c'*64)))
        self.assertTrue(self.ingest(chunk)); self.assertFalse(self.ingest(end))
        self.assertIsNone(self.result())
        self.assertTrue(self.ingest(begin)); self.now=2_000_000_101
        self.assertFalse(self.ingest(chunk)); self.assertIsNone(self.result())
        self.now=100
        for frame in image_frames(): self.assertTrue(self.ingest(frame))
        self.provider.invalidate()
        self.assertIsNone(self.result()); self.assertFalse(self.ingest(begin))
    def test_declared_dimensions_cannot_hide_bad_png(self):
        for data in [b'not a PNG', png(width=1921), png(width=2)]:
            frames=image_frames(data)
            self.assertTrue(self.ingest(frames[0]))
            self.assertTrue(self.ingest(frames[1]))
            self.assertFalse(self.ingest(frames[2]))
            self.assertIsNone(self.result())
    def test_new_begin_cannot_replace_inflight_transfer(self):
        frames=image_frames()
        self.assertTrue(self.ingest(frames[0]))
        self.assertFalse(self.ingest(dict(frames[0],transferID='55555555-5555-5555-5555-555555555555')))
        self.assertFalse(self.ingest(frames[1]))


class SharedScreenFixtureTests(unittest.TestCase):
    def test_native_synthetic_fixture_uses_the_same_strict_text_contract(self):
        from pathlib import Path
        path = Path(__file__).resolve().parents[1] / 'spikes/macos-context/Tests/RelayScreenContextTests/Fixtures/screen_context_v1.synthetic.json'
        payload = path.read_bytes()
        native = json.loads(payload)
        provider = SupplementalScreenProvider(now_ns=lambda: 100, snippet_factory=SimpleNamespace)
        self.assertTrue(provider.ingest(payload, native))
        self.assertEqual(provider(native).text, 'def solve(items):\n    return len(items)')

class ScreenContextCaseTests(unittest.TestCase):
    def test_original_native_uuid_spelling_is_preserved_for_answer_port(self):
        native = dict(REQUEST, captureSessionID='ABCDEFAB-1111-1111-1111-111111111111')
        frame = dict(FRAME, captureSessionID='abcdefab-1111-1111-1111-111111111111')
        provider = SupplementalScreenProvider(now_ns=lambda: 100,snippet_factory=SimpleNamespace)
        self.assertTrue(provider.ingest(wire(frame),native))
        self.assertEqual(provider(native).session_id,native['captureSessionID'])

class ScreenRetirementTests(unittest.TestCase):
    def setUp(self):
        self.changes = 0
        self.provider = SupplementalScreenProvider(now_ns=lambda: 100, snippet_factory=SimpleNamespace, on_invalidation=self.changed)
        self.assertTrue(self.provider.ingest(wire(FRAME),REQUEST))
        self.retired = {k:FRAME[k] for k in ('captureSessionID','sessionEpoch','presentationGeneration','requestID','selectionRevision','permissionRevision')}
        self.retired.update(schemaVersion=1,kind='screen_context_retired',reasonCode='selection_changed')
    def changed(self): self.changes += 1
    def test_matching_original_retirement_clears_once_and_replay_cannot_restore(self):
        self.assertTrue(self.provider.retire_frame(wire(self.retired),REQUEST))
        self.assertIsNone(self.provider(REQUEST))
        self.assertTrue(self.provider.retire_frame(wire(self.retired),REQUEST))
        self.assertEqual(self.changes,1)
        self.assertFalse(self.provider.ingest(wire(FRAME),REQUEST))
    def test_future_unknown_or_old_retirement_cannot_clear_current_context(self):
        issued=self.provider(REQUEST)
        for update in [dict(selectionRevision=2),dict(permissionRevision=True),dict(reasonCode='anything'),dict(extra=True),
                       dict(requestID='33333333-3333-3333-3333-333333333333')]:
            self.assertFalse(self.provider.retire_frame(wire(dict(self.retired,**update)),REQUEST))
            self.assertIs(self.provider(REQUEST),issued)
        new_request=dict(REQUEST,presentationGeneration=3,requestID='33333333-3333-3333-3333-333333333333')
        self.assertTrue(self.provider.ingest(wire(dict(FRAME,**new_request,capturedUptimeNanoseconds=95)),new_request))
        new=self.provider(new_request)
        self.assertFalse(self.provider.retire_frame(wire(self.retired),new_request))
        self.assertIs(self.provider(new_request),new)
    def test_request_only_retirement_allows_next_question_from_same_selected_source(self):
        self.assertTrue(self.provider.retire_frame(wire(dict(self.retired,reasonCode='request_superseded')),REQUEST))
        new_request=dict(REQUEST,presentationGeneration=3,requestID='33333333-3333-3333-3333-333333333333')
        self.assertTrue(self.provider.ingest(wire(dict(FRAME,**new_request,capturedUptimeNanoseconds=95)),new_request))


class SharedRetirementFixtureTests(unittest.TestCase):
    def test_native_retirement_fixture_retires_only_the_matching_issued_context(self):
        from pathlib import Path
        folder = Path(__file__).resolve().parents[1] / 'spikes/macos-context/Tests/RelayScreenContextTests/Fixtures'
        text = (folder / 'screen_context_v1.synthetic.json').read_bytes()
        retired = (folder / 'screen_context_retired_v1.synthetic.json').read_bytes()
        native=json.loads(text)
        provider=SupplementalScreenProvider(now_ns=lambda:100,snippet_factory=SimpleNamespace)
        self.assertTrue(provider.ingest(text,native))
        self.assertTrue(provider.retire_frame(retired,native))
        self.assertIsNone(provider(native))
