"""Encrypted product credentials, separate from profile consent and CLI files.

Only the verified OAuth service may commit a registration. Storage validation
does not verify an ID token. The OS key is supplied privately by native code;
there is no key generation, plaintext fallback, network or IO at construction.
"""
from contextlib import contextmanager
from copy import deepcopy
import json
import math
from pathlib import Path
import secrets
import time
import unicodedata
import uuid
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from . import auth,protected_storage as storage
from .generated_answer import strict_json,CardError

_HEADER=b'RELAYAUTH1\n'
_LIMIT=1_048_576
_TOKENS=('access_token','refresh_token','id_token','token_type','expires_in','saved_at')
_GRANT=('issuer','subject','client_id','email','ext_agent_host_id','scopes',*_TOKENS)
_RECORD=(*_GRANT,'registration_id','label','state','notice_ack','last_validated_at')

class AccountStoreError(auth.AuthError):
    def __init__(self,code):self.code=code;super().__init__(code)

def _identity(value):
    if not isinstance(value,str) or str(uuid.UUID(value))!=value.lower():raise ValueError()
    return value.lower()

def _text(value,limit,*,ascii_only=False):
    if not isinstance(value,str) or not value.strip() or len(value.encode())>limit:raise ValueError()
    if any(unicodedata.category(c) in ('Cc','Cf','Cs','Zl','Zp') for c in value):raise ValueError()
    if ascii_only and not value.isascii():raise ValueError()

def _grant(record,host):
    if record['issuer']!=auth.ISSUER or record['ext_agent_host_id']!=host:raise ValueError()
    _text(record['subject'],512);_text(record['client_id'],512,ascii_only=True)
    if record['client_id']=='dynamic_agent_client':raise ValueError()
    if record['email'] is not None:_text(record['email'],254)
    scopes=record['scopes']
    if not isinstance(scopes,list) or len(scopes)>32 or len(set(scopes))!=len(scopes):raise ValueError()
    for scope in scopes:
        _text(scope,80,ascii_only=True)
        if any(c.isspace() for c in scope):raise ValueError()
    if record.get('state') in ('signed_out','reauth_required'):
        if scopes or any(record[k] is not None for k in _TOKENS):raise ValueError()
        return
    for field in ('access_token','id_token'):_text(record[field],32768,ascii_only=True)
    refresh=record['refresh_token']
    if refresh is not None:_text(refresh,32768,ascii_only=True)
    if 'offline_access' in scopes and refresh is None:raise ValueError()
    if record['token_type']!='Bearer' or type(record['expires_in']) is not int or not 0<record['expires_in']<=2**31-1:raise ValueError()
    saved=record['saved_at']
    if type(saved) not in (int,float) or not math.isfinite(saved) or saved<=0:raise ValueError()

def _registry(value):
    if not isinstance(value,dict) or set(value)!=set(('schema','host_id','revision','active','registrations')):raise ValueError()
    if type(value['schema']) is not int or value['schema']!=1:raise ValueError()
    if not isinstance(value['host_id'],str) or not value['host_id'].startswith('urn:uuid:'):raise ValueError()
    _identity(value['host_id'][9:])
    if type(value['revision']) is not int or not 1<=value['revision']<2**64:raise ValueError()
    records=value['registrations']
    if not isinstance(records,dict) or len(records)>8:raise ValueError()
    for identity,record in records.items():
        _identity(identity)
        if not isinstance(record,dict) or set(record)!=set(_RECORD) or record['registration_id']!=identity:raise ValueError()
        _text(record['label'],80)
        if record['state'] not in ('available','refreshing','signing_out','signed_out','reauth_required'):raise ValueError()
        if type(record['notice_ack']) is not bool or type(record['last_validated_at']) not in (int,float):raise ValueError()
        if not math.isfinite(record['last_validated_at']) or record['last_validated_at']<=0:raise ValueError()
        _grant(record,value['host_id'])
    active=value['active']
    if active is not None:
        if not isinstance(active,dict) or set(active)!=set(('registration_id','generation')):raise ValueError()
        _identity(active['registration_id']);_identity(active['generation'])
        if active['registration_id'] not in records:raise ValueError()

class AccountCredentialStore:
    def __init__(self,directory,key,*,now=time.time):
        if not isinstance(key,bytes) or len(key)!=32:raise AccountStoreError('storage_unavailable')
        directory=Path(directory)
        if not directory.is_absolute():raise AccountStoreError('storage_unavailable')
        self.path=directory/'credentials.relayvault';self._key=key;self._now=now

    @contextmanager
    def _locked(self):
        try:
            with storage.credential_lock(self.path):yield
        except storage.ProtectedStorageError:raise AccountStoreError('storage_unavailable') from None

    def _read(self):
        try:
            data=storage.read_bytes(self.path,limit=_LIMIT+len(_HEADER)+28)
            if not data.startswith(_HEADER):raise ValueError()
            body=data[len(_HEADER):]
            plain=AESGCM(self._key).decrypt(body[:12],body[12:],_HEADER)
            value=strict_json(plain,max_bytes=_LIMIT);_registry(value);return value
        except (storage.ProtectedStorageError,InvalidTag,ValueError,TypeError,KeyError,CardError,UnicodeError):
            raise AccountStoreError('storage_unavailable') from None

    def _write(self,value):
        try:
            _registry(value)
            data=json.dumps(value,ensure_ascii=False,allow_nan=False,separators=(',',':')).encode()
            if not data or len(data)>_LIMIT:raise ValueError()
            nonce=secrets.token_bytes(12)
            storage.replace_bytes(self.path,_HEADER+nonce+AESGCM(self._key).encrypt(nonce,data,_HEADER))
        except (storage.ProtectedStorageError,ValueError,TypeError,KeyError,UnicodeError):
            raise AccountStoreError('storage_unavailable') from None

    def initialize(self):
        with self._locked():
            # lexists includes a broken symlink: corruption never creates a key/store.
            import os
            if os.path.lexists(self.path):return self._read()['host_id']
            value=dict(schema=1,host_id='urn:uuid:'+str(uuid.uuid4()),revision=1,active=None,registrations={})
            self._write(value);return value['host_id']

    def _save(self,value):
        value['revision']+=1;self._write(value)

    def save_registration(self,record,*,registration_id=None):
        """Internal OAuth-service boundary, after actual ID-token verification."""
        with self._locked():
            value=self._read()
            try:
                if not isinstance(record,dict) or set(record)!=set(_GRANT):raise ValueError()
                _grant(record,value['host_id'])
                if registration_id is not None:
                    registration_id=_identity(registration_id);old=value['registrations'][registration_id]
                    if any(record[k]!=old[k] for k in ('issuer','subject','client_id')):raise ValueError()
                else:
                    registration_id=next((key for key,old in value['registrations'].items()
                        if all(record[k]==old[k] for k in ('issuer','subject','client_id'))),None)
                    if registration_id is None:
                        if len(value['registrations'])>=8:raise ValueError()
                        registration_id=str(uuid.uuid4())
                    old=value['registrations'].get(registration_id,{})
                value['registrations'][registration_id]={**deepcopy(record),'registration_id':registration_id,
                    'label':old.get('label',f'ChatGPT account {len(value["registrations"])+1}'),
                    'state':'available','notice_ack':old.get('notice_ack',False),'last_validated_at':self._now()}
            except (ValueError,TypeError,KeyError,UnicodeError):raise AccountStoreError('authorization_failed') from None
            self._save(value);return registration_id

    def select(self,registration_id,generation):
        with self._locked():
            value=self._read()
            try:
                registration_id=_identity(registration_id);generation=_identity(generation)
                if value['registrations'][registration_id]['state']!='available':raise ValueError()
            except (ValueError,TypeError,KeyError):raise AccountStoreError('reauthentication_required') from None
            value['active']=dict(registration_id=registration_id,generation=generation);self._save(value)

    def metadata(self):
        with self._locked():
            value=self._read()
            return dict(revision=value['revision'],host_id=value['host_id'],active=deepcopy(value['active']),
                registrations=[dict(registration_id=r['registration_id'],label=r['label'],email=r['email'],
                    session_state='reauth_required' if r['state']=='refreshing' else r['state'],
                    plan_permission=auth.REQUIRED_PLAN_SCOPE in r['scopes'] if r['state']=='available' else None,
                    last_validated_at=r['last_validated_at'],notice_ack=r['notice_ack']) for r in value['registrations'].values()])

    def registration(self,registration_id):
        """Private reauthorization/revocation input, never a public DTO."""
        with self._locked():
            try:return deepcopy(self._read()['registrations'][_identity(registration_id)])
            except (KeyError,ValueError,TypeError):raise AccountStoreError('reauthentication_required') from None

    @staticmethod
    def _clear(record,state):
        record.update({key:None for key in _TOKENS});record['scopes']=[];record['state']=state

    def active_access_token(self,registration_id,generation,*,refresh=None):
        with self._locked():
            value=self._read()
            if value['active']!=dict(registration_id=registration_id,generation=generation):raise AccountStoreError('account_changed')
            record=value['registrations'][registration_id]
            if record['state']!='available':raise AccountStoreError('reauthentication_required')
            if auth.REQUIRED_PLAN_SCOPE not in record['scopes']:raise AccountStoreError('plan_permission_missing')
            if self._now()<record['saved_at']+record['expires_in']-auth.REFRESH_SKEW_SECONDS:return record['access_token']
            if refresh is None:raise AccountStoreError('reauthentication_required')
            if not record['refresh_token'] or 'offline_access' not in record['scopes']:raise AccountStoreError('reauthentication_required')
            # A crash after remote consumption must not blindly reuse the old
            # rotating grant on restart. Transient confirmed failure preserves it.
            record['state']='refreshing';self._save(value)
            try:payload=refresh(deepcopy(record))
            except (auth.UnusableRefreshToken,auth.MalformedRefreshResponse):
                self._clear(record,'reauth_required');self._save(value)
                raise AccountStoreError('reauthentication_required') from None
            except auth.AuthError:
                record['state']='available';self._save(value)
                raise AccountStoreError('credential_request_failed') from None
            except Exception:
                # An unclassified success/parsing failure may have consumed
                # the grant. Keep the durable intent blocked across restart.
                raise AccountStoreError('reauthentication_required') from None
            try:
                if not isinstance(payload,dict):raise ValueError()
                if type(payload.get('expires_in')) is not int:raise ValueError()
                access,scopes,lifetime=auth.validate_token_fields(payload)
                replacement=payload.get('refresh_token')
                if (not isinstance(replacement,str) or not replacement.strip() or replacement==record['refresh_token']
                    or access==record['access_token'] or payload.get('client_id',record['client_id'])!=record['client_id']
                    or auth.REQUIRED_PLAN_SCOPE not in scopes or 'offline_access' not in scopes):raise ValueError()
                rotated={**record,'access_token':access,'refresh_token':replacement,'scopes':scopes,
                    'expires_in':lifetime,'saved_at':self._now(),'token_type':'Bearer','state':'available'}
                _grant(rotated,value['host_id'])
            except (auth.AuthError,ValueError,TypeError,KeyError,UnicodeError):
                self._clear(record,'reauth_required');self._save(value)
                raise AccountStoreError('reauthentication_required') from None
            value['registrations'][registration_id]=rotated;self._save(value);return access

    def begin_sign_out(self,registration_id):
        with self._locked():
            value=self._read()
            try:record=value['registrations'][_identity(registration_id)]
            except (KeyError,ValueError,TypeError):raise AccountStoreError('reauthentication_required') from None
            previous=deepcopy(record)
            if record['state'] not in ('signed_out','reauth_required'):
                record['state']='signing_out';self._save(value)
            return previous

    def finish_sign_out(self,registration_id):
        with self._locked():
            value=self._read()
            try:record=value['registrations'][_identity(registration_id)]
            except (KeyError,ValueError,TypeError):raise AccountStoreError('reauthentication_required') from None
            self._clear(record,'signed_out')
            if value['active'] is not None and value['active']['registration_id']==registration_id:value['active']=None
            self._save(value)
