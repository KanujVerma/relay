"""Cancelable plan-OAuth adapter. No credential access until explicit live use.

HTTPX 0.28.1 (BSD-3-Clause) is invoked, not copied. AsyncClient's context
manager closes responses on cancellation. A local-socket regression tests it.
Local disconnect bounds waiting; it does not prove provider token work stopped.
"""
from __future__ import annotations
import asyncio
from collections import deque
import time
from .generated_answer import strict_json, CardError
from .response_assembly import ResponseAssembler, ResponseProtocolError
from .stream import RESPONSES, response_payload, StreamError


class AnswerTransportError(RuntimeError):
    pass


class SSEDecoder:
    def __init__(self):
        self.buffer = bytearray()
        self.total = 0

    def feed(self, chunk):
        if not isinstance(chunk, bytes): raise AnswerTransportError('stream_invalid')
        self.total += len(chunk)
        if self.total > 524288: raise AnswerTransportError('stream_budget')
        self.buffer.extend(chunk)
        result=[]
        while True:
            # Normalize CRLF only after a full frame is available.
            end=self.buffer.find(b'\n\n'); crend=self.buffer.find(b'\r\n\r\n')
            if crend >= 0 and (end < 0 or crend < end): end, width = crend,4
            else: width=2
            if end < 0:
                if len(self.buffer)>65536: raise AnswerTransportError('event_budget')
                break
            if end>65536: raise AnswerTransportError('event_budget')
            frame=bytes(self.buffer[:end]); del self.buffer[:end+width]
            data=[]; event_type=None
            try:
                for line in frame.decode('utf-8').splitlines():
                    if line.startswith('data:'): data.append(line[5:].lstrip(' '))
                    elif line.startswith('event:'): event_type=line[6:].strip()
                if data:
                    if '\n'.join(data)=='[DONE]': continue
                    parsed=strict_json('\n'.join(data),max_bytes=65536)
                    if not isinstance(parsed,dict) or event_type is not None and parsed.get('type')!=event_type: raise CardError('event_type')
                    result.append(parsed)
            except (UnicodeError,CardError): raise AnswerTransportError('event_invalid') from None
        return tuple(result)

    def finish(self):
        if self.buffer: raise AnswerTransportError('stream_truncated')


class OAuthAnswerStream:
    def __init__(self, *, model='gpt-6-luna', effort=None, deadline=15.0,
                 token_provider=None, endpoint=RESPONSES, client_factory=None):
        if not 0 < deadline <= 30: raise ValueError('Invalid deadline.')
        self.model,self.effort,self.deadline=model,effort,deadline
        self._token_provider,self._endpoint,self._client_factory=token_provider,endpoint,client_factory
        self._active=False
        self._spent=0
        self._recent=deque()

    async def complete(self, question, instructions):
        now=time.monotonic()
        while self._recent and now-self._recent[0]>=60: self._recent.popleft()
        if self._active: raise AnswerTransportError('request_busy')
        if self._spent>=60 or len(self._recent)>=10: raise AnswerTransportError('request_budget')
        self._active=True; self._spent+=1; self._recent.append(now)
        try:
            import httpx
            if self._token_provider is None:
                from .auth import active_access_token
                provider=active_access_token
            else: provider=self._token_provider
            # Credential refresh can block; outer deadline bounds local waiting.
            async with asyncio.timeout(self.deadline):
                token=await asyncio.to_thread(provider)
                body=response_payload(self.model,question,instructions=instructions,effort=self.effort)
                factory=self._client_factory or httpx.AsyncClient
                async with factory(timeout=httpx.Timeout(10,connect=5),follow_redirects=False,trust_env=False,limits=httpx.Limits(max_connections=1,max_keepalive_connections=0)) as client:
                    async with client.stream('POST',self._endpoint,json=body,headers={'Authorization':'Bearer '+token,'Accept':'text/event-stream','Accept-Encoding':'identity'}) as response:
                        if response.status_code != 200: raise AnswerTransportError('request_rejected')
                        if not response.headers.get('content-type','').lower().startswith('text/event-stream'): raise AnswerTransportError('stream_invalid')
                        decoder,assembler=SSEDecoder(),ResponseAssembler()
                        async for chunk in response.aiter_raw():
                            # HTTP core reads <=64KiB. Do not coalesce small SSE
                            # completions into an artificial 4KiB output chunk.
                            if len(chunk)>65536: raise AnswerTransportError('stream_budget')
                            for event in decoder.feed(chunk):
                                answer=assembler.feed(event)
                                if answer is not None: return answer
                        decoder.finish(); assembler.finish()
                        raise AnswerTransportError('missing_response_completed')
        except asyncio.CancelledError: raise
        except AnswerTransportError: raise
        except (TimeoutError,StreamError,ResponseProtocolError,ImportError):
            raise AnswerTransportError('request_unavailable') from None
        except Exception:
            # Provider/HTTP exceptions can contain credentials or private content.
            raise AnswerTransportError('request_unavailable') from None
        finally: self._active=False
