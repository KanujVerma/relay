"""Controller-owned issue29 acceptance. Worker must not edit this file or fixtures.

The opt-in integration command MUST execute with no skipped tests:
RELAY_DOCUMENT_INTEGRATION=1 python -m unittest discover -s tests -p test_document_acceptance.py -v
"""
from __future__ import annotations

from contextlib import ExitStack
from dataclasses import replace
from hashlib import sha256
from io import BytesIO
import json
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile, ZIP_DEFLATED

from relay_spike.document_conversion import convert_document, stage_converted
from relay_spike.personal_brain import BrainStore, BrainError
from relay_spike.resume_candidates import ReviewGateway

ROOT = Path(__file__).parent / 'fixtures' / 'documents'
GOLDEN = json.loads((ROOT / 'manifest.json').read_text())
INTEGRATION = os.environ.get('RELAY_DOCUMENT_INTEGRATION') == '1'
WHEN = '2026-10-22T12:00:00-05:00'
BAD = {'unsupported', 'invalid', 'unavailable'}


class DocumentAcceptance(unittest.TestCase):
    def test_fixture_bytes_match_controller_manifest(self):
        for name, digest in GOLDEN['files'].items():
            with self.subTest(name=name):
                self.assertEqual(sha256((ROOT / name).read_bytes()).hexdigest(), digest)

    def test_bytes_only_closed_format_backend_and_size_boundary(self):
        for data in ('https://example.invalid/resume.pdf', '/tmp/resume.pdf',
                     BytesIO(b'not-selected'), None, b'', b'x' * (2*1024*1024 + 1)):
            with self.subTest(kind=type(data).__name__):
                result = convert_document(data, file_type='pdf')
                self.assertIn(result.status, BAD)
                self.assertEqual(result.text, '')
                self.assertEqual(result.segments, ())
        for kind in ('html', 'https://example.invalid/r.pdf', '../docx'):
            result = convert_document(b'example', file_type=kind)
            self.assertIn(result.status, BAD)
            self.assertEqual(result.text, '')
        result = convert_document(b'example', file_type='pdf', backend='remote')
        self.assertIn(result.status, BAD)
        self.assertEqual(result.text, '')

    def test_raw_digest_keyword_rejects_bad_digest_before_source_write(self):
        with BrainStore() as brain:
            host = object(); gateway = ReviewGateway(brain, host_capability=host)
            with self.assertRaises((BrainError, ValueError)):
                gateway.select_source('I built a synthetic report.', observed_at=WHEN,
                    capability=host, raw_document_sha256='not-a-sha256')
            self.assertEqual(brain.db.execute('SELECT COUNT(*) FROM source').fetchone()[0], 0)


@unittest.skipUnless(INTEGRATION, 'run with RELAY_DOCUMENT_INTEGRATION=1 and pinned optional dependencies')
class RealDocumentAcceptance(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        temp = self.stack.enter_context(tempfile.TemporaryDirectory())
        self.stack.enter_context(patch.dict(os.environ, {
            'HF_HOME':temp+'/hf', 'HUGGINGFACE_HUB_CACHE':temp+'/hf/hub',
            'TORCH_HOME':temp+'/torch', 'XDG_CACHE_HOME':temp+'/cache',
            'HF_HUB_OFFLINE':'1', 'TRANSFORMERS_OFFLINE':'1',
        }))
        self.attempts = []
        def no_network(*args, **kwargs):
            self.attempts.append(True)
            raise AssertionError('network forbidden during document conversion')
        for target in ('socket.socket.connect', 'socket.socket.connect_ex',
                       'socket.create_connection', 'socket.getaddrinfo', 'socket.gethostbyname'):
            self.stack.enter_context(patch(target, side_effect=no_network))
        self.addCleanup(lambda: self.assertEqual(self.attempts, []))

    def convert(self, name, *, backend='native'):
        result = convert_document((ROOT/name).read_bytes(),
            file_type=name.rsplit('.',1)[1], backend=backend)
        self.assertEqual(result.document_sha256, GOLDEN['files'][name])
        self.assertEqual(result.text_sha256, sha256(result.text.encode('utf-8')).hexdigest())
        return result

    def assert_locators(self, result, expected, locator):
        self.assertEqual(result.status, 'converted', result.reason)
        for segment in result.segments:
            self.assertEqual(result.text[segment.start:segment.end], segment.text)
            self.assertGreaterEqual(segment.start, 0)
            self.assertGreater(segment.end, segment.start)
            self.assertEqual(getattr(segment, 'paragraph' if locator=='page' else 'page'), None)
        for claim in expected:
            matching = [s for s in result.segments if claim['text'] in s.text]
            self.assertTrue(matching, claim['text'])
            self.assertTrue(any(getattr(s, locator)==claim[locator] for s in matching))

    def test_native_pdf_exact_page_locations(self):
        self.assert_locators(self.convert('synthetic-two-page.pdf'), GOLDEN['pdf_claims'], 'page')

    def test_native_docx_unicode_exact_paragraph_locations(self):
        self.assert_locators(self.convert('synthetic-unicode.docx'), GOLDEN['docx_claims'], 'paragraph')

    def test_duplicate_docx_keeps_distinct_paragraphs(self):
        result = self.convert('synthetic-duplicate.docx')
        self.assert_locators(result, GOLDEN['duplicate_claims'], 'paragraph')
        self.assertEqual([s.paragraph for s in result.segments
            if s.text == 'I implemented a synthetic SQL reporting service.'], [2,3])

    def test_real_vendor_comparators_recover_text_without_fabricated_locations(self):
        for backend, name, expected in (
            ('markitdown','synthetic-two-page.pdf',GOLDEN['pdf_claims']),
            ('markitdown','synthetic-unicode.docx',GOLDEN['docx_claims']),
            ('docling','synthetic-unicode.docx',GOLDEN['docx_claims']),
        ):
            with self.subTest(backend=backend,name=name):
                result = self.convert(name, backend=backend)
                self.assertEqual(result.status, 'needs_review', result.reason)
                folded = ' '.join(result.text.split())
                for item in expected:
                    self.assertIn(item['text'], folded)
                self.assertFalse(any(s.page is not None or s.paragraph is not None for s in result.segments))
                with BrainStore() as brain:
                    host=object(); gateway=ReviewGateway(brain,host_capability=host)
                    with self.assertRaises((BrainError,ValueError)):
                        stage_converted(result,gateway,observed_at=WHEN,capability=host)
                    self.assertEqual(brain.db.execute('SELECT COUNT(*) FROM source').fetchone()[0],0)

    def test_corrupt_encrypted_blank_are_unavailable_without_content(self):
        for name in ('synthetic-corrupt.pdf','synthetic-corrupt.docx',
                     'synthetic-encrypted.pdf','synthetic-blank.pdf'):
            for backend in ('native','markitdown','docling'):
                with self.subTest(name=name,backend=backend):
                    result=self.convert(name,backend=backend)
                    self.assertIn(result.status,BAD)
                    self.assertEqual(result.text,'')
                    self.assertEqual(result.segments,())

    def test_docx_archive_bounds_external_relationships_and_tables_fail_closed(self):
        original=(ROOT/'synthetic-unicode.docx').read_bytes()
        def rewrite(replacement=None, extra=None):
            out=BytesIO()
            with ZipFile(BytesIO(original)) as src, ZipFile(out,'w',ZIP_DEFLATED) as dst:
                for name in src.namelist():
                    dst.writestr(name,replacement[1] if replacement and name==replacement[0] else src.read(name))
                for name,data in (extra or []): dst.writestr(name,data)
            return out.getvalue()
        rel=b'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="x" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" TargetMode="External" Target="https://example.invalid/private"/></Relationships>'
        with ZipFile(BytesIO(original)) as src: xml=src.read('word/document.xml')
        cases=[rewrite(extra=[('word/bomb.bin',b'x'*(8*1024*1024+1))]),
               rewrite(extra=[('extra/'+str(n),b'x') for n in range(257)]),
               rewrite(replacement=('word/_rels/document.xml.rels',rel)),
               rewrite(replacement=('word/document.xml',xml.replace(b'</w:body>',b'<w:tbl/></w:body>')))]
        for value in cases:
            with self.subTest(size=len(value)):
                result=convert_document(value,file_type='docx')
                self.assertIn(result.status,{'invalid','unsupported'})
                self.assertEqual(result.text,'')

    def test_limits_on_extracted_text_and_pdf_pages(self):
        original=(ROOT/'synthetic-unicode.docx').read_bytes();out=BytesIO()
        with ZipFile(BytesIO(original)) as src, ZipFile(out,'w',ZIP_DEFLATED) as dst:
            for name in src.namelist():
                data=src.read(name)
                if name=='word/document.xml':
                    data=data.replace(b'I implemented a synthetic SQL reporting service.',b'I implemented '+b'x'*30001)
                dst.writestr(name,data)
        result=convert_document(out.getvalue(),file_type='docx')
        self.assertIn(result.status,{'invalid','unsupported'})
        self.assertEqual(result.text,'')
        result=convert_document((ROOT/'synthetic-too-many-pages.pdf').read_bytes(),file_type='pdf')
        self.assertIn(result.status,{'invalid','unsupported'})
        self.assertEqual(result.text,'')

    def test_original_byte_revision_is_distinct_from_derived_text_revision(self):
        original=(ROOT/'synthetic-two-page.pdf').read_bytes()
        one=convert_document(original,file_type='pdf')
        two=convert_document(original+b'\n% synthetic byte revision\n',file_type='pdf')
        self.assertEqual(one.status,'converted');self.assertEqual(two.status,'converted')
        self.assertNotEqual(one.document_sha256,two.document_sha256)
        self.assertEqual(one.text_sha256,two.text_sha256)

    def test_existing_review_authority_hashes_and_revocation_are_preserved(self):
        result=self.convert('synthetic-unicode.docx')
        with BrainStore() as brain:
            host=object();gateway=ReviewGateway(brain,host_capability=host)
            with self.assertRaises((BrainError,ValueError)):
                stage_converted(result,gateway,observed_at=WHEN,capability=object())
            self.assertEqual(brain.db.execute('SELECT COUNT(*) FROM source').fetchone()[0],0)
            for bad in (replace(result,text='tampered'),replace(result,segments=())):
                with self.assertRaises((BrainError,ValueError)):
                    stage_converted(bad,gateway,observed_at=WHEN,capability=host)
            self.assertEqual(brain.db.execute('SELECT COUNT(*) FROM source').fetchone()[0],0)
            source,cards=stage_converted(result,gateway,observed_at=WHEN,capability=host)
            self.assertEqual(len(cards),5)
            self.assertEqual(brain.verified_claims(),())
            row=brain.db.execute('SELECT external_ref,checksum FROM source WHERE id=?',(source,)).fetchone()
            self.assertEqual(row['external_ref'],'document-sha256:'+result.document_sha256)
            self.assertEqual(row['checksum'],result.text_sha256)
            for card in cards:
                self.assertEqual(result.text[card.span_start:card.span_end],card.snippet)
                self.assertTrue(any(s.start<=card.span_start<card.span_end<=s.end for s in result.segments))
            gateway.decide(cards[0],decision='approve',capability=host,
                approved_actor='self',claim_key='synthetic.sql')
            self.assertEqual(len(brain.verified_claims(actor='self')),1)
            gateway.revoke_selected_source(source,capability=host)
            self.assertEqual(brain.verified_claims(),())
            self.assertEqual(brain.db.execute('SELECT external_ref FROM source WHERE id=?',(source,)).fetchone()[0],None)
            self.assertEqual(brain.db.execute('SELECT COUNT(*) FROM candidate_evidence').fetchone()[0],0)


if __name__=='__main__':unittest.main()
