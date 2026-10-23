#!/usr/bin/env python3
"""Explicit synthetic launcher for native visual-retirement regression tests.

pythonArguments: [this_file, "--synthetic-visual-test", "--log", new_temp_path]
The exact module/role/mode suffix appended by HelperTransport is validated too.
The real helper runs with an injected token and HTTPX MockTransport only.
JSONL records contain exactly {kind, count}; never headers, prompts or PNGs.
Importing this module starts nothing and creates no files.
"""
from __future__ import annotations


def _open_log(name):
    import os
    from pathlib import Path
    import tempfile

    path = Path(name)
    if not path.is_absolute():
        raise ValueError('A temporary absolute log path is required.')
    parent = path.parent.resolve(strict=True)
    roots = {Path(tempfile.gettempdir()).resolve(), Path('/tmp').resolve()}
    roots.discard(Path('/'))
    if not any(parent == root or root in parent.parents for root in roots):
        raise ValueError('The log must be in a temporary directory.')
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(parent / path.name, flags, 0o600)
    return os.fdopen(descriptor, 'w', encoding='utf-8', buffering=1)


def main(argv=None):
    import argparse
    import asyncio
    import json
    from pathlib import Path
    import sys
    from types import SimpleNamespace

    parser = argparse.ArgumentParser(description='Synthetic native visual test helper; no real account or network.')
    parser.add_argument('--synthetic-visual-test', action='store_true', required=True)
    parser.add_argument('--log', required=True, help='New, nonexistent absolute temporary JSONL path.')
    arguments = list(sys.argv[1:] if argv is None else argv)
    boundary = arguments.index('-m') if '-m' in arguments else len(arguments)
    args = parser.parse_args(arguments[:boundary])
    tail = arguments[boundary:]
    if tail and (len(tail) not in (4, 5)
                 or tail[:3] != ['-m', 'relay_spike.session_host', '--role']
                 or tail[3] not in ('analytics', 'epic', 'developer')
                 or (len(tail) == 5 and tail[4] not in ('--fixture-model', '--oauth'))):
        parser.error('Expected only the HelperTransport module/role/mode suffix.')
    role = tail[3] if tail else 'analytics'

    try:
        # Direct script execution otherwise puts tests/support, not the repo,
        # on sys.path. All production/test imports follow the explicit flags.
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        import httpx
        from relay_spike.oauth_answer_stream import OAuthAnswerStream
        from relay_spike.session_host import run_stdio
        from relay_spike.stream import MODELS, RESPONSES
        from relay_spike.visual_input import PROBE_INSTRUCTIONS
        from tests.test_visual_host_backend import MODEL, generated_card
        from tests.test_visual_input import completed_wire, read_probe_pixels

        with _open_log(args.log) as log:
            counts = {}

            def record(kind):
                if sum(counts.values()) >= 256:
                    raise ValueError('Synthetic request log budget exceeded.')
                counts[kind] = counts.get(kind, 0) + 1
                log.write(json.dumps({'kind': kind, 'count': counts[kind]}, separators=(',', ':')) + '\n')
                log.flush()

            async def respond(request):
                if request.method == 'GET' and str(request.url) == MODELS:
                    record('catalog')
                    data = {'models': [{'slug': MODEL, 'display_name': 'Synthetic', 'visibility': 'list'}]}
                    return httpx.Response(200, stream=httpx.ByteStream(json.dumps(data).encode()))
                if request.method != 'POST' or str(request.url) != RESPONSES:
                    raise ValueError('Unexpected synthetic route.')
                body = json.loads(request.content)
                if body.get('instructions') == PROBE_INSTRUCTIONS:
                    record('probe')
                    # Decode the actual generated tiny probe, never guess or
                    # return an expected answer copied from its prompt.
                    answer, _ = read_probe_pixels(body)
                else:
                    parts = body['input'][0]['content']
                    has_image = isinstance(parts, list) and any(
                        isinstance(part, dict) and part.get('type') == 'input_image' for part in parts)
                    record('image_question' if has_image else 'text_question')
                    answer = generated_card()
                return httpx.Response(200, stream=httpx.ByteStream(completed_wire(answer)),
                                      headers={'content-type': 'text/event-stream'})

            stream = OAuthAnswerStream(model=MODEL, token_provider=lambda: 'synthetic-native-test-bearer',
                client_factory=lambda **options: httpx.AsyncClient(transport=httpx.MockTransport(respond), **options))
            # The native mode suffix is syntax only here: the explicit test
            # launcher always selects the same injected synthetic OAuth stream.
            options = SimpleNamespace(oauth=True, fixture_model=False, model=MODEL, role=role)
            return asyncio.run(run_stdio(options, oauth_stream=stream))
    except Exception:
        # A harness failure must never print request data or provider exceptions
        # into native test logs. Actual helper framing remains stdout-only.
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
