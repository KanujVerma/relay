"""Explicit test-only actual protected SessionHost with synthetic HTTP only.

No import effects. The production factory, encrypted provider and host run;
every client is MockTransport and DNS/socket connect are forbidden. Private
bootstrap must name an owned temporary test directory before any store read.
"""
def main():
    import argparse
    import asyncio
    import json
    import os
    from pathlib import Path
    import secrets
    import socket
    import sys
    import tempfile
    import time

    arguments=sys.argv[1:]
    if '-m' not in arguments:return 2
    boundary=arguments.index('-m');prefix,tail=arguments[:boundary],arguments[boundary:]
    if tail[:2]!=['-m','relay_spike.session_host']:return 2
    parser=argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('--synthetic-product-account-test',action='store_true',required=True)
    parser.add_argument('--log',type=Path,required=True);parser.add_argument('--hold-refresh',type=Path)
    options=parser.parse_args(prefix)
    host=argparse.ArgumentParser(allow_abbrev=False)
    host.add_argument('--role',required=True);host.add_argument('--oauth',action='store_true',required=True)
    host.add_argument('--protected-account',action='store_true',required=True);host.add_argument('--model',required=True)
    args=host.parse_args(tail[2:]);args.fixture_model=False
    roots=(Path(tempfile.gettempdir()).resolve(),Path('/private/tmp'),Path('/private/var/folders'))
    def temporary(path):
        value=path.absolute();value=value.parent.resolve()/value.name
        if not any(value.is_relative_to(root) for root in roots):raise ValueError('synthetic_temporary_path_required')
        return value
    try:
        destination=temporary(options.log);gate=temporary(options.hold_refresh) if options.hold_refresh else None
        fd=os.open(destination,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
    except (OSError,ValueError):return 2
    def denied(*_,**__):raise AssertionError('synthetic_helper_network_forbidden')
    socket.socket.connect=denied;socket.socket.connect_ex=denied;socket.getaddrinfo=denied
    try:
        sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
        import httpx
        from relay_spike import auth
        from relay_spike.account_bridge import read_bootstrap_fd
        from relay_spike.account_oauth import AccountOAuthService
        from relay_spike.product_session import protected_answer_stream
        from relay_spike.session_host import run_stdio
        from tests.test_visual_input import completed_wire,read_probe_pixels
        clock=[time.time()];rows=[0]
        def record(kind,**fields):
            rows[0]+=1
            if rows[0]>128:raise ValueError('synthetic_log_bound')
            os.write(fd,json.dumps(dict(kind=kind,**fields),separators=(',',':')).encode()+b'\n')
        def response(request):
            if str(request.url)==auth.TOKEN_URL:
                record('refresh_waiting' if gate is not None else 'refresh')
                while gate is not None and not gate.exists():time.sleep(.01)
                suffix=secrets.token_urlsafe(16)
                return httpx.Response(200,json=dict(access_token='synthetic-product-rotated-'+suffix,
                    refresh_token='synthetic-product-refresh-'+suffix,token_type='Bearer',scope=auth.SCOPE,expires_in=3600))
            if request.url.path=='/v1/responses':
                body=json.loads(request.content)
                if body.get('store') is not False or body.get('stream') is not True:raise ValueError('synthetic_payload_contract')
                if body.get('instructions','').startswith('Relay synthetic visual check'):
                    expected,_=read_probe_pixels(body);return httpx.Response(200,stream=httpx.ByteStream(completed_wire(expected)),headers={'content-type':'text/event-stream'})
                token=request.headers.get('Authorization','')
                record('model',credential='rotated' if 'synthetic-product-rotated-' in token else 'original')
                clock[0]+=4000
                card=dict(lead='Explain how an event loop runs queued callbacks and resumes asynchronous work.',
                    points=['Use a separate worker or a nonblocking API for blocking operations.',
                        'Explain the callback queue and when suspended work can continue.'],detail=None,
                    assumptions=['This is injected synthetic output for the protected account product regression.'],
                    coverage=['current_request'],personal_fact_ids=[])
                return httpx.Response(200,stream=httpx.ByteStream(completed_wire(json.dumps(card))),headers={'content-type':'text/event-stream'})
            raise AssertionError('unexpected_synthetic_http_route')
        class Service(AccountOAuthService):
            def __init__(self,store):
                store._now=lambda:clock[0]
                super().__init__(store,client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(response),**kw),
                    sync_client_factory=lambda **kw:httpx.Client(transport=httpx.MockTransport(response),**kw),now=lambda:clock[0])
        def private_bootstrap(fd,*,purpose):
            bootstrap=read_bootstrap_fd(fd,purpose=purpose)
            temporary(bootstrap.directory) # Before any registry/credential IO.
            return bootstrap
        stream=protected_answer_stream(args.model,input_fd=0,service_factory=Service,
            client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(response),**kw),bootstrap_reader=private_bootstrap)
        return asyncio.run(run_stdio(args,oauth_stream=stream))
    except Exception:return 2
    finally:os.close(fd)

if __name__=='__main__':raise SystemExit(main())
