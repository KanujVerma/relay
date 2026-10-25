"""Product OAuth protocol over bounded HTTPX; no browser/disk fallback.

Existing Relay PKCE/callback/OIDC validation is reused. Construction is inert.
Only explicit calls create a loopback listener or make identity/API requests.
"""
import asyncio
from http.server import HTTPServer
import secrets
import socket
import threading
import time
import unicodedata
from urllib.parse import urlsplit
import httpx
from . import auth
from .generated_answer import strict_json,CardError
from .catalog_diagnostics import CatalogDiagnostic,write_catalog_diagnostic

class AccountOAuthError(auth.AuthError):
    def __init__(self,code,*,status=None):
        self.code=code;self.status=status if type(status) is int and 100<=status<=599 else None
        super().__init__(code)

async def owned_thread(function,*args,**kwargs):
    """Cancellation joins the actual lock/file worker before acknowledging it.

    Cancelling asyncio.to_thread alone leaves its thread running. Repeated
    cancellation cannot turn that live worker into a false cleanup receipt.
    A native process-exit receipt is the final bound if an OS lock stays held.
    """
    task=asyncio.create_task(asyncio.to_thread(function,*args,**kwargs));cancelled=False
    while True:
        try:
            result=await asyncio.shield(task)
            if cancelled:raise asyncio.CancelledError()
            return result
        except asyncio.CancelledError:
            cancelled=True
            if task.done():
                # Consume any worker failure without publishing private errors.
                if not task.cancelled():task.exception()
                raise
        except Exception:
            if cancelled:raise asyncio.CancelledError() from None
            raise

def _options():
    return dict(timeout=httpx.Timeout(10,connect=5),follow_redirects=False,trust_env=False,
        limits=httpx.Limits(max_connections=1,max_keepalive_connections=0))

def _auth_url(value):
    try:
        url=urlsplit(value)
        if (url.scheme!='https' or url.hostname!='auth.openai.com' or url.username is not None
            or url.password is not None or url.port not in (None,443) or url.fragment or not url.path.startswith('/')):raise ValueError()
        return value
    except (ValueError,TypeError,AttributeError):raise AccountOAuthError('authorization_failed') from None

class _CallbackServer(HTTPServer):
    def __init__(self,*args):
        self._connections=set();self._lock=threading.Lock();self._closed=False
        super().__init__(*args)
    def get_request(self):
        connection,address=super().get_request();connection.settimeout(1)
        with self._lock:
            if self._closed:connection.close();raise OSError('callback closed')
            self._connections.add(connection)
        return connection,address
    def shutdown_request(self,request):
        with self._lock:self._connections.discard(request)
        super().shutdown_request(request)
    def handle_error(self,*_):pass  # No callback URLs/codes in diagnostics.
    def stop_connections(self):
        with self._lock:self._closed=True;connections=tuple(self._connections)
        for connection in connections:
            try:connection.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            connection.close()

class CallbackListener:
    def __init__(self,state):
        self._server,self._result=auth._callback_server(state,server_factory=_CallbackServer,
            completion_message=b'Return to Relay to finish connecting your account.')
        self._server.timeout=.1;self._stop=threading.Event();self._task=None
        self.redirect_uri=f'http://127.0.0.1:{self._server.server_port}{auth.AUTH_PATH}'
    def _wait(self):
        deadline=time.monotonic()+240
        while not self._stop.is_set() and time.monotonic()<deadline:
            self._server.handle_request()
            if 'query' in self._result:return self._result['query']
        raise AccountOAuthError('authorization_failed')
    async def wait(self):
        self._task=asyncio.create_task(asyncio.to_thread(self._wait))
        try:return await asyncio.shield(self._task)
        except asyncio.CancelledError:
            await self.close();raise
    async def close(self):
        self._stop.set();self._server.stop_connections()
        if self._task is not None:await asyncio.gather(asyncio.shield(self._task),return_exceptions=True)
        self._server.server_close()

class AccountOAuthService:
    def __init__(self,store,*,client_factory=None,sync_client_factory=None,listener_factory=None,now=time.time,catalog_diagnostic_writer=None):
        self.store=store;self._client=client_factory or httpx.AsyncClient
        self._sync_client=sync_client_factory or httpx.Client;self._listener=listener_factory or CallbackListener
        self._now=now
        self._catalog_diagnostic_writer=catalog_diagnostic_writer or write_catalog_diagnostic

    async def _json(self,client,method,url,*,form=None,token=None,catalog_diagnostic=None,max_bytes=65536):
        client.cookies.clear()
        headers={'Accept':'application/json'}
        if token is not None:headers['Authorization']='Bearer '+token
        try:
            async with client.stream(method,url,data=form,headers=headers) as response:
                if catalog_diagnostic is not None:catalog_diagnostic.response(response.status_code,response.headers.get('content-length'))
                budget=max_bytes if response.status_code==200 else 65536
                data=bytearray()
                async for chunk in response.aiter_bytes():
                    data.extend(chunk)
                    if catalog_diagnostic is not None:catalog_diagnostic.bytes_at_stop=len(data)
                    if len(data)>budget:
                        if catalog_diagnostic is not None:catalog_diagnostic.fail('body_limit')
                        raise AccountOAuthError('authorization_failed')
                if response.status_code!=200:
                    if catalog_diagnostic is not None:catalog_diagnostic.fail('http_error')
                    raise AccountOAuthError('authorization_failed',status=response.status_code)
                value=strict_json(bytes(data),max_bytes=budget)
                if not isinstance(value,dict):
                    if catalog_diagnostic is not None:catalog_diagnostic.fail('object_shape')
                    raise CardError('object_required')
                return value
        except (httpx.HTTPError,CardError,UnicodeError) as error:
            if catalog_diagnostic is not None:catalog_diagnostic.fail('transport_error' if isinstance(error,httpx.HTTPError) else 'invalid_json')
            raise AccountOAuthError('authorization_failed') from None
        finally:client.cookies.clear()

    async def _discovery(self,client):
        value=await self._json(client,'GET',auth.DISCOVERY_URL)
        if value.get('issuer')!=auth.ISSUER:raise AccountOAuthError('authorization_failed')
        return value

    async def connect(self,registration_id,publish_authorization,*,enable_plan=False):
        auth.require_verification_dependencies()
        host=await owned_thread(self.store.initialize)
        old=await owned_thread(self.store.registration,registration_id) if registration_id is not None else None
        client_id=old['client_id'] if old else 'dynamic_agent_client'
        state,nonce=secrets.token_urlsafe(32),secrets.token_urlsafe(32)
        verifier,challenge=auth.pkce_pair();listener=self._listener(state)
        try:
            options=dict(client_id=client_id,host_id=host,redirect_uri=listener.redirect_uri,
                state=state,nonce=nonce,challenge=challenge,id_token_hint=old.get('id_token') if old else None,
                login_hint=old.get('email') if old else None,enable_plan=enable_plan)
            url=auth.authorization_url(**options)
            if len(url.encode())>12288:
                # This optional optimization is not identity authority. Large
                # signed tokens must not overflow the private effect frame.
                options['id_token_hint']=None;url=auth.authorization_url(**options)
            if len(url.encode())>12288:raise AccountOAuthError('authorization_failed')
            publish_authorization(url)
            query=await listener.wait()
            if query.get('error')==['access_denied'] and auth.callback_state_is_valid(query,state):
                raise AccountOAuthError('authorization_declined')
            code,issued=auth.verify_callback(query,state,client_id)
            async with asyncio.timeout(30),self._client(**_options()) as client:
                tokens=await self._json(client,'POST',auth.TOKEN_URL,form=dict(grant_type='authorization_code',
                    client_id=issued,code=code,code_verifier=verifier,redirect_uri=listener.redirect_uri,resource=auth.RESOURCE))
                if type(tokens.get('expires_in')) is not int:raise AccountOAuthError('authorization_failed')
                token=tokens.get('id_token')
                if not isinstance(token,str) or not 0<len(token)<=32768:raise AccountOAuthError('authorization_failed')
                discovery=await self._discovery(client)
                keys=await self._json(client,'GET',_auth_url(discovery.get('jwks_uri')))
                jwt,_=auth.require_verification_dependencies();header=jwt.get_unverified_header(token)
                if header.get('alg')!='RS256' or not isinstance(header.get('kid'),str):raise AccountOAuthError('authorization_failed')
                keyset=keys.get('keys')
                if not isinstance(keyset,list) or not 0<len(keyset)<=32:raise AccountOAuthError('authorization_failed')
                matches=[item for item in keyset if isinstance(item,dict) and item.get('kid')==header['kid']]
                if len(matches)!=1 or matches[0].get('kty')!='RSA' or matches[0].get('use') not in (None,'sig'):
                    raise AccountOAuthError('authorization_failed')
                key=jwt.PyJWK.from_dict(matches[0],algorithm='RS256')
                claims=auth.verified_id_claims(token,issued,nonce,key.key)
            if old and (old['issuer']!=claims['iss'] or old['subject']!=claims['sub'] or old['client_id']!=issued):
                raise AccountOAuthError('authorization_failed')
            access,scopes,lifetime=auth.validate_token_fields(tokens)
            refresh=tokens.get('refresh_token')
            if 'offline_access' in scopes and (not isinstance(refresh,str) or not refresh.strip()):raise AccountOAuthError('authorization_failed')
            return dict(issuer=claims['iss'],subject=claims['sub'],client_id=issued,email=claims.get('email'),
                ext_agent_host_id=host,scopes=scopes,id_token=token,access_token=access,refresh_token=refresh,
                token_type='Bearer',expires_in=lifetime,saved_at=self._now())
        except asyncio.CancelledError:raise
        except AccountOAuthError:raise
        except Exception:raise AccountOAuthError('authorization_failed') from None
        finally:await listener.close()

    def refresh(self,record):
        """One classified token response; caller owns lock/durable rotation."""
        try:
            with self._sync_client(**_options()) as client:
                with client.stream('POST',auth.TOKEN_URL,data=dict(grant_type='refresh_token',
                    client_id=record['client_id'],refresh_token=record['refresh_token'],resource=auth.RESOURCE)) as response:
                    data=bytearray()
                    for chunk in response.iter_bytes():
                        data.extend(chunk)
                        if len(data)>65536:raise auth.MalformedRefreshResponse('credential_response_invalid')
                    try:value=strict_json(bytes(data),max_bytes=65536)
                    except CardError:
                        if response.status_code==200:raise auth.MalformedRefreshResponse('credential_response_invalid') from None
                        raise auth.AuthError('credential_request_failed') from None
                    if response.status_code!=200:
                        item=value.get('error') if isinstance(value,dict) else None
                        code=item if isinstance(item,str) else item.get('code') if isinstance(item,dict) else None
                        if 400<=response.status_code<500 and isinstance(code,str) and code in auth.INVALID_REFRESH_CODES:
                            raise auth.UnusableRefreshToken('reauthentication_required')
                        raise auth.AuthError('credential_request_failed')
                    if not isinstance(value,dict):raise auth.MalformedRefreshResponse('credential_response_invalid')
                    return value
        except httpx.HTTPError:raise auth.AuthError('credential_request_failed') from None

    async def catalog(self,registration_id,generation):
        diagnostic=CatalogDiagnostic();token_ready=False
        try:
            token=await owned_thread(self.store.active_access_token,registration_id,generation,refresh=self.refresh);token_ready=True
            try:
                async with asyncio.timeout(15),self._client(**_options()) as client:
                    value=await self._json(client,'GET',auth.RESOURCE+'/models',token=token,catalog_diagnostic=diagnostic,max_bytes=1048576)
            except TimeoutError:
                diagnostic.fail('timeout');raise AccountOAuthError('catalog_unavailable') from None
            diagnostic.models(value);models=value.get('models')
            if not isinstance(models,list):
                diagnostic.fail('models_missing' if 'models' not in value else 'models_shape');raise AccountOAuthError('catalog_unavailable')
            if len(models)>256:
                diagnostic.fail('raw_limit');raise AccountOAuthError('catalog_unavailable')
            result=[]
            for model in models:
                if not isinstance(model,dict) or model.get('visibility')!='list':continue
                slug,name=model.get('slug'),model.get('display_name')
                if (not isinstance(slug,str) or not 0<len(slug.encode())<=128 or not slug.isascii()
                    or any(c.isspace() for c in slug) or not isinstance(name,str) or not name.strip()
                    or not 0<len(name.encode())<=160
                    or any(unicodedata.category(c) in ('Cc','Cf','Cs','Zl','Zp') for c in slug+name)):
                    diagnostic.fail('model_fields_invalid');raise AccountOAuthError('catalog_unavailable')
                result.append(dict(slug=slug,displayName=name))
                if len(result)>32:
                    diagnostic.fail('visible_limit');raise AccountOAuthError('catalog_unavailable')
            diagnostic.outcome='valid' if result else 'empty_visible'
            return result
        except asyncio.CancelledError:
            diagnostic.outcome='cancelled';raise
        except Exception:
            diagnostic.fail('token_unavailable' if not token_ready else 'catalog_unavailable');raise
        finally:
            await self._finish_catalog_diagnostic(diagnostic)

    async def _finish_catalog_diagnostic(self,diagnostic):
        # Keep control/status responsive, but never leave an unjoined file worker.
        try:
            await owned_thread(self._catalog_diagnostic_writer,self.store.path.parent,diagnostic.record())
        except asyncio.CancelledError:
            if diagnostic.outcome!='cancelled':
                diagnostic.outcome='cancelled'
                # At most one latest-record correction after the original
                # writer joins. A repeated cancel still joins this worker.
                try:await owned_thread(self._catalog_diagnostic_writer,self.store.path.parent,diagnostic.record())
                except (Exception,asyncio.CancelledError):pass
            raise
        except Exception:pass

    async def revoke(self,record):
        if not record.get('refresh_token'):return True
        try:
            async with asyncio.timeout(5),self._client(**_options()) as client:
                discovery=await self._discovery(client)
                endpoint=_auth_url(discovery.get('revocation_endpoint'))
                async with client.stream('POST',endpoint,data=dict(token=record['refresh_token'],
                    token_type_hint='refresh_token',client_id=record['client_id'])) as response:
                    count=0
                    async for chunk in response.aiter_bytes():
                        count+=len(chunk)
                        if count>4096:return False
                    return response.status_code==200 and count==0
        except (httpx.HTTPError,AccountOAuthError,TimeoutError):return False
