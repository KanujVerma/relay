"""Fictional real document→review→restore→provider→Host acceptance.

Run all real-format cases without skips using the existing pinned document
environment and RELAY_RESUME_DOCUMENT_INTEGRATION=1. No network/model is used.
"""
from contextlib import ExitStack
from hashlib import sha256
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from io import BytesIO
from zipfile import ZipFile, ZIP_DEFLATED

from relay_spike.document_conversion import convert_document
from relay_spike.personal_brain import BrainStore
from relay_spike.personal_brain import BrainError
from relay_spike.profile_preparation import ProfilePreparation, export_memory_snapshot, restore_memory_snapshot
from relay_spike.session_host import SessionHost
from tests.test_resume_structure import STAMP
from tests.test_session_host import start
from tests.test_user_question import question

FIXTURES = Path(__file__).parent/'fixtures'/'resume-coverage'
MANIFEST = json.loads((FIXTURES/'manifest.json').read_text())
REAL = os.environ.get('RELAY_RESUME_DOCUMENT_INTEGRATION') == '1'


class ResumeFixtureIntegrity(unittest.TestCase):
    def test_all_files_are_the_frozen_fictional_generated_documents(self):
        self.assertIs(MANIFEST['fictional'], True)
        for name, identity in MANIFEST['files'].items():
            data = (FIXTURES/name).read_bytes()
            self.assertEqual(len(data), identity['size'])
            self.assertEqual(sha256(data).hexdigest(), identity['sha256'])

    def test_table_docx_does_not_gain_authority_through_the_structured_path(self):
        output = BytesIO()
        with ZipFile(BytesIO((FIXTURES/'fictional-linear.docx').read_bytes())) as source, ZipFile(output, 'w', ZIP_DEFLATED) as target:
            for name in source.namelist():
                data = source.read(name)
                if name == 'word/document.xml':
                    data = data.replace(b'</w:body>', b'<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Fictional table</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body>')
                target.writestr(name, data)
        with BrainStore() as store:
            cap = object(); prep = ProfilePreparation(store, host_capability=cap)
            with self.assertRaises(BrainError):
                prep.select_bytes(output.getvalue(), file_type='docx', purpose='resume',
                    label='Fictional unsupported table', role='developer', observed_at=STAMP, capability=cap)
            self.assertEqual(store.db.execute('SELECT COUNT(*) FROM source').fetchone()[0], 0)


class RealResumeDocuments(unittest.IsolatedAsyncioTestCase):
    async def check(self, file_type):
        with ExitStack() as stack:
            temporary = stack.enter_context(tempfile.TemporaryDirectory())
            stack.enter_context(patch.dict(os.environ, {'HF_HOME':temporary+'/hf',
                'HUGGINGFACE_HUB_CACHE':temporary+'/hf/hub', 'TORCH_HOME':temporary+'/torch',
                'XDG_CACHE_HOME':temporary+'/cache', 'HF_HUB_OFFLINE':'1', 'TRANSFORMERS_OFFLINE':'1'}))
            attempts = []
            def forbidden(*args, **kwargs): attempts.append(True); raise AssertionError('network forbidden')
            for target in ('socket.socket.connect','socket.socket.connect_ex','socket.create_connection',
                           'socket.getaddrinfo','socket.gethostbyname'):
                stack.enter_context(patch(target, side_effect=forbidden))
            store = stack.enter_context(BrainStore()); cap = object()
            prep = ProfilePreparation(store, host_capability=cap)
            data = (FIXTURES/('fictional-linear.'+file_type)).read_bytes()
            conversions = []
            def actual_convert(*args, **kwargs):
                result = convert_document(*args, **kwargs); conversions.append(result); return result
            with patch('relay_spike.profile_preparation.convert_document', side_effect=actual_convert):
                selected = prep.select_bytes(data, file_type=file_type, purpose='resume',
                    label='Fictional linear résumé', role='developer', observed_at=STAMP, capability=cap)
            self.assertTrue(selected.cards)
            source = store.db.execute('SELECT * FROM source WHERE id=?', (selected.source_id,)).fetchone()
            self.assertEqual(source['external_ref'], 'document-sha256:'+sha256(data).hexdigest())
            if file_type == 'txt':
                self.assertEqual(conversions, []); text = data.decode()
            else:
                self.assertEqual(len(conversions), 1)
                result = conversions[0]; self.assertEqual(result.status, 'converted', result.reason)
                self.assertEqual(result.document_sha256, sha256(data).hexdigest())
                text = result.text
            self.assertEqual(source['checksum'], sha256(text.encode()).hexdigest())
            self.assertEqual(prep.provider.retrieve('Tell me about yourself.', 'developer').facts, ())
            locations = {'txt':'text:line:', 'pdf':'pdf:page:', 'docx':'docx:paragraph:'}
            for card in selected.cards:
                self.assertEqual(card.schema_version, 2)
                self.assertEqual(text[card.span_start:card.span_end], card.snippet)
                self.assertTrue(card.locator.startswith(locations[file_type]))
                for field in card.review_context.fields:
                    self.assertEqual(text[field.span_start:field.span_end], field.text)
                    self.assertTrue(field.locator.startswith(locations[file_type]))
                prep.decide_v2(card.fact_id, card.card_fingerprint, decision='approve',
                    actor=card.actor_hint if card.actor_hint != 'unknown' else 'self',
                    claim_key='fixture.'+card.fact_id, replaces_fact_id=None,
                    card_version=2, context_sha256=card.context_sha256, capability=cap)
            restored = stack.enter_context(restore_memory_snapshot(export_memory_snapshot(store)))
            reopened_cap = object(); reopened = ProfilePreparation(restored, host_capability=reopened_cap)
            out = []
            async def no_inference(*args): self.fail('Reviewed background called a model')
            host = SessionHost(personal_provider=reopened.provider, complete=no_inference, emit=out.append)
            try:
                await host.handle(start())
                cases = (
                    ('What is your GPA at Cedar University?', ('Cedar University','Expected 2027','GPA: 3.8/4.0'), ('Pine College',)),
                    ('What is your GPA at Pine College?', ('Pine College','Completed 2023','GPA: 3.6/4.0'), ('Cedar University',)),
                    ('What did you personally do at Harbor Labs?', ('Harbor Labs','using Python'), ('Summit Clinic',)),
                    ('What did you personally do at Summit Clinic?', ('Summit Clinic','SQL validation'), ('Harbor Labs',)),
                    ('What did you personally do on Nurse Handoff?', ('Nurse Handoff','workflow in R'), ('Atlas Monitor',)),
                    ('Is C++ in your listed skills?', ('Listed skill: C++',), ('proficient',)),
                    ('Is R in your listed skills?', ('Listed skill: R',), ('proficient',)),
                    ('Which certifications do you list?', ('Cedar Institute','In progress','Pine Institute','Awarded 2024'), ()),
                )
                for request, expected, excluded in cases:
                    with self.subTest(format=file_type, question=request):
                        self.assertTrue(await host.handle_user_question(question(host, request)))
                        await host.drain(); value = out[-1]
                        self.assertEqual(value['reasonCode'], 'grounded_personal')
                        rendered = str(value['card'])
                        for literal in expected: self.assertIn(literal, rendered)
                        for literal in excluded: self.assertNotIn(literal, rendered)
                for request in ('What did you personally do on Atlas Monitor?', 'How proficient are you in C++?'):
                    self.assertTrue(await host.handle_user_question(question(host, request))); await host.drain()
                    self.assertEqual(out[-1]['reasonCode'], 'personal_context_missing')
                self.assertEqual(host.model_requests, 0)
                original = reopened.provider.retrieve('What is your GPA at Cedar University?', 'developer')
                reopened.revoke(selected.source_id, capability=reopened_cap)
                self.assertFalse(reopened.provider.validate_current(original))
            finally: host.close(); await host.drain()
            self.assertEqual(attempts, [])

    async def test_actual_txt_review_restore_and_personal_answers(self): await self.check('txt')

    @unittest.skipUnless(REAL, 'opt in with the pinned native document environment')
    async def test_actual_selectable_pdf_review_restore_and_personal_answers(self): await self.check('pdf')

    @unittest.skipUnless(REAL, 'opt in with the pinned native document environment')
    async def test_actual_plain_docx_review_restore_and_personal_answers(self): await self.check('docx')
