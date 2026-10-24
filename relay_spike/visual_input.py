"""Explicit verified visual-input authority. No IO occurs on import/construction.

The actual bearer is fingerprinted privately, not interpreted as a person ID.
Any credential change (including refresh) requires another explicit probe.
PNG validation is reused unchanged from the accepted selected-screen port.
"""
from __future__ import annotations

import base64
from dataclasses import dataclass
import hashlib
import hmac
import secrets
import struct
import time
from typing import Protocol
import zlib

from .screen_context import _validate_png

_ISSUER = object()
MAX_IMAGE_BYTES = 2 * 1024 * 1024


def validated_image_part(part):
    """Strict standard content part; body construction is not authorization."""
    try:
        if (type(part) is not dict or set(part) != {'type', 'detail', 'image_url'}
                or part['type'] != 'input_image' or part['detail'] != 'high'
                or not isinstance(part['image_url'], str)
                or not part['image_url'].startswith('data:image/png;base64,')
                or len(part['image_url']) > 4 * ((MAX_IMAGE_BYTES + 2) // 3) + 22):
            raise ValueError
        encoded = part['image_url'][22:]
        data = base64.b64decode(encoded, validate=True)
        if not 0 < len(data) <= MAX_IMAGE_BYTES or base64.b64encode(data).decode('ascii') != encoded:
            raise ValueError
        width, height = struct.unpack('>II', data[16:24])
        if not 1 <= width <= 1920 or not 1 <= height <= 1920:
            raise ValueError
        _validate_png(data, width, height)
        return dict(part)
    except (ValueError, TypeError, KeyError, struct.error):
        raise VisualInputError('image_invalid') from None


class VisualInputError(ValueError):
    """Only fixed local codes, never provider text, pixels or credential values."""


class _Issued:
    __slots__ = ()

    def __init__(self, key):
        if key is not _ISSUER:
            raise TypeError('Host-issued visual authority required.')

    def __reduce_ex__(self, protocol):
        raise TypeError('Visual authority cannot be serialized or copied.')

    def __repr__(self):
        return '<host-issued visual authority>'


class VisualConsent(_Issued):
    __slots__ = ()


class VerifiedImageCapability(_Issued):
    __slots__ = ()


@dataclass(frozen=True, repr=False)
class VisualImageClaim:
    """Trusted producer output, not authority by itself.

    owner is the original issued observation, retaining its source/request fences.
    owns() must validate that identity even after PNG storage is released. The
    producer must not retain this bytearray for persistence or diagnostics.
    """
    png: bytearray
    width: int
    height: int
    image_digest: str
    owner: object

    def __post_init__(self):
        object.__setattr__(self, 'png', bytearray(self.png))


class VisualImagePort(Protocol):
    def claim_for_request(self, request: object) -> VisualImageClaim | None: ...
    def owns(self, claim: VisualImageClaim, request: object) -> bool: ...
    def release_bytes(self, claim: VisualImageClaim) -> None: ...


def _current(callback):
    try:
        return callable(callback) and callback() is True
    except Exception:
        return False


def _valid_claim(claim):
    if not isinstance(claim, VisualImageClaim):
        raise VisualInputError('image_unavailable')
    if (type(claim.width) is not int or type(claim.height) is not int
            or not 1 <= claim.width <= 1920 or not 1 <= claim.height <= 1920
            or not 0 < len(claim.png) <= MAX_IMAGE_BYTES or claim.owner is None
            or not isinstance(claim.image_digest, str) or len(claim.image_digest) != 64
            or any(c not in '0123456789abcdef' for c in claim.image_digest)):
        raise VisualInputError('image_invalid')
    try:
        _validate_png(bytes(claim.png), claim.width, claim.height)
    except (ValueError, TypeError, struct.error):
        raise VisualInputError('image_invalid') from None


def _drop_bytes(claim, port):
    if isinstance(claim, VisualImageClaim):
        claim.png[:] = b'\0' * len(claim.png)
        claim.png.clear()
        try:
            port.release_bytes(claim)
        except Exception:
            # Cleanup cannot expose a producer exception or revive authority.
            pass


@dataclass(frozen=True, repr=False)
class _Probe:
    png: bytes
    expected: str

    def image_part(self):
        return {'type': 'input_image', 'detail': 'high',
                'image_url': 'data:image/png;base64,' + base64.b64encode(self.png).decode('ascii')}


def _make_probe():
    """Six randomly ordered RGB bars. Expected order is never in the prompt."""
    palette = [('red', (255, 0, 0)), ('green', (0, 255, 0)), ('blue', (0, 0, 255)),
               ('cyan', (0, 255, 255)), ('magenta', (255, 0, 255)), ('yellow', (255, 255, 0))]
    secrets.SystemRandom().shuffle(palette)
    width, height = 192, 96
    row = b'\0' + b''.join(bytes(rgb) * 32 for _, rgb in palette)

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

    image = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
             + chunk(b'IDAT', zlib.compress(row * height)) + chunk(b'IEND', b''))
    _validate_png(image, width, height)
    return _Probe(image, ','.join(name for name, _ in palette))


PROBE_QUESTION = ('Read the six colored vertical bars from left to right. Reply with exactly six '
                  'lowercase color names separated by commas, with no spaces or explanation. '
                  'Allowed names: red, green, blue, cyan, magenta, yellow.')
PROBE_INSTRUCTIONS = 'Relay synthetic visual check. Describe only the generated test image as requested.'


@dataclass(frozen=True, repr=False)
class _Capability:
    receipt: VerifiedImageCapability
    consent: VisualConsent
    fingerprint: bytes
    model: str
    effort: str | None
    endpoint: str
    issued: float
    guard: object


class VisualInputController:
    """One explicit consent, one verified grant and at most one image permit.

    Call lifecycle operations on the host's serial admission loop. Guards are
    required synchronous checks of actual host authority, not wire booleans.
    """
    def __init__(self, *, clock=time.monotonic, receipt_lifetime=900):
        if not callable(clock) or type(receipt_lifetime) not in (int, float) or not 0 < receipt_lifetime <= 3600:
            raise ValueError('Invalid visual verification lifetime.')
        self._clock, self._lifetime = clock, receipt_lifetime
        self._salt = secrets.token_bytes(32)
        self._consent = self._capability = self._probe = self._permit = None

    def begin_enable(self, model):
        """Explicit user action only. This alone never enables image transport."""
        if not isinstance(model, str) or not model.strip() or len(model.encode()) > 160:
            raise VisualInputError('model_invalid')
        self.disable()
        consent = VisualConsent(_ISSUER)
        self._consent = (consent, model)
        return consent

    def disable(self):
        self._consent = self._capability = self._probe = None
        if self._permit is not None:
            self._permit.retire()
            self._permit = None

    def _fingerprint(self, token):
        if not isinstance(token, str) or not token or len(token) > 32768:
            raise VisualInputError('credential_unavailable')
        return hmac.digest(self._salt, token.encode('utf-8'), 'sha256')

    def _consent_current(self, consent, model, guard):
        if self._consent != (consent, model) or not _current(guard):
            raise VisualInputError('visual_consent_retired')

    def _begin_probe(self, consent, *, model, effort, endpoint, token, is_current):
        self._consent_current(consent, model, is_current)
        self._revoke_capability()
        probe = _make_probe()
        self._probe = (consent, probe, self._fingerprint(token), model, effort, endpoint)
        return probe

    def _abort_probe(self, consent):
        if self._probe is not None and self._probe[0] is consent:
            self._probe = None

    def _probe_current(self, consent, probe, *, token, model, effort, endpoint, is_current):
        self._consent_current(consent, model, is_current)
        if self._probe != (consent, probe, self._fingerprint(token), model, effort, endpoint):
            self._abort_probe(consent)
            raise VisualInputError('visual_probe_retired')

    def _accept_probe(self, consent, probe, answer, *, token, model, effort, endpoint, is_current):
        self._probe_current(consent, probe, token=token, model=model, effort=effort,
                            endpoint=endpoint, is_current=is_current)
        expected = (consent, probe, self._fingerprint(token), model, effort, endpoint)
        if self._probe != expected or not isinstance(answer, str) or len(answer.encode()) > 128 or answer.strip() != probe.expected:
            self._abort_probe(consent)
            raise VisualInputError('visual_probe_unverified')
        receipt = VerifiedImageCapability(_ISSUER)
        self._capability = _Capability(receipt, consent, expected[2], model, effort, endpoint, self._clock(), is_current)
        self._probe = None
        return receipt

    def _revoke_capability(self):
        self._capability = None
        if self._permit is not None:
            self._permit.retire()
            self._permit = None

    def _require_receipt(self, receipt, *, token=None, model=None, effort=None, endpoint=None, check_config=False):
        capability = self._capability
        if capability is None or receipt is not capability.receipt:
            raise VisualInputError('visual_capability_unverified')
        valid = (self._consent == (capability.consent, capability.model)
                 and 0 <= self._clock() - capability.issued <= self._lifetime
                 and _current(capability.guard))
        if token is not None:
            valid = valid and hmac.compare_digest(capability.fingerprint, self._fingerprint(token))
        if check_config:
            valid = valid and (model, effort, endpoint) == (capability.model, capability.effort, capability.endpoint)
        if not valid:
            self._revoke_capability()
            raise VisualInputError('visual_capability_retired')
        return capability

    def prepare_attachment(self, receipt, *, request, image_port, is_current):
        self._require_receipt(receipt)
        if request is None or not callable(is_current) or not _current(is_current):
            raise VisualInputError('visual_request_retired')
        if not all(callable(getattr(image_port, method, None)) for method in ('claim_for_request', 'owns', 'release_bytes')):
            raise VisualInputError('image_port_unavailable')
        if self._permit is not None:
            self._permit.retire()
        claim = None
        try:
            claim = image_port.claim_for_request(request)
            _valid_claim(claim)
            if image_port.owns(claim, request) is not True or not _current(is_current):
                raise VisualInputError('visual_request_retired')
            self._require_receipt(receipt)
            permit = VisualAttachmentPermit(_ISSUER)
            permit._configure(self, receipt, request, image_port, claim, is_current)
            self._permit = permit
            return permit
        except Exception:
            _drop_bytes(claim, image_port)
            raise VisualInputError('image_unavailable') from None


class VisualAttachmentPermit(_Issued):
    __slots__ = ('_controller', '_receipt', '_request', '_port', '_claim', '_guard',
                 '_digest', '_sent', '_completed', '_retired', '_released')

    def _configure(self, controller, receipt, request, port, claim, guard):
        self._controller, self._receipt, self._request = controller, receipt, request
        self._port, self._claim, self._guard = port, claim, guard
        self._digest = hashlib.sha256(claim.png).digest()
        self._sent = self._completed = self._retired = self._released = False

    @property
    def used_image(self):
        """Historical fact set only after this image request actually completed."""
        return self._completed

    def _check(self, *, token=None, model=None, effort=None, endpoint=None, check_config=False):
        try:
            if self._retired or self._controller._permit is not self:
                raise VisualInputError('visual_request_retired')
            self._controller._require_receipt(self._receipt, token=token, model=model, effort=effort,
                                              endpoint=endpoint, check_config=check_config)
            if not _current(self._guard) or self._port.owns(self._claim, self._request) is not True:
                raise VisualInputError('visual_request_retired')
        except Exception:
            self.retire()
            raise VisualInputError('visual_request_retired') from None

    def _begin_send(self, *, token, model, effort, endpoint):
        if self._sent:
            raise VisualInputError('visual_request_already_sent')
        self._check(token=token, model=model, effort=effort, endpoint=endpoint, check_config=True)
        try:
            _valid_claim(self._claim)
            if not hmac.compare_digest(hashlib.sha256(self._claim.png).digest(), self._digest):
                raise VisualInputError('image_changed')
            part = {'type': 'input_image', 'detail': 'high',
                    'image_url': 'data:image/png;base64,' + base64.b64encode(self._claim.png).decode('ascii')}
            self._sent = True
            return part
        except Exception:
            self.retire()
            raise VisualInputError('image_invalid') from None

    def _mark_completed(self, *, token, model, effort, endpoint):
        self._check(token=token, model=model, effort=effort, endpoint=endpoint, check_config=True)
        if not self._sent:
            raise VisualInputError('visual_request_not_sent')
        self._completed = True
        self._release_bytes()

    def _release_bytes(self):
        if not self._released:
            self._released = True
            _drop_bytes(self._claim, self._port)

    def retire(self):
        self._retired = True
        self._release_bytes()

    def validate_for_publication(self):
        if not self._completed:
            return False
        try:
            self._check()
            return True
        except VisualInputError:
            return False
