"""Private product bootstrap and bounded account control, never model input.

No IO/browser/network at import or construction. Public DTOs contain last-check
metadata only; the actual protected session provider independently checks store
selection/generation/scope at use. Native owns helper retirement before mutation.
"""
import asyncio
import base64
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import select
import sys
import time
from urllib.parse import urlsplit
from . import auth,protected_storage
from .account_store import AccountCredentialStore,AccountStoreError
from .account_oauth import AccountOAuthService,AccountOAuthError,owned_thread
from .generated_answer import strict_json,CardError,bounded_text
from .panel_wire import exact,uuid_string,encode_frame,FrameDecoder,WireError

class AccountProtocolError(ValueError):pass

@dataclass(frozen=True,repr=False)
class AccountBootstrap:
    purpose:str
    key:bytes
    directory:Path
    registration_id:str|None
    generation:str

def decode_bootstrap(data,*,purpose):
    try:
        value=strict_json(data,max_bytes=16384)
        exact(value,('schemaVersion','kind','purpose','key','vaultDirectory','registrationID','accountGeneration'))
        if (type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='account_secret_bootstrap'
            or purpose not in ('account_control','oauth_session') or value['purpose']!=purpose):raise ValueError()
        key=base64.b64decode(value['key'],validate=True)
        if len(key)!=32 or base64.b64encode(key).decode()!=value['key']:raise ValueError()
        directory=bounded_text(value['vaultDirectory'],2048)
        if directory!=value['vaultDirectory'] or not Path(directory).is_absolute():raise ValueError()
        identity=None if value['registrationID'] is None else uuid_string(value['registrationID'])
        if purpose=='oauth_session' and identity is None:raise ValueError()
        return AccountBootstrap(purpose,key,Path(directory),identity,uuid_string(value['accountGeneration']))
    except (ValueError,TypeError,KeyError,UnicodeError,CardError,WireError):
        raise AccountProtocolError('account_bootstrap_invalid') from None

def read_bootstrap_fd(fd,*,purpose,timeout=3):
    """Consume exactly one private BE32 frame, without buffered read-ahead.

    Must precede attaching the normal asyncio reader to this same inherited
    descriptor. No fallback path may inspect legacy plaintext credentials.
    """
    deadline=time.monotonic()+timeout
    def read_exact(count):
        data=bytearray()
        while len(data)<count:
            remaining=deadline-time.monotonic()
            if remaining<=0 or not select.select([fd],[],[],remaining)[0]:raise ValueError()
            part=os.read(fd,count-len(data))
            if not part:raise ValueError()
            data.extend(part)
        return bytes(data)
    try:
        size=int.from_bytes(read_exact(4),'big')
        if not 0<size<=16384:raise ValueError()
        return decode_bootstrap(read_exact(size),purpose=purpose)
    except (ValueError,OSError):raise AccountProtocolError('account_bootstrap_invalid') from None

class ProtectedAccountSession:
    """Private product token source; selection is checked again on every use."""
    def __init__(self,bootstrap,*,service_factory=AccountOAuthService):
        if not isinstance(bootstrap,AccountBootstrap) or bootstrap.purpose!='oauth_session':raise AccountProtocolError('account_bootstrap_invalid')
        self._bootstrap=bootstrap;self.store=AccountCredentialStore(bootstrap.directory,bootstrap.key)
        self.service=service_factory(self.store)
    def open(self):
        value=self.store.metadata();boot=self._bootstrap
        if value['active']!=dict(registration_id=boot.registration_id,generation=boot.generation):raise AccountStoreError('account_changed')
        row=next((r for r in value['registrations'] if r['registration_id']==boot.registration_id),None)
        if row is None or row['session_state']!='available':raise AccountStoreError('reauthentication_required')
        if row['plan_permission'] is not True:raise AccountStoreError('plan_permission_missing')
        return self
    def token(self):
        return self.store.active_access_token(self._bootstrap.registration_id,self._bootstrap.generation,refresh=self.service.refresh)

_PAYLOADS={'status':(),'connect':('registrationID',),'enable_plan':('registrationID',),
    'cancel':('targetRequestID',),'select':('registrationID',),'sign_out':('registrationID',),
    'models':(),'acknowledge_plan_notice':('registrationID',)}

def _request(value):
    try:
        exact(value,('schemaVersion','kind','requestID','action','payload'))
        if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='account_request':raise ValueError()
        identity=uuid_string(value['requestID']);action=value['action']
        exact(value['payload'],_PAYLOADS[action]);payload=dict(value['payload'])
        for key,item in payload.items():
            if not(action=='connect' and item is None):payload[key]=uuid_string(item)
        return dict(schemaVersion=1,kind='account_request',requestID=identity,action=action,payload=payload)
    except (ValueError,TypeError,KeyError,WireError):raise AccountProtocolError('account_protocol_rejected') from None

def _models(value):
    if not isinstance(value,list) or len(value)>32:raise AccountOAuthError('catalog_unavailable')
    result=[];seen=set()
    try:
        for model in value:
            exact(model,('slug','displayName'))
            slug=bounded_text(model['slug'],128);name=bounded_text(model['displayName'],160)
            if slug!=model['slug'] or name!=model['displayName'] or not slug.isascii() or any(c.isspace() for c in slug) or slug in seen:raise ValueError()
            seen.add(slug);result.append(dict(slug=slug,displayName=name))
    except (ValueError,TypeError,KeyError,CardError,WireError):raise AccountOAuthError('catalog_unavailable') from None
    return result

class AccountBridge:
    def __init__(self,bootstrap,*,emit,service_factory=AccountOAuthService,revoke_backoff=.5,on_failure=lambda:None):
        if not isinstance(bootstrap,AccountBootstrap) or bootstrap.purpose!='account_control':raise AccountProtocolError('account_bootstrap_invalid')
        self.bootstrap=bootstrap;self.store=AccountCredentialStore(bootstrap.directory,bootstrap.key)
        self.service=service_factory(self.store);self.emit=emit;self._backoff=revoke_backoff;self._on_failure=on_failure
        self._owner=None;self._closed=False;self._started=False;self._active=None;self._task=None;self._executing=False
        self._tasks=set();self._cancelled=set();self._ledger={};self._replies=[]
        self._snapshot=dict(revision=0,activeRegistrationID=None,registrations=[],models=[],catalogState='unloaded')

    async def _load_snapshot(self,*,models=None,catalog=None):
        value=await owned_thread(self.store.metadata);rows=[]
        for row in value['registrations']:
            scope=row['plan_permission']
            rows.append(dict(registrationID=row['registration_id'],label=row['label'],email=row['email'],
                identityState='validated_at_sign_in',planUsageState='unknown' if scope is None else 'granted' if scope else 'not_granted',
                sessionState=row['session_state'],lastValidatedAt=int(row['last_validated_at']),planNoticeAcknowledged=row['notice_ack']))
        candidate=dict(revision=value['revision'],activeRegistrationID=value['active']['registration_id'] if value['active'] else None,
            registrations=rows,models=self._snapshot['models'] if models is None else models,
            catalogState=self._snapshot['catalogState'] if catalog is None else catalog)
        def fits():
            try:return len(encode_frame(candidate))<=16384-512
            except WireError:return False
        if not fits():
            # Keep every registration. An unrepresentable complete catalog is
            # unavailable, never silently presented as a partial current list.
            candidate.update(models=[],catalogState='unavailable')
            if not fits():raise AccountStoreError('storage_unavailable')
        self._snapshot=candidate

    async def start(self):
        if self._started or self._closed:raise AccountProtocolError('account_protocol_rejected')
        owner=protected_storage.credential_lock(self.store.path.with_name('account-control-owner'),nonblocking=True)
        try:
            def initialize():
                owner.__enter__();self._owner=owner;self.store.initialize()
            await owned_thread(initialize);await self._load_snapshot();self._started=True
        except BaseException:
            if self._owner is not None:self._owner.__exit__(None,None,None);self._owner=None
            raise AccountStoreError('storage_unavailable') from None

    def _reply(self,request,status,reason,revision=2):
        if self._closed:return
        value=dict(schemaVersion=1,kind='account_response',requestID=request['requestID'],action=request['action'],
            resultRevision=revision,status=status,reasonCode=reason,snapshot=deepcopy(self._snapshot))
        encode_frame(value)
        self._ledger[request['requestID']]=(self._ledger[request['requestID']][0],value)
        if request['requestID'] in self._replies:self._replies.remove(request['requestID'])
        self._replies.append(request['requestID'])
        while len(self._replies)>8:
            old=self._replies.pop(0)
            if old==self._active:self._replies.append(old);continue
            fingerprint,_=self._ledger[old];self._ledger[old]=(fingerprint,None)
        self.emit(value)

    def _status(self):
        identity=self._snapshot['activeRegistrationID']
        row=next((row for row in self._snapshot['registrations'] if row['registrationID']==identity),None)
        if row is None:return 'signed_out'
        if row['sessionState']!='available':return 'reauth_required'
        return 'ready' if row['planUsageState']=='granted' else 'plan_disabled'

    def _current(self,request):
        return not self._closed and self._active==request['requestID'] and request['requestID'] not in self._cancelled

    def _authorization(self,request,url):
        if not self._current(request):return
        parsed=urlsplit(url)
        if (parsed.scheme!='https' or parsed.hostname!='auth.openai.com' or parsed.path!='/api/accounts/authorize'
            or parsed.username is not None or parsed.password is not None or parsed.port not in (None,443)
            or parsed.fragment or len(url.encode())>12288):raise AccountOAuthError('authorization_failed')
        value=dict(schemaVersion=1,kind='account_authorization',requestID=request['requestID'],authorizationURL=url)
        encode_frame(value);self.emit(value)

    def _track(self,coroutine):
        task=asyncio.create_task(coroutine);self._tasks.add(task)
        def done(task):
            self._tasks.discard(task)
            if not task.cancelled() and task.exception() is not None:
                self._closed=True;self._on_failure()
        task.add_done_callback(done);return task

    def _cancel(self):
        # A Task cancelled before its first instruction never runs finally.
        # Keep that owned coroutine scheduled so it can issue its one terminal
        # receipt, after observing the already-denied currentness predicate.
        if self._executing and self._task is not None and not self._task.cancelling():self._task.cancel()

    async def handle(self,value):
        if not self._started or self._closed:raise AccountProtocolError('account_protocol_rejected')
        try:request=_request(value)
        except AccountProtocolError:
            self._closed=True
            self._cancel()
            raise
        identity=request['requestID'];fingerprint=hashlib.sha256(json.dumps(request,sort_keys=True,separators=(',',':')).encode()).digest()
        if identity in self._ledger:
            original,reply=self._ledger[identity]
            if original!=fingerprint:
                self._closed=True
                self._cancel()
                raise AccountProtocolError('account_protocol_rejected')
            if reply is None:
                self._closed=True;self._cancel()
                raise AccountProtocolError('account_protocol_rejected')
            self.emit(deepcopy(reply))
            return
        if len(self._ledger)>=512:
            self._closed=True
            self._cancel()
            raise AccountProtocolError('account_protocol_rejected')
        self._ledger[identity]=(fingerprint,None)
        if request['action']=='status':
            self._reply(request,'busy' if self._task else self._status(),'operation_busy' if self._task else 'current_status');return
        if request['action']=='cancel':
            owner=self._task;target=request['payload']['targetRequestID']
            if owner is None or self._active!=target:
                self._reply(request,'cancelled','authorization_cancelled');return
            self._cancelled.add(target);self._cancel()
            self._reply(request,'pending','authorization_pending',1)
            async def joined():
                await asyncio.gather(asyncio.shield(owner),return_exceptions=True)
                self._reply(request,'cancelled','authorization_cancelled')
            self._track(joined());return
        if self._task is not None:self._reply(request,'busy','operation_busy');return
        self._active=identity
        self._reply(request,'pending','authorization_pending',1)
        self._task=self._track(self._operate(request))

    async def _catalog(self,identity):
        try:
            models=_models(await self.service.catalog(identity,self.bootstrap.generation))
            await self._load_snapshot(models=models,catalog='current')
        except (AccountOAuthError,AccountStoreError):await self._load_snapshot(models=[],catalog='unavailable')

    async def _operate(self,request):
        identity=request['requestID'];action=request['action'];payload=request['payload']
        status=reason=None;self._executing=True
        try:
            if not self._current(request):return
            if action in ('connect','enable_plan'):
                record=await self.service.connect(payload['registrationID'],lambda url:self._authorization(request,url),enable_plan=action=='enable_plan')
                if not self._current(request):return
                registration=await owned_thread(self.store.save_registration,record,registration_id=payload['registrationID'])
                if not self._current(request):return
                await owned_thread(self.store.select,registration,self.bootstrap.generation)
                await self._load_snapshot(models=[],catalog='unloaded')
                if auth.REQUIRED_PLAN_SCOPE in record['scopes']:await self._catalog(registration)
                status=self._status();reason='connected' if status=='ready' else 'plan_permission_missing'
            elif action=='select':
                registration=payload['registrationID'];await owned_thread(self.store.select,registration,self.bootstrap.generation)
                await self._load_snapshot(models=[],catalog='unloaded')
                if self._status()=='ready':await self._catalog(registration)
                status=self._status();reason='account_selected'
            elif action=='models':
                registration=self._snapshot['activeRegistrationID']
                if registration is None:raise AccountStoreError('reauthentication_required')
                await self._catalog(registration);status=self._status()
                reason='catalog_updated' if self._snapshot['catalogState']=='current' else 'catalog_unavailable'
            elif action=='sign_out':
                registration=payload['registrationID'];record=await owned_thread(self.store.begin_sign_out,registration)
                confirmed=False
                try:
                    for attempt in range(2):
                        confirmed=await self.service.revoke(record)
                        if confirmed:break
                        if attempt==0:await asyncio.sleep(self._backoff)
                finally:
                    await owned_thread(self.store.finish_sign_out,registration)
                    await self._load_snapshot(models=[],catalog='unloaded')
                status='signed_out';reason='signed_out' if confirmed else 'remote_revocation_unconfirmed'
            elif action=='acknowledge_plan_notice':
                await owned_thread(self.store.acknowledge_notice,payload['registrationID']);await self._load_snapshot()
                status=self._status();reason='current_status'
        except asyncio.CancelledError:pass
        except (AccountOAuthError,AccountStoreError) as error:
            code=error.code
            reason=code if code in ('authorization_declined','reauthentication_required','storage_unavailable','plan_permission_missing') else 'authorization_failed'
            status='reauth_required' if reason=='reauthentication_required' else 'plan_disabled' if reason=='plan_permission_missing' else 'error'
            try:await self._load_snapshot()
            except AccountStoreError:pass
        except Exception:status='error';reason='authorization_failed'
        finally:
            if identity in self._cancelled or status is None:status='cancelled';reason='authorization_cancelled'
            try:self._reply(request,status,reason)
            finally:
                if self._active==identity:self._active=None;self._task=None;self._executing=False

    async def drain(self):
        while self._tasks:await asyncio.gather(*tuple(self._tasks),return_exceptions=True)

    async def close(self):
        self._closed=True
        self._cancel()
        await self.drain()
        if self._owner is not None:self._owner.__exit__(None,None,None);self._owner=None

async def run_stdio(bootstrap,*,input_fd=0,output_fd=1,service_factory=AccountOAuthService):
    """The private frame has already been consumed with raw descriptor IO."""
    loop=asyncio.get_running_loop();main=asyncio.current_task()
    reader=asyncio.StreamReader(limit=32768)
    source=os.fdopen(os.dup(input_fd),'rb',buffering=0)
    sink=os.fdopen(os.dup(output_fd),'wb',buffering=0)
    incoming,_=await loop.connect_read_pipe(lambda:asyncio.StreamReaderProtocol(reader),source)
    transport,protocol=await loop.connect_write_pipe(asyncio.streams.FlowControlMixin,sink)
    writer=asyncio.StreamWriter(transport,protocol,None,loop)
    queue=asyncio.Queue(maxsize=32);queued_bytes=0;failed=False
    def failure():
        nonlocal failed
        failed=True
        if not main.cancelling():main.cancel()
    def emit(value):
        nonlocal queued_bytes
        frame=encode_frame(value)
        if queued_bytes+len(frame)>262144:raise WireError('writer_overflow')
        try:queue.put_nowait(frame)
        except asyncio.QueueFull:raise WireError('writer_overflow') from None
        queued_bytes+=len(frame)
    async def output():
        nonlocal queued_bytes
        try:
            while True:
                frame=await queue.get()
                try:writer.write(frame);await asyncio.wait_for(writer.drain(),2)
                finally:queued_bytes-=len(frame);queue.task_done()
        except asyncio.CancelledError:raise
        except Exception:failure()
    bridge=AccountBridge(bootstrap,emit=emit,service_factory=service_factory,on_failure=failure)
    output_task=asyncio.create_task(output());decoder=FrameDecoder()
    try:
        await bridge.start()
        while True:
            chunk=await (asyncio.wait_for(reader.read(4096),3) if decoder.buffer or decoder.length else reader.read(4096))
            if not chunk:decoder.finish();break
            for value in decoder.feed(chunk):await bridge.handle(value)
        return 2 if failed else 0
    finally:
        await bridge.close()
        if not failed:await asyncio.wait_for(queue.join(),2)
        output_task.cancel();await asyncio.gather(output_task,return_exceptions=True)
        incoming.close();writer.close()

def main():
    # No arbitrary module/auth/mode flags. Product secrets arrive only on stdin.
    if len(sys.argv)!=1:return 2
    try:
        bootstrap=read_bootstrap_fd(sys.stdin.fileno(),purpose='account_control')
        return asyncio.run(run_stdio(bootstrap))
    except (Exception,asyncio.CancelledError):return 2

if __name__=='__main__':raise SystemExit(main())
