"""Run with: python3 -m relay_spike [auth|models|infer|disconnect]."""
from __future__ import annotations

import argparse
import json
import sys

from .auth import AuthError, active_access_token, disconnect, request_json, sign_in
from .benchmark import (BenchmarkError, DEFAULT_CASES, DEFAULT_MODELS, evaluate_plan,
                        instructions_for, make_plan, summary)
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
        "--role", choices=["general", "analytics", "epic"], default="general",
        help="Verified context role: general by default, or choose analytics/epic."
    )
    infer.add_argument(
        "--question", default="In SQL, what is the difference between WHERE and HAVING?",
        help="Synthetic question only. No personal or confidential details in Slice 01A.",
    )
    commands.add_parser("disconnect", help="Delete local OAuth credential record.")
    benchmark = commands.add_parser(
        "benchmark", help="Compare synthetic prompts; DRY-RUN unless --execute."
    )
    benchmark.add_argument(
        "--models", default=",".join(DEFAULT_MODELS),
        help="Comma-separated slugs. Default: Luna and GPT-6.1 Sol."
    )
    benchmark.add_argument(
        "--cases", default=",".join(DEFAULT_CASES),
        help="Comma-separated synthetic EVALS case IDs, e.g. D02,D01,E01."
    )
    benchmark.add_argument("--repeats", type=int, default=1)
    benchmark.add_argument(
        "--execute", action="store_true", help="Explicitly authorize LIVE plan inference."
    )
    benchmark.add_argument(
        "--show-answers", action="store_true",
        help="Print synthetic-case model answers locally for manual quality review."
    )
    args = parser.parse_args(argv)

    try:
        if args.command == "auth":
            result = sign_in()
            return 0 if result["plan_usage_authorized"] else 2
        if args.command == "disconnect":
            disconnect()
            return 0
        if args.command == "benchmark":
            models = tuple(x.strip() for x in args.models.split(","))
            case_ids = tuple(x.strip() for x in args.cases.split(","))
            plan = make_plan(models, case_ids, args.repeats)
            if not args.execute:
                print(json.dumps({
                    "dry_run": True, "requests_if_executed": len(plan),
                    "model_slugs": list(models), "synthetic_case_ids": list(case_ids),
                    "note": "No authentication or inference was invoked.",
                }, sort_keys=True))
                return 0
            token = active_access_token()
            listed = visible_models(request_json(MODELS, token=token))
            unknown = sorted(set(models) - {entry["slug"] for entry in listed})
            if unknown:
                raise BenchmarkError("Model not in current OAuth account catalog: " +
                                     ", ".join(unknown))
            shown_answers = []

            def run_one(model, case):
                fragments = []
                result = stream_answer(
                    token, model, case["question"],
                    instructions=instructions_for(case["role"]),
                    on_delta=fragments.append,
                )
                answer = "".join(fragments)
                if args.show_answers:
                    shown_answers.append({
                        "model": model, "case_id": case["id"], "answer": answer
                    })
                return result, answer

            results = evaluate_plan(plan, run_one)
            # Results contain no raw model output, account identity or OAuth tokens.
            print(json.dumps({"dry_run": False, "runs": results,
                              "summary": summary(results)}, sort_keys=True, indent=2))
            if args.show_answers:
                print("SYNTHETIC ANSWERS FOR MANUAL QUALITY REVIEW")
                print(json.dumps(shown_answers, indent=2))
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
        # Direct 'infer' uses general concise instructions unless role is explicit.
        result = stream_answer(token, model, args.question,
                               instructions=instructions_for(args.role),
                               on_delta=lambda s: print(s, end="", flush=True))
        print()
        print("Verified stream completed (timings measured locally).")
        print(json.dumps(result, sort_keys=True))
        return 0
    except (AuthError, StreamError, BenchmarkError) as exc:
        print("Relay spike failed: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
