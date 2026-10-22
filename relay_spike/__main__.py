"""Run with: python3 -m relay_spike [auth|models|infer|disconnect]."""
from __future__ import annotations

import argparse
import json
import sys

from .auth import AuthError, active_access_token, disconnect, request_json, sign_in
from .stream import MODELS, StreamError, stream_answer, visible_models


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Relay Slice 01A: experimental OAuth-backed inference (no paid API key)."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("auth", help="Open browser and authorize Relay using ChatGPT.")
    commands.add_parser("models", help="List currently displayed models for this OAuth account.")
    infer = commands.add_parser("infer", help="Stream exactly one synthetic question.")
    infer.add_argument("--model", help="Model slug from models command; default first visible.")
    infer.add_argument(
        "--question", default="In SQL, what is the difference between WHERE and HAVING?",
        help="Synthetic question only. No personal or confidential details in Slice 01A.",
    )
    commands.add_parser("disconnect", help="Delete local OAuth credential record.")
    args = parser.parse_args(argv)

    try:
        if args.command == "auth":
            result = sign_in()
            return 0 if result["plan_usage_authorized"] else 2
        if args.command == "disconnect":
            disconnect()
            return 0
        token = active_access_token()
        listed = visible_models(request_json(MODELS, token=token))
        if args.command == "models":
            if not listed:
                raise StreamError("No visible model slugs returned for this account.")
            for entry in listed:
                print(entry["slug"] + "  " + str(entry["display_name"]))
            return 0
        model = args.model or (listed[0]["slug"] if listed else None)
        if model is None or model not in {x["slug"] for x in listed}:
            raise StreamError("Model not in current account catalog. Run models command.")
        if len(args.question) > 1000:
            raise StreamError("This feasibility test limits questions to 1000 characters.")
        print(f"Model: {model}")
        print("Streaming answer: ", end="", flush=True)
        result = stream_answer(token, model, args.question,
                               on_delta=lambda s: print(s, end="", flush=True))
        print()
        print("Verified stream completed (timings measured locally).")
        print(json.dumps(result, sort_keys=True))
        return 0
    except (AuthError, StreamError) as exc:
        print("Relay spike failed: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
