"""Synthetic only: request lifetime/timing, no account or external network."""
import asyncio
from dataclasses import FrozenInstanceError, asdict
import json
import unittest

from relay_spike.oauth_answer_stream import OAuthAnswerStream, AnswerTransportError


def events(text='a bounded answer'):
    item = {'id': 'm', 'type': 'message', 'status': 'completed',
            'content': [{'type': 'output_text', 'text': text}]}
    return [
        {'type': 'response.created', 'response': {'id': 'r', 'status': 'in_progress'}},
        {'type': 'response.output_item.added', 'output_index': 0,
         'item': {'id': 'm', 'type': 'message', 'status': 'in_progress', 'content': []}},
        {'type': 'response.content_part.added', 'output_index': 0, 'content_index': 0,
         'item_id': 'm', 'part': {'type': 'output_text', 'text': ''}},
        {'type': 'response.output_text.delta', 'output_index': 0, 'content_index': 0,
         'item_id': 'm', 'delta': text},
        {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
        {'type': 'response.completed', 'response': {'id': 'r', 'status': 'completed', 'output': [item]}},
    ]


def wire(rows):
    return b''.join(b'data: ' + json.dumps(dict(row, sequence_number=i)).encode() + b'\n\n'
                    for i, row in enumerate(rows))


class ClientReuseBehaviorTests(unittest.IsolatedAsyncioTestCase):
    async def test_two_complete_requests_construct_one_client(self):
        try:
            import httpx
        except ImportError:
            self.skipTest('optional HTTPX transport dependency')
        clients = []
        def factory(**options):
            client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _:
                httpx.Response(200, headers={'content-type': 'text/event-stream'},
                               stream=httpx.ByteStream(wire(events())))), **options)
            clients.append(client)
            return client
        stream = OAuthAnswerStream(token_provider=lambda: 'synthetic', client_factory=factory)
        try:
            await stream.complete('question', 'instructions')
            await stream.complete('question', 'instructions')
            self.assertEqual(len(clients), 1)
        finally:
            for client in clients: await client.aclose()


class AnswerTransportLifetimeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        try:
            import httpx
        except ImportError:
            self.skipTest('optional HTTPX transport dependency')
        self.httpx = httpx
        self.clients, self.requests = [], []
        self.token = 'synthetic-one'
        self.rows = events()
        self.clock = 10.0

        async def handler(request):
            self.requests.append(request)
            self.clock += .010
            return httpx.Response(200, headers={'content-type': 'text/event-stream',
                                               'set-cookie': 'must_not_persist=synthetic'},
                                  stream=httpx.ByteStream(wire(self.rows)))
        self.handler = handler

        def factory(**options):
            self.clock += .020
            client = httpx.AsyncClient(transport=httpx.MockTransport(self.handler), **options)
            self.clients.append(client)
            return client
        self.stream = OAuthAnswerStream(token_provider=lambda: self.token,
            client_factory=factory, clock=lambda: self.clock)
        self.addAsyncCleanup(self.stream.aclose)

    async def test_lazy_single_client_fresh_bearer_no_cookies_and_awaited_close(self):
        self.assertEqual(self.clients, [])
        self.assertIsNone(self.stream.last_timing)
        self.assertEqual(await self.stream.complete('question', 'instructions'), 'a bounded answer')
        self.token = 'synthetic-two'
        await self.stream.complete('new question', 'instructions')
        self.assertEqual(len(self.clients), 1)
        self.assertFalse(self.clients[0].is_closed)
        self.assertEqual([r.headers['authorization'] for r in self.requests],
                         ['Bearer synthetic-one', 'Bearer synthetic-two'])
        self.assertTrue(all('cookie' not in r.headers for r in self.requests))
        self.assertNotIn('authorization', self.clients[0].headers)
        await self.stream.aclose()
        await self.stream.aclose()
        self.assertTrue(self.clients[0].is_closed)
        with self.assertRaisesRegex(AnswerTransportError, 'request_closed'):
            await self.stream.complete('question', 'instructions')
        self.assertEqual(len(self.requests), 2)

    async def test_complete_timing_is_immutable_numeric_and_content_free(self):
        await self.stream.complete('private synthetic question', 'private synthetic instructions')
        timing = self.stream.last_timing
        self.assertEqual(timing.outcome, 'completed')
        self.assertEqual(timing.request_index, 1)
        self.assertAlmostEqual(timing.token_ready_ms, 0)
        self.assertAlmostEqual(timing.client_ready_ms, 20)
        self.assertAlmostEqual(timing.request_started_ms, 20)
        self.assertAlmostEqual(timing.response_headers_ms, 30)
        self.assertAlmostEqual(timing.first_text_ms, 30)
        self.assertAlmostEqual(timing.response_completed_ms, 30)
        self.assertAlmostEqual(timing.finished_ms, 30)
        self.assertEqual(timing.output_bytes, len('a bounded answer'.encode()))
        with self.assertRaises(FrozenInstanceError):
            timing.outcome = 'failed'
        recorded = json.dumps(asdict(timing))
        for private in ('private', 'synthetic', 'bounded answer', 'instructions', 'Bearer'):
            self.assertNotIn(private, recorded)
        self.assertIsNone(timing.first_useful_verified_ms)

    async def test_valid_partial_text_is_timed_but_truncated_stream_is_failed(self):
        self.rows = events()[:4]
        with self.assertRaises(AnswerTransportError):
            await self.stream.complete('question', 'instructions')
        timing = self.stream.last_timing
        self.assertEqual(timing.outcome, 'failed')
        self.assertIsNotNone(timing.first_text_ms)
        self.assertIsNone(timing.response_completed_ms)

    async def test_malformed_delta_never_acquires_a_first_text_timestamp(self):
        self.rows = events()[:4]
        self.rows[-1]['item_id'] = 'wrong-message'
        with self.assertRaises(AnswerTransportError):
            await self.stream.complete('question', 'instructions')
        self.assertEqual(self.stream.last_timing.outcome, 'failed')
        self.assertIsNone(self.stream.last_timing.first_text_ms)
        self.assertIsNone(self.stream.last_timing.response_completed_ms)

    async def test_terminal_failed_after_valid_text_never_reports_success(self):
        self.rows = events()[:4] + [{'type': 'response.failed', 'response':
            {'id': 'r', 'status': 'failed', 'error': {'message': 'private provider detail'}}}]
        with self.assertRaises(AnswerTransportError):
            await self.stream.complete('question', 'instructions')
        self.assertEqual(self.stream.last_timing.outcome, 'failed')
        self.assertIsNotNone(self.stream.last_timing.first_text_ms)
        self.assertIsNone(self.stream.last_timing.response_completed_ms)
        self.assertNotIn('private', repr(self.stream.last_timing))

    async def test_close_cancels_and_joins_owned_active_request_before_client_close(self):
        entered, released, response_closed = asyncio.Event(), asyncio.Event(), asyncio.Event()
        httpx = self.httpx

        class HeldBody(httpx.AsyncByteStream):
            async def __aiter__(self):
                entered.set()
                try:
                    await asyncio.Event().wait()
                    yield b''
                finally:
                    released.set()
            async def aclose(self):
                response_closed.set()

        async def handler(request):
            self.requests.append(request)
            return httpx.Response(200, headers={'content-type': 'text/event-stream'}, stream=HeldBody())
        self.handler = handler
        task = asyncio.create_task(self.stream.complete('question', 'instructions'))
        await asyncio.wait_for(entered.wait(), 1)
        await self.stream.aclose()
        self.assertTrue(task.done())
        self.assertTrue(task.cancelled())
        self.assertTrue(released.is_set())
        self.assertTrue(response_closed.is_set())
        self.assertTrue(self.clients[0].is_closed)
        self.assertEqual(self.stream.last_timing.outcome, 'cancelled')

    async def test_busy_attempt_does_not_replace_owned_timing_or_spend_budget(self):
        entered = asyncio.Event()
        async def handler(_):
            entered.set()
            await asyncio.Event().wait()
        self.handler = handler
        task = asyncio.create_task(self.stream.complete('question', 'instructions'))
        await asyncio.wait_for(entered.wait(), 1)
        with self.assertRaisesRegex(AnswerTransportError, 'request_busy'):
            await self.stream.complete('other', 'instructions')
        self.assertEqual(self.stream._spent, 1)
        self.assertIsNone(self.stream.last_timing)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        self.assertEqual(self.stream.last_timing.request_index, 1)

    async def test_warm_client_setup_is_not_charged_again(self):
        await self.stream.complete('question', 'instructions')
        cold = self.stream.last_timing
        await self.stream.complete('question', 'instructions')
        warm = self.stream.last_timing
        self.assertAlmostEqual(cold.client_ready_ms - cold.token_ready_ms, 20)
        self.assertAlmostEqual(warm.client_ready_ms - warm.token_ready_ms, 0)
        self.assertEqual(warm.request_index, 2)

    async def test_deadline_closes_response_and_records_failed_attempt_without_retry(self):
        entered, closed = asyncio.Event(), asyncio.Event()
        httpx = self.httpx
        class Stalled(httpx.AsyncByteStream):
            async def __aiter__(self):
                entered.set()
                await asyncio.Event().wait()
                yield b''
            async def aclose(self): closed.set()
        async def handler(request):
            self.requests.append(request)
            return httpx.Response(200, headers={'content-type': 'text/event-stream'}, stream=Stalled())
        self.handler = handler
        self.stream.deadline = .02
        with self.assertRaises(AnswerTransportError):
            await self.stream.complete('question', 'instructions')
        self.assertTrue(entered.is_set())
        self.assertTrue(closed.is_set())
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(self.stream.last_timing.outcome, 'failed')
        self.assertIsNone(self.stream.last_timing.response_completed_ms)

    async def test_request_budget_stays_bounded_with_reused_client(self):
        for _ in range(10): await self.stream.complete('question', 'instructions')
        timing = self.stream.last_timing
        with self.assertRaisesRegex(AnswerTransportError, 'request_budget'):
            await self.stream.complete('question', 'instructions')
        self.assertIs(self.stream.last_timing, timing)
        self.assertEqual(len(self.requests), 10)
        self.assertEqual(len(self.clients), 1)

    async def test_closed_before_first_use_is_inert(self):
        await self.stream.aclose()
        with self.assertRaisesRegex(AnswerTransportError, 'request_closed'):
            await self.stream.complete('question', 'instructions')
        self.assertEqual(self.clients, [])
        self.assertEqual(self.requests, [])
        self.assertIsNone(self.stream.last_timing)


class OwnedClientSocketTests(unittest.IsolatedAsyncioTestCase):
    async def test_actual_close_joins_stalled_socket_and_never_reuses_retired_helper(self):
        entered, disconnected = asyncio.Event(), asyncio.Event()
        async def serve(reader, writer):
            try:
                headers = await reader.readuntil(b'\r\n\r\n')
                size = int(next(row.split(b':')[1] for row in headers.split(b'\r\n')
                                if row.lower().startswith(b'content-length:')))
                await reader.readexactly(size)
                writer.write(b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n'
                             b'Transfer-Encoding: chunked\r\n\r\n')
                await writer.drain()
                entered.set()
                await reader.read()
                disconnected.set()
            finally:
                writer.close()
                await writer.wait_closed()
        server = await asyncio.start_server(serve, '127.0.0.1', 0)
        async with server:
            port = server.sockets[0].getsockname()[1]
            stream = OAuthAnswerStream(token_provider=lambda: 'synthetic',
                endpoint=f'http://127.0.0.1:{port}/responses')
            self.addAsyncCleanup(stream.aclose)
            task = asyncio.create_task(stream.complete('question', 'instructions'))
            await asyncio.wait_for(entered.wait(), 1)
            await asyncio.wait_for(asyncio.gather(stream.aclose(), stream.aclose()), 1)
            self.assertTrue(task.done())
            self.assertTrue(task.cancelled())
            await asyncio.wait_for(disconnected.wait(), 1)
            self.assertEqual(stream.last_timing.outcome, 'cancelled')
            self.assertIsNone(stream.last_timing.response_completed_ms)
            with self.assertRaisesRegex(AnswerTransportError, 'request_closed'):
                await stream.complete('question', 'instructions')


if __name__ == '__main__':
    unittest.main()
