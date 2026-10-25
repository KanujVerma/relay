"""Safe attempt observations only; synthetic transport, no live account/model."""
import asyncio
from dataclasses import FrozenInstanceError, asdict, replace
import json
from pathlib import Path
import shutil
import tempfile
import threading
import unittest
from unittest.mock import patch

import httpx
from relay_spike.answer_diagnostics import AnswerDiagnosticSink, FILENAME, build_record, write_record
from relay_spike.oauth_answer_stream import OAuthAnswerStream, AnswerTransportError
from relay_spike.response_assembly import ResponseAssembler, ResponseProtocolError
from relay_spike.session_host import SessionHost
from relay_spike.generated_answer import CardError
from tests.test_answer_transport_lifetime import events, wire
from tests.test_session_host import start, speech, end, final

SECRET = 'synthetic-private-content-token-id-question-sentinel'
CARD = dict(lead='Explain the event loop and its callback queue.', points=['Keep blocking work off the loop.'],
    detail=None, assumptions=[], coverage=['current_request'], personal_fact_ids=[])


class AnswerAttemptDiagnosticsTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(); self.addCleanup(self.folder.cleanup)
        self.directory = Path(self.folder.name)/'Accounts'; self.directory.mkdir(mode=0o700)
        self.streams = []

    async def asyncTearDown(self):
        for stream in self.streams: await stream.aclose()

    def stream(self, response, *, deadline=15, sink=None, token=None):
        def handler(request):
            self.assertEqual(request.method, 'POST'); self.assertEqual(request.url.path, '/v1/responses')
            return response(request) if callable(response) else response
        value = OAuthAnswerStream(token_provider=token or (lambda: SECRET), deadline=deadline,
            client_factory=lambda **kw: httpx.AsyncClient(transport=httpx.MockTransport(handler), **kw),
            attempt_diagnostic_sink=sink)
        self.streams.append(value); return value

    def response(self, text=None):
        return httpx.Response(200, stream=httpx.ByteStream(wire(events(json.dumps(CARD) if text is None else text))),
            headers={'content-type': 'text/event-stream', 'x-private': SECRET})

    def latest(self):
        path = self.directory/FILENAME; data = path.read_bytes()
        self.assertLessEqual(len(data), 2048); self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        for private in (SECRET, 'https://', 'synthetic-question-marker', 'RuntimeError'):
            self.assertNotIn(private.encode(), data)
        return json.loads(data)

    async def host(self, stream, *, deadline=15):
        out = []; host = SessionHost(complete=stream.complete, emit=out.append, deadline=deadline)
        for value in (start(), speech(2), end(3), final(4, 'Explain event loops for a synthetic-question-marker.')):
            await host.handle(value)
        await host.drain(); return host, out

    async def test_http_provider_error_is_safe_and_writer_never_changes_primary_error(self):
        sink = AnswerDiagnosticSink(self.directory)
        stream = self.stream(httpx.Response(403, stream=httpx.ByteStream(json.dumps({'error': {'code': 'subscription_sharing_user_not_eligible',
            'param': 'model', 'message': SECRET}}).encode())), sink=sink)
        _, out = await self.host(stream)
        self.assertEqual(out[-1]['reasonCode'], 'answer_unavailable')
        value = self.latest(); self.assertEqual(value['transport']['httpStatus'], 403)
        self.assertEqual(value['transport']['providerCode'], 'subscription_sharing_user_not_eligible')
        self.assertEqual(value['transport']['paramCategory'], 'model')
        self.assertEqual(value['hostOutcome'], 'abstain_emitted'); self.assertEqual(value['validationCode'], 'not_run')
        def denied(*_): raise OSError(SECRET)
        stream = self.stream(httpx.Response(503, stream=httpx.ByteStream(json.dumps({'error': SECRET}).encode())), sink=AnswerDiagnosticSink(self.directory, writer=denied))
        _, out = await self.host(stream)
        self.assertEqual(out[-1]['reasonCode'], 'answer_unavailable')

    async def test_network_timeout_deadline_and_unknown_exception_categories_are_fixed(self):
        for response, expected, token in (
            (lambda req: (_ for _ in ()).throw(httpx.ReadTimeout(SECRET, request=req)), 'http_read_timeout', None),
            (self.response(), 'other', lambda: (_ for _ in ()).throw(RuntimeError(SECRET))),
        ):
            stream = self.stream(response, sink=AnswerDiagnosticSink(self.directory), token=token)
            await self.host(stream)
            self.assertEqual(self.latest()['transport']['failureKind'], expected)
        class Held(httpx.AsyncByteStream):
            async def __aiter__(self): await asyncio.Event().wait(); yield b''
        stream = self.stream(httpx.Response(200, stream=Held(), headers={'content-type': 'text/event-stream'}),
            deadline=.02, sink=AnswerDiagnosticSink(self.directory))
        await self.host(stream)
        self.assertEqual(self.latest()['transport']['failureKind'], 'deadline')

    async def test_host_deadline_cancelling_transport_is_distinct_from_inner_deadline(self):
        class Held(httpx.AsyncByteStream):
            async def __aiter__(self): await asyncio.Event().wait(); yield b''
        stream = self.stream(httpx.Response(200, stream=Held(), headers={'content-type': 'text/event-stream'}),
            sink=AnswerDiagnosticSink(self.directory))
        _, out = await self.host(stream, deadline=.02)
        self.assertEqual(out[-1]['reasonCode'], 'answer_timeout')
        value = self.latest(); self.assertEqual(value['hostOutcome'], 'host_timeout')
        self.assertEqual(value['transportOutcome'], 'cancelled')

    async def test_sse_provider_terminal_and_unknown_event_never_expose_raw_strings(self):
        for last, expected in (
            (dict(type='response.failed', response=dict(id=SECRET, status='failed', error=dict(
                code='subscription_sharing_usage_limit_exceeded', param='reasoning.effort', message=SECRET))), 'provider'),
            (dict(type=SECRET, data=SECRET), 'response_protocol'),
        ):
            rows = [dict(type='response.created', response=dict(id=SECRET, status='in_progress')), last]
            stream = self.stream(httpx.Response(200, stream=httpx.ByteStream(wire(rows)), headers={'content-type': 'text/event-stream'}),
                sink=AnswerDiagnosticSink(self.directory))
            await self.host(stream); value = self.latest()
            self.assertEqual(value['transport']['failureKind'], expected)
            if expected == 'provider':
                self.assertEqual(value['providerTerminal'], 'failed')
                self.assertEqual(value['transport']['providerCode'], 'subscription_sharing_usage_limit_exceeded')
                self.assertEqual(value['transport']['paramCategory'], 'reasoning')
            else: self.assertEqual(value['transport']['lastEvent'], 'other')

    async def test_failing_event_shape_is_captured_before_feed_without_reasoning_or_ids(self):
        rows = [dict(type='response.created', response=dict(id=SECRET, status='in_progress')),
            dict(type='response.output_item.added', output_index=0, item=dict(id=SECRET, type='reasoning', summary=[])),
            dict(type='response.output_item.done', output_index=0, item=dict(id=SECRET, type='reasoning', summary=[dict(text=SECRET)]))]
        original = ResponseAssembler.feed
        def reject_at_boundary(assembler, event):
            if event.get('type') == 'response.output_item.done': raise ResponseProtocolError('invalid_response_lifecycle')
            return original(assembler, event)
        stream = self.stream(httpx.Response(200, stream=httpx.ByteStream(wire(rows)), headers={'content-type': 'text/event-stream'}),
            sink=AnswerDiagnosticSink(self.directory))
        with patch.object(ResponseAssembler, 'feed', reject_at_boundary): await self.host(stream)
        value = self.latest()['transport']
        self.assertEqual(value['failureKind'], 'response_protocol')
        self.assertEqual(value['lastEvent'], 'response.output_item.done'); self.assertEqual(value['itemKind'], 'reasoning')
        self.assertFalse(value['itemStatusPresent']); self.assertEqual(value['itemStatus'], 'missing')
        with self.assertRaises(FrozenInstanceError): stream.last_timing.diagnostic.httpStatus = 201
        serialized = json.dumps(asdict(stream.last_timing))
        self.assertNotIn(SECRET, serialized); self.assertNotIn('_last_timing_owner', serialized)
        rows[-1] = dict(type='response.content_part.added', output_index=0, content_index=0,
            item_id=SECRET, part=dict(type='reasoning_text', text=SECRET))
        def reject_part(assembler, event):
            if event.get('type') == 'response.content_part.added': raise ResponseProtocolError('invalid_response_lifecycle')
            return original(assembler, event)
        stream = self.stream(httpx.Response(200, stream=httpx.ByteStream(wire(rows)), headers={'content-type': 'text/event-stream'}),
            sink=AnswerDiagnosticSink(self.directory))
        with patch.object(ResponseAssembler, 'feed', reject_part): await self.host(stream)
        self.assertEqual(self.latest()['transport']['partKind'], 'reasoning_text')
        self.assertEqual(self.latest()['transport']['lastEvent'], 'response.content_part.added')

    async def test_completed_transport_card_error_and_unknown_card_code_are_separate(self):
        stream = self.stream(self.response('{}'), sink=AnswerDiagnosticSink(self.directory))
        await self.host(stream)
        value = self.latest(); self.assertEqual(value['transportOutcome'], 'completed')
        self.assertEqual(value['validationCode'], 'card_schema'); self.assertEqual(value['hostOutcome'], 'abstain_emitted')
        stream = self.stream(self.response(), sink=AnswerDiagnosticSink(self.directory))
        with patch('relay_spike.session_host.parse_generated_card', side_effect=CardError(SECRET)): await self.host(stream)
        self.assertEqual(self.latest()['validationCode'], 'other')

    async def test_success_and_no_new_snapshot_cannot_relabel_previous_attempt(self):
        stream = self.stream(self.response(), sink=AnswerDiagnosticSink(self.directory))
        host, out = await self.host(stream)
        self.assertEqual(out[-1]['disposition'], 'answer')
        before = (self.directory/FILENAME).read_bytes(); self.assertEqual(self.latest()['validationCode'], 'passed')
        stream._spent = 60
        for value in (speech(5, activity=2, generation=3), end(6, activity=2, generation=3),
                      final(7, 'Explain asynchronous callbacks.', activity=2, generation=3)):
            await host.handle(value)
        await host.drain()
        self.assertEqual((self.directory/FILENAME).read_bytes(), before)

    async def test_snapshot_from_a_different_task_is_not_owned_by_the_caller(self):
        stream = self.stream(self.response())
        async def original():
            await stream.complete('synthetic question', 'synthetic instructions')
            self.assertIs(stream._owned_diagnostic_timing(None), stream.last_timing)
        await asyncio.create_task(original())
        self.assertIsNone(stream._owned_diagnostic_timing(None))

    async def test_owned_sink_cancel_joins_and_newer_attempt_cannot_be_overtaken(self):
        stream = self.stream(self.response()); await stream.complete('synthetic question', 'synthetic instructions')
        first = stream.last_timing; second = replace(first, request_index=first.request_index+1)
        entered = threading.Event(); release = threading.Event(); calls = []
        def held(directory, record):
            calls.append(record['attemptIndex']); entered.set()
            if not release.wait(2): raise AssertionError('bounded synthetic writer timeout')
            write_record(directory, record)
        sink = AnswerDiagnosticSink(self.directory, writer=held)
        task = asyncio.create_task(sink(first, host_outcome='answer_emitted', validation_code='passed'))
        try:
            self.assertTrue(await asyncio.to_thread(entered.wait, 1)); task.cancel(); task.cancel()
            newer = asyncio.create_task(sink(second, host_outcome='answer_emitted', validation_code='passed'))
            for _ in range(3): await asyncio.sleep(0)
            self.assertFalse(task.done()); self.assertFalse(newer.done()); self.assertEqual(calls, [1])
            task.cancel(); await asyncio.sleep(0); self.assertFalse(task.done())
            release.set()
            with self.assertRaises(asyncio.CancelledError): await task
            await newer; await sink(first, host_outcome='abstain_emitted', validation_code='other')
            self.assertEqual(calls, [1, 2]); self.assertEqual(self.latest()['attemptIndex'], 2)
        finally: release.set(); await asyncio.gather(task, return_exceptions=True)

    async def test_removed_root_is_not_recreated_and_constructor_is_inert(self):
        missing = Path(self.folder.name)/'missing'; sink = AnswerDiagnosticSink(missing)
        self.assertFalse(missing.exists())
        stream = self.stream(self.response()); await stream.complete('synthetic question', 'synthetic instructions')
        await sink(stream.last_timing, host_outcome='answer_emitted', validation_code='passed')
        self.assertFalse(missing.exists())
        from relay_spike import answer_diagnostics
        original = answer_diagnostics.storage.directory; removed = []
        def interleaved(path, *, create=False):
            original(path, create=create)
            if not removed: removed.append(True); shutil.rmtree(self.directory)
        with patch.object(answer_diagnostics.storage, 'directory', side_effect=interleaved):
            await AnswerDiagnosticSink(self.directory)(stream.last_timing, host_outcome='answer_emitted', validation_code='passed')
        self.assertFalse(self.directory.exists())

    async def test_factory_only_sink_and_exact_schema_privacy(self):
        from relay_spike.product_session import protected_answer_stream
        from relay_spike.account_bridge import AccountBootstrap
        from relay_spike.account_store import AccountCredentialStore
        from tests.test_account_store import grant, KEY
        import time
        store = AccountCredentialStore(self.directory, KEY)
        host = store.initialize(); identity = store.save_registration(grant(host, saved_at=time.time()))
        generation = '00000000-0000-0000-0000-000000000001'; store.select(identity, generation)
        boot = AccountBootstrap('oauth_session', KEY, self.directory, identity, generation)
        stream = protected_answer_stream('synthetic-model', bootstrap_reader=lambda *a, **kw: boot,
            client_factory=lambda **kw: httpx.AsyncClient(transport=httpx.MockTransport(lambda _: self.response()), **kw))
        self.streams.append(stream)
        self.assertIsInstance(stream.attempt_diagnostic_sink, AnswerDiagnosticSink)
        await self.host(stream); value = self.latest()
        self.assertEqual(value['hostOutcome'], 'answer_emitted')
        record = build_record(stream.last_timing, host_outcome='answer_emitted', validation_code='passed')
        record['unsafe'] = SECRET
        with self.assertRaises(ValueError): write_record(self.directory, record)
