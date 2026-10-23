import asyncio
import json
import unittest
from relay_spike.oauth_answer_stream import OAuthAnswerStream, SSEDecoder, AnswerTransportError

class SSETests(unittest.TestCase):
    def test_fragmentation_duplicates_and_size(self):
        d=SSEDecoder()
        self.assertEqual(d.feed(b'data: {"type":"x","sequence_'), ())
        self.assertEqual(d.feed(b'number":1}\n\n')[0]['type'], 'x')
        with self.assertRaises(AnswerTransportError): d.feed(b'x'*65537)
        with self.assertRaises(AnswerTransportError): SSEDecoder().feed(b'data: {"x":1,"x":2}\n\n')

class OAuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_actual_httpx_adapter_uses_existing_payload_and_closes_stalled_socket_on_cancel(self):
        try: import httpx
        except ImportError: self.skipTest('optional HTTPX transport dependency')
        got_headers=asyncio.Event(); disconnected=asyncio.Event(); captured=[]
        async def serve(reader,writer):
            try:
                headers=await reader.readuntil(b'\r\n\r\n'); captured.append(headers)
                length=int(next(x.split(b':')[1] for x in headers.split(b'\r\n') if x.lower().startswith(b'content-length:')))
                captured.append(await reader.readexactly(length))
                writer.write(b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n'); await writer.drain(); got_headers.set()
                await reader.read(); disconnected.set()
            finally: writer.close(); await writer.wait_closed()
        server=await asyncio.start_server(serve,'127.0.0.1',0)
        async with server:
            port=server.sockets[0].getsockname()[1]
            # Endpoint injection is test-only constructor port; production default fixed.
            stream=OAuthAnswerStream(token_provider=lambda:'synthetic-token', endpoint=f'http://127.0.0.1:{port}/responses', client_factory=httpx.AsyncClient)
            task=asyncio.create_task(stream.complete('question','instructions'))
            await asyncio.wait_for(got_headers.wait(),2)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError): await task
            await asyncio.wait_for(disconnected.wait(),2)
        payload=json.loads(captured[1]); self.assertFalse(payload['store']); self.assertTrue(payload['stream'])
        self.assertEqual(payload['instructions'],'instructions'); self.assertNotIn('max_output_tokens',payload)
        self.assertIn(b'Bearer synthetic-token',captured[0])
