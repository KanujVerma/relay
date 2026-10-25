"""Latest content-free catalog observation. Never account/inference authority."""
import json
from pathlib import Path
import time
from . import protected_storage as storage

FILENAME = 'catalog-diagnostic.json'
_FIELDS = frozenset(('schemaVersion', 'outcome', 'httpStatus', 'bytesAtStop',
    'declaredContentLength', 'modelsPresent', 'rawModelCount', 'visibleModelCount', 'monotonicNanoseconds'))
_OUTCOMES = frozenset(('valid', 'empty_visible', 'body_limit', 'http_error', 'invalid_json',
    'object_shape', 'models_missing', 'models_shape', 'raw_limit', 'model_fields_invalid',
    'visible_limit', 'token_unavailable', 'cancelled', 'timeout', 'transport_error', 'catalog_unavailable'))


class CatalogDiagnostic:
    """Inert per-attempt scalars only; never retains a response, token or body."""
    def __init__(self):
        self.outcome = None
        self.http_status = None
        self.bytes_at_stop = 0
        self.declared_length = None
        self.models_present = None
        self.raw_count = None
        self.visible_count = None

    def fail(self, outcome):
        if self.outcome is None: self.outcome = outcome

    def response(self, status, declared_length):
        self.http_status = status if type(status) is int and 100 <= status <= 599 else None
        if (isinstance(declared_length, str) and declared_length.isascii()
                and declared_length.isdecimal() and len(declared_length) <= 19):
            value = int(declared_length)
            if value <= 2**63 - 1: self.declared_length = value

    def models(self, value):
        self.models_present = 'models' in value
        models = value.get('models')
        if isinstance(models, list):
            self.raw_count = len(models)
            self.visible_count = sum(isinstance(row, dict) and row.get('visibility') == 'list' for row in models)

    def record(self):
        return dict(schemaVersion=1, outcome=self.outcome or 'catalog_unavailable', httpStatus=self.http_status,
            bytesAtStop=self.bytes_at_stop, declaredContentLength=self.declared_length,
            modelsPresent=self.models_present, rawModelCount=self.raw_count, visibleModelCount=self.visible_count,
            monotonicNanoseconds=time.monotonic_ns())


def write_catalog_diagnostic(directory, record):
    """Use the existing owner-only atomic replacement, never create a root."""
    if (type(record) is not dict or set(record) != _FIELDS or type(record['schemaVersion']) is not int
            or record['schemaVersion'] != 1 or record['outcome'] not in _OUTCOMES):
        raise ValueError('catalog_diagnostic_invalid')
    status = record['httpStatus']
    if status is not None and not (type(status) is int and 100 <= status <= 599):
        raise ValueError('catalog_diagnostic_invalid')
    present = record['modelsPresent']
    if present is not None and type(present) is not bool: raise ValueError('catalog_diagnostic_invalid')
    for name in ('bytesAtStop', 'declaredContentLength', 'rawModelCount', 'visibleModelCount', 'monotonicNanoseconds'):
        value = record[name]
        if value is None and name not in ('bytesAtStop', 'monotonicNanoseconds'): continue
        if type(value) is not int or not 0 <= value <= 2**64 - 1: raise ValueError('catalog_diagnostic_invalid')
    encoded = json.dumps(record, sort_keys=True, separators=(',', ':'), allow_nan=False).encode() + b'\n'
    if len(encoded) > 1024: raise ValueError('catalog_diagnostic_budget')
    directory = Path(directory)
    storage.directory(directory, create=False)
    storage.replace_bytes(directory / FILENAME, encoded, create_parent=False)
