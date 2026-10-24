"""Real PKCE/OIDC/HTTPX paths with generated keys and in-memory HTTP only."""
import asyncio
import base64
import json
from pathlib import Path
import tempfile
import time
import unittest
from urllib.parse import parse_qs,urlsplit
import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa

from relay_spike import auth
from relay_spike.account_store import AccountCredentialStore
from relay_spike.account_oauth import AccountOAuthService,AccountOAuthError
from relay_spike.account_bridge import ProtectedAccountSession,decode_bootstrap
from relay_spike.oauth_answer_stream import OAuthAnswerStream,AnswerTransportError
from tests.test_visual_input import completed_wire

class FixtureListener:
    redirect_uri='http://127.0.0.1:14888/auth/callback'
    def __init__(self,environment,state):self.environment=environment;self.state=state;self.closed=False
    async def wait(self):
        await asyncio.sleep(0)
        return dict(code=['synthetic-code'],state=[self.state],client_id=[self.environment.client_id])
    async def close(self):self.closed=True

class OAuthEnvironment:
    def __init__(self,key):
        self.key=key;self.client_id='oaiapp_synthetic';self.subject='synthetic-subject'
        self.url=None;self.listeners=[];self.requests=[];self.scopes=auth.SCOPE;self.bad_nonce=False
        self.signing_key=key;self.token_response=None;self.options=[];self.bearer_matches=False
        self.revoke_matches=False;self.foreign_host=False;self.catalog_models=None
    def listener(self,state):
        listener=FixtureListener(self,state);self.listeners.append(listener);return listener
    def opened(self,url):self.url=url
    def handler(self,request):
        self.requests.append((request.method,request.url.path))
        if request.url.host not in ('auth.openai.com','api.openai.com'):self.foreign_host=True
        if str(request.url)==auth.DISCOVERY_URL:
            return httpx.Response(200,json=dict(issuer=auth.ISSUER,jwks_uri=auth.ISSUER+'/.well-known/jwks.json',
                revocation_endpoint=auth.ISSUER+'/oauth/revoke'))
        if request.url.path=='/.well-known/jwks.json':
            key=json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(self.key.public_key()));key['kid']='synthetic-key'
            return httpx.Response(200,json={'keys':[key]})
        if str(request.url)==auth.TOKEN_URL:
            if self.token_response is not None:return self.token_response()
            body=parse_qs(request.content.decode())
            if body.get('grant_type')==['refresh_token']:
                return httpx.Response(200,json=dict(access_token='synthetic-rotated-access',refresh_token='synthetic-rotated-refresh',
                    token_type='Bearer',expires_in=3600,scope=self.scopes))
            nonce=parse_qs(urlsplit(self.url).query)['nonce'][0]
            now=int(time.time())
            token=jwt.encode(dict(iss=auth.ISSUER,aud=self.client_id,sub=self.subject,email='synthetic@example.test',
                iat=now,exp=now+3600,nonce='wrong' if self.bad_nonce else nonce),self.signing_key,algorithm='RS256',headers={'kid':'synthetic-key'})
            return httpx.Response(200,json=dict(access_token='synthetic-access',refresh_token='synthetic-refresh',
                id_token=token,token_type='Bearer',expires_in=3600,scope=self.scopes))
        if request.url.path=='/oauth/revoke':
            body=parse_qs(request.content.decode())
            self.revoke_matches=body==dict(token=['synthetic-refresh'],token_type_hint=['refresh_token'],client_id=[self.client_id])
            return httpx.Response(200,content=b'')
        if request.url.path=='/v1/models':
            self.bearer_matches=request.headers.get('Authorization')=='Bearer synthetic-access'
            if self.catalog_models is not None:return httpx.Response(200,json={'models':self.catalog_models})
            return httpx.Response(200,json={'models':[
                {'slug':'gpt-synthetic-hidden','display_name':'Hidden','visibility':'hidden'},
                {'slug':'gpt-synthetic-first','display_name':'First','visibility':'list'},
                {'slug':'gpt-synthetic-second','display_name':'Second','visibility':'list'}]})
        raise AssertionError('Unexpected synthetic HTTP path')
    def client(self,**options):
        self.options.append(options)
        return httpx.AsyncClient(transport=httpx.MockTransport(self.handler),**options)
    def sync_client(self,**options):return httpx.Client(transport=httpx.MockTransport(self.handler),**options)

class AccountOAuthTests(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):cls.key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup)
        self.store=AccountCredentialStore(Path(self.directory.name)/'accounts',bytes(range(32)))
        self.store.initialize();self.environment=OAuthEnvironment(self.key)
        self.service=AccountOAuthService(self.store,client_factory=self.environment.client,
            sync_client_factory=self.environment.sync_client,listener_factory=self.environment.listener)
    async def connected(self):
        record=await self.service.connect(None,self.environment.opened)
        identity=self.store.save_registration(record);self.store.select(identity,'00000000-0000-0000-0000-000000000001')
        return identity
    async def test_generated_signature_nonce_identity_and_scope_are_verified_before_any_store_activation(self):
        self.assertEqual(self.environment.requests,[])
        record=await self.service.connect(None,self.environment.opened)
        query=parse_qs(urlsplit(self.environment.url).query)
        self.assertEqual(query['client_id'],['dynamic_agent_client'])
        self.assertEqual(query['agent_name_hint'],['Relay'])
        self.assertEqual(record['subject'],'synthetic-subject');self.assertEqual(record['client_id'],self.environment.client_id)
        self.assertEqual(self.store.metadata()['registrations'],[])
        self.assertTrue(self.environment.listeners[-1].closed)
        self.assertNotIn(('POST','/v1/responses'),self.environment.requests)
    async def test_bad_nonce_and_returning_subject_never_replace_existing_registration(self):
        identity=await self.connected();before=self.store.metadata()
        self.environment.bad_nonce=True
        with self.assertRaises(AccountOAuthError):await self.service.connect(identity,self.environment.opened)
        self.environment.bad_nonce=False;self.environment.subject='different-synthetic-subject'
        with self.assertRaises(AccountOAuthError):await self.service.connect(identity,self.environment.opened)
        self.assertEqual(self.store.metadata(),before)
        self.assertTrue(all(listener.closed for listener in self.environment.listeners))
    async def test_reconnect_uses_same_client_host_hints_and_only_explicit_plan_enable_requests_consent(self):
        identity=await self.connected();old=self.store.registration(identity)
        await self.service.connect(identity,self.environment.opened)
        query=parse_qs(urlsplit(self.environment.url).query)
        self.assertEqual(query['client_id'],[old['client_id']]);self.assertNotIn('agent_name_hint',query)
        self.assertEqual(query['id_token_hint'],[old['id_token']]);self.assertNotIn('prompt',query)
        await self.service.connect(identity,self.environment.opened,enable_plan=True)
        self.assertEqual(parse_qs(urlsplit(self.environment.url).query)['prompt'],['consent'])

    async def test_oversized_optional_id_token_hint_is_omitted_before_private_url_publication(self):
        identity=await self.connected();record=self.store.registration(identity)
        record={k:v for k,v in record.items() if k not in ('registration_id','label','state','notice_ack','last_validated_at')}
        record['id_token']='synthetic-opaque-hint-'+'a'*32000
        self.store.save_registration(record,registration_id=identity)
        await self.service.connect(identity,self.environment.opened)
        query=parse_qs(urlsplit(self.environment.url).query)
        self.assertTrue('id_token_hint' not in query);self.assertEqual(query['client_id'],[self.environment.client_id])
        self.assertLessEqual(len(self.environment.url.encode()),12288)
    async def test_identity_only_scope_stays_signed_in_without_catalog_or_inference(self):
        self.environment.scopes='openid profile email'
        record=await self.service.connect(None,self.environment.opened)
        self.assertNotIn(auth.REQUIRED_PLAN_SCOPE,record['scopes'])
        self.assertNotIn(('GET','/v1/models'),self.environment.requests)
    async def test_catalog_uses_selected_actual_bearer_and_preserves_visible_server_order(self):
        identity=await self.connected()
        models=await self.service.catalog(identity,'00000000-0000-0000-0000-000000000001')
        self.assertEqual([model['slug'] for model in models],['gpt-synthetic-first','gpt-synthetic-second'])
        self.assertTrue(self.environment.bearer_matches)
        self.assertNotIn(('POST','/v1/responses'),self.environment.requests)
    async def test_revoke_requires_empty_200_and_does_not_itself_clear_local_credentials(self):
        identity=await self.connected();record=self.store.begin_sign_out(identity)
        self.assertTrue(await self.service.revoke(record))
        self.assertEqual(self.store.metadata()['registrations'][0]['session_state'],'signing_out')
        self.assertEqual(self.environment.requests[-1],('POST','/oauth/revoke'))
        self.assertTrue(self.environment.revoke_matches)
    async def test_wrong_jwks_signature_is_not_treated_as_valid_identity(self):
        self.environment.signing_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
        with self.assertRaises(AccountOAuthError):await self.service.connect(None,self.environment.opened)
        self.assertEqual(self.store.metadata()['registrations'],[])
    async def test_redirects_are_not_followed_and_provider_body_is_not_in_error(self):
        self.environment.token_response=lambda:httpx.Response(302,headers={'Location':'https://example.test/secret'},content=b'synthetic-private-provider-body')
        with self.assertRaises(AccountOAuthError) as caught:await self.service.connect(None,self.environment.opened)
        self.assertNotIn('private',str(caught.exception));self.assertFalse(self.environment.foreign_host)
        self.assertTrue(all(option.get('follow_redirects') is False and option.get('trust_env') is False for option in self.environment.options))
    async def test_cancel_closes_the_owned_listener_before_connect_task_finishes(self):
        entered=asyncio.Event();listeners=[]
        class HeldListener(FixtureListener):
            async def wait(self):entered.set();await asyncio.Event().wait()
        def listener(state):
            value=HeldListener(self.environment,state);listeners.append(value);return value
        service=AccountOAuthService(self.store,client_factory=self.environment.client,listener_factory=listener)
        task=asyncio.create_task(service.connect(None,self.environment.opened))
        await entered.wait();task.cancel();await asyncio.gather(task,return_exceptions=True)
        self.assertTrue(listeners[0].closed);self.assertEqual(self.environment.requests,[])
        self.assertEqual(self.store.metadata()['registrations'],[])
    async def test_catalog_rejects_hidden_control_characters_in_server_labels(self):
        identity=await self.connected()
        self.environment.catalog_models=[dict(slug='gpt-synthetic',display_name='hidden\u200bname',visibility='list')]
        with self.assertRaises(AccountOAuthError):await self.service.catalog(identity,'00000000-0000-0000-0000-000000000001')
    async def test_refresh_malformed_success_is_terminal_but_503_invalid_grant_is_transient(self):
        record=await self.service.connect(None,self.environment.opened);record['saved_at']=time.time()-3590
        identity=self.store.save_registration(record);generation='00000000-0000-0000-0000-000000000001';self.store.select(identity,generation)
        self.environment.token_response=lambda:httpx.Response(503,json={'error':'invalid_grant'})
        with self.assertRaises(auth.AuthError):self.store.active_access_token(identity,generation,refresh=self.service.refresh)
        self.assertEqual(self.store.metadata()['registrations'][0]['session_state'],'available')
        self.environment.token_response=lambda:httpx.Response(200,content=b'synthetic-not-json')
        with self.assertRaises(auth.AuthError):self.store.active_access_token(identity,generation,refresh=self.service.refresh)
        self.assertEqual(self.store.metadata()['registrations'][0]['session_state'],'reauth_required')

    async def test_actual_stream_uses_protected_rotating_bearer_and_stops_after_local_signout(self):
        from unittest.mock import patch
        identity=await self.connected();generation='00000000-0000-0000-0000-000000000001'
        boot=decode_bootstrap(json.dumps(dict(schemaVersion=1,kind='account_secret_bootstrap',purpose='oauth_session',
            key=base64.b64encode(bytes(range(32))).decode(),vaultDirectory=str(self.store.path.parent),
            registrationID=identity,accountGeneration=generation)).encode(),purpose='oauth_session')
        session=ProtectedAccountSession(boot,service_factory=lambda _:self.service).open();bearers=[]
        def handler(request):
            self.assertEqual(request.url.path,'/v1/responses');bearers.append(request.headers['Authorization'])
            self.assertFalse(json.loads(request.content)['store'])
            return httpx.Response(200,headers={'Content-Type':'text/event-stream'},stream=httpx.ByteStream(completed_wire('bounded synthetic answer')))
        stream=OAuthAnswerStream(model='gpt-synthetic-first',token_provider=session.token,
            client_factory=lambda **options:httpx.AsyncClient(transport=httpx.MockTransport(handler),**options))
        with patch.object(auth,'load_auth',side_effect=AssertionError('legacy credential source')):
            self.assertEqual(await stream.complete('synthetic prompt','synthetic instructions'),'bounded synthetic answer')
            record=self.store.registration(identity);record={k:record[k] for k in ('issuer','subject','client_id','email',
                'ext_agent_host_id','scopes','id_token','access_token','refresh_token','token_type','expires_in','saved_at')}
            record['saved_at']=time.time()-3590;self.store.save_registration(record,registration_id=identity)
            self.assertEqual(await stream.complete('synthetic prompt','synthetic instructions'),'bounded synthetic answer')
            self.store.begin_sign_out(identity)
            with self.assertRaises(AnswerTransportError):await stream.complete('synthetic prompt','synthetic instructions')
        self.assertEqual(bearers,['Bearer synthetic-access','Bearer synthetic-rotated-access'])
        self.assertEqual(len([item for item in self.environment.requests if item==('POST',urlsplit(auth.TOKEN_URL).path)]),2)
