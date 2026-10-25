#!/usr/bin/env python3
"""Explicit actual-host idle lifecycle fixture, using only synthetic completion.

No import-time IO. Required paths are new temporary artifacts, never user data.
The real scope/worker/provider/framing code runs unchanged; only a receipt or
injected synthetic transport is held to expose actual lifecycle ownership.
"""


def main():
    import argparse
    import asyncio
    import json
    from pathlib import Path
    import sys
    import time
    from types import SimpleNamespace

    parser=argparse.ArgumentParser()
    parser.add_argument('--synthetic-idle-test',action='store_true',required=True)
    parser.add_argument('--log',required=True)
    parser.add_argument('--release',required=True)
    parser.add_argument('--hold',choices=('none','worker','token','open','eof'),default='none')
    arguments=sys.argv[1:];boundary=arguments.index('-m') if '-m' in arguments else len(arguments)
    args=parser.parse_args(arguments[:boundary]);tail=arguments[boundary:]
    if (len(tail) not in (4,5) or tail[:3]!=['-m','relay_spike.session_host','--role']
        or tail[3] not in ('analytics','developer','epic')
        or len(tail)==5 and tail[4] not in ('--fixture-model','--oauth')):
        parser.error('Expected the actual native module/role/mode suffix.')
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
    from tests.support.visual_backend_helper import _open_log
    # Reuse the existing strict temporary log-path validator for both paths.
    release=Path(args.release)
    with _open_log(args.release) as marker:pass
    release.unlink()
    import httpx
    from relay_spike.assistant_scope import AssistantScopeCoordinator
    from relay_spike.oauth_answer_stream import OAuthAnswerStream
    from relay_spike.session_host import run_stdio
    from tests.test_visual_host_backend import MODEL,generated_card
    from tests.test_visual_input import completed_wire
    import threading
    with _open_log(args.log) as log:
        lock=threading.Lock();count=0
        def record(kind):
            nonlocal count
            with lock:
                count+=1
                if count>64:raise ValueError('Synthetic log budget.')
                log.write(json.dumps({'kind':kind})+'\n');log.flush()
        def token():
            if args.hold=='token':
                record('token_entered')
                while not release.exists():time.sleep(.002)
                record('token_finished')
            return 'synthetic-idle-bearer'
        async def respond(request):
            if request.method!='POST':raise ValueError('Unexpected synthetic request.')
            record('text_post')
            if args.hold=='worker':
                record('worker_entered')
                while not release.exists():
                    try:await asyncio.sleep(.002)
                    except asyncio.CancelledError:pass
                record('worker_finished')
            return httpx.Response(200,stream=httpx.ByteStream(completed_wire(generated_card())),
                headers={'content-type':'text/event-stream'})
        if args.hold in ('open','eof'):
            original=AssistantScopeCoordinator._reply
            held=False
            def reply(self,n,status,**options):
                nonlocal held
                if args.hold=='eof':
                    original(self,n,status,**options)
                    if status=='ready' and not held:
                        held=True
                        async def terminate():
                            import os
                            while not release.exists():await asyncio.sleep(.002)
                            record('child_exit');os._exit(0)
                        asyncio.create_task(terminate())
                    return
                if status=='ready' and not held:
                    held=True;record('open_ready')
                    async def finish():
                        while not release.exists():await asyncio.sleep(.002)
                        original(self,n,status,**options)
                    asyncio.create_task(finish())
                else:original(self,n,status,**options)
            AssistantScopeCoordinator._reply=reply
        stream=OAuthAnswerStream(model=MODEL,token_provider=token,
            client_factory=lambda **options:httpx.AsyncClient(transport=httpx.MockTransport(respond),**options))
        return asyncio.run(run_stdio(SimpleNamespace(oauth=True,fixture_model=False,model=MODEL,role=tail[3]),oauth_stream=stream))


if __name__=='__main__':
    try:raise SystemExit(main())
    except Exception:raise SystemExit(2)
