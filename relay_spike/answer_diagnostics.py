"""Bounded attempt metadata only. Never a source/account/publication grant."""
import asyncio
from contextvars import ContextVar
from dataclasses import asdict, dataclass, field
import json
import math
from pathlib import Path
from . import protected_storage as storage
from .generated_answer import strict_json, CardError

FILENAME = 'answer-attempt-diagnostic.json'
INSPECTION_DEADLINE = ContextVar('answer_diagnostic_inspection_deadline', default=None)
INSPECTIONS = frozenset(('not_run', 'encoded_uninspected', 'no_time', 'empty', 'complete_json', 'invalid_json',
    'body_limit', 'prefix_sse', 'prefix_html', 'truncated', 'read_error', 'timeout'))
ENCODINGS = frozenset(('missing', 'identity', 'gzip', 'deflate', 'br', 'other'))
ROOT_SHAPES = frozenset(('uninspected', 'empty', 'object', 'array', 'scalar', 'invalid'))
ROOT_STATUSES = frozenset(('uninspected', 'missing', 'other', 'completed', 'in_progress', 'queued', 'failed', 'incomplete', 'cancelled'))
ROOT_OBJECTS = frozenset(('uninspected', 'missing', 'other', 'response', 'list', 'error'))
ERROR_TYPES = frozenset(('missing', 'other', 'oauth', 'authentication', 'permission', 'invalid_request', 'rate_limit', 'server'))
EVENTS = frozenset(('none', 'other', 'error', 'response.created', 'response.in_progress', 'response.completed',
    'response.failed', 'response.incomplete', 'response.output_item.added', 'response.output_item.done',
    'response.content_part.added', 'response.content_part.done', 'response.output_text.delta', 'response.output_text.done',
    'response.refusal.delta', 'response.refusal.done', 'response.reasoning_text.delta', 'response.reasoning_text.done',
    'response.reasoning_summary_part.added', 'response.reasoning_summary_part.done',
    'response.reasoning_summary_text.delta', 'response.reasoning_summary_text.done'))
FAILURES = frozenset(('provider', 'http', 'http_connect_timeout', 'http_read_timeout', 'http_write_timeout',
    'http_pool_timeout', 'http_timeout', 'http_transport', 'deadline', 'payload', 'response_protocol',
    'dependency', 'credential', 'sse', 'guard', 'other'))
TRANSPORT_CODES = frozenset(('other', 'request_unavailable', 'request_rejected', 'request_closed', 'request_busy',
    'request_budget', 'credential_unavailable', 'stream_invalid', 'stream_budget', 'event_budget', 'event_invalid',
    'stream_truncated', 'missing_response_completed', 'invalid_response_lifecycle', 'response_budget',
    'account_changed', 'storage_unavailable', 'reauthentication_required', 'plan_permission_missing', 'credential_request_failed'))
PROVIDER_CODES = frozenset(('subscription_sharing_user_not_eligible', 'subscription_sharing_usage_limit_exceeded',
    'subscription_sharing_usage_unavailable', 'subscription_sharing_unsupported_capability',
    'subscription_sharing_route_not_supported', 'subscription_sharing_invalid_user',
    'chatpass_v2_scope_not_authorized', 'chatpass_v2_invalid_authorization_context', 'subscription_sharing_user_unavailable'))
PARAMS = frozenset(('input', 'model', 'tools', 'reasoning', 'service_tier'))
CARD_CODES = frozenset(('not_run', 'passed', 'other', 'duplicate_key', 'json_budget', 'json_depth', 'nonfinite',
    'invalid_json', 'invalid_unicode', 'text_budget', 'control_character', 'personal_or_authority_claim',
    'neutral_form_required', 'card_schema', 'personal_authority_forbidden', 'coverage_missing', 'detail_schema',
    'language_required', 'python_syntax', 'code_required', 'unsupported_claim', 'prompt_budget'))
HOST_OUTCOMES = frozenset(('answer_emitted', 'abstain_emitted', 'host_timeout', 'cancelled', 'retired', 'publication_denied'))


def fixed(value, allowed, fallback='other'):
    return value if type(value) is str and value in allowed else fallback


def card_code(error):
    return fixed(error.args[0] if error.args else None, CARD_CODES)


@dataclass(frozen=True, slots=True)
class NonSseObservation:
    inspectionOutcome: str = 'not_run'
    bytesAtStop: int = 0
    bodyComplete: bool = False
    encodedBody: str = 'missing'
    rootShape: str = 'uninspected'
    status: str = 'uninspected'
    object: str = 'uninspected'
    errorPresent: bool | None = None
    errorTypeCategory: str = 'missing'
    outputCount: int | None = None
    outputKindMask: int = 0
    contentPartKindMask: int = 0
    refusalPresent: bool | None = None
    ssePrefix: bool | None = None
    rootEventCategory: str = 'none'
    envelopePresent: bool | None = None


@dataclass(frozen=True, slots=True)
class TransportObservation:
    httpStatus: int | None = None
    failureKind: str | None = None
    transportCode: str | None = None
    providerCode: str | None = None
    paramCategory: str | None = None
    contentType: str = 'none'
    sseHeaderPrefix: bool | None = None
    lastEvent: str = 'none'
    itemKind: str = 'none'
    itemStatusPresent: bool | None = None
    itemStatus: str = 'none'
    partKind: str = 'none'
    streamBytesAtStop: int = 0
    eventCount: int = 0
    nonSse: NonSseObservation = field(default_factory=NonSseObservation)


class TransportObservationAttempt:
    def __init__(self): self.fields = asdict(TransportObservation())
    def response(self, status, content_type, content_encoding=None):
        self.fields['httpStatus'] = status if type(status) is int and 100 <= status <= 599 else None
        mime = content_type.split(';', 1)[0].strip().lower() if isinstance(content_type, str) else ''
        self.fields['contentType'] = ('missing' if not mime else 'sse' if mime == 'text/event-stream' else
            'json' if mime == 'application/json' or mime.startswith('application/') and mime.endswith('+json') else
            'html' if mime == 'text/html' else 'plain' if mime == 'text/plain' else 'other')
        self.fields['sseHeaderPrefix'] = isinstance(content_type, str) and content_type.lower().startswith('text/event-stream')
        encoding = content_encoding.strip().lower() if isinstance(content_encoding, str) else ''
        self.fields['nonSse']['encodedBody'] = fixed(encoding, ENCODINGS) if encoding else 'missing'
    def chunk(self, size): self.fields['streamBytesAtStop'] += size
    def event(self, event):
        self.fields['eventCount'] += 1
        self.fields['lastEvent'] = fixed(event.get('type'), EVENTS)
        item, part = event.get('item'), event.get('part')
        self.fields['itemKind'] = fixed(item.get('type'), ('reasoning', 'message')) if isinstance(item, dict) else 'none'
        self.fields['itemStatusPresent'] = 'status' in item if isinstance(item, dict) else None
        self.fields['itemStatus'] = ('missing' if 'status' not in item else 'null' if item['status'] is None else
            fixed(item['status'], ('in_progress', 'completed', 'incomplete'))) if isinstance(item, dict) else 'none'
        self.fields['partKind'] = fixed(part.get('type'), ('reasoning_text', 'output_text')) if isinstance(part, dict) else 'none'
    def failure(self, kind, *, code=None, status=None, provider=None, param=None):
        self.fields['failureKind'] = fixed(kind, FAILURES)
        self.fields['transportCode'] = fixed(code, TRANSPORT_CODES) if code is not None else None
        if status is not None: self.fields['httpStatus'] = status if type(status) is int and 100 <= status <= 599 else None
        if provider is not None: self.fields['providerCode'] = fixed(provider, PROVIDER_CODES, None)
        if param is not None: self.fields['paramCategory'] = fixed(param, PARAMS, None)
    def snapshot(self): return TransportObservation(**{**self.fields, 'nonSse': NonSseObservation(**self.fields['nonSse'])})


def _json_shape(value, observation):
    body = observation.fields['nonSse']; body['rootShape'] = 'object' if isinstance(value, dict) else 'array' if isinstance(value, list) else 'scalar'
    if not isinstance(value, dict): return
    root = value
    body['rootEventCategory'] = fixed(value.get('type'), EVENTS) if 'type' in value else 'none'
    body['envelopePresent'] = isinstance(value.get('response'), dict)
    if body['rootEventCategory'] not in ('none', 'other') and body['envelopePresent']: value = value['response']
    body['status'] = fixed(value.get('status'), ('completed', 'in_progress', 'queued', 'failed', 'incomplete', 'cancelled')) if 'status' in value else 'missing'
    body['object'] = fixed(value.get('object'), ('response', 'list', 'error')) if 'object' in value else 'missing'
    error = root.get('error') if 'error' in root else value.get('error'); root_error = root.get('type') == 'error' or value.get('type') == 'error'
    body['errorPresent'] = 'error' in root or 'error' in value or root_error
    raw_type = error.get('type') if isinstance(error, dict) else error if isinstance(error, str) else 'error' if root_error else None
    types = {'authentication_error': 'authentication', 'permission_error': 'permission', 'invalid_request_error': 'invalid_request',
        'rate_limit_error': 'rate_limit', 'server_error': 'server', 'api_error': 'server', 'oauth_error': 'oauth',
        'invalid_grant': 'oauth', 'invalid_client': 'oauth', 'invalid_scope': 'oauth', 'invalid_token': 'oauth',
        'access_denied': 'oauth', 'unauthorized_client': 'oauth', 'unsupported_grant_type': 'oauth'}
    body['errorTypeCategory'] = types.get(raw_type, 'other') if type(raw_type) is str else 'missing' if raw_type is None else 'other'
    details = error if isinstance(error, dict) else root if root.get('type') == 'error' else value if root_error else None
    if details is not None:
        observation.fields['providerCode'] = fixed(details.get('code'), PROVIDER_CODES, None)
        param = details.get('param')
        if isinstance(param, str) and len(param) <= 256:
            observation.fields['paramCategory'] = next((name for name in PARAMS if param == name or param.startswith(name+'[') or param.startswith(name+'.')), None)
    output = value.get('output')
    if not isinstance(output, list): return
    body['outputCount'] = len(output); body['refusalPresent'] = False
    for item in output:
        if not isinstance(item, dict): body['outputKindMask'] |= 8; continue
        body['outputKindMask'] |= 1 if item.get('type') == 'message' else 2 if item.get('type') == 'reasoning' else 4
        content = item.get('content')
        if not isinstance(content, list): continue
        for part in content:
            if not isinstance(part, dict): body['contentPartKindMask'] |= 16; continue
            kind = part.get('type')
            body['contentPartKindMask'] |= 1 if kind == 'output_text' else 2 if kind == 'reasoning_text' else 4 if kind == 'refusal' else 8
            if kind == 'refusal' or 'refusal' in part: body['refusalPresent'] = True


async def inspect_non_sse(response, observation, deadline):
    """Bounded metadata inspection only; never returns an answer or body."""
    body = observation.fields['nonSse']; data = bytearray()
    if body['encodedBody'] not in ('missing', 'identity'):
        body['inspectionOutcome'] = 'encoded_uninspected'; return
    remaining = deadline-asyncio.get_running_loop().time()
    if remaining <= .05: body['inspectionOutcome'] = 'no_time'; return
    try:
        async with asyncio.timeout(min(.2, remaining-.05)):
            async for chunk in response.aiter_raw():
                data.extend(chunk[:65536-len(data)]); body['bytesAtStop'] = len(data)
                prefix = bytes(data[:128]).lstrip(b' \r\n\t')
                if prefix.startswith(b'\xef\xbb\xbf'): prefix = prefix[3:]
                body['ssePrefix'] = prefix.startswith((b'event:', b'data:', b':'))
                if body['ssePrefix']: body['inspectionOutcome'] = 'prefix_sse'; return
                if prefix.lower().startswith((b'<!doctype html', b'<html', b'<head', b'<body')):
                    body['inspectionOutcome'] = 'prefix_html'; return
                if len(data) >= 65536: body['inspectionOutcome'] = 'body_limit'; return
            body['bodyComplete'] = True
            declared = response.headers.get('content-length')
            if isinstance(declared, str) and declared.isascii() and declared.isdecimal() and len(declared) <= 19 and int(declared) != len(data):
                body['bodyComplete'] = False; body['inspectionOutcome'] = 'truncated'; return
            if not data.strip(): body['inspectionOutcome'] = 'empty'; body['rootShape'] = 'empty'; return
            try: value = strict_json(bytes(data), max_bytes=65536)
            except CardError: body['inspectionOutcome'] = 'invalid_json'; body['rootShape'] = 'invalid'; return
            _json_shape(value, observation); body['inspectionOutcome'] = 'complete_json'
    except asyncio.CancelledError: raise
    except TimeoutError: body['inspectionOutcome'] = 'timeout'
    except Exception as error:
        import httpx
        body['inspectionOutcome'] = 'timeout' if isinstance(error, httpx.TimeoutException) else 'truncated' if isinstance(error, (httpx.RemoteProtocolError, EOFError)) else 'read_error'
    finally: data.clear()


_TIMINGS = ('token_ready_ms', 'client_ready_ms', 'request_started_ms', 'response_headers_ms',
    'first_text_ms', 'response_completed_ms', 'finished_ms')
_FIELDS = frozenset(('schemaVersion', 'attemptIndex', 'startedMonotonicNanoseconds', 'finishedMonotonicNanoseconds', 'transportOutcome',
    'providerTerminal', 'outputBytes', 'timing', 'transport', 'hostOutcome', 'validationCode'))


def _validate(record):
    if type(record) is not dict or set(record) != _FIELDS or type(record['schemaVersion']) is not int or record['schemaVersion'] != 2:
        raise ValueError('answer_diagnostic_invalid')
    for field in ('attemptIndex', 'startedMonotonicNanoseconds', 'finishedMonotonicNanoseconds', 'outputBytes'):
        if type(record[field]) is not int or not 0 <= record[field] <= 2**64-1: raise ValueError('answer_diagnostic_invalid')
    if any(type(record[name]) is not str for name in ('transportOutcome', 'hostOutcome', 'validationCode')):
        raise ValueError('answer_diagnostic_invalid')
    if (record['transportOutcome'] not in ('completed', 'failed', 'cancelled') or record['hostOutcome'] not in HOST_OUTCOMES
            or record['validationCode'] not in CARD_CODES or record['providerTerminal'] not in (None, 'failed', 'incomplete', 'refused', 'completed')):
        raise ValueError('answer_diagnostic_invalid')
    timing = record['timing']
    if type(timing) is not dict or set(timing) != set(_TIMINGS): raise ValueError('answer_diagnostic_invalid')
    if any(value is not None and (type(value) not in (int, float) or not math.isfinite(value) or value < 0) for value in timing.values()):
        raise ValueError('answer_diagnostic_invalid')
    meta = record['transport']
    if type(meta) is not dict or set(meta) != set(asdict(TransportObservation())): raise ValueError('answer_diagnostic_invalid')
    enums = dict(failureKind=FAILURES, transportCode=TRANSPORT_CODES, providerCode=PROVIDER_CODES, paramCategory=PARAMS,
        contentType={'none', 'sse', 'json', 'html', 'plain', 'missing', 'other'}, lastEvent=EVENTS, itemKind={'none', 'reasoning', 'message', 'other'},
        itemStatus={'none', 'missing', 'null', 'in_progress', 'completed', 'incomplete', 'other'}, partKind={'none', 'reasoning_text', 'output_text', 'other'})
    for name, allowed in enums.items():
        if meta[name] is not None and (type(meta[name]) is not str or meta[name] not in allowed): raise ValueError('answer_diagnostic_invalid')
    if meta['httpStatus'] is not None and not (type(meta['httpStatus']) is int and 100 <= meta['httpStatus'] <= 599): raise ValueError('answer_diagnostic_invalid')
    if meta['itemStatusPresent'] is not None and type(meta['itemStatusPresent']) is not bool: raise ValueError('answer_diagnostic_invalid')
    if meta['sseHeaderPrefix'] is not None and type(meta['sseHeaderPrefix']) is not bool: raise ValueError('answer_diagnostic_invalid')
    for name in ('streamBytesAtStop', 'eventCount'):
        if type(meta[name]) is not int or not 0 <= meta[name] <= 2**64-1: raise ValueError('answer_diagnostic_invalid')
    body = meta['nonSse']
    if type(body) is not dict or set(body) != set(asdict(NonSseObservation())): raise ValueError('answer_diagnostic_invalid')
    for name, allowed in dict(inspectionOutcome=INSPECTIONS, encodedBody=ENCODINGS, rootShape=ROOT_SHAPES, status=ROOT_STATUSES,
                             object=ROOT_OBJECTS, errorTypeCategory=ERROR_TYPES, rootEventCategory=EVENTS).items():
        if type(body[name]) is not str or body[name] not in allowed: raise ValueError('answer_diagnostic_invalid')
    for name in ('bodyComplete', 'errorPresent', 'refusalPresent', 'ssePrefix', 'envelopePresent'):
        if body[name] is not None and type(body[name]) is not bool: raise ValueError('answer_diagnostic_invalid')
    for name, maximum in (('bytesAtStop', 65536), ('outputKindMask', 15), ('contentPartKindMask', 31), ('outputCount', 65536)):
        if name == 'outputCount' and body[name] is None: continue
        if type(body[name]) is not int or not 0 <= body[name] <= maximum: raise ValueError('answer_diagnostic_invalid')


def build_record(timing, *, host_outcome, validation_code):
    record = dict(schemaVersion=2, attemptIndex=timing.request_index, startedMonotonicNanoseconds=timing.started_uptime_nanoseconds,
        finishedMonotonicNanoseconds=timing.started_uptime_nanoseconds+int(timing.finished_ms*1_000_000),
        transportOutcome=timing.outcome, providerTerminal=timing.provider_terminal, outputBytes=timing.output_bytes,
        timing={name: getattr(timing, name) for name in _TIMINGS}, transport=asdict(timing.diagnostic or TransportObservation()),
        hostOutcome=host_outcome, validationCode=validation_code)
    _validate(record); return record


def write_record(directory, record):
    _validate(record)
    data = json.dumps(record, separators=(',', ':'), sort_keys=True, allow_nan=False).encode()+b'\n'
    if len(data) > 2048: raise ValueError('answer_diagnostic_budget')
    directory = Path(directory); storage.directory(directory, create=False)
    storage.replace_bytes(directory/FILENAME, data, create_parent=False)


class AnswerDiagnosticSink:
    """Inert sink; one owned joined writer and no stale-attempt overwrite."""
    def __init__(self, directory, *, writer=write_record):
        self.directory, self.writer, self.lock, self.latest = Path(directory), writer, asyncio.Lock(), 0
    async def __call__(self, timing, *, host_outcome, validation_code):
        from .account_oauth import owned_thread
        async with self.lock:
            if timing.request_index <= self.latest: return
            record = build_record(timing, host_outcome=host_outcome, validation_code=validation_code)
            self.latest = timing.request_index
            try: await owned_thread(self.writer, self.directory, record)
            except Exception: pass
