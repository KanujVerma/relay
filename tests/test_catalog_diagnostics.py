"""Content-free latest diagnostics through real catalog code, synthetic HTTP only."""
import asyncio
import importlib
import json
import os
from pathlib import Path
import stat
import tempfile
import time
import unittest
from unittest.mock import patch

import httpx
from relay_spike import catalog_diagnostics
from relay_spike.account_oauth import AccountOAuthService, AccountOAuthError
from relay_spike.account_store import AccountCredentialStore, AccountStoreError
from tests.test_account_store import grant, KEY, NOW

GENERATION = '00000000-0000-0000-0000-000000000001'
TOKEN = 'synthetic-catalog-private-token-sentinel'
RAW_SECRET = 'synthetic-raw-body-secret-sentinel'
MODEL = dict(slug='synthetic-model-name-sentinel', display_name='Synthetic display sentinel', visibility='list')
FIELDS = {'schemaVersion', 'outcome', 'httpStatus', 'bytesAtStop', 'declaredContentLength',
          'modelsPresent', 'rawModelCount', 'visibleModelCount', 'monotonicNanoseconds'}


class CatalogDiagnosticsTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(); self.addCleanup(self.folder.cleanup)
        self.directory = Path(self.folder.name) / 'Accounts'
        self.store = AccountCredentialStore(self.directory, KEY, now=lambda: NOW)
        host = self.store.initialize()
        self.identity = self.store.save_registration(grant(host, access_token=TOKEN))
        self.store.select(self.identity, GENERATION)
        self.requests = []

    def service(self, response, *, writer=None):
        def handler(request):
            self.requests.append(request)
            self.assertEqual(request.method, 'GET'); self.assertEqual(request.url.path, '/v1/models')
            self.assertEqual(request.headers['authorization'], 'Bearer ' + TOKEN)
            return response(request) if callable(response) else response
        options = {} if writer is None else {'catalog_diagnostic_writer': writer}
        return AccountOAuthService(self.store, client_factory=lambda **kw: httpx.AsyncClient(
            transport=httpx.MockTransport(handler), **kw), **options)

    def latest(self):
        path = self.directory / catalog_diagnostics.FILENAME
        raw = path.read_bytes(); value = json.loads(raw)
        self.assertLessEqual(len(raw), 1024); self.assertEqual(set(value), FIELDS)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(path.stat().st_nlink, 1); self.assertEqual(path.stat().st_uid, os.getuid())
        for secret in (TOKEN, RAW_SECRET, MODEL['slug'], MODEL['display_name'], 'https://', 'synthetic@example.test'):
            self.assertNotIn(secret.encode(), raw)
        self.assertIs(type(value['monotonicNanoseconds']), int)
        return value

    async def test_actual_catalog_success_writes_exact_latest_safe_record_and_preserves_store(self):
        before = self.store.metadata(); started = time.monotonic_ns()
        body = {'models': [MODEL, dict(slug='hidden', display_name='Hidden', visibility='hidden')], 'ignored': RAW_SECRET}
        response = httpx.Response(200, json=body, headers={'x-private-test': RAW_SECRET})
        models = await self.service(response).catalog(self.identity, GENERATION)
        self.assertEqual(models, [dict(slug=MODEL['slug'], displayName=MODEL['display_name'])])
        value = self.latest()
        self.assertEqual(value['outcome'], 'valid'); self.assertEqual(value['httpStatus'], 200)
        self.assertEqual(value['bytesAtStop'], len(response.content))
        self.assertEqual(value['declaredContentLength'], len(response.content))
        self.assertTrue(value['modelsPresent']); self.assertEqual(value['rawModelCount'], 2)
        self.assertEqual(value['visibleModelCount'], 1)
        self.assertGreaterEqual(value['monotonicNanoseconds'], started)
        self.assertLessEqual(value['monotonicNanoseconds'], time.monotonic_ns())
        self.assertEqual(self.store.metadata(), before)
        await self.service(httpx.Response(200, json={'models': []})).catalog(self.identity, GENERATION)
        self.assertEqual(self.latest()['outcome'], 'empty_visible')
        self.assertEqual([p.name for p in self.directory.glob('*diagnostic*')], [catalog_diagnostics.FILENAME])

    async def test_oversize_records_bytes_at_stop_and_original_error_without_parsing_or_leaking(self):
        prefix = b'{"models":[],"ignored":"'; suffix = b'"}'
        body = prefix + b'x' * (65537 - len(prefix) - len(suffix)) + suffix
        with self.assertRaises(AccountOAuthError) as error:
            await self.service(httpx.Response(200, content=body)).catalog(self.identity, GENERATION)
        self.assertEqual(error.exception.code, 'authorization_failed')
        value = self.latest()
        self.assertEqual(value['outcome'], 'body_limit'); self.assertEqual(value['httpStatus'], 200)
        self.assertEqual(value['bytesAtStop'], 65537); self.assertEqual(value['declaredContentLength'], 65537)
        self.assertIsNone(value['modelsPresent']); self.assertIsNone(value['rawModelCount'])
        self.assertIsNone(value['visibleModelCount'])

    async def test_exact_existing_limit_and_partial_oversize_count_are_distinct(self):
        prefix = b'{"models":[],"ignored":"'; suffix = b'"}'
        exact = prefix + b'x' * (65536 - len(prefix) - len(suffix)) + suffix
        self.assertEqual(await self.service(httpx.Response(200, content=exact)).catalog(self.identity, GENERATION), [])
        self.assertEqual(self.latest()['bytesAtStop'], 65536)
        self.assertEqual(self.latest()['outcome'], 'empty_visible')
        closed = []
        class Partial(httpx.AsyncByteStream):
            async def __aiter__(self):
                yield b'x' * 65537
                raise AssertionError('The reader must stop before the rest of the declared body')
            async def aclose(self): closed.append(True)
        with self.assertRaises(AccountOAuthError):
            await self.service(httpx.Response(200, stream=Partial(), headers={'content-length': '131074'})).catalog(self.identity, GENERATION)
        value = self.latest()
        self.assertEqual(value['outcome'], 'body_limit'); self.assertEqual(value['bytesAtStop'], 65537)
        self.assertEqual(value['declaredContentLength'], 131074); self.assertTrue(closed)

    async def test_http_json_shape_and_visible_bounds_keep_existing_outcomes(self):
        cases = [
            (httpx.Response(503, json={'error': RAW_SECRET}), 'http_error', 'authorization_failed', None, None, None),
            (httpx.Response(200, content=RAW_SECRET.encode()), 'invalid_json', 'authorization_failed', None, None, None),
            (httpx.Response(200, json=[]), 'object_shape', 'authorization_failed', None, None, None),
            (httpx.Response(200, json={}), 'models_missing', 'catalog_unavailable', False, None, None),
            (httpx.Response(200, json={'models': {}}), 'models_shape', 'catalog_unavailable', True, None, None),
            (httpx.Response(200, json={'models': []}), 'empty_visible', None, True, 0, 0),
            (httpx.Response(200, json={'models': [{'visibility': 'hidden'}]}), 'empty_visible', None, True, 1, 0),
            (httpx.Response(200, json={'models': [dict(slug='x', visibility='list')]}), 'model_fields_invalid', 'catalog_unavailable', True, 1, 1),
            (httpx.Response(200, json={'models': [MODEL] * 33}), 'visible_limit', 'catalog_unavailable', True, 33, 33),
            (httpx.Response(200, json={'models': [{'visibility': 'hidden'}] * 257}), 'raw_limit', 'catalog_unavailable', True, 257, 0),
        ]
        for response, outcome, code, present, raw, visible in cases:
            with self.subTest(outcome=outcome):
                if code:
                    with self.assertRaises(AccountOAuthError) as error:
                        await self.service(response).catalog(self.identity, GENERATION)
                    self.assertEqual(error.exception.code, code)
                    if response.status_code == 503: self.assertEqual(error.exception.status, 503)
                else:
                    self.assertEqual(await self.service(response).catalog(self.identity, GENERATION), [])
                value = self.latest()
                self.assertEqual(value['outcome'], outcome); self.assertEqual(value['modelsPresent'], present)
                self.assertEqual(value['rawModelCount'], raw); self.assertEqual(value['visibleModelCount'], visible)

    async def test_token_failure_is_redacted_and_never_makes_an_http_request(self):
        failure = AccountStoreError(RAW_SECRET)
        with patch.object(self.store, 'active_access_token', side_effect=failure):
            with self.assertRaises(AccountStoreError) as error:
                await self.service(httpx.Response(200, json={'models': []})).catalog(self.identity, GENERATION)
        self.assertIs(error.exception, failure); self.assertEqual(self.requests, [])
        value = self.latest(); self.assertEqual(value['outcome'], 'token_unavailable')
        self.assertIsNone(value['httpStatus']); self.assertEqual(value['bytesAtStop'], 0)
        self.assertIsNone(value['modelsPresent'])

    async def test_cancel_closes_actual_mock_response_and_records_no_raw_details(self):
        entered = asyncio.Event(); closed = []
        class Held(httpx.AsyncByteStream):
            async def __aiter__(self):
                entered.set(); await asyncio.Event().wait(); yield b''
            async def aclose(self): closed.append(True)
        task = asyncio.create_task(self.service(httpx.Response(200, stream=Held(),
            headers={'content-length': '777', 'x-private-test': RAW_SECRET})).catalog(self.identity, GENERATION))
        await entered.wait(); task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        self.assertTrue(closed)
        value = self.latest(); self.assertEqual(value['outcome'], 'cancelled')
        self.assertEqual(value['bytesAtStop'], 0); self.assertEqual(value['declaredContentLength'], 777)
        self.assertIsNone(value['rawModelCount'])

    async def test_cancel_during_error_cleanup_remains_cancelled_not_a_stale_error_label(self):
        closing = asyncio.Event()
        class HeldClose(httpx.AsyncByteStream):
            async def __aiter__(self): yield b'x' * 65537
            async def aclose(self): closing.set(); await asyncio.Event().wait()
        task = asyncio.create_task(self.service(httpx.Response(200, stream=HeldClose())).catalog(self.identity, GENERATION))
        await closing.wait(); task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        value = self.latest()
        self.assertEqual(value['outcome'], 'cancelled'); self.assertEqual(value['bytesAtStop'], 65537)

    async def test_writer_failure_cannot_change_success_error_or_cancel(self):
        failures = []
        def denied(directory, record):
            failures.append(record['outcome']); raise OSError(RAW_SECRET)
        expected = [dict(slug=MODEL['slug'], displayName=MODEL['display_name'])]
        self.assertEqual(await self.service(httpx.Response(200, json={'models': [MODEL]}), writer=denied).catalog(self.identity, GENERATION), expected)
        with self.assertRaises(AccountOAuthError) as error:
            await self.service(httpx.Response(503, json={'error': RAW_SECRET}), writer=denied).catalog(self.identity, GENERATION)
        self.assertEqual(error.exception.code, 'authorization_failed'); self.assertEqual(error.exception.status, 503)
        entered = asyncio.Event()
        class Held(httpx.AsyncByteStream):
            async def __aiter__(self): entered.set(); await asyncio.Event().wait(); yield b''
        task = asyncio.create_task(self.service(httpx.Response(200, stream=Held()), writer=denied).catalog(self.identity, GENERATION))
        await entered.wait(); task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        self.assertEqual(failures, ['valid', 'http_error', 'cancelled'])
        self.assertFalse((self.directory / catalog_diagnostics.FILENAME).exists())

    async def test_diagnostic_symlink_does_not_write_through_or_change_catalog_success(self):
        victim = Path(self.folder.name) / 'unrelated'; victim.write_bytes(RAW_SECRET.encode())
        (self.directory / catalog_diagnostics.FILENAME).symlink_to(victim)
        models = await self.service(httpx.Response(200, json={'models': [MODEL]})).catalog(self.identity, GENERATION)
        self.assertEqual(len(models), 1); self.assertEqual(victim.read_bytes(), RAW_SECRET.encode())

    def test_import_and_construction_are_inert_and_writer_rejects_nonfixed_payload(self):
        with (patch.object(catalog_diagnostics.storage, 'directory', side_effect=AssertionError('unexpected directory IO')),
              patch.object(catalog_diagnostics.storage, 'replace_bytes', side_effect=AssertionError('unexpected write'))):
            importlib.reload(catalog_diagnostics)
            catalog_diagnostics.CatalogDiagnostic()
            AccountOAuthService(self.store)
        record = catalog_diagnostics.CatalogDiagnostic().record()
        record['unsafe'] = RAW_SECRET
        with self.assertRaises(ValueError): catalog_diagnostics.write_catalog_diagnostic(self.directory, record)
        self.assertFalse((self.directory / catalog_diagnostics.FILENAME).exists())
        missing = Path(self.folder.name) / 'missing'
        with self.assertRaises(catalog_diagnostics.storage.ProtectedStorageError):
            catalog_diagnostics.write_catalog_diagnostic(missing, catalog_diagnostics.CatalogDiagnostic().record())
        self.assertFalse(missing.exists())
