"""Content-free latest diagnostics through real catalog code, synthetic HTTP only."""
import asyncio
import importlib
import json
import os
from pathlib import Path
import stat
import shutil
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import httpx
from relay_spike import catalog_diagnostics
from relay_spike.account_oauth import AccountOAuthService, AccountOAuthError
from relay_spike.account_store import AccountCredentialStore, AccountStoreError
from relay_spike.account_bridge import AccountBridge, AccountBootstrap
from tests.test_account_bridge import request
from tests.test_account_store import grant, KEY, NOW

GENERATION = '00000000-0000-0000-0000-000000000001'
TOKEN = 'synthetic-catalog-private-token-sentinel'
RAW_SECRET = 'synthetic-raw-body-secret-sentinel'
MODEL = dict(slug='synthetic-model-name-sentinel', display_name='Synthetic display sentinel', visibility='list')
FIELDS = {'schemaVersion', 'outcome', 'httpStatus', 'bytesAtStop', 'declaredContentLength',
          'modelsPresent', 'rawModelCount', 'visibleModelCount', 'monotonicNanoseconds'}
CATALOG_LIMIT = 1048576  # Models-success policy; parent6122 preserves the original64KiB controls.


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
        body = prefix + b'x' * (CATALOG_LIMIT + 1 - len(prefix) - len(suffix)) + suffix
        with self.assertRaises(AccountOAuthError) as error:
            await self.service(httpx.Response(200, content=body)).catalog(self.identity, GENERATION)
        self.assertEqual(error.exception.code, 'authorization_failed')
        value = self.latest()
        self.assertEqual(value['outcome'], 'body_limit'); self.assertEqual(value['httpStatus'], 200)
        self.assertEqual(value['bytesAtStop'], CATALOG_LIMIT + 1); self.assertEqual(value['declaredContentLength'], CATALOG_LIMIT + 1)
        self.assertIsNone(value['modelsPresent']); self.assertIsNone(value['rawModelCount'])
        self.assertIsNone(value['visibleModelCount'])

    async def test_exact_catalog_limit_and_partial_oversize_count_are_distinct(self):
        prefix = b'{"models":[],"ignored":"'; suffix = b'"}'
        exact = prefix + b'x' * (CATALOG_LIMIT - len(prefix) - len(suffix)) + suffix
        self.assertEqual(await self.service(httpx.Response(200, content=exact)).catalog(self.identity, GENERATION), [])
        self.assertEqual(self.latest()['bytesAtStop'], CATALOG_LIMIT)
        self.assertEqual(self.latest()['outcome'], 'empty_visible')
        closed = []
        class Partial(httpx.AsyncByteStream):
            async def __aiter__(self):
                yield b'x' * (CATALOG_LIMIT + 1)
                raise AssertionError('The reader must stop before the rest of the declared body')
            async def aclose(self): closed.append(True)
        with self.assertRaises(AccountOAuthError):
            await self.service(httpx.Response(200, stream=Partial(), headers={'content-length': str((CATALOG_LIMIT+1)*2)})).catalog(self.identity, GENERATION)
        value = self.latest()
        self.assertEqual(value['outcome'], 'body_limit'); self.assertEqual(value['bytesAtStop'], CATALOG_LIMIT + 1)
        self.assertEqual(value['declaredContentLength'], (CATALOG_LIMIT+1)*2); self.assertTrue(closed)

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
            async def __aiter__(self): yield b'x' * (CATALOG_LIMIT + 1)
            async def aclose(self): closing.set(); await asyncio.Event().wait()
        task = asyncio.create_task(self.service(httpx.Response(200, stream=HeldClose())).catalog(self.identity, GENERATION))
        await closing.wait(); task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        value = self.latest()
        self.assertEqual(value['outcome'], 'cancelled'); self.assertEqual(value['bytesAtStop'], CATALOG_LIMIT + 1)

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

    async def test_held_writer_keeps_control_responsive_and_cancel_waits_for_actual_join(self):
        entered = threading.Event(); release = threading.Event(); returned = threading.Event(); watchdog_fired = threading.Event()
        loop_thread = threading.get_ident(); writer_threads = []; written = []
        def writer(directory, record):
            writer_threads.append(threading.get_ident()); entered.set()
            if not release.wait(3): raise AssertionError('bounded held-writer fixture timed out')
            catalog_diagnostics.write_catalog_diagnostic(directory, record)
            written.append(record['outcome']); returned.set()
        def watchdog():
            if not entered.wait(2) or not release.wait(1): watchdog_fired.set(); release.set()
        safety = threading.Thread(target=watchdog); safety.start()
        out = []
        def factory(store):
            store._now = lambda: NOW
            return AccountOAuthService(store, catalog_diagnostic_writer=writer,
                client_factory=lambda **kw: httpx.AsyncClient(transport=httpx.MockTransport(
                    lambda _: httpx.Response(200, json={'models': [MODEL]})), **kw))
        bridge = AccountBridge(AccountBootstrap('account_control', KEY, self.directory, None, GENERATION), emit=out.append, service_factory=factory)
        try:
            await bridge.start()
            selection = request('select', registrationID=self.identity); await bridge.handle(selection)
            self.assertTrue(await asyncio.to_thread(entered.wait, 2))
            self.assertFalse(returned.is_set(), 'the control loop must run while the writer remains held')
            self.assertFalse(watchdog_fired.is_set(), 'the safety release is not a responsiveness proof')
            status = request('status'); await bridge.handle(status)
            self.assertEqual(out[-1]['requestID'], status['requestID']); self.assertEqual(out[-1]['status'], 'busy')
            cancellation = request('cancel', targetRequestID=selection['requestID']); await bridge.handle(cancellation)
            for _ in range(3): await asyncio.sleep(0)
            self.assertFalse(returned.is_set()); self.assertFalse(bridge._task.done())
            self.assertFalse(any(row['requestID'] in (selection['requestID'], cancellation['requestID']) and row['resultRevision'] == 2 for row in out))
            release.set(); await bridge.drain()
            for identity in (selection['requestID'], cancellation['requestID']):
                terminals = [row for row in out if row['requestID'] == identity and row['resultRevision'] == 2]
                self.assertEqual(len(terminals), 1); self.assertEqual(terminals[0]['status'], 'cancelled')
            self.assertTrue(all(identity != loop_thread for identity in writer_threads))
            self.assertEqual(written, ['valid', 'cancelled']); self.assertEqual(self.latest()['outcome'], 'cancelled')
        finally:
            release.set(); await bridge.close(); safety.join(2)
        self.assertFalse(safety.is_alive())

    async def test_removed_validated_root_is_not_recreated_by_diagnostic_replace(self):
        original = catalog_diagnostics.storage.directory; removed = []
        def interleaved(path, *, create=False):
            original(path, create=create)
            if not create and not removed:
                removed.append(True); shutil.rmtree(self.directory)
        def writer(directory, record):
            with patch.object(catalog_diagnostics.storage, 'directory', side_effect=interleaved):
                catalog_diagnostics.write_catalog_diagnostic(directory, record)
        models = await self.service(httpx.Response(200, json={'models': [MODEL]}), writer=writer).catalog(self.identity, GENERATION)
        self.assertEqual(len(models), 1); self.assertEqual(removed, [True])
        self.assertFalse(self.directory.exists(), 'a telemetry writer cannot recreate a removed Accounts root')

    def test_existing_only_replace_does_not_change_default_creating_callers(self):
        target = Path(self.folder.name) / 'default-owned' / 'value'
        catalog_diagnostics.storage.replace_bytes(target, b'synthetic-public-bytes')
        self.assertEqual(target.read_bytes(), b'synthetic-public-bytes')
        absent = Path(self.folder.name) / 'absent-owned' / 'value'
        with self.assertRaises(catalog_diagnostics.storage.ProtectedStorageError):
            catalog_diagnostics.storage.replace_bytes(absent, b'synthetic-public-bytes', create_parent=False)
        self.assertFalse(absent.parent.exists())

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
