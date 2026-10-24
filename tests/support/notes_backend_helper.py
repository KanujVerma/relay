"""Explicit synthetic source-helper launcher. Importing this file is inert."""
import argparse
import os
from pathlib import Path
import stat
import sys
import tempfile


class _Parser(argparse.ArgumentParser):
    def error(self,message):raise ValueError('synthetic_test_arguments_required')


def _arguments(argv):
    marker=argv.index('-m') if '-m' in argv else len(argv)
    head,tail=argv[:marker],argv[marker:]
    parser=_Parser(add_help=False,allow_abbrev=False)
    parser.add_argument('--synthetic-notes-test',action='store_true',required=True)
    parser.add_argument('--log',required=True);parser.add_argument('--release',required=True)
    args=parser.parse_args(head)
    role='developer'
    if tail:
        if (len(tail)!=5 or tail[:3]!=['-m','relay_spike.session_host','--role']
            or tail[-1]!='--fixture-model'):raise ValueError('synthetic_test_tail_required')
        role=tail[3]
    if not 1<=len(role)<=80 or not all(c.isascii() and (c.isalnum() or c in ' _-') for c in role):raise ValueError('synthetic_test_role')
    log,release=Path(args.log),Path(args.release)
    if (not log.is_absolute() or not release.is_absolute() or log.parent!=release.parent or log==release
        or not log.parent.name.startswith('relay-notes-') or not log.parent.is_dir()):raise ValueError('synthetic_test_temporary_paths_required')
    parent=log.parent.resolve();metadata=parent.stat()
    roots={Path(tempfile.gettempdir()).resolve(),Path('/private/tmp').resolve(),Path('/tmp').resolve()}
    if (not any(parent.is_relative_to(root) for root in roots) or metadata.st_uid!=os.geteuid()
        or stat.S_IMODE(metadata.st_mode)!=0o700):raise ValueError('synthetic_test_owned_temporary_paths_required')
    return log,release,role


def main(argv=None):
    try:log,release,role=_arguments(sys.argv[1:] if argv is None else argv)
    except (ValueError,OSError,SystemExit):return 2
    # Test-only source import, after explicit synthetic argument validation.
    # This path is never used by the product resolver or bundled acceptance.
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
    import asyncio
    import json
    import os
    import time
    from types import SimpleNamespace
    import httpx
    from relay_spike import auth,session_host
    from relay_spike.oauth_answer_stream import OAuthAnswerStream
    from tests.test_visual_input import completed_wire
    try:fd=os.open(log,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    except OSError:return 2
    with os.fdopen(fd,'w',encoding='utf-8',buffering=1) as record:
        count=0
        def event(name,kind=None):
            nonlocal count
            count+=1
            if count>4096:raise ValueError('synthetic_log_budget')
            value={'event':name}
            if kind is not None:value['kind']=kind
            record.write(json.dumps(value,separators=(',',':'))+'\n')
        def forbidden():raise AssertionError('synthetic_test_has_no_legacy_credentials')
        auth.load_auth=forbidden
        async def run():
            loop=asyncio.get_running_loop();connect=loop.connect_read_pipe;reader_transport=None;poll=None
            async def connected(*args,**kwargs):
                nonlocal reader_transport
                reader_transport,protocol=await connect(*args,**kwargs);return reader_transport,protocol
            loop.connect_read_pipe=connected
            def resume(deadline):
                nonlocal poll
                if release.exists() or time.monotonic()>=deadline:
                    reader_transport.resume_reading();event('staging_released');poll=None
                else:poll=loop.call_later(.002,resume,deadline)
            original=session_host.SessionHost
            class ObservedHost(original):
                def handle_notes(self,value):
                    nonlocal poll
                    accepted=super().handle_notes(value)
                    kind=value['kind'];event('command',kind)
                    if accepted and kind=='notes_source_begin':
                        reader_transport.pause_reading();event('staging_held')
                        poll=loop.call_later(.002,resume,time.monotonic()+10)
                    return accepted
            session_host.SessionHost=ObservedHost
            async def response(request):
                event('model_post')
                prompt=json.loads(json.loads(request.content)['input'][0]['content']);row=prompt['rows'][0]
                quote=row['text'].encode()[:240].decode('utf-8',errors='ignore')
                output={'schemaVersion':1,'summary':[{'text':'Injected synthetic saved-text summary.',
                    'citations':[{'rowID':row['id'],'quote':quote}]}],'decisions':[],'nextSteps':[]}
                return httpx.Response(200,headers={'content-type':'text/event-stream'},
                    stream=httpx.ByteStream(completed_wire(json.dumps(output,separators=(',',':')))))
            stream=OAuthAnswerStream(model='relay-synthetic-fixture',token_provider=lambda:'synthetic-notes-only',
                client_factory=lambda **kw:httpx.AsyncClient(transport=httpx.MockTransport(response),**kw))
            args=SimpleNamespace(oauth=True,protected_account=False,fixture_model=False,model=stream.model,role=role)
            try:return await session_host.run_stdio(args,oauth_stream=stream)
            finally:
                if poll is not None:poll.cancel()
                session_host.SessionHost=original;loop.connect_read_pipe=connect
                await stream.aclose()
        return asyncio.run(run())


if __name__=='__main__':raise SystemExit(main())
