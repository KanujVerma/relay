"""Native noncapture scope, not audio permission or account-thread ownership.

Quiescence joins the inference/probe/cancellation coroutines. A protected
account-global token refresh running in to_thread can outlive cancellation;
its retired coroutine cannot POST/publish. Account/mode/identity changes must
additionally stop and reap the actual helper before mutating that identity.
"""
from collections import OrderedDict
from hashlib import sha256
import asyncio
import json
import time

from .panel_wire import exact, u64, uuid_string, WireError

_CONTROL=('schemaVersion','kind','action','requestID','assistantSessionID','sessionEpoch',
          'presentationGeneration','controlSequence','emittedUptimeNanoseconds')


def decode_assistant_scope(value):
    exact(value,_CONTROL)
    if type(value['schemaVersion']) is not int or value['schemaVersion']!=1 or value['kind']!='assistant_scope_request':
        raise WireError('assistant_scope_schema')
    if value['action'] not in ('open','close'):raise WireError('assistant_scope_action')
    uuid_string(value['requestID']);uuid_string(value['assistantSessionID'])
    for key in ('sessionEpoch','presentationGeneration','controlSequence'):u64(value[key],True)
    u64(value['emittedUptimeNanoseconds'])
    return dict(value)


class AssistantScopeCoordinator:
    def __init__(self,host):
        self.host=host
        self._ledger={}
        self._replies=OrderedDict()
        self._closing=None

    @property
    def closing(self):return self._closing is not None

    def _reply(self,n,status,*,quiesced=False):
        reply={key:n[key] for key in ('schemaVersion','action','requestID','assistantSessionID',
                                     'sessionEpoch','presentationGeneration','controlSequence')}
        reply.update(kind='assistant_scope_response',status=status)
        if n['action']=='close':reply['quiesced']=quiesced
        self._replies[n['requestID'].lower()]=reply
        while len(self._replies)>8:self._replies.popitem(last=False)
        self.host.emit(dict(reply))

    def _work_pending(self):
        h=self.host
        return (self.closing or h._worker is not None and not h._worker.done()
                or any(not task.done() for task in h.tasks)
                or any(not task.done() for task in h.user.cancel_tasks)
                or h.visual._probe_task is not None)

    def handle(self,raw):
        try:n=decode_assistant_scope(raw)
        except Exception:
            self.host.close();raise WireError('invalid_assistant_scope') from None
        identity=n['requestID'].lower()
        fingerprint=sha256(json.dumps(n,sort_keys=True,separators=(',',':')).encode()).digest()
        if identity in self._ledger:
            if self._ledger[identity]!=fingerprint:
                self.host.close();raise WireError('assistant_scope_reuse')
            if identity in self._replies:self.host.emit(dict(self._replies[identity]))
            return False
        if len(self._ledger)>=512:
            self.host.close();raise WireError('assistant_scope_budget')
        self._ledger[identity]=fingerprint
        fresh=0<=time.monotonic_ns()-n['emittedUptimeNanoseconds']<=2_000_000_000
        if n['action']=='open':
            if self.host.live or self._work_pending():self._reply(n,'busy');return False
            if not fresh or (n['sessionEpoch'],n['presentationGeneration'],n['controlSequence'])!=(1,1,1):
                self._reply(n,'unavailable');return False
            scope=(n['assistantSessionID'].lower(),n['sessionEpoch'])
            if scope==self.host.session:self._reply(n,'unavailable');return False
            self.host._begin_assistant_scope(scope)
            self._reply(n,'ready');return True
        h=self.host
        if (not fresh or self.closing or not h.live or h.scope_kind!='assistant'
            or (n['assistantSessionID'].lower(),n['sessionEpoch'])!=h.session
            or n['controlSequence']!=2 or n['presentationGeneration']<=h.presentation):
            self._reply(n,'unavailable');return False
        h.presentation=n['presentationGeneration']
        h.close()
        async def finish():
            try:
                await h.drain()
                self._reply(n,'closed',quiesced=True)
            finally:self._closing=None
        # This task is deliberately outside the inference/cancel sets it joins.
        self._closing=asyncio.create_task(finish())
        return True

    async def drain(self):
        task=self._closing
        if task is not None:await asyncio.gather(task,return_exceptions=True)
