"""Bounded dispatch for the two existing frozen inherited-pipe hosts."""
from __future__ import annotations

import sys


def main(arguments: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if arguments is None else arguments
    if (not 2 <= len(arguments) <= 16 or arguments[0] != "-m"
            or any(not isinstance(value, str) or len(value.encode("utf-8")) > 512 for value in arguments)):
        print("Unsupported Relay helper invocation.", file=sys.stderr)
        return 2
    module, remaining = arguments[1], arguments[2:]
    if module == "relay_spike.session_host":
        from relay_spike.session_host import main as run
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
