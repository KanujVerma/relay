"""Explicit synthetic native-test launcher; imports never run a helper.

The actual account bridge/OIDC/HTTPX code runs with generated test RSA keys,
an in-memory callback and MockTransport. No OS credentials/browser/network.
This file is test support and must not be included in the product runtime.
"""
def main():
    import argparse
    import asyncio
    import json
    import os
    from pathlib import Path
    import sys
    import tempfile

    arguments=sys.argv[1:]
    if arguments[-2:]==['-m','relay_spike.account_bridge']:arguments=arguments[:-2]
    parser=argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('--synthetic-account-test',action='store_true',required=True)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--hold-callback',type=Path)
    options=parser.parse_args(arguments)
    raw=options.log.absolute();destination=raw.parent.resolve()/raw.name
    temporary_roots=(Path(tempfile.gettempdir()).resolve(),Path('/private/tmp'),Path('/private/var/folders'))
    if (not options.synthetic_account_test
        or not any(destination.is_relative_to(base) for base in temporary_roots)):
        return 2
    gate=None
    if options.hold_callback is not None:
        candidate=options.hold_callback.absolute();gate=candidate.parent.resolve()/candidate.name
        if not any(gate.is_relative_to(base) for base in temporary_roots):return 2
    fd=os.open(destination,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
    try:
        # File arguments are fixed test metadata paths, never token/env input.
        repository=Path(__file__).resolve().parents[2]
        sys.path.insert(0,str(repository))
        from cryptography.hazmat.primitives.asymmetric import rsa
        from relay_spike import auth
        from relay_spike.account_bridge import read_bootstrap_fd,run_stdio
        from relay_spike.account_oauth import AccountOAuthService
        from tests.test_account_oauth import OAuthEnvironment
        class Environment(OAuthEnvironment):
            def handler(self,request):
                kind=('token' if str(request.url)==auth.TOKEN_URL else 'catalog' if request.url.path=='/v1/models'
                    else 'revocation' if request.url.path=='/oauth/revoke' else 'identity_metadata')
                os.write(fd,json.dumps({'kind':kind},separators=(',',':')).encode()+b'\n')
                return super().handler(request)
        environment=Environment(rsa.generate_private_key(public_exponent=65537,key_size=2048))
        def listener(state):
            original=environment.listener(state)
            if gate is None:return original
            class HeldListener:
                redirect_uri=original.redirect_uri
                async def wait(self):
                    while not gate.exists():await asyncio.sleep(.01)
                    return await original.wait()
                async def close(self):await original.close()
            return HeldListener()
        class Service(AccountOAuthService):
            def __init__(self,store):
                super().__init__(store,client_factory=environment.client,sync_client_factory=environment.sync_client,
                    listener_factory=listener)
            async def connect(self,identity,publish,**kwargs):
                def authorized(url):environment.opened(url);publish(url)
                return await super().connect(identity,authorized,**kwargs)
        bootstrap=read_bootstrap_fd(0,purpose='account_control')
        return asyncio.run(run_stdio(bootstrap,service_factory=Service))
    except Exception:return 2
    finally:os.close(fd)

if __name__=='__main__':raise SystemExit(main())
