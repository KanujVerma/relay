"""Models-only response budget over synthetic HTTP and a temporary grant."""
import json
from pathlib import Path
import tempfile
import unittest

import httpx
from relay_spike import auth
from relay_spike.account_oauth import AccountOAuthService, AccountOAuthError
from relay_spike.account_store import AccountCredentialStore
from relay_spike.catalog_diagnostics import FILENAME, CatalogDiagnostic
from relay_spike.account_bridge import AccountBridge, AccountBootstrap, _models
from relay_spike.panel_wire import encode_frame
from tests.test_account_store import grant, KEY, NOW

GENERATION = '00000000-0000-0000-0000-000000000001'
PRIVATE = 'synthetic-irrelevant-private-sentinel'
MODELS = [dict(slug='synthetic-first', display_name='First', visibility='list', ignored=PRIVATE),
          dict(slug='synthetic-hidden', display_name='Hidden', visibility='hidden'),
          dict(slug='synthetic-second', display_name='Second', visibility='list')]
PROJECTED = [dict(slug='synthetic-first', displayName='First'), dict(slug='synthetic-second', displayName='Second')]


def rich_body(size, *, value=None):
    value = dict(models=MODELS, ignoredMetadata=PRIVATE) if value is None else dict(value)
    value.setdefault('ignoredMetadata', PRIVATE)
    initial = json.dumps(value, separators=(',', ':')).encode()
    assert len(initial) <= size
    value['ignoredMetadata'] += 'x' * (size - len(initial))
    result = json.dumps(value, separators=(',', ':')).encode()
    assert len(result) == size
    return result


class CatalogResponseBudgetTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(); self.addCleanup(self.folder.cleanup)
        self.directory = Path(self.folder.name) / 'Accounts'
        self.store = AccountCredentialStore(self.directory, KEY, now=lambda: NOW)
        host = self.store.initialize(); self.identity = self.store.save_registration(grant(host))
        self.store.select(self.identity, GENERATION)

    def service(self, response):
        return AccountOAuthService(self.store, client_factory=lambda **kw: httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: response), **kw))

    def diagnostic(self):
        data = (self.directory / FILENAME).read_bytes()
        self.assertLessEqual(len(data), 1024)
        for secret in (PRIVATE, 'synthetic-first', 'First', 'https://', 'synthetic-access-secret'):
            self.assertNotIn(secret.encode(), data)
        return json.loads(data)

    async def test_valid_65738_byte_rich_catalog_projects_only_visible_server_order(self):
        raw = rich_body(65738)
        models = await self.service(httpx.Response(200, content=raw)).catalog(self.identity, GENERATION)
        self.assertEqual(models, PROJECTED)
        self.assertEqual(_models(models), PROJECTED)
        bridge = AccountBridge(AccountBootstrap('account_control', KEY, self.directory, None, GENERATION), emit=lambda _: None)
        await bridge._load_snapshot(models=models, catalog='current')
        frame = dict(schemaVersion=1, kind='account_response', requestID=GENERATION, action='status',
            resultRevision=2, status='ready', reasonCode='current_status', snapshot=bridge._snapshot)
        self.assertLessEqual(len(encode_frame(frame)), 16384)
        self.assertNotIn(PRIVATE.encode(), encode_frame(frame))
        value = self.diagnostic()
        self.assertEqual(value['outcome'], 'valid'); self.assertEqual(value['bytesAtStop'], 65738)
        self.assertEqual(value['rawModelCount'], 3); self.assertEqual(value['visibleModelCount'], 2)

    async def test_models_exact_one_mib_accepts_and_one_byte_over_rejects(self):
        models = await self.service(httpx.Response(200, content=rich_body(1048576))).catalog(self.identity, GENERATION)
        self.assertEqual(models, PROJECTED)
        self.assertEqual(self.diagnostic()['bytesAtStop'], 1048576)
        with self.assertRaises(AccountOAuthError) as error:
            await self.service(httpx.Response(200, content=rich_body(1048577))).catalog(self.identity, GENERATION)
        self.assertEqual(error.exception.code, 'authorization_failed')
        value = self.diagnostic()
        self.assertEqual(value['outcome'], 'body_limit'); self.assertEqual(value['bytesAtStop'], 1048577)
        self.assertIsNone(value['rawModelCount']); self.assertIsNone(value['visibleModelCount'])

    async def test_default_token_discovery_jwks_and_model_error_bodies_stay_64k(self):
        service = self.service(httpx.Response(200, json={}))
        routes = [('token', 'POST', auth.TOKEN_URL), ('discovery', 'GET', auth.DISCOVERY_URL),
                  ('jwks', 'GET', 'https://auth.openai.com/synthetic-jwks')]
        for kind, method, url in routes:
            for size in (65536, 65537):
                with self.subTest(kind=kind, size=size):
                    body = rich_body(size, value={'issuer': auth.ISSUER})
                    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=body))) as client:
                        async def read():
                            return await service._discovery(client) if kind == 'discovery' else await service._json(client, method, url)
                        if size == 65536:
                            self.assertEqual((await read())['issuer'], auth.ISSUER)
                        else:
                            with self.assertRaises(AccountOAuthError): await read()
        with self.assertRaises(AccountOAuthError):
            await self.service(httpx.Response(503, content=rich_body(65537))).catalog(self.identity, GENERATION)
        value = self.diagnostic()
        self.assertEqual(value['outcome'], 'body_limit'); self.assertEqual(value['httpStatus'], 503)
        self.assertEqual(value['bytesAtStop'], 65537)

    async def test_explicit_budget_is_independent_of_diagnostic_presence(self):
        service = self.service(httpx.Response(200, json={}))
        body = rich_body(65738)
        for diagnostic in (None, CatalogDiagnostic()):
            async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=body))) as client:
                with self.assertRaises(AccountOAuthError):
                    await service._json(client, 'GET', auth.RESOURCE+'/models', catalog_diagnostic=diagnostic)
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=body))) as client:
            value = await service._json(client, 'GET', auth.RESOURCE+'/models', max_bytes=1048576)
        self.assertEqual(value['models'], MODELS)

    async def test_larger_success_budget_keeps_strict_json_and_model_limits(self):
        invalid = [b'{"models":[],"models":[],"ignored":"'+b'x'*65700+b'"}',
                   b'{"models":[],"ignored":NaN}',
                   b'{"models":[],"ignored":'+b'['*13+b'0'+b']'*13+b'}']
        for body in invalid:
            with self.subTest(kind='strict_json'):
                with self.assertRaises(AccountOAuthError):
                    await self.service(httpx.Response(200, content=body)).catalog(self.identity, GENERATION)
                self.assertEqual(self.diagnostic()['outcome'], 'invalid_json')
        for rows, outcome in (([MODELS[0]]*33, 'visible_limit'), ([{'visibility': 'hidden'}]*257, 'raw_limit')):
            with self.subTest(kind=outcome):
                with self.assertRaises(AccountOAuthError) as error:
                    await self.service(httpx.Response(200, content=rich_body(65738, value={'models': rows}))).catalog(self.identity, GENERATION)
                self.assertEqual(error.exception.code, 'catalog_unavailable')
                self.assertEqual(self.diagnostic()['outcome'], outcome)
