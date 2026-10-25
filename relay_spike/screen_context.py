"""Ephemeral selected-screen ports. No capture, credentials, disk writes or networking.

Only an inherited native helper channel may supply these frames. A valid frame
is task evidence, never a permission grant, personal fact, or model instruction.
"""
from __future__ import annotations

from dataclasses import dataclass
import base64
import hashlib
import json
import struct
import zlib
import re
import threading
import time
from uuid import UUID

_MAX_FRAME = 16384
_MAX_AGE = 10_000_000_000
_FENCES = {'captureSessionID', 'sessionEpoch', 'presentationGeneration', 'requestID'}
_IDENTITY = _FENCES | {'source', 'selectionRevision', 'permissionRevision',
                       'capturedUptimeNanoseconds', 'contentDigest', 'imageDigest'}
_TEXT_KEYS = _IDENTITY | {'schemaVersion', 'kind', 'text', 'provenance'}
_RETIRE_KEYS = _FENCES | {'schemaVersion', 'kind', 'selectionRevision', 'permissionRevision', 'reasonCode'}
_RETIRE_REASONS = {'selection_changed', 'permission_revoked', 'source_closed', 'context_changed', 'context_expired', 'request_superseded', 'user_stop'}
_HASH = re.compile(r'[0-9a-f]{64}\Z')


def _integer(value, low=1, high=2**64-1):
    if type(value) is not int or not low <= value <= high:
        raise ValueError('Invalid screen counter.')
    return value


def _string(value, limit, *, multiline=False):
    if not isinstance(value, str) or not 0 < len(value.encode('utf-8')) <= limit:
        raise ValueError('Invalid screen text budget.')
    if any(ord(c) < 32 and not (multiline and c in '\n\t') for c in value):
        raise ValueError('Invalid screen text controls.')
    return value


def _uuid(value):
    if not isinstance(value, str) or len(value) != 36:
        raise ValueError('Invalid screen identity.')
    parsed = UUID(value)
    if str(parsed) != value.lower():
        raise ValueError('Noncanonical screen identity.')
    return str(parsed)


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate screen field.')
        result[key] = value
    return result


def _load(payload):
    if not isinstance(payload, bytes) or not 0 < len(payload) <= _MAX_FRAME:
        raise ValueError('Invalid screen frame budget.')
    value = json.loads(payload.decode('utf-8', errors='strict'), object_pairs_hook=_pairs,
                       parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Invalid number.')))
    if not isinstance(value, dict):
        raise ValueError('Invalid screen frame.')
    return value


def _fences(value):
    return (_uuid(value['captureSessionID']), _integer(value['sessionEpoch']),
            _integer(value['presentationGeneration']), _uuid(value['requestID']))


def _source(value):
    if not isinstance(value, dict) or set(value) != {'windowID', 'bundleID', 'processID', 'label'}:
        raise ValueError('Invalid screen source.')
    return (_integer(value['windowID'], high=2**32-1), _string(value['bundleID'], 160),
            _integer(value['processID'], high=2**31-1), _string(value['label'], 160))


def _identity(value):
    hashes = (value['contentDigest'], value['imageDigest'])
    if any(not isinstance(h, str) or not _HASH.fullmatch(h) for h in hashes):
        raise ValueError('Invalid screen digest.')
    return (_fences(value), _source(value['source']), _integer(value['selectionRevision']),
            _integer(value['permissionRevision']), _integer(value['capturedUptimeNanoseconds']), *hashes)


@dataclass(frozen=True)
class ScreenObservation:
    identity: tuple
    text: str
    @property
    def request(self):
        return self.identity[0]
    @property
    def captured_ns(self):
        return self.identity[4]


class SupplementalScreenProvider:
    """Strict native text consumer with provider-issued identity and revision checks.

    Pass answer-lane ContextSnippet as snippet_factory when composing the helper.
    Final native publication still needs one bounded producer observation recheck.
    The lock covers helper receive/generation threads; callbacks run after clearing.
    """
    def __init__(self, *, now_ns=time.monotonic_ns, on_invalidation=lambda: None, snippet_factory=None):
        self._now, self._changed, self._factory = now_ns, on_invalidation, snippet_factory
        self._lock = threading.RLock()
        self._observation = self._snippet = None
        self._high_water = None
        self._blocked_authority = None
        self._last_retirement = None
        self._images = ScreenImageAssembler(now_ns=now_ns)

    def _current(self, native):
        if self._observation is None:
            return False
        try:
            return (_fences(native) == self._observation.request
                    and 0 <= self._now() - self._observation.captured_ns <= _MAX_AGE)
        except (KeyError, ValueError, TypeError, UnicodeError):
            return False

    def ingest(self, payload: bytes, native) -> bool:
        try:
            frame = _load(payload)
            if set(frame) != _TEXT_KEYS or type(frame['schemaVersion']) is not int or frame['schemaVersion'] != 1:
                return False
            if frame['kind'] != 'screen_context' or frame['provenance'] != 'local_ocr':
                return False
            identity = _identity(frame)
            if identity[0] != _fences(native) or not 0 <= self._now() - identity[4] <= _MAX_AGE:
                return False
            text = _string(frame['text'], 8192, multiline=True)
            observation = ScreenObservation(identity, text)
            with self._lock:
                previous = self._high_water
                if previous and previous[0][:2] == identity[0][:2]:
                    if identity[2] < previous[2] or identity[3] < previous[3] or identity[4] <= previous[4]:
                        return False
                    if identity[0][2] < previous[0][2] or (identity[0][2] == previous[0][2] and identity[0][3] != previous[0][3]):
                        return False
                    if identity[1] != previous[1] and identity[2] == previous[2]:
                        return False
                if self._blocked_authority and identity[0][:2] == self._blocked_authority[0][:2]:
                    blocked = self._blocked_authority
                    if identity[2] <= blocked[2] and identity[3] <= blocked[3]:
                        return False
                factory = self._factory
                if factory is None:
                    from .conversation_context import ContextSnippet
                    factory = ContextSnippet
                snippet = factory(kind='screen_text', text=text, source=identity[1][3],
                                  captured_uptime_ns=identity[4], session_id=native['captureSessionID'],
                                  presentation_generation=identity[0][2], provenance='local_ocr')
                replaced = self._snippet is not None
                self._observation, self._snippet, self._high_water = observation, snippet, identity
                self._images.clear()
                self._blocked_authority = None
            if replaced:
                self._changed()
            return True
        except (KeyError, ValueError, TypeError, UnicodeError, OverflowError, RecursionError):
            return False

    def __call__(self, native):
        with self._lock:
            return self._snippet if self._current(native) else None

    def validate_current(self, snippet, native) -> bool:
        with self._lock:
            return snippet is not None and snippet is self._snippet and self._current(native)

    def current_observation(self, native):
        """Read-only original issued identity, never a copy or permission grant."""
        with self._lock:
            return self._observation if self._current(native) else None

    def owns_observation(self, observation, native) -> bool:
        with self._lock:
            return observation is not None and observation is self._observation and self._current(native)

    def invalidate(self, *, require_new_authority=True):
        with self._lock:
            if require_new_authority and self._high_water:
                self._blocked_authority = self._high_water
            self._observation = self._snippet = None
            self._images.clear()
        self._changed()

    def retire_frame(self, payload, native):
        try:
            frame = _load(payload)
            if set(frame) != _RETIRE_KEYS or type(frame['schemaVersion']) is not int or frame['schemaVersion'] != 1 or frame['kind'] != 'screen_context_retired':
                return False
            reason = frame['reasonCode']
            if reason not in _RETIRE_REASONS:
                return False
            record = (_fences(frame), _integer(frame['selectionRevision']), _integer(frame['permissionRevision']), reason)
            with self._lock:
                if record == self._last_retirement:
                    return True  # Exact duplicate acknowledgement never mutates a newer context.
                observed = self._observation
                if observed is None or record[0] != observed.request or record[0] != _fences(native) or record[1:3] != observed.identity[2:4]:
                    return False
                if reason in {'selection_changed', 'permission_revoked', 'source_closed', 'user_stop'}:
                    self._blocked_authority = self._high_water
                self._observation = self._snippet = None
                self._images.clear()
                self._last_retirement = record
            self._changed()
            return True
        except (KeyError, ValueError, TypeError, UnicodeError, OverflowError, RecursionError):
            return False

    def ingest_image(self, payload, native, *, policy=None, model='', account_id=''):
        with self._lock:
            if not isinstance(policy, ImageInputPolicy) or not policy.allows(model=model, account_id=account_id) or not self._current(native):
                self._images.clear()
                return False
            return self._images.ingest(payload, self._observation)

    def image_input(self, native, *, policy=None, model='', account_id=''):
        with self._lock:
            if not isinstance(policy, ImageInputPolicy) or not policy.allows(model=model, account_id=account_id) or not self._current(native):
                self._images.clear()
                return None
            image = self._images.completed(self._observation)
            if image is None:
                return None
            return {'type': 'input_image', 'image_url': 'data:image/png;base64,' + base64.b64encode(image).decode('ascii'), 'detail': 'high'}

@dataclass(frozen=True)
class ImageInputPolicy:
    model: str = ''
    account_id: str = ''
    model_supports_images: bool | None = None
    user_enabled: bool = False

    def __post_init__(self):
        if not isinstance(self.model, str) or not isinstance(self.account_id, str) or len(self.model.encode()) > 160 or len(self.account_id.encode()) > 160:
            raise ValueError('Invalid image policy identity.')
        if self.model_supports_images is not None and type(self.model_supports_images) is not bool or type(self.user_enabled) is not bool:
            raise ValueError('Invalid image capability policy.')

    def allows(self, *, model, account_id):
        # This typed host policy is NEVER read from screen JSON. Construct it only
        # after trusted model/account capability verification and user enablement.
        return (self.model_supports_images is True and self.user_enabled is True
                and bool(self.model) and bool(self.account_id)
                and self.model == model and self.account_id == account_id)


_IMAGE_COMMON = _IDENTITY | {'schemaVersion', 'kind', 'transferID'}
_IMAGE_MAX = 2 * 1024 * 1024
_IMAGE_CHUNK = 6144
_IMAGE_TTL = 2_000_000_000


class ScreenImageAssembler:
    """One bounded PNG transfer. Source/request change retires all transient bytes.

    Native sends lazily under the helper's queue backpressure. Nothing is decoded
    or uploaded here; only validated PNG bytes can become an input_image part.
    """
    def __init__(self, *, now_ns=time.monotonic_ns):
        self._now = now_ns
        self.clear()

    def clear(self):
        self._active = None
        self._complete = None

    def ingest(self, payload, observation):
        try:
            frame = _load(payload)
            if type(frame.get('schemaVersion')) is not int or frame['schemaVersion'] != 1:
                raise ValueError('Invalid image schema.')
            identity, transfer = _identity(frame), _uuid(frame['transferID'])
            if identity != observation.identity or not 0 <= self._now() - observation.captured_ns <= _MAX_AGE:
                raise ValueError('Retired image identity.')
            kind = frame['kind']
            if kind == 'screen_image_begin':
                if set(frame) != _IMAGE_COMMON | {'mimeType', 'width', 'height', 'totalBytes', 'chunkCount', 'sha256'}:
                    raise ValueError('Invalid image begin.')
                if self._active is not None:
                    raise ValueError('Image transfer busy.')
                size = _integer(frame['totalBytes'], high=_IMAGE_MAX)
                count = _integer(frame['chunkCount'], high=(_IMAGE_MAX + _IMAGE_CHUNK - 1) // _IMAGE_CHUNK)
                if count != (size + _IMAGE_CHUNK - 1) // _IMAGE_CHUNK or frame['mimeType'] != 'image/png':
                    raise ValueError('Invalid image bounds.')
                width, height = _integer(frame['width'], high=1920), _integer(frame['height'], high=1920)
                digest = frame['sha256']
                if not isinstance(digest, str) or not _HASH.fullmatch(digest):
                    raise ValueError('Invalid image digest.')
                self._complete = None
                self._active = dict(identity=identity, transfer=transfer, size=size, count=count, width=width, height=height,
                                    digest=digest, started=self._now(), next_index=0, data=bytearray())
                return True
            active = self._active
            if active is None or identity != active['identity'] or transfer != active['transfer']:
                raise ValueError('Missing image begin.')
            if not 0 <= self._now() - active['started'] <= _IMAGE_TTL:
                raise ValueError('Expired image transfer.')
            if kind == 'screen_image_chunk':
                if set(frame) != _IMAGE_COMMON | {'index', 'data'}:
                    raise ValueError('Invalid image chunk.')
                index = _integer(frame['index'], low=0)
                if index != active['next_index'] or index >= active['count']:
                    raise ValueError('Invalid image order.')
                encoded = _string(frame['data'], 8192)
                data = base64.b64decode(encoded, validate=True)
                expected = min(_IMAGE_CHUNK, active['size'] - len(active['data']))
                if len(data) != expected or base64.b64encode(data).decode('ascii') != encoded:
                    raise ValueError('Invalid image chunk budget.')
                active['data'].extend(data)
                active['next_index'] += 1
                return True
            if kind != 'screen_image_end' or set(frame) != _IMAGE_COMMON:
                raise ValueError('Invalid image end.')
            data = bytes(active['data'])
            if active['next_index'] != active['count'] or len(data) != active['size'] or hashlib.sha256(data).hexdigest() != active['digest']:
                raise ValueError('Incomplete image transfer.')
            _validate_png(data, active['width'], active['height'])
            self._active = None
            self._complete = (identity, data)
            return True
        except (KeyError, ValueError, TypeError, UnicodeError, OverflowError, RecursionError, struct.error):
            self.clear()
            return False

    def completed(self, observation):
        if self._complete is None:
            return None
        if self._complete[0] != observation.identity or not 0 <= self._now() - observation.captured_ns <= _MAX_AGE:
            self.clear()
            return None
        return self._complete[1]


def _validate_png(data, width, height):
    # Bound dimensions and basic PNG structure without decompressing untrusted data.
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Invalid PNG signature.')
    offset, saw_header, saw_pixels, saw_end = 8, False, False, False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError('Incomplete PNG chunk.')
        length, kind = struct.unpack('>I4s', data[offset:offset+8])
        end = offset + 12 + length
        if end > len(data):
            raise ValueError('Oversized PNG chunk.')
        body = data[offset+8:end-4]
        crc = struct.unpack('>I', data[end-4:end])[0]
        if zlib.crc32(kind + body) != crc:
            raise ValueError('Invalid PNG checksum.')
        if not saw_header:
            if kind != b'IHDR' or length != 13 or struct.unpack('>II', body[:8]) != (width, height):
                raise ValueError('Invalid PNG dimensions.')
            saw_header = True
        elif kind == b'IHDR':
            raise ValueError('Duplicate PNG header.')
        if kind == b'IDAT':
            saw_pixels = True
        if kind == b'IEND':
            if length != 0 or end != len(data):
                raise ValueError('Invalid PNG end.')
            saw_end = True
        offset = end
    if not saw_header or not saw_pixels or not saw_end:
        raise ValueError('Incomplete PNG.')
