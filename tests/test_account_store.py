"""Synthetic protected account storage only: no OS key, browser or network."""
import json
import os
import multiprocessing
import time
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch

from relay_spike import auth
from relay_spike.account_store import AccountCredentialStore, AccountStoreError

KEY=bytes(range(32))
NOW=100_000.0

def grant(host,**changes):
    value=dict(issuer=auth.ISSUER,subject='synthetic-subject',client_id='oaiapp_synthetic',
        email='synthetic@example.test',ext_agent_host_id=host,scopes=auth.SCOPE.split(),
        id_token='synthetic-id-secret',access_token='synthetic-access-secret',
        refresh_token='synthetic-refresh-secret',token_type='Bearer',expires_in=3600,saved_at=NOW)
    value.update(changes);return value

def replacement(**changes):
    value=dict(access_token='synthetic-access-rotated',refresh_token='synthetic-refresh-rotated',
        token_type='Bearer',scope=auth.SCOPE,expires_in=3600)
    value.update(changes);return value

def _refresh_process(folder,identity,generation,log,crash=False):
    store=AccountCredentialStore(folder,KEY,now=lambda:NOW)
    def refresh(_):
        with open(log,'a') as output:output.write('refresh\n');output.flush()
        if crash:os._exit(23)
        time.sleep(.1);return replacement()
    store.active_access_token(identity,generation,refresh=refresh)

class AccountStoreTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory();self.addCleanup(self.folder.cleanup)
        self.directory=Path(self.folder.name)/'accounts'
        self.store=AccountCredentialStore(self.directory,KEY,now=lambda:NOW)
        self.host=self.store.initialize()

    def saved(self,**changes):
        identity=self.store.save_registration(grant(self.host,**changes))
        generation=str(uuid.uuid4());self.store.select(identity,generation)
        return identity,generation

    def test_constructor_is_inert_and_full_record_is_encrypted_with_stable_host(self):
        absent=Path(self.folder.name)/'unopened'
        AccountCredentialStore(absent,KEY)
        self.assertFalse(absent.exists())
        identity,generation=self.saved()
        raw=self.store.path.read_bytes()
        for text in ('synthetic-subject','oaiapp_synthetic','synthetic@example.test',
                     'synthetic-id-secret','synthetic-access-secret','synthetic-refresh-secret'):
            self.assertNotIn(text.encode(),raw)
        self.assertEqual(self.store.path.stat().st_mode&0o777,0o600)
        self.assertEqual(self.directory.stat().st_mode&0o777,0o700)
        self.assertEqual(AccountCredentialStore(self.directory,KEY).initialize(),self.host)
        with patch.object(auth,'load_auth',side_effect=AssertionError('no plaintext fallback')):
            self.assertEqual(self.store.active_access_token(identity,generation),'synthetic-access-secret')

    def test_wrong_key_tamper_and_unsafe_file_never_replace_the_ciphertext(self):
        self.saved();original=self.store.path.read_bytes()
        wrong=AccountCredentialStore(self.directory,b'x'*32)
        with self.assertRaises(AccountStoreError):wrong.initialize()
        self.assertEqual(self.store.path.read_bytes(),original)
        corrupted=original[:-1]+bytes([original[-1]^1]);self.store.path.write_bytes(corrupted)
        with self.assertRaises(AccountStoreError):self.store.metadata()
        self.assertEqual(self.store.path.read_bytes(),corrupted)
        self.store.path.write_bytes(original);self.store.path.chmod(0o644)
        with self.assertRaises(AccountStoreError):self.store.metadata()

    def test_registration_identity_is_not_email_and_returning_identity_cannot_change(self):
        first,_=self.saved()
        second=self.store.save_registration(grant(self.host,client_id='oaiapp_second'))
        self.assertNotEqual(first,second)
        self.assertEqual(len(self.store.metadata()['registrations']),2)
        for changes in ({'subject':'other'},{'client_id':'oaiapp_other'},{'issuer':'https://example.test'}):
            with self.subTest(changes=changes),self.assertRaises(AccountStoreError):
                self.store.save_registration(grant(self.host,**changes),registration_id=first)
        self.assertEqual(len(self.store.metadata()['registrations']),2)

    def test_refresh_rotates_complete_grant_once_and_reloads_under_same_lock(self):
        identity,generation=self.saved(saved_at=NOW-3590)
        calls=[]
        def refresh(record):
            calls.append(record['refresh_token']);return replacement()
        self.assertEqual(self.store.active_access_token(identity,generation,refresh=refresh),'synthetic-access-rotated')
        self.assertEqual(self.store.active_access_token(identity,generation,refresh=refresh),'synthetic-access-rotated')
        self.assertEqual(calls,['synthetic-refresh-secret'])
        self.assertNotIn(b'synthetic-refresh-rotated',self.store.path.read_bytes())
        self.assertTrue((self.directory/(self.store.path.name+'.lock')).is_file())

    def test_terminal_and_malformed_rotation_block_old_tokens_but_transient_failure_preserves(self):
        identity,generation=self.saved(saved_at=NOW-3590)
        def temporary(_):raise auth.AuthError('private upstream detail')
        with self.assertRaises(AccountStoreError) as caught:
            self.store.active_access_token(identity,generation,refresh=temporary)
        self.assertNotIn('private',str(caught.exception))
        self.assertEqual(self.store.metadata()['registrations'][0]['session_state'],'available')
        self.assertEqual(self.store.active_access_token(identity,generation,refresh=lambda _:replacement()),'synthetic-access-rotated')
        for result in (None,{},replacement(refresh_token='synthetic-refresh-secret'),auth.UnusableRefreshToken('terminal')):
            # Use an explicitly expired fresh grant for each independent rotation.
            self.store.save_registration(grant(self.host,saved_at=NOW-3590),registration_id=identity)
            self.store.select(identity,generation)
            def invalid(_):
                if isinstance(result,Exception):raise result
                return result
            with self.subTest(result=result),self.assertRaises(AccountStoreError):
                self.store.active_access_token(identity,generation,refresh=invalid)
            self.assertEqual(self.store.metadata()['registrations'][0]['session_state'],'reauth_required')

    def test_selection_generation_and_plan_scope_are_independent_network_gates(self):
        identity,generation=self.saved()
        with self.assertRaises(AccountStoreError):self.store.active_access_token(identity,str(uuid.uuid4()))
        other=self.store.save_registration(grant(self.host,client_id='oaiapp_identity_only',scopes=['openid','email']))
        self.store.select(other,generation)
        with self.assertRaises(AccountStoreError):self.store.active_access_token(other,generation)
        with self.assertRaises(AccountStoreError):self.store.active_access_token(identity,generation)

    def test_signout_denial_survives_restart_and_clears_only_token_material(self):
        identity,generation=self.saved()
        self.store.begin_sign_out(identity)
        reopened=AccountCredentialStore(self.directory,KEY,now=lambda:NOW)
        with self.assertRaises(AccountStoreError):reopened.active_access_token(identity,generation)
        reopened.finish_sign_out(identity)
        snapshot=reopened.metadata()
        self.assertEqual(snapshot['host_id'],self.host)
        self.assertIsNone(snapshot['active'])
        self.assertEqual(snapshot['registrations'][0]['session_state'],'signed_out')
        self.assertEqual(snapshot['registrations'][0]['registration_id'],identity)

    def test_hardlink_symlink_and_directory_mode_fail_closed(self):
        self.saved();alias=Path(self.folder.name)/'alias';os.link(self.store.path,alias)
        with self.assertRaises(AccountStoreError):self.store.metadata()
        alias.unlink();self.directory.chmod(0o755)
        with self.assertRaises(AccountStoreError):self.store.metadata()
        self.directory.chmod(0o700)
        target=self.store.path.with_name('ciphertext');self.store.path.rename(target)
        self.store.path.symlink_to(target)
        with self.assertRaises(AccountStoreError):self.store.metadata()

    def test_two_actual_processes_refresh_once_and_reload_the_rotated_grant(self):
        identity,generation=self.saved(saved_at=NOW-3590)
        log=Path(self.folder.name)/'refresh.log';processes=[]
        try:
            for _ in range(2):
                process=multiprocessing.get_context('spawn').Process(target=_refresh_process,
                    args=(self.directory,identity,generation,log))
                process.start();processes.append(process)
            for process in processes:process.join(8);self.assertEqual(process.exitcode,0)
        finally:
            for process in processes:
                if process.is_alive():process.kill();process.join(2)
        self.assertEqual(log.read_text().splitlines(),['refresh'])

    def test_crashed_refresh_owner_leaves_durable_denial_instead_of_reusing_old_grant(self):
        identity,generation=self.saved(saved_at=NOW-3590);log=Path(self.folder.name)/'refresh.log'
        process=multiprocessing.get_context('spawn').Process(target=_refresh_process,
            args=(self.directory,identity,generation,log,True))
        process.start();process.join(8)
        if process.is_alive():process.kill();process.join(2);self.fail('owned process did not exit')
        self.assertEqual(process.exitcode,23)
        calls=[]
        with self.assertRaises(AccountStoreError):
            AccountCredentialStore(self.directory,KEY,now=lambda:NOW).active_access_token(identity,generation,
                refresh=lambda _:(calls.append(1),replacement())[1])
        self.assertEqual(calls,[])
        self.assertEqual(log.read_text().splitlines(),['refresh'])

    def test_rotation_write_failure_does_not_return_token_or_reuse_possibly_spent_refresh(self):
        from relay_spike import protected_storage
        identity,generation=self.saved(saved_at=NOW-3590)
        original=protected_storage.durable_sync;calls=[]
        def fail_rotation_file(fd):
            calls.append(fd)
            if len(calls)==3:raise OSError('synthetic write failure')
            original(fd)
        with patch.object(protected_storage,'durable_sync',side_effect=fail_rotation_file),self.assertRaises(AccountStoreError):
            self.store.active_access_token(identity,generation,refresh=lambda _:replacement())
        retries=[]
        with self.assertRaises(AccountStoreError):
            AccountCredentialStore(self.directory,KEY,now=lambda:NOW).active_access_token(identity,generation,
                refresh=lambda _:(retries.append(1),replacement())[1])
        self.assertEqual(retries,[])
        self.assertFalse(list(self.directory.glob('.relay-*')))

    def test_refresh_success_with_noninteger_expiry_is_quarantined_not_coerced(self):
        for expiry in (True,'3600',3600.0):
            with self.subTest(expiry=expiry):
                identity,generation=self.saved(saved_at=NOW-3590)
                with self.assertRaises(AccountStoreError):
                    self.store.active_access_token(identity,generation,refresh=lambda _:replacement(expires_in=expiry))
                self.assertEqual(self.store.metadata()['registrations'][0]['session_state'],'reauth_required')

    def test_registration_budget_refuses_new_record_without_replacing_existing_mapping(self):
        for index in range(8):self.store.save_registration(grant(self.host,client_id=f'oaiapp_{index}'))
        before=self.store.metadata()
        with self.assertRaises(AccountStoreError):self.store.save_registration(grant(self.host,client_id='oaiapp_ninth'))
        self.assertEqual(self.store.metadata(),before)

    def test_unknown_refresh_exception_keeps_durable_uncertainty_without_reusing_grant(self):
        identity,generation=self.saved(saved_at=NOW-3590)
        def unknown(_):raise ValueError('synthetic unclassified success parsing failure')
        with self.assertRaises(AccountStoreError):self.store.active_access_token(identity,generation,refresh=unknown)
        calls=[]
        with self.assertRaises(AccountStoreError):
            AccountCredentialStore(self.directory,KEY,now=lambda:NOW).active_access_token(identity,generation,
                refresh=lambda _:(calls.append(1),replacement())[1])
        self.assertEqual(calls,[])
