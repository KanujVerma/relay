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
from .stream import MODELS, RESPONSES, response_payload, StreamError
from .visual_input import (VisualInputController, VisualAttachmentPermit, VisualInputError,
                           PROBE_QUESTION, PROBE_INSTRUCTIONS)


class AnswerTransportError(RuntimeError):
    def __init__(self, code, *, status=None, provider_code=None, param_category=None):
        super().__init__(code)
        self.status = status if type(status) is int and 100 <= status <= 599 else None
        self.provider_code = provider_code if provider_code in _PROVIDER_CODES else None
        self.param_category = param_category if param_category in _PARAM_CATEGORIES else None


_PROVIDER_CODES = frozenset((
    'subscription_sharing_user_not_eligible', 'subscription_sharing_usage_limit_exceeded',
    'subscription_sharing_usage_unavailable', 'subscription_sharing_unsupported_capability',
    'subscription_sharing_route_not_supported', 'subscription_sharing_invalid_user',
    'chatpass_v2_scope_not_authorized', 'chatpass_v2_invalid_authorization_context',
    'subscription_sharing_user_unavailable',
))
_PARAM_CATEGORIES = frozenset(('input', 'model', 'tools', 'reasoning', 'service_tier'))


def _response_error(payload, *, status=None):
    error = payload.get('error') if isinstance(payload, dict) else None
    if not isinstance(error, dict) and isinstance(payload, dict) and payload.get('type') == 'error':
        error = payload
    code, category = None, None
    if isinstance(error, dict):
        raw_code, param = error.get('code'), error.get('param')
        if isinstance(raw_code, str) and raw_code in _PROVIDER_CODES:
            code = raw_code
        if isinstance(param, str) and len(param) <= 256:
            category = next((name for name in _PARAM_CATEGORIES
                             if param == name or param.startswith(name + '[') or param.startswith(name + '.')), None)
    return AnswerTransportError('request_rejected', status=status, provider_code=code, param_category=category)


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
                 token_provider=None, endpoint=RESPONSES, client_factory=None, models_endpoint=MODELS):
        if not 0 < deadline <= 30: raise ValueError('Invalid deadline.')
        self.model,self.effort,self.deadline=model,effort,deadline
        self._token_provider,self._endpoint,self._client_factory=token_provider,endpoint,client_factory
        self._models_endpoint = models_endpoint
        self._active=False
        self._spent=0
        self._recent=deque()

    def _enter(self):
        now=time.monotonic()
        while self._recent and now-self._recent[0]>=60: self._recent.popleft()
        if self._active: raise AnswerTransportError('request_busy')
        if self._spent>=60 or len(self._recent)>=10: raise AnswerTransportError('request_budget')
        self._active=True; self._spent+=1; self._recent.append(now)

    async def _token(self):
        if self._token_provider is None:
            from .auth import active_access_token
            provider = active_access_token
        else:
            provider = self._token_provider
        token = await asyncio.to_thread(provider)
        if not isinstance(token, str) or not token.strip() or len(token) > 32768:
            raise AnswerTransportError('credential_unavailable')
        return token

    def _client(self):
        import httpx
        factory = self._client_factory or httpx.AsyncClient
        return factory(timeout=httpx.Timeout(10, connect=5), follow_redirects=False, trust_env=False,
                       limits=httpx.Limits(max_connections=1, max_keepalive_connections=0))

    async def _small_body(self, response, *, budget=65536):
        data = bytearray()
        async for chunk in response.aiter_raw():
            if len(data) + len(chunk) > budget:
                raise AnswerTransportError('response_budget', status=response.status_code)
            data.extend(chunk)
        try:
            return strict_json(bytes(data), max_bytes=budget)
        except CardError:
            return None

    async def _request(self, client, body, token, *, guard=None):
        if guard is not None:
            guard()
        async with client.stream('POST', self._endpoint, json=body, headers={
            'Authorization': 'Bearer ' + token, 'Accept': 'text/event-stream', 'Accept-Encoding': 'identity',
        }) as response:
            if response.status_code != 200:
                raise _response_error(await self._small_body(response), status=response.status_code)
            if not response.headers.get('content-type', '').lower().startswith('text/event-stream'):
                raise AnswerTransportError('stream_invalid')
            decoder, assembler = SSEDecoder(), ResponseAssembler()
            async for chunk in response.aiter_raw():
                if guard is not None:
                    guard()
                if len(chunk) > 65536:
                    raise AnswerTransportError('stream_budget')
                for event in decoder.feed(chunk):
                    if event.get('type') in ('response.failed', 'response.incomplete', 'error'):
                        payload = event.get('response') if isinstance(event.get('response'), dict) else event
                        raise _response_error(payload)
                    answer = assembler.feed(event)
                    if answer is not None:
                        if guard is not None:
                            guard()
                        return answer
            decoder.finish(); assembler.finish()
            raise AnswerTransportError('missing_response_completed')

    async def complete(self, question, instructions, *, visual_attachment=None):
        if visual_attachment is not None and not isinstance(visual_attachment, VisualAttachmentPermit):
            raise VisualInputError('visual_permit_unverified')
        try:
            self._enter()
        except Exception:
            if visual_attachment is not None:
                visual_attachment.retire()
            raise
        success = False
        try:
            async with asyncio.timeout(self.deadline):
                token = await self._token()
                part, guard = None, None
                if visual_attachment is not None:
                    part = visual_attachment._begin_send(token=token, model=self.model, effort=self.effort, endpoint=self._endpoint)
                    guard = lambda: visual_attachment._check(token=token, model=self.model, effort=self.effort,
                                                             endpoint=self._endpoint, check_config=True)
                body = response_payload(self.model, question, instructions=instructions, effort=self.effort, image_input=part)
                async with self._client() as client:
                    answer = await self._request(client, body, token, guard=guard)
                if visual_attachment is not None:
                    current_token = await self._token()
                    visual_attachment._mark_completed(token=current_token, model=self.model, effort=self.effort, endpoint=self._endpoint)
                success = True
                return answer
        except asyncio.CancelledError: raise
        except AnswerTransportError as error:
            if (visual_attachment is not None
                    and error.provider_code == 'subscription_sharing_unsupported_capability'
                    and error.param_category in ('input', 'model')):
                visual_attachment._controller._revoke_capability()
            raise
        except VisualInputError: raise
        except (TimeoutError,StreamError,ResponseProtocolError,ImportError):
            raise AnswerTransportError('request_unavailable') from None
        except Exception:
            # Provider/HTTP exceptions can contain credentials or private content.
            raise AnswerTransportError('request_unavailable') from None
        finally:
            self._active = False
            if visual_attachment is not None and not success:
                visual_attachment.retire()

    async def verify_visual_input(self, visual, consent, *, is_current):
        """Explicit user action only: account catalog plus exactly one image probe.

        No real screenshot is accepted by this method. Default construction and
        complete() never call it. Re-reading the provider catches token rotation;
        it never changes the original bearer used for catalog/probe requests.
        """
        if not isinstance(visual, VisualInputController) or not callable(is_current):
            raise VisualInputError('visual_consent_unverified')
        self._enter()
        try:
            async with asyncio.timeout(self.deadline):
                token = await self._token()
                probe = visual._begin_probe(consent, token=token, model=self.model, effort=self.effort,
                                             endpoint=self._endpoint, is_current=is_current)
                def guard():
                    visual._probe_current(consent, probe, token=token, model=self.model, effort=self.effort,
                                           endpoint=self._endpoint, is_current=is_current)
                async with self._client() as client:
                    guard()
                    async with client.stream('GET', self._models_endpoint, headers={
                        'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'Accept-Encoding': 'identity',
                    }) as response:
                        catalog = await self._small_body(response, budget=1048576 if response.status_code == 200 else 65536)
                        if response.status_code != 200:
                            raise _response_error(catalog, status=response.status_code)
                    rows = catalog.get('models') if isinstance(catalog, dict) else None
                    if not isinstance(rows, list):
                        raise VisualInputError('model_catalog_invalid')
                    matches = [row for row in rows if isinstance(row, dict) and row.get('slug') == self.model]
                    if len(matches) != 1 or matches[0].get('visibility') != 'list':
                        raise VisualInputError('model_not_available')
                    current_token = await self._token()
                    visual._probe_current(consent, probe, token=current_token, model=self.model, effort=self.effort,
                                           endpoint=self._endpoint, is_current=is_current)
                    body = response_payload(self.model, PROBE_QUESTION, instructions=PROBE_INSTRUCTIONS,
                                            effort=self.effort, image_input=probe.image_part())
                    answer = await self._request(client, body, token, guard=guard)
                current_token = await self._token()
                return visual._accept_probe(consent, probe, answer, token=current_token, model=self.model,
                                             effort=self.effort, endpoint=self._endpoint, is_current=is_current)
        except asyncio.CancelledError: raise
        except (VisualInputError, AnswerTransportError): raise
        except Exception:
            raise AnswerTransportError('request_unavailable') from None
        finally:
            self._active = False
            visual._abort_probe(consent)

    async def validate_visual_publication(self, permit):
        """Refresh actual bearer continuity, then host does its native final gate.

        This performs no inference or retry. A refresh that changes the bearer
        retires the permit. Native must still recheck pixels and synchronously
        validate permit/producer/current lease after that final await.
        """
        if not isinstance(permit, VisualAttachmentPermit):
            return False
        try:
            async with asyncio.timeout(self.deadline):
                token = await self._token()
                permit._check(token=token, model=self.model, effort=self.effort,
                              endpoint=self._endpoint, check_config=True)
                return permit.validate_for_publication()
        except asyncio.CancelledError:
            permit.retire()
            raise
        except Exception:
            permit.retire()
            return False
