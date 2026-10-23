import json
import time
import unittest
import uuid
from relay_spike.supplemental_context import SupplementalContextProvider
from relay_spike.conversation_context import ContextSnippet

class SupplementalContextTests(unittest.TestCase):
    def setUp(self):
        self.now = time.monotonic_ns()
        self.native = dict(captureSessionID=str(uuid.uuid4()), sessionEpoch=1, presentationGeneration=2, requestID=str(uuid.uuid4()))
        self.current = None
        self.provider = SupplementalContextProvider(current_request=lambda native: native is self.current, now_ns=lambda:self.now)
    def selected(self, **changes):
        value = dict(schemaVersion=1, kind='selected_text_context', **self.native,
            source={'bundleID':'com.example.editor','processID':42,'launchTimeMilliseconds':1234567},
            consentGeneration=str(uuid.uuid4()), observationID=str(uuid.uuid4()),
            capturedUptimeNanoseconds=self.now, provenance='selected_accessibility_text', text='def solve(items):\n    pass')
        value.update(changes)
        return json.dumps(value,separators=(',',':')).encode()
    def test_unaccepted_native_envelope_cannot_authorize_context(self):
        self.assertTrue(self.provider.stage(self.selected()))
        self.assertIsNone(self.provider(self.native))
        self.current=self.native
        self.assertIsNone(self.provider(self.native))
    def test_selected_text_is_issued_once_with_its_own_provenance(self):
        raw=self.selected();self.assertTrue(self.provider.stage(raw));self.current=self.native
        snippet=self.provider(self.native)
        self.assertIsInstance(snippet,ContextSnippet)
        self.assertEqual((snippet.kind,snippet.provenance),('screen_text','selected_accessibility_text'))
        self.assertEqual(snippet.source,'Selected text: com.example.editor')
        self.assertTrue(self.provider.validate_current(snippet,self.native))
        self.assertIs(self.provider(self.native),snippet)
        self.assertFalse(self.provider.stage(raw))
    def test_staging_expires_and_never_attaches_to_a_different_request(self):
        self.assertTrue(self.provider.stage(self.selected()));self.current=self.native
        self.now+=2_000_000_001
        self.assertIsNone(self.provider(self.native))
        self.assertTrue(self.provider.stage(self.selected(requestID=str(uuid.uuid4()))))
        self.assertIsNone(self.provider(self.native))
    def test_only_one_staged_context_and_retirement_clears_current(self):
        self.assertTrue(self.provider.stage(self.selected()))
        self.assertFalse(self.provider.stage(self.selected()))
        self.current=self.native
        self.assertIsNone(self.provider(self.native))
        self.assertTrue(self.provider.stage(self.selected()))
        snippet=self.provider(self.native)
        self.provider.invalidate()
        self.assertFalse(self.provider.validate_current(snippet,self.native))
    def test_strict_schema_rejects_duplicate_fields_booleans_and_ocr_claims(self):
        for raw in [self.selected(sessionEpoch=True),self.selected(extra=True),self.selected(provenance='local_ocr'),self.selected().replace(b'"schemaVersion":1',b'"schemaVersion":1,"schemaVersion":1')]:
            self.assertFalse(self.provider.stage(raw))

    def test_screen_frame_uses_reviewed_provider_only_after_actual_request_admission(self):
        from pathlib import Path
        fixture=Path(__file__).parents[1]/'spikes/macos-context/Tests/RelayScreenContextTests/Fixtures/screen_context_v1.synthetic.json'
        frame=json.loads(fixture.read_text());frame.update(self.native);frame['capturedUptimeNanoseconds']=self.now
        self.assertTrue(self.provider.stage(json.dumps(frame).encode()))
        self.current=self.native
        snippet=self.provider(self.native)
        self.assertIsInstance(snippet,ContextSnippet)
        self.assertEqual(snippet.provenance,'local_ocr')
        self.assertTrue(self.provider.validate_current(snippet,self.native))
        self.current=None
        self.assertFalse(self.provider.validate_current(snippet,self.native))

if __name__=='__main__':unittest.main()
