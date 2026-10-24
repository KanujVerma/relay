"""Synthetic only: no credentials, external network, capture or permissions."""
import asyncio
import base64
import copy
import json
import pickle
import struct
import unittest
import zlib

from relay_spike.oauth_answer_stream import OAuthAnswerStream, AnswerTransportError
from relay_spike.visual_input import (
    VisualInputController, VisualInputError, VisualImageClaim,
    VerifiedImageCapability, VisualAttachmentPermit,
)
from tests.test_screen_context import png


MODEL = 'synthetic-image-model'


def completed_wire(text):
    item = {'id': 'm', 'type': 'message', 'status': 'completed',
            'content': [{'type': 'output_text', 'text': text}]}
    events = [
        {'type': 'response.created', 'response': {'id': 'r', 'status': 'in_progress'}},
        {'type': 'response.output_item.added', 'output_index': 0,
         'item': {'id': 'm', 'type': 'message', 'status': 'in_progress', 'content': []}},
        {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
        {'type': 'response.completed', 'response': {'id': 'r', 'status': 'completed', 'output': [item]}},
    ]
    return b''.join(b'data: ' + json.dumps(dict(event, sequence_number=i)).encode() + b'\n\n'
                    for i, event in enumerate(events))


def read_probe_pixels(body):
    """Independent oracle: read actual RGB pixels, not verifier's expected answer."""
    parts = body['input'][0]['content']
    image = base64.b64decode(parts[1]['image_url'].split(',', 1)[1], validate=True)
    width, height = struct.unpack('>II', image[16:24])
    offset, compressed = 8, bytearray()
    while offset < len(image):
        length = struct.unpack('>I', image[offset:offset+4])[0]
        if image[offset+4:offset+8] == b'IDAT':
            compressed.extend(image[offset+8:offset+8+length])
        offset += length + 12
    raw = zlib.decompress(compressed)
    palette = {(255, 0, 0): 'red', (0, 255, 0): 'green', (0, 0, 255): 'blue',
               (0, 255, 255): 'cyan', (255, 0, 255): 'magenta', (255, 255, 0): 'yellow'}
    row = raw[(height // 2) * (width * 3 + 1):]
    assert row[0] == 0
    colors = [palette[tuple(row[1 + (width * (2*i+1) // 12) * 3:4 + (width * (2*i+1) // 12) * 3])]
              for i in range(6)]
    return ','.join(colors), image


class ImagePort:
    """A synthetic selected producer; release preserves original owner validity."""
    def __init__(self, request, data=None):
        self.request, self.valid, self.releases = request, True, 0
        self.claim = VisualImageClaim(png=png() if data is None else data, width=1, height=1,
                                      image_digest='b' * 64, owner=object())

    def claim_for_request(self, request):
        return self.claim if request is self.request and self.valid else None

    def owns(self, claim, request):
        return self.valid and request is self.request and claim is self.claim

    def release_bytes(self, claim):
        self.releases += 1


class VisualInputTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        try:
            import httpx
        except ImportError:
            self.skipTest('optional HTTPX transport dependency')
        self.httpx = httpx
        self.now, self.token, self.current = 100., 'synthetic-bearer-one', True
        self.calls, self.answer, self.probe_correct = [], '{"lead":"answer"}', True
        self.catalog = {'models': [{'slug': MODEL, 'display_name': 'Synthetic', 'visibility': 'list'}]}
        self.next_error = None
        self.visual = VisualInputController(clock=lambda: self.now, receipt_lifetime=60)
        self.request = object()

        async def handler(request):
            body = json.loads(request.content) if request.content else None
            self.calls.append((request.method, str(request.url), request.headers.get('authorization'), body))
            if request.method == 'GET':
                return httpx.Response(200, stream=httpx.ByteStream(json.dumps(self.catalog).encode()))
            if self.next_error is not None:
                status, error = self.next_error
                return httpx.Response(status, stream=httpx.ByteStream(json.dumps(error).encode()))
            if body.get('instructions', '').startswith('Relay synthetic visual check'):
                expected, _ = read_probe_pixels(body)
                text = expected if self.probe_correct else 'wrong'
            else:
                text = self.answer
            return httpx.Response(200, stream=httpx.ByteStream(completed_wire(text)), headers={'content-type': 'text/event-stream'})

        self.handler = handler
        async def dispatch(request):
            # Keep failure/retirement injection live with the helper-owned client.
            return await self.handler(request)
        self.stream = OAuthAnswerStream(model=MODEL, token_provider=lambda: self.token,
            client_factory=lambda **kw: httpx.AsyncClient(transport=httpx.MockTransport(dispatch), **kw))
        self.addAsyncCleanup(self.stream.aclose)

    async def verified(self):
        consent = self.visual.begin_enable(MODEL)
        return await self.stream.verify_visual_input(self.visual, consent, is_current=lambda: self.current)

    def attachment(self, receipt, port=None, guard=None):
        port = ImagePort(self.request) if port is None else port
        permit = self.visual.prepare_attachment(receipt, request=self.request, image_port=port,
                                               is_current=guard or (lambda: self.current))
        return permit, port

    async def test_explicit_probe_uses_current_catalog_and_one_image_request_same_bearer(self):
        receipt = await self.verified()
        self.assertIsInstance(receipt, VerifiedImageCapability)
        self.assertEqual([c[0] for c in self.calls], ['GET', 'POST'])
        self.assertEqual([c[2] for c in self.calls], ['Bearer synthetic-bearer-one'] * 2)
        body = self.calls[1][3]
        expected, image = read_probe_pixels(body)
        self.assertNotIn(expected, json.dumps(body['input'][0]['content'][0]))
        self.assertLess(len(image), 4096)
        self.assertFalse(body['store']); self.assertTrue(body['stream'])
        self.assertEqual(body['input'][0]['content'][1]['detail'], 'high')
        self.assertNotIn('max_output_tokens', body)
        self.assertNotIn(self.token, repr(receipt))
        with self.assertRaises(TypeError): pickle.dumps(receipt)
        with self.assertRaises(TypeError): VerifiedImageCapability()
        with self.assertRaises(TypeError): VisualAttachmentPermit()

    async def test_unverified_or_copied_receipt_and_missing_real_guards_do_not_authorize(self):
        with self.assertRaises(VisualInputError): self.attachment(object())
        receipt = await self.verified()
        with self.assertRaises((TypeError, VisualInputError)): copy.copy(receipt)
        with self.assertRaises(VisualInputError):
            self.visual.prepare_attachment(receipt, request=self.request, image_port=ImagePort(self.request), is_current=None)
        self.assertEqual(len(self.calls), 2)

    async def test_wrong_probe_answer_never_issues_capability_and_never_retries(self):
        self.probe_correct = False
        with self.assertRaises(VisualInputError): await self.verified()
        self.assertEqual([c[0] for c in self.calls], ['GET', 'POST'])
        with self.assertRaises(VisualInputError): self.attachment(object())

    async def test_model_catalog_and_probe_cannot_cross_a_bearer_change(self):
        original = self.handler
        async def change_after_catalog(request):
            response = await original(request)
            if request.method == 'GET':
                self.token = 'synthetic-replacement-grant'
            return response
        self.handler = change_after_catalog
        with self.assertRaises(VisualInputError): await self.verified()
        self.assertEqual([c[0] for c in self.calls], ['GET'])

    async def test_probe_requires_completed_lifecycle_and_correct_bounded_result(self):
        original = self.handler
        for failed_wire in (b'data: {"type":"response.created","sequence_number":0,"response":{"id":"r","status":"in_progress"}}\n\n',
                            completed_wire('x' * 129),
                            completed_wire('wrong').replace(b'"status": "completed"', b'"status": "incomplete"')):
            with self.subTest(size=len(failed_wire)):
                self.calls = []
                async def broken(request):
                    if request.method == 'GET': return await original(request)
                    self.calls.append(('POST', str(request.url), None, None))
                    return self.httpx.Response(200, stream=self.httpx.ByteStream(failed_wire),
                                               headers={'content-type': 'text/event-stream'})
                self.handler = broken
                with self.assertRaises((VisualInputError, AnswerTransportError)): await self.verified()
                self.assertEqual([c[0] for c in self.calls], ['GET', 'POST'])

    async def test_catalog_admission_duplicate_json_and_size_fail_closed(self):
        for data in (b'{"models":[],"models":[]}', b'{"detail":"synthetic private diagnostic"}', b'x' * 1048577):
            with self.subTest(size=len(data)):
                self.calls = []
                async def bad_catalog(request):
                    self.calls.append((request.method, str(request.url), None, None))
                    return self.httpx.Response(200, stream=self.httpx.ByteStream(data))
                self.handler = bad_catalog
                with self.assertRaises((VisualInputError, AnswerTransportError)): await self.verified()
                self.assertEqual([c[0] for c in self.calls], ['GET'])

    async def test_catalog_metadata_has_a_separate_bounded_budget_from_error_bodies(self):
        self.catalog['models'][0]['description'] = 's' * 70000
        self.assertIsInstance(await self.verified(), VerifiedImageCapability)
        self.assertEqual([c[0] for c in self.calls], ['GET', 'POST'])

    async def test_hidden_missing_duplicate_or_malformed_catalog_never_probes(self):
        for catalog in ({'models': []}, {'models': [{'slug': MODEL, 'visibility': 'hide'}]},
                        {'models': [{'slug': MODEL, 'visibility': 'list'}] * 2}, {'models': True}):
            with self.subTest(catalog=catalog):
                self.catalog, self.calls = catalog, []
                with self.assertRaises((VisualInputError, AnswerTransportError)): await self.verified()
                self.assertEqual([c[0] for c in self.calls], ['GET'])

    async def test_success_keeps_one_use_publication_evidence_but_releases_png(self):
        receipt = await self.verified()
        permit, port = self.attachment(receipt)
        original = bytes(port.claim.png)
        self.assertFalse(permit.used_image)
        self.assertEqual(await self.stream.complete('question', 'instructions', visual_attachment=permit), self.answer)
        body = self.calls[-1][3]
        self.assertEqual(body['input'][0]['content'][0], {'type': 'input_text', 'text': 'question'})
        self.assertEqual(base64.b64decode(body['input'][0]['content'][1]['image_url'].split(',')[1]), original)
        self.assertTrue(permit.used_image)
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertEqual(port.releases, 1)
        self.assertTrue(permit.validate_for_publication())
        self.assertTrue(await self.stream.validate_visual_publication(permit))
        with self.assertRaises(AttributeError): permit.used_image = False
        before = len(self.calls)
        with self.assertRaises((VisualInputError, AnswerTransportError)):
            await self.stream.complete('again', 'instructions', visual_attachment=permit)
        self.assertEqual(len(self.calls), before)

    async def test_changed_actual_bearer_including_refresh_retires_permit_before_send(self):
        receipt = await self.verified()
        permit, port = self.attachment(receipt)
        self.token = 'synthetic-refreshed-bearer'
        with self.assertRaises((VisualInputError, AnswerTransportError)):
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertFalse(permit.validate_for_publication())
        with self.assertRaises(VisualInputError): self.attachment(receipt)

    async def test_model_effort_endpoint_or_expiry_changes_reject_the_receipt(self):
        for attribute, value in (('model', 'other-model'), ('effort', 'low'), ('_endpoint', 'https://example.invalid/responses')):
            with self.subTest(attribute=attribute):
                receipt = await self.verified(); permit, port = self.attachment(receipt)
                original = getattr(self.stream, attribute); setattr(self.stream, attribute, value)
                before = len(self.calls)
                with self.assertRaises((VisualInputError, AnswerTransportError)):
                    await self.stream.complete('question', 'instructions', visual_attachment=permit)
                self.assertEqual(len(self.calls), before)
                self.assertEqual(bytes(port.claim.png), b'')
                setattr(self.stream, attribute, original)
        receipt = await self.verified(); self.now += 61
        with self.assertRaises(VisualInputError): self.attachment(receipt)

    async def test_source_request_consent_retirement_and_new_permit_clear_old_bytes(self):
        receipt = await self.verified(); first, port = self.attachment(receipt)
        second, _ = self.attachment(receipt)
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertFalse(first.validate_for_publication())
        self.visual.disable()
        self.assertFalse(second.validate_for_publication())
        receipt = await self.verified(); permit, port = self.attachment(receipt)
        port.valid = False
        with self.assertRaises((VisualInputError, AnswerTransportError)):
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertFalse(permit.validate_for_publication())

    async def test_request_guard_rechecks_after_awaited_auth(self):
        receipt = await self.verified(); permit, port = self.attachment(receipt)
        def token_after_change():
            self.current = False
            return self.token
        self.stream._token_provider = token_after_change
        with self.assertRaises((VisualInputError, AnswerTransportError)):
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.assertEqual(len(self.calls), 2)
        self.assertEqual(bytes(port.claim.png), b'')

    async def test_producer_callback_cannot_issue_after_consent_retirement(self):
        receipt = await self.verified()
        port = ImagePort(self.request)
        original = port.claim_for_request
        def retire_while_claiming(request):
            claim = original(request)
            self.visual.disable()
            return claim
        port.claim_for_request = retire_while_claiming
        with self.assertRaises(VisualInputError): self.attachment(receipt, port)
        self.assertEqual(bytes(port.claim.png), b'')

    async def test_publication_observes_late_bearer_or_source_change(self):
        receipt = await self.verified(); permit, _ = self.attachment(receipt)
        await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.token = 'synthetic-different-account-bearer'
        self.assertFalse(await self.stream.validate_visual_publication(permit))
        self.assertTrue(permit.used_image)
        self.assertFalse(permit.validate_for_publication())

    async def test_closed_transport_never_reads_credentials_or_validates_old_image_permit(self):
        receipt = await self.verified(); permit, _ = self.attachment(receipt)
        await self.stream.complete('question', 'instructions', visual_attachment=permit)
        reads = []
        async def token():
            reads.append(True)
            return self.token
        self.stream._token = token
        await self.stream.aclose()
        self.assertFalse(await self.stream.validate_visual_publication(permit))
        self.assertEqual(reads, [])
        self.assertFalse(permit.validate_for_publication())

    async def test_close_during_bearer_recheck_withholds_original_image_permit(self):
        receipt = await self.verified(); permit, _ = self.attachment(receipt)
        await self.stream.complete('question', 'instructions', visual_attachment=permit)
        entered, release = asyncio.Event(), asyncio.Event()
        async def token():
            entered.set(); await release.wait(); return self.token
        self.stream._token = token
        task = asyncio.create_task(self.stream.validate_visual_publication(permit))
        await asyncio.wait_for(entered.wait(), 1)
        await self.stream.aclose(); release.set()
        self.assertFalse(await task)
        self.assertFalse(permit.validate_for_publication())

    async def test_source_changes_during_sse_veto_completion_and_release_bytes(self):
        receipt = await self.verified(); permit, port = self.attachment(receipt)
        original = self.handler
        async def changed(request):
            response = await original(request)
            self.current = False
            return response
        self.handler = changed
        with self.assertRaises((VisualInputError, AnswerTransportError)):
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.assertEqual(len(self.calls), 3)
        self.assertFalse(permit.used_image)
        self.assertEqual(bytes(port.claim.png), b'')

    async def test_completed_image_still_needs_original_producer_and_consent_at_publication(self):
        for change in ('producer', 'consent', 'expiry'):
            with self.subTest(change=change):
                receipt = await self.verified(); permit, port = self.attachment(receipt)
                await self.stream.complete('question', 'instructions', visual_attachment=permit)
                self.assertTrue(permit.validate_for_publication())
                if change == 'producer': port.valid = False
                elif change == 'consent': self.visual.disable()
                else: self.now += 61
                self.assertFalse(permit.validate_for_publication())
                self.assertTrue(permit.used_image)
                self.assertEqual(bytes(port.claim.png), b'')

    async def test_bad_or_mutated_png_cannot_bypass_exact_bounded_validator(self):
        receipt = await self.verified()
        for data in (b'not png', png()[:-1], b'x' * (2 * 1024 * 1024 + 1)):
            with self.subTest(size=len(data)):
                port = ImagePort(self.request, data)
                with self.assertRaises(VisualInputError): self.attachment(receipt, port)
                self.assertEqual(bytes(port.claim.png), b'')
        permit, port = self.attachment(receipt)
        port.claim.png[-1] ^= 1
        with self.assertRaises((VisualInputError, AnswerTransportError)):
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.assertEqual(len(self.calls), 2)

    async def test_capability_error_is_sanitized_retires_and_does_not_text_retry(self):
        receipt = await self.verified(); permit, port = self.attachment(receipt)
        self.next_error = (400, {'error': {'code': 'subscription_sharing_unsupported_capability',
            'param': 'input[0].content[1].image_url', 'message': 'private pixels synthetic-bearer-one'}})
        with self.assertRaises(AnswerTransportError) as caught:
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        error = caught.exception
        self.assertEqual(error.status, 400)
        self.assertEqual(error.provider_code, 'subscription_sharing_unsupported_capability')
        self.assertEqual(error.param_category, 'input')
        self.assertNotIn('private', str(error)); self.assertNotIn(self.token, repr(error))
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertFalse(permit.used_image)
        with self.assertRaises(VisualInputError): self.attachment(receipt)

    async def test_top_level_sse_error_retains_only_allowlisted_diagnostics(self):
        receipt = await self.verified(); permit, port = self.attachment(receipt)
        event = {'type': 'error', 'sequence_number': 0,
                 'code': 'subscription_sharing_unsupported_capability',
                 'param': 'input[0].content[1]', 'message': 'synthetic-private-diagnostic'}
        async def failed(request):
            self.calls.append(('POST', str(request.url), None, None))
            return self.httpx.Response(200, stream=self.httpx.ByteStream(b'data: ' + json.dumps(event).encode() + b'\n\n'),
                                       headers={'content-type': 'text/event-stream'})
        self.handler = failed
        with self.assertRaises(AnswerTransportError) as caught:
            await self.stream.complete('question', 'instructions', visual_attachment=permit)
        self.assertEqual(caught.exception.provider_code, 'subscription_sharing_unsupported_capability')
        self.assertEqual(caught.exception.param_category, 'input')
        self.assertNotIn('diagnostic', repr(caught.exception))
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertEqual(len(self.calls), 3)

    async def test_arbitrary_image_dictionary_never_reaches_auth_or_http(self):
        async def disallowed():
            raise AssertionError('must not reach credentials')
        self.stream._token = disallowed
        with self.assertRaises(VisualInputError):
            await self.stream.complete('question', 'instructions', visual_attachment={'type': 'input_image', 'authorized': True})
        self.assertEqual(self.calls, [])

    async def test_text_completion_stays_text_only_without_consent_or_probe(self):
        self.assertEqual(await self.stream.complete('question', 'instructions'), self.answer)
        self.assertEqual([c[0] for c in self.calls], ['POST'])
        self.assertEqual(self.calls[0][3]['input'], [{'role': 'user', 'content': 'question'}])

    async def test_cancellation_retires_image_bytes_and_never_retries(self):
        receipt = await self.verified(); permit, port = self.attachment(receipt)
        entered = asyncio.Event()
        httpx = self.httpx
        class Stalled(httpx.AsyncByteStream):
            async def __aiter__(self):
                entered.set()
                await asyncio.Event().wait()
                yield b''
        async def stalled(request):
            self.calls.append(('POST', str(request.url), None, None))
            return httpx.Response(200, stream=Stalled(), headers={'content-type': 'text/event-stream'})
        self.handler = stalled
        task = asyncio.create_task(self.stream.complete('question', 'instructions', visual_attachment=permit))
        await asyncio.wait_for(entered.wait(), 1)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(bytes(port.claim.png), b'')
        self.assertFalse(permit.validate_for_publication())
