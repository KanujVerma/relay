"""Bounded attempt metadata only. Never a source/account/publication grant."""
import asyncio
from dataclasses import asdict, dataclass
import json
import math
from pathlib import Path
from . import protected_storage as storage

FILENAME = 'answer-attempt-diagnostic.json'
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
class TransportObservation:
    httpStatus: int | None = None
    failureKind: str | None = None
    transportCode: str | None = None
    providerCode: str | None = None
    paramCategory: str | None = None
    contentType: str = 'none'
    lastEvent: str = 'none'
    itemKind: str = 'none'
    itemStatusPresent: bool | None = None
    itemStatus: str = 'none'
    partKind: str = 'none'
    streamBytesAtStop: int = 0
    eventCount: int = 0


class TransportObservationAttempt:
    def __init__(self): self.fields = asdict(TransportObservation())
    def response(self, status, content_type):
        self.fields['httpStatus'] = status if type(status) is int and 100 <= status <= 599 else None
        self.fields['contentType'] = 'sse' if isinstance(content_type, str) and content_type.lower().startswith('text/event-stream') else 'other'
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
        self.fields['providerCode'] = fixed(provider, PROVIDER_CODES, None)
        self.fields['paramCategory'] = fixed(param, PARAMS, None)
    def snapshot(self): return TransportObservation(**self.fields)


_TIMINGS = ('token_ready_ms', 'client_ready_ms', 'request_started_ms', 'response_headers_ms',
    'first_text_ms', 'response_completed_ms', 'finished_ms')
_FIELDS = frozenset(('schemaVersion', 'attemptIndex', 'startedMonotonicNanoseconds', 'finishedMonotonicNanoseconds', 'transportOutcome',
    'providerTerminal', 'outputBytes', 'timing', 'transport', 'hostOutcome', 'validationCode'))


def _validate(record):
    if type(record) is not dict or set(record) != _FIELDS or type(record['schemaVersion']) is not int or record['schemaVersion'] != 1:
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
        contentType={'none', 'sse', 'other'}, lastEvent=EVENTS, itemKind={'none', 'reasoning', 'message', 'other'},
        itemStatus={'none', 'missing', 'null', 'in_progress', 'completed', 'incomplete', 'other'}, partKind={'none', 'reasoning_text', 'output_text', 'other'})
    for name, allowed in enums.items():
        if meta[name] is not None and (type(meta[name]) is not str or meta[name] not in allowed): raise ValueError('answer_diagnostic_invalid')
    if meta['httpStatus'] is not None and not (type(meta['httpStatus']) is int and 100 <= meta['httpStatus'] <= 599): raise ValueError('answer_diagnostic_invalid')
    if meta['itemStatusPresent'] is not None and type(meta['itemStatusPresent']) is not bool: raise ValueError('answer_diagnostic_invalid')
    for name in ('streamBytesAtStop', 'eventCount'):
        if type(meta[name]) is not int or not 0 <= meta[name] <= 2**64-1: raise ValueError('answer_diagnostic_invalid')


def build_record(timing, *, host_outcome, validation_code):
    record = dict(schemaVersion=1, attemptIndex=timing.request_index, startedMonotonicNanoseconds=timing.started_uptime_nanoseconds,
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
