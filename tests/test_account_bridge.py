"""Owned account control with synthetic grants, keys and asynchronous gates."""
import asyncio
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from relay_spike import auth
from relay_spike.account_bridge import AccountBridge,AccountProtocolError,decode_bootstrap,read_bootstrap_fd,ProtectedAccountSession
from relay_spike.account_store import AccountCredentialStore,AccountStoreError
from relay_spike.panel_wire import encode_frame,FrameDecoder
from tests.test_account_store import grant

def request(action,**payload):
    return dict(schemaVersion=1,kind='account_request',requestID=str(uuid.uuid4()),action=action,payload=payload)

class FakeService:
    def __init__(self,store):self.store=store;self.calls=[];self.scopes=auth.SCOPE.split();self.gate=None;self.entered=asyncio.Event()
    async def connect(self,identity,publish,**options):
        self.calls.append('connect');self.entered.set();publish(auth.AUTHORIZE_URL+'?synthetic=1')
        if self.gate:
            try:await self.gate.wait()
            except asyncio.CancelledError:await self.gate.wait()
        return grant(self.store.initialize(),saved_at=time.time(),scopes=self.scopes)
    async def catalog(self,*_):self.calls.append('models');return [dict(slug='gpt-synthetic',displayName='Synthetic')]
    async def revoke(self,_):self.calls.append('revoke');return False
    def refresh(self,_):raise AssertionError('unexpected synthetic refresh')

class BootstrapTests(unittest.TestCase):
    def bootstrap(self,directory,*,purpose='account_control',identity=None,generation=None):
        return dict(schemaVersion=1,kind='account_secret_bootstrap',purpose=purpose,
            key=base64.b64encode(bytes(range(32))).decode(),vaultDirectory=str(directory),registrationID=identity,
            accountGeneration=generation or str(uuid.uuid4()))

    def test_exact_private_bootstrap_has_no_io_and_cannot_be_an_oauth_flag(self):
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'accounts'
            value=dict(schemaVersion=1,kind='account_secret_bootstrap',purpose='account_control',
                key=base64.b64encode(bytes(range(32))).decode(),vaultDirectory=str(directory),registrationID=None,
                accountGeneration=str(uuid.uuid4()))
            boot=decode_bootstrap(json.dumps(value).encode(),purpose='account_control')
            self.assertFalse(directory.exists());self.assertNotIn(value['key'],repr(boot))
            for changes in ({'schemaVersion':True},{'key':'bad'},{'purpose':'oauth_session'},
                            {'vaultDirectory':'relative'},{'authorized':True},{'accountGeneration':'bad'}):
                with self.subTest(changes=changes),self.assertRaises(AccountProtocolError):
                    decode_bootstrap(json.dumps({**value,**changes}).encode(),purpose='account_control')

    def test_first_private_frame_never_consumes_the_following_framed_command(self):
        with tempfile.TemporaryDirectory() as folder:
            value=self.bootstrap(Path(folder)/'accounts');following=encode_frame(request('status'))
            read,write=os.pipe()
            try:
                os.write(write,encode_frame(value)+following);os.close(write);write=None
                boot=read_bootstrap_fd(read,purpose='account_control')
                self.assertEqual(boot.generation,value['accountGeneration'])
                self.assertEqual(os.read(read,16384),following)
            finally:
                os.close(read)
                if write is not None:os.close(write)

    def test_missing_truncated_wrong_purpose_and_slow_bootstrap_never_open_storage(self):
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'accounts'
            for data in (b'',b'\0\0',b'\0\0\0\x05{}',encode_frame(self.bootstrap(directory))):
                read,write=os.pipe()
                try:
                    os.write(write,data);os.close(write)
                    with self.assertRaises(AccountProtocolError):read_bootstrap_fd(read,purpose='oauth_session',timeout=.05)
                finally:os.close(read)
            read,write=os.pipe()
            try:
                with self.assertRaises(AccountProtocolError):read_bootstrap_fd(read,purpose='account_control',timeout=.01)
            finally:os.close(read);os.close(write)
            self.assertFalse(directory.exists())

    def test_protected_provider_reloads_actual_selection_and_never_loads_legacy_auth(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as folder:
            directory=Path(folder)/'accounts';store=AccountCredentialStore(directory,bytes(range(32)))
            host=store.initialize();record=grant(host,saved_at=time.time());identity=store.save_registration(record)
            generation=str(uuid.uuid4());store.select(identity,generation)
            boot=decode_bootstrap(json.dumps(self.bootstrap(directory,purpose='oauth_session',identity=identity,generation=generation)).encode(),purpose='oauth_session')
            session=ProtectedAccountSession(boot,service_factory=FakeService)
            with patch.object(auth,'load_auth',side_effect=AssertionError('legacy credentials read')):
                self.assertEqual(session.open(),session)
                self.assertEqual(session.token(),record['access_token'])
                store.select(identity,str(uuid.uuid4()))
                with self.assertRaises(AccountStoreError):session.token()
                with self.assertRaises(AccountStoreError):session.open()

    def test_actual_child_bootstrap_and_status_in_same_write_are_framed_and_inert(self):
        with tempfile.TemporaryDirectory() as folder:
            boot=self.bootstrap(Path(folder)/'accounts');command=request('status')
            result=subprocess.run([sys.executable,'-m','relay_spike.account_bridge'],
                input=encode_frame(boot)+encode_frame(command),capture_output=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stderr)
            decoder=FrameDecoder();values=decoder.feed(result.stdout);decoder.finish()
            self.assertEqual(len(values),1);self.assertEqual(values[0]['requestID'],command['requestID'])
            self.assertEqual(values[0]['status'],'signed_out');self.assertEqual(result.stderr,b'')
            missing=subprocess.run([sys.executable,'-m','relay_spike.account_bridge'],input=encode_frame(command),capture_output=True,timeout=5)
            self.assertEqual(missing.returncode,2);self.assertEqual(missing.stdout+missing.stderr,b'')

class AccountBridgeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.folder=tempfile.TemporaryDirectory();self.addCleanup(self.folder.cleanup)
        self.out=[];self.boot=decode_bootstrap(json.dumps(dict(schemaVersion=1,kind='account_secret_bootstrap',
            purpose='account_control',key=base64.b64encode(bytes(range(32))).decode(),
            vaultDirectory=str(Path(self.folder.name)/'accounts'),registrationID=None,accountGeneration=str(uuid.uuid4()))).encode(),purpose='account_control')
        self.bridge=AccountBridge(self.boot,emit=self.out.append,service_factory=FakeService,revoke_backoff=0)
        self.assertEqual(self.out,[])
        await self.bridge.start();self.addAsyncCleanup(self.bridge.close)
    async def connect(self):
        operation=request('connect',registrationID=None)
        await self.bridge.handle(operation);await self.bridge.drain()
        return operation,self.out[-1]['snapshot']['activeRegistrationID']
    async def test_connect_replay_status_and_private_url_do_not_repeat_network_or_publish_secrets(self):
        operation,identity=await self.connect()
        self.assertIsNotNone(identity);self.assertEqual(self.out[-1]['status'],'ready')
        responses=[row for row in self.out if row['kind']=='account_response']
        self.assertEqual([row['resultRevision'] for row in responses],[1,2])
        self.assertEqual(set(responses[-1]),set(('schemaVersion','kind','requestID','action','resultRevision','status','reasonCode','snapshot')))
        public=json.dumps(responses)
        for field in ('access_token','refresh_token','id_token','synthetic-subject','oaiapp_synthetic'):
            self.assertNotIn(field,public)
        calls=list(self.bridge.service.calls)
        await self.bridge.handle(operation)
        self.assertEqual(self.bridge.service.calls,calls)
        await self.bridge.handle(request('status'))
        self.assertEqual(self.bridge.service.calls,calls)
    async def test_pending_duplicate_and_cancel_wait_for_actual_uncooperative_operation(self):
        self.bridge.service.gate=asyncio.Event();operation=request('connect',registrationID=None)
        await self.bridge.handle(operation);await self.bridge.service.entered.wait()
        await self.bridge.handle(operation)
        self.assertEqual(self.bridge.service.calls,['connect'])
        cancellation=request('cancel',targetRequestID=operation['requestID'])
        await self.bridge.handle(cancellation);await asyncio.sleep(0)
        self.assertFalse(any(row['kind']=='account_response' and row['resultRevision']==2 for row in self.out))
        await self.bridge.handle(request('status'))
        self.assertEqual(self.out[-1]['reasonCode'],'operation_busy')
        self.bridge.service.gate.set();await self.bridge.drain()
        self.assertEqual(self.bridge.store.metadata()['registrations'],[])
        terminals=[row for row in self.out if row['kind']=='account_response' and row['resultRevision']==2]
        self.assertEqual(len([row for row in terminals if row['requestID']==operation['requestID']]),1)
        self.assertEqual(terminals[-1]['requestID'],cancellation['requestID'])
        self.assertEqual(terminals[-1]['status'],'cancelled')

    async def test_cancel_in_same_reader_batch_before_worker_starts_has_both_exact_terminal_receipts(self):
        operation=request('connect',registrationID=None);cancel=request('cancel',targetRequestID=operation['requestID'])
        await self.bridge.handle(operation);await self.bridge.handle(cancel);await self.bridge.drain()
        terminals=[row for row in self.out if row['kind']=='account_response' and row['resultRevision']==2]
        self.assertEqual([row['requestID'] for row in terminals],[operation['requestID'],cancel['requestID']])
        self.assertTrue(all(row['status']=='cancelled' for row in terminals))
        self.assertEqual(self.bridge.service.calls,[])
    async def test_identity_only_connection_and_unconfirmed_signout_keep_mapping_not_tokens(self):
        self.bridge.service.scopes=['openid','email']
        _,identity=await self.connect()
        self.assertEqual(self.out[-1]['status'],'plan_disabled');self.assertEqual(self.bridge.service.calls,['connect'])
        await self.bridge.handle(request('sign_out',registrationID=identity));await self.bridge.drain()
        self.assertEqual(self.out[-1]['status'],'signed_out')
        self.assertEqual(self.out[-1]['reasonCode'],'remote_revocation_unconfirmed')
        metadata=self.bridge.store.metadata()
        self.assertIsNone(metadata['active']);self.assertEqual(metadata['registrations'][0]['registration_id'],identity)
        self.assertEqual(metadata['registrations'][0]['session_state'],'signed_out')
    async def test_changed_uuid_payload_cannot_reopen_or_overwrite_a_registration(self):
        operation,_=await self.connect();before=self.bridge.store.metadata()
        with self.assertRaises(AccountProtocolError):
            await self.bridge.handle({**operation,'action':'status','payload':{}})
        self.assertEqual(self.bridge.store.metadata(),before)
    async def test_notice_acknowledgement_is_persisted_without_any_network_or_permission_change(self):
        _,identity=await self.connect();before=list(self.bridge.service.calls)
        await self.bridge.handle(request('acknowledge_plan_notice',registrationID=identity));await self.bridge.drain()
        row=self.out[-1]['snapshot']['registrations'][0]
        self.assertTrue(row['planNoticeAcknowledged']);self.assertEqual(row['planUsageState'],'granted')
        self.assertEqual(self.bridge.service.calls,before)

    async def test_cancel_replay_and_second_cancel_cannot_interrupt_actual_cleanup(self):
        self.bridge.service.gate=asyncio.Event();operation=request('connect',registrationID=None)
        await self.bridge.handle(operation);await self.bridge.service.entered.wait()
        cancellation=request('cancel',targetRequestID=operation['requestID'])
        await self.bridge.handle(cancellation);await asyncio.sleep(0)
        await self.bridge.handle(cancellation)
        await self.bridge.handle(request('cancel',targetRequestID=operation['requestID']))
        await asyncio.sleep(0)
        self.assertFalse(any(row['kind']=='account_response' and row['resultRevision']==2 for row in self.out))
        self.bridge.service.gate.set();await self.bridge.drain()
        self.assertEqual(self.bridge.store.metadata()['registrations'],[])
        self.assertEqual(self.bridge.service.calls,['connect'])

    async def test_store_lock_wait_does_not_block_status_or_fake_cancellation_receipt(self):
        _,identity=await self.connect();entered=threading.Event();release=threading.Event()
        original=self.bridge.store.acknowledge_notice
        def held(identity):entered.set();release.wait(2);original(identity)
        self.bridge.store.acknowledge_notice=held
        operation=request('acknowledge_plan_notice',registrationID=identity)
        await self.bridge.handle(operation)
        self.assertTrue(await asyncio.to_thread(entered.wait,1))
        await asyncio.wait_for(self.bridge.handle(request('status')),.1)
        self.assertEqual(self.out[-1]['reasonCode'],'operation_busy')
        cancel=request('cancel',targetRequestID=operation['requestID']);await self.bridge.handle(cancel)
        await asyncio.sleep(.02)
        self.assertFalse(any(row['kind']=='account_response' and row['requestID']==cancel['requestID'] and row['resultRevision']==2 for row in self.out))
        release.set();await self.bridge.drain()
        self.assertEqual(self.out[-1]['requestID'],cancel['requestID'])

    async def test_joint_frame_budget_keeps_every_account_and_never_calls_partial_catalog_current(self):
        host=self.bridge.store.initialize();identities=[]
        for index in range(8):
            record=grant(host,saved_at=time.time(),subject=f'synthetic-subject-{index}',client_id=f'oaiapp_synthetic_{index}',email='"\\'*127)
            identities.append(self.bridge.store.save_registration(record))
        with self.bridge.store._locked():
            value=self.bridge.store._read()
            for row in value['registrations'].values():row['label']='"\\'*40
            self.bridge.store._save(value)
        for name in ('"\\'*80,'é'*80,'日'*53):
            with self.subTest(name_length=len(name.encode())):
                models=[dict(slug=('"\\'*62)+f'{index:04}',displayName=name) for index in range(32)]
                await self.bridge._load_snapshot(models=models,catalog='current')
                await self.bridge.handle(request('status'));response=self.out[-1]
                self.assertLessEqual(len(encode_frame(response)),16388)
                self.assertEqual([r['registrationID'] for r in response['snapshot']['registrations']],identities)
                self.assertEqual(response['snapshot']['models'],[])
                self.assertEqual(response['snapshot']['catalogState'],'unavailable')
        small=[dict(slug='second',displayName='Second'),dict(slug='first',displayName='First')]
        await self.bridge._load_snapshot(models=small,catalog='current')
        await self.bridge.handle(request('status'))
        self.assertEqual(self.out[-1]['snapshot']['models'],small)

    async def test_ledger_is_bounded_and_old_evicted_replay_fails_closed_without_io(self):
        operations=[request('status') for _ in range(512)]
        for operation in operations:await self.bridge.handle(operation)
        self.assertEqual(len(self.bridge._ledger),512);self.assertEqual(len(self.bridge._replies),8)
        self.assertEqual(self.bridge.service.calls,[])
        await self.bridge.handle(operations[-1]);self.assertEqual(self.out[-1]['requestID'],operations[-1]['requestID'])
        with self.assertRaises(AccountProtocolError):await self.bridge.handle(operations[0])
        self.assertEqual(self.bridge.service.calls,[])
