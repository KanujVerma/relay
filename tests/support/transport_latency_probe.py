"""Content-free loopback client-setup probe. No account or external model call.

Run from the repo with `python -m tests.support.transport_latency_probe`.
The same script supports the pre-change adapter for matched measurements.
"""
import asyncio
import json
from statistics import median
import time

import httpx
from relay_spike.oauth_answer_stream import OAuthAnswerStream
from tests.test_answer_transport_lifetime import events, wire


async def measure():
    elapsed, construction = [], []
    counts = []
    body = wire(events())
    async def serve(reader, writer):
        try:
            header = await reader.readuntil(b'\r\n\r\n')
            size = int(next(row.split(b':')[1] for row in header.split(b'\r\n')
                            if row.lower().startswith(b'content-length:')))
            await reader.readexactly(size)
            writer.write(b'HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n'
                         + b'Content-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
            await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()
    server = await asyncio.start_server(serve, '127.0.0.1', 0)
    async with server:
        port = server.sockets[0].getsockname()[1]
        for _ in range(3):
            created = []
            def factory(**options):
                start = time.perf_counter()
                client = httpx.AsyncClient(**options)
                construction.append((time.perf_counter() - start) * 1000)
                created.append(client)
                return client
            stream = OAuthAnswerStream(token_provider=lambda: 'synthetic-offline', client_factory=factory,
                                       endpoint=f'http://127.0.0.1:{port}/responses')
            try:
                run = []
                for _ in range(8):
                    start = time.perf_counter()
                    await stream.complete('synthetic question', 'synthetic instructions')
                    run.append((time.perf_counter() - start) * 1000)
                elapsed.append(run)
                counts.append(len(created))
            finally:
                close = getattr(stream, 'aclose', None)
                if close is not None: await close()
    print(json.dumps({'fixture': 'loopback-httpx-client-setup-v1', 'httpx': httpx.__version__,
        'batches': 3, 'requests_per_batch': 8, 'client_counts': counts,
        'first_request_median_ms': round(median(row[0] for row in elapsed), 3),
        'subsequent_request_median_ms': round(median(t for row in elapsed for t in row[1:]), 3),
        'client_construction_median_ms': round(median(construction), 3),
        'all_request_ms': [[round(t, 3) for t in row] for row in elapsed]}, sort_keys=True))


if __name__ == '__main__':
    asyncio.run(measure())
