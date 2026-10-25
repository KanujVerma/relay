"""Bounded product dispatch. OAuth always requires private account bootstrap."""
from __future__ import annotations

import sys
import argparse

class _Parser(argparse.ArgumentParser):
    def error(self,message):raise ValueError('unsupported_invocation')

def _session_arguments(arguments):
    """Exact public product grammar, without argparse aliases or raw errors."""
    parser=_Parser(add_help=False,allow_abbrev=False)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--oauth',action='store_true');mode.add_argument('--fixture-model',action='store_true')
    parser.add_argument('--protected-account',action='store_true');parser.add_argument('--role');parser.add_argument('--model')
    flags=('--oauth','--fixture-model','--protected-account','--role','--model')
    try:
        if any(arguments.count(flag)>1 for flag in flags):return False
        value=parser.parse_args(arguments)
        return (not value.oauth and not value.protected_account) or (value.oauth and value.protected_account and value.model is not None)
    except (ValueError,SystemExit):return False


def main(arguments: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if arguments is None else arguments
    if (not 2 <= len(arguments) <= 16 or arguments[0] != "-m"
            or any(not isinstance(value, str) or len(value.encode("utf-8")) > 512 for value in arguments)):
        print("Unsupported Relay helper invocation.", file=sys.stderr)
        return 2
    module, remaining = arguments[1], arguments[2:]
    if module == "relay_spike.session_host" and _session_arguments(remaining):
        from relay_spike.session_host import main as run
    elif module == "relay_spike.account_bridge" and not remaining:
        from relay_spike.account_bridge import main as run
    elif module == "relay_spike.profile_bridge" and not remaining:
        from relay_spike.profile_bridge import main as run
    else:
        print("Unsupported Relay helper invocation.", file=sys.stderr)
        return 2
    original = sys.argv
    try:
        sys.argv = [module, *remaining]
        return run()
    finally:
        sys.argv = original


if __name__ == "__main__":
    raise SystemExit(main())
