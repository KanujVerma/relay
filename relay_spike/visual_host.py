"""Python helper composition for the reviewed visual-input authority.

No IO at construction. Untrusted PNG staging remains local. Only an explicit
idle native control can run the existing synthetic probe with the configured
OAuth stream. Status describes the last check, never an account entitlement.
"""
from __future__ import annotations
import asyncio
from .oauth_answer_stream import OAuthAnswerStream
from .panel_wire import exact, uuid_string, WireError, encode_frame
from .visual_input import VisualInputController, VisualImageClaim, VisualInputError

_CONTROL_KEYS = ('schemaVersion', 'kind', 'requestID', 'action')


class ScreenVisualImagePort:
    """Adapter to actual admitted OCR/PNG ownership, without a legacy policy."""
    def __init__(self, provider):
        self._provider = provider
        self._claim = self._native = None

    def claim_for_request(self, native):
        data = self._provider.image_for_request(native)
        if data is None:
            return None
        owner, png, width, height = data
        self._native = native
        self._claim = VisualImageClaim(png=png, width=width, height=height,
                                       image_digest=owner.identity[-1], owner=owner)
        return self._claim

    def owns(self, claim, native):
        return (claim is not None and claim is self._claim and native is self._native
                and self._provider.owns_image_observation(claim.owner, native) is True)

    def release_bytes(self, claim):
        if claim is self._claim:
            self._provider.release_image_bytes(claim.owner, self._native)


class HostVisualInput:
    """One cancellable idle probe, bounded replay ledger, one current permit."""
    def __init__(self, host, stream=None):
        if stream is not None and not isinstance(stream, OAuthAnswerStream):
            raise ValueError('Configured OAuth visual stream required.')
        self._host, self._stream = host, stream
        self._controller = VisualInputController()
        self._enabled = False
        self._revision = 0
        self._receipt = self._probe_task = None
        self._ledger = {}
        self._state = 'disabled'
        self._request = self._permit = self._port = None

    def _configuration(self):
        stream = self._stream
        if stream is None:
            return None
        return (stream, stream.model, stream.effort, stream._endpoint)

    def _configured(self, configuration):
        complete = self._host.complete
        return (self._stream is not None and configuration == self._configuration()
                and getattr(complete, '__self__', None) is self._stream
                and getattr(complete, '__func__', None) is OAuthAnswerStream.complete)

    def _model(self):
        return self._stream.model if self._stream is not None else None

    def _reply(self, request, status, reason, revision=2):
        response = {'schemaVersion': 1, 'kind': 'visual_input_response',
                    'requestID': request['requestID'], 'action': request['action'],
                    'resultRevision': revision, 'status': status, 'reasonCode': reason, 'model': self._model()}
        encode_frame(response)
        self._ledger[uuid_string(request['requestID'])] = (tuple(request[key] for key in _CONTROL_KEYS), response)
        self._host.emit(response)

    def _finish_probe(self, request, status, reason):
        latest = self._ledger[uuid_string(request['requestID'])][1]
        if latest['resultRevision'] == 1:
            self._reply(request, status, reason)

    def _verified(self):
        if self._receipt is None:
            return False
        try:
            self._controller._require_receipt(self._receipt)
            return True
        except VisualInputError:
            self._receipt = None
            self._state = 'unverified'
            dependent=self._request is not None and self._host.active is self._request
            self.retire_request()
            if dependent:self._host._invalidate()
            return False

    def handle_control(self, value):
        try:
            exact(value, _CONTROL_KEYS)
            if (type(value['schemaVersion']) is not int or value['schemaVersion'] != 1
                    or value['kind'] != 'visual_input_request' or value['action'] not in ('verify', 'disable', 'status')):
                raise WireError('visual_control_schema')
            identity = uuid_string(value['requestID'])
        except Exception:
            self.disable()
            raise WireError('visual_control_schema') from None
        value=dict(value)  # Freeze the original four-field control across awaits.
        fingerprint=tuple(value[key] for key in _CONTROL_KEYS)
        if identity in self._ledger:
            original, response = self._ledger[identity]
            if original != fingerprint:
                self.disable()
                raise WireError('visual_control_replay')
            self._host.emit(response)
            return
        if len(self._ledger) >= 512:
            self.disable()
            raise WireError('visual_control_budget')
        # Reserve before any task or callback can run.
        self._ledger[identity] = (fingerprint, None)
        if value['action'] == 'disable':
            self.disable()
            self._reply(value, 'disabled', 'user_disabled')
            return
        probing = self._probe_task is not None
        if value['action'] == 'status':
            status = 'busy' if probing else 'verified' if self._verified() else self._state
            self._reply(value, status, 'probe_in_progress' if probing else 'current_status')
            return
        if self._stream is None or not self._configured(self._configuration()):
            self._reply(value, 'unavailable', 'inference_disabled')
            return
        if self._host.live:
            self._reply(value, 'busy', 'session_active')
            return
        if self._host._pending_work is not None or (self._host._worker is not None and not self._host._worker.done()):
            self._reply(value, 'busy', 'answer_in_progress')
            return
        if probing:
            self._reply(value, 'busy', 'probe_in_progress')
            return
        self._revision += 1
        revision, configuration = self._revision, self._configuration()
        self._enabled = True
        self._receipt = None
        consent = self._controller.begin_enable(self._stream.model)
        guard = lambda: self._enabled and self._revision == revision and self._configured(configuration)
        self._state = 'checking'
        self._reply(value, 'checking', 'checking', 1)
        task = asyncio.create_task(self._probe(consent, guard))
        self._probe_task = task
        def finished(done):
            error=None if done.cancelled() else done.exception()
            if self._probe_task is done:
                self._probe_task = None
            if done.cancelled() or self._revision != revision:
                status,reason='cancelled','probe_cancelled'
                if self._revision==revision:self._state='cancelled'
            else:
                receipt=None if error is not None else done.result()
                if receipt is not None and guard():
                    self._receipt,self._state=receipt,'verified'
                    status,reason='verified','probe_verified'
                else:
                    self._receipt=None;self._state='unverified';self._controller.disable()
                    status,reason='unverified','probe_unverified'
            try:self._finish_probe(value,status,reason)
            except Exception:self._host.close()  # Fail admission without logging callback content.
        task.add_done_callback(finished)

    async def _probe(self, consent, guard):
        try:
            receipt = await self._stream.verify_visual_input(self._controller, consent, is_current=guard)
            if not guard():
                raise VisualInputError('visual_probe_retired')
            return receipt
        except asyncio.CancelledError:raise
        except Exception:
            return None

    async def drain_probe(self):
        task = self._probe_task
        if task is not None:
            await asyncio.gather(task, return_exceptions=True)

    def session_starting(self):
        if self._probe_task is not None:
            self.disable(cancel_work=False)

    def retire_request(self):
        if self._permit is not None:
            self._permit.retire()
        self._request = self._permit = self._port = None

    def disable(self, *, cancel_work=True):
        dependent = self._request is not None and self._host.active is self._request
        self._revision += 1
        self._enabled = False
        self._receipt = None
        self._state = 'disabled'
        self._controller.disable()
        self.retire_request()
        discard = getattr(self._host.supplemental_provider, 'discard_images', None)
        if callable(discard):
            discard()
        task = self._probe_task
        if task is not None and not task.done() and not task.cancelling():
            task.cancel()
        if cancel_work and dependent:
            self._host._invalidate()

    def prepare(self, request, supplemental):
        self.retire_request()
        if (supplemental is None or supplemental.provenance != 'local_ocr'
                or not self._verified() or not self._configured(self._configuration())):
            discard = getattr(self._host.supplemental_provider, 'discard_images', None)
            if callable(discard): discard()
            return None
        port = ScreenVisualImagePort(self._host.supplemental_provider)
        try:
            permit = self._controller.prepare_attachment(self._receipt, request=request.native, image_port=port,
                is_current=lambda: self._host.supplemental_request_current(request.native))
        except (VisualInputError, AttributeError):
            return None
        self._request, self._permit, self._port = request, permit, port
        return permit

    def current_for(self, request):
        if request is not self._request:
            return True
        try:
            self._permit._check()
            return True
        except VisualInputError:
            return False

    async def validate_publication(self, request, *, permit=None):
        if permit is None:
            return True
        if request is not self._request or permit is not self._permit:
            return False
        return (await self._stream.validate_visual_publication(self._permit)
                and self._host.supplemental_request_current(request.native)
                and self._permit.validate_for_publication())

    def used_image_digest(self, request):
        if request is self._request and self._permit.used_image:
            return self._port._claim.image_digest
        return None

    def failed_request(self, request):
        if request is self._request:
            self.retire_request()
