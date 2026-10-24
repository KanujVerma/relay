"""Opt-in synthetic pipe-order observer; no raw guidance, prompt or pixels logged."""
def main():
    import argparse
    import json
    from pathlib import Path
    import sys
    arguments=sys.argv[1:]
    if '-m' not in arguments:return 2
    boundary=arguments.index('-m')
    parser=argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('--synthetic-preferences-test',action='store_true',required=True)
    parser.add_argument('--trace',required=True);parser.add_argument('--log',required=True)
    options=parser.parse_args(arguments[:boundary])
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
    from tests.support.visual_backend_helper import _open_log,main as visual_main
    from relay_spike.panel_wire import FrameDecoder
    try:
        with _open_log(options.trace) as trace:
            original=FrameDecoder.feed;count=0
            def observe(self,chunk):
                nonlocal count
                values=original(self,chunk)
                for value in values:
                    count+=1
                    if count>512:raise ValueError('synthetic_trace_bound')
                    allowed=('kind','captureSessionID','sessionEpoch','presentationGeneration','requestID','eventSequence','preferencesRevision')
                    row={key:value[key] for key in allowed if key in value}
                    trace.write(json.dumps(row,separators=(',',':'))+'\n');trace.flush()
                return values
            FrameDecoder.feed=observe
            try:return visual_main(['--synthetic-visual-test','--log',options.log]+arguments[boundary:])
            finally:FrameDecoder.feed=original
    except Exception:return 2
if __name__=='__main__':raise SystemExit(main())
