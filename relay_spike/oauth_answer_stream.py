"""Cancelable plan-OAuth adapter. No credential access until explicit live use.

HTTPX 0.28.1 (BSD-3-Clause) is invoked, not copied. Each response context
closes on cancellation. One lazy client belongs to this helper until aclose().
Local disconnect bounds waiting; it does not prove provider token work stopped.
"""
from __future__ import annotations
import asyncio
from collections import deque
import time
import weakref
from .generated_answer import strict_json, CardError
from .response_assembly import ResponseAssembler, ResponseProtocolError
from .answer_timing import AnswerTimingAttempt
from .answer_diagnostics import INSPECTION_DEADLINE, inspect_non_sse
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
                 token_provider=None, endpoint=RESPONSES, client_factory=None, models_endpoint=MODELS,
                 clock=time.monotonic, attempt_diagnostic_sink=None):
        if not 0 < deadline <= 30: raise ValueError('Invalid deadline.')
        self.model,self.effort,self.deadline=model,effort,deadline
        self._token_provider,self._endpoint,self._client_factory=token_provider,endpoint,client_factory
        self._models_endpoint = models_endpoint
        self._active=False
        self._spent=0
        self._recent=deque()
        self._clock=clock
        self._owned_client=None
        self._active_task=None
        self._closed=False
        self._close_task=None
        self._last_timing=None
        self._last_timing_owner=None
        self.attempt_diagnostic_sink=attempt_diagnostic_sink

    @property
    def last_timing(self):
        """The latest admitted complete() attempt only; one immutable snapshot."""
        return self._last_timing

    def _owned_diagnostic_timing(self,previous):
        current=self._last_timing
        return current if (current is not None and current is not previous and self._last_timing_owner is not None
            and self._last_timing_owner() is asyncio.current_task()) else None

    def _enter(self):
        if self._closed: raise AnswerTransportError('request_closed')
        now=time.monotonic()
        while self._recent and now-self._recent[0]>=60: self._recent.popleft()
        if self._active: raise AnswerTransportError('request_busy')
        if self._spent>=60 or len(self._recent)>=10: raise AnswerTransportError('request_budget')
        self._active=True; self._spent+=1; self._recent.append(now)
        self._active_task=asyncio.current_task()

    def _leave(self):
        self._active=False
        self._active_task=None

    async def aclose(self):
        """Retire admission, join the actual owned request, then close its client.

        A separate close task makes simultaneous/retried cleanup idempotent.
        Shielding keeps ownership even when a cleanup caller is cancelled.
        """
        if self._active_task is asyncio.current_task():
            raise RuntimeError('active_request_cannot_close_itself')
        if self._close_task is None:
            self._closed=True
            self._close_task=asyncio.create_task(self._close_owned())
        await asyncio.shield(self._close_task)

    async def _close_owned(self):
        task=self._active_task
        if task is not None and not task.done():
            task.cancel()
            await asyncio.gather(task,return_exceptions=True)
        if self._owned_client is not None:
            await self._owned_client.aclose()
            self._owned_client.cookies.clear()

    async def _token(self, *, notes_owned=False):
        if self._token_provider is None:
            from .auth import active_access_token
            provider = active_access_token
        else:
            provider = self._token_provider
        if notes_owned:
            from .account_oauth import owned_thread
            token = await owned_thread(provider)
        else:
            token = await asyncio.to_thread(provider)
        if not isinstance(token, str) or not token.strip() or len(token) > 32768:
            raise AnswerTransportError('credential_unavailable')
        return token

    def _client(self):
        if self._owned_client is not None: return self._owned_client
        import httpx
        factory = self._client_factory or httpx.AsyncClient
        self._owned_client=factory(timeout=httpx.Timeout(10, connect=5), follow_redirects=False, trust_env=False,
                       limits=httpx.Limits(max_connections=1, max_keepalive_connections=1, keepalive_expiry=15))
        return self._owned_client

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

    async def _request(self, client, body, token, *, guard=None, timing=None, inspection_deadline=None):
        if guard is not None:
            guard()
        # A retained client must not add a provider cookie to a later bearer.
        client.cookies.clear()
        if timing is not None: timing.mark('request_started_ms')
        async with client.stream('POST', self._endpoint, json=body, headers={
            'Authorization': 'Bearer ' + token, 'Accept': 'text/event-stream', 'Accept-Encoding': 'identity',
        }) as response:
            if timing is not None: timing.mark('response_headers_ms')
            if timing is not None: timing.diagnostic.response(response.status_code,response.headers.get('content-type'),response.headers.get('content-encoding'))
            if response.status_code != 200:
                raise _response_error(await self._small_body(response), status=response.status_code)
            if not response.headers.get('content-type', '').lower().startswith('text/event-stream'):
                host_deadline=INSPECTION_DEADLINE.get()
                if timing is not None and self.attempt_diagnostic_sink is not None and host_deadline is not None and inspection_deadline is not None:
                    try:await inspect_non_sse(response,timing.diagnostic,min(host_deadline,inspection_deadline))
                    except asyncio.CancelledError:raise
                    except Exception:timing.diagnostic.fields['nonSse']['inspectionOutcome']='read_error'
                raise AnswerTransportError('stream_invalid')
            decoder, assembler = SSEDecoder(), ResponseAssembler()
            async for chunk in response.aiter_raw():
                if timing is not None: timing.diagnostic.chunk(len(chunk))
                if guard is not None:
                    guard()
                if len(chunk) > 65536:
                    raise AnswerTransportError('stream_budget')
                for event in decoder.feed(chunk):
                    if timing is not None: timing.diagnostic.event(event)
                    if timing is not None:
                        terminal={'response.failed':'failed','response.incomplete':'incomplete',
                            'response.refusal.delta':'refused','response.refusal.done':'refused'}.get(event.get('type'))
                        if terminal is not None:timing.provider_terminal=terminal
                    if event.get('type') in ('response.failed', 'response.incomplete', 'error'):
                        payload = event.get('response') if isinstance(event.get('response'), dict) else event
                        raise _response_error(payload)
                    answer = assembler.feed(event)
                    if (timing is not None and event.get('type')=='response.output_text.delta'
                            and event.get('delta', '').strip()):
                        # The assembler has validated item identity and order.
                        timing.mark('first_text_ms')
                    if answer is not None:
                        if guard is not None:
                            guard()
                        if timing is not None:
                            timing.mark('response_completed_ms')
                            timing.provider_terminal='completed'
                            timing.output_bytes=len(answer.encode('utf-8'))
                        return answer
            decoder.finish(); assembler.finish()
            raise AnswerTransportError('missing_response_completed')

    async def complete(self, question, instructions, *, visual_attachment=None, notes_text_permit=None):
        if notes_text_permit is not None:
            from .notes_text_permit import is_issued_notes_permit,NotesPermitError
            if not is_issued_notes_permit(notes_text_permit):raise NotesPermitError('notes_permit_unverified')
            if visual_attachment is not None:
                notes_text_permit.retire()
                raise NotesPermitError('notes_image_not_allowed')
        if visual_attachment is not None and not isinstance(visual_attachment, VisualAttachmentPermit):
            raise VisualInputError('visual_permit_unverified')
        try:
            self._enter()
        except Exception:
            if visual_attachment is not None:
                visual_attachment.retire()
            if notes_text_permit is not None:notes_text_permit.retire()
            raise
        success = False
        timing=AnswerTimingAttempt(self._spent,self._clock)
        outcome='failed'
        try:
            async with asyncio.timeout(self.deadline) as request_timeout:
                token = await self._token(notes_owned=notes_text_permit is not None)
                timing.mark('token_ready_ms')
                part, guard = None, None
                if visual_attachment is not None:
                    part = visual_attachment._begin_send(token=token, model=self.model, effort=self.effort, endpoint=self._endpoint)
                    guard = lambda: visual_attachment._check(token=token, model=self.model, effort=self.effort,
                                                             endpoint=self._endpoint, check_config=True)
                if notes_text_permit is not None:
                    notes_text_permit._begin_send(token=token,model=self.model,effort=self.effort,endpoint=self._endpoint,
                        question=question,instructions=instructions)
                    guard=lambda:notes_text_permit._check(token=token,model=self.model,effort=self.effort,endpoint=self._endpoint)
                body = response_payload(self.model, question, instructions=instructions, effort=self.effort, image_input=part)
                client=self._client()
                timing.mark('client_ready_ms')
                answer = await self._request(client, body, token, guard=guard, timing=timing,inspection_deadline=request_timeout.when())
                if visual_attachment is not None:
                    current_token = await self._token()
                    visual_attachment._mark_completed(token=current_token, model=self.model, effort=self.effort, endpoint=self._endpoint)
                if notes_text_permit is not None:
                    current_token = await self._token(notes_owned=True)
                    notes_text_permit._mark_completed(token=current_token,model=self.model,effort=self.effort,endpoint=self._endpoint)
                success = True
                outcome='completed'
                return answer
        except asyncio.CancelledError:
            outcome='cancelled'
            raise
        except AnswerTransportError as error:
            timing.diagnostic.failure('provider' if error.args and error.args[0]=='request_rejected' else 'sse',
                code=error.args[0] if error.args else None,status=error.status,provider=error.provider_code,param=error.param_category)
            if (visual_attachment is not None
                    and error.provider_code == 'subscription_sharing_unsupported_capability'
                    and error.param_category in ('input', 'model')):
                visual_attachment._controller._revoke_capability()
            raise
        except VisualInputError:
            timing.diagnostic.failure('guard');raise
        except TimeoutError:
            timing.diagnostic.failure('deadline');raise AnswerTransportError('request_unavailable') from None
        except (StreamError,ResponseProtocolError,ImportError) as error:
            timing.diagnostic.failure('payload' if isinstance(error,StreamError) else 'response_protocol' if isinstance(error,ResponseProtocolError) else 'dependency',
                code=error.args[0] if isinstance(error,ResponseProtocolError) and error.args else None)
            raise AnswerTransportError('request_unavailable') from None
        except Exception as error:
            kind='other';code=None
            try:
                import httpx
                from .account_store import AccountStoreError
                for typ,label in ((httpx.ConnectTimeout,'http_connect_timeout'),(httpx.ReadTimeout,'http_read_timeout'),
                                  (httpx.WriteTimeout,'http_write_timeout'),(httpx.PoolTimeout,'http_pool_timeout'),
                                  (httpx.TimeoutException,'http_timeout'),(httpx.HTTPError,'http_transport')):
                    if isinstance(error,typ):kind=label;break
                if isinstance(error,AccountStoreError):kind='credential';code=error.code
            except Exception:pass
            timing.diagnostic.failure(kind,code=code)
            # Provider/HTTP exceptions can contain credentials or private content.
            raise AnswerTransportError('request_unavailable') from None
        finally:
            self._last_timing=timing.finish(outcome)
            self._last_timing_owner=weakref.ref(asyncio.current_task())
            self._leave()
            if visual_attachment is not None and not success:
                visual_attachment.retire()
            if notes_text_permit is not None and not success:notes_text_permit.retire()

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
                client=self._client()
                client.cookies.clear()
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
            self._leave()
            visual._abort_probe(consent)

    async def validate_visual_publication(self, permit):
        """Refresh actual bearer continuity, then host does its native final gate.

        This performs no inference or retry. A refresh that changes the bearer
        retires the permit. Native must still recheck pixels and synchronously
        validate permit/producer/current lease after that final await.
        """
        if not isinstance(permit, VisualAttachmentPermit):
            return False
        if self._closed:
            permit.retire()
            return False
        try:
            async with asyncio.timeout(self.deadline):
                token = await self._token()
                if self._closed:
                    permit.retire()
                    return False
                permit._check(token=token, model=self.model, effort=self.effort,
                              endpoint=self._endpoint, check_config=True)
                return permit.validate_for_publication()
        except asyncio.CancelledError:
            permit.retire()
            raise
        except Exception:
            permit.retire()
            return False
