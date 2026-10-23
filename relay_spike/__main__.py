"""Run with: python3 -m relay_spike [auth|models|infer|disconnect]."""
from __future__ import annotations

import argparse
import json
import sys

from .auth import AuthError, active_access_token, disconnect, request_json, sign_in
from .benchmark import (BenchmarkError, DEFAULT_CASES, DEFAULT_EFFORTS, DEFAULT_MODELS, evaluate_plan,
                        instructions_for, make_plan, summary)
from .stream import (MODELS, StreamError, stream_answer, visible_models,
                     validated_reasoning_effort)
from .live_qa import run_live_synthetic_case, validate_live_case
from .publication_policy import PolicyInput
from .reference_host import ReferencePermission, preview_reference, publish_reference
from .streaming_qa import ActiveTurns


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
        "--effort", choices=["default", "none", "low", "medium", "high", "xhigh", "max"],
        default="default", help="Optional reasoning effort, default means model setting."
    )
    infer.add_argument(
        "--role", choices=["general", "analytics", "epic"], default="general",
        help="Verified context role: general by default, or choose analytics/epic."
    )
    infer.add_argument(
        "--question", default="In SQL, what is the difference between WHERE and HAVING?",
        help="Synthetic question only. No personal or confidential details in Slice 01A.",
    )
    live = commands.add_parser(
        "live-qa", help="One synthetic OAuth inference through QA; dry-run by default."
    )
    live.add_argument("--case", default="D02", help="Reviewed technical EVALS case ID.")
    live.add_argument("--model", default="gpt-6-luna",
                      choices=["gpt-6-luna", "gpt-6.1-sol"])
    live.add_argument("--effort", default="default",
                      choices=["default", "low", "medium"])
    live.add_argument("--execute", action="store_true",
                      help="Explicitly authorize ONE real ChatGPT-plan inference.")
    live.add_argument("--technical-card", action="store_true",
                      help="Opt in to reviewed canonical D02/E09 technical-card QA after completion.")
    # A separate fully offline host reference route. No authentication,
    # inference, or model catalog lookup may be reached by this command.
    reference = commands.add_parser(
        "reference-qa",
        help="Review a known synthetic technical question without any model request."
    )
    reference.add_argument("--question", required=True,
                           help="Synthetic technical question, never private interview text.")
    reference.add_argument("--role", required=True,
                           choices=["analytics", "epic"])
    reference.add_argument("--category", required=True,
                           help="Trusted host category (e.g. sql); unsupported categories withhold.")
    reference.add_argument("--synthetic-source", action="store_true",
                           help="Attest that this is an authorized synthetic input, not real ASR.")
    reference.add_argument("--final", action="store_true",
                           help="Attest that this is the final complete question.")
    reference.add_argument("--authorized", action="store_true",
                           help="Attest explicit host authorization for this synthetic demo.")
    reference.add_argument("--constraint", action="append", default=[],
                           help="Additional question requirement (withholds unmatched cards).")
    reference.add_argument("--publish", action="store_true",
                           help="Synchronously show a reviewed local card, no OAuth or model call.")
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
        "--efforts", default=",".join(DEFAULT_EFFORTS),
        help="Comma-separated effort levels: default,none,low,medium,high,xhigh,max."
    )
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
        if args.command == "reference-qa":
            # CLI permits synthetic input only. No contact with ASR, mic or
            # ChatGPT happens on this path. Real native host integration is
            # a separate permission and transport boundary.
            turns = ActiveTurns()
            token = turns.activate("synthetic:reference-qa", 1)
            consent = ReferencePermission(turns)
            if args.authorized:
                consent.grant()
            request = PolicyInput(
                question=args.question, role=args.role, category=args.category,
                source_channel="user_synthetic" if args.synthetic_source else "unknown",
                question_status="final" if args.final else "partial",
                host_authorized=args.authorized,
                constraints=tuple(args.constraint),
            )
            if not args.publish:
                result = preview_reference(
                    request, turns=turns, token=token, consent=consent,
                )
                print(json.dumps({
                    "dry_run": True,
                    "state": result.state,
                    "reason_code": result.reason_code,
                    "would_publish_reviewed_reference": result.would_publish,
                    "answer": None,
                    "model_requests": 0,
                    "oauth_requests": 0,
                    "first_useful_verified_ms": None,
                    "note": "Synthetic offline preview, no UI paint or model inference.",
                }, sort_keys=True, indent=2))
                return 0
            shown = []
            result = publish_reference(
                request, turns=turns, token=token, consent=consent,
                on_present=shown.append,
            )
            card = shown[0] if result.state == "reviewed_reference" else None
            print(json.dumps({
                "dry_run": False,
                "state": result.state,
                "reason_code": result.reason_code,
                "answer": card.text if card is not None else None,
                "reference_id": card.reference_id if card is not None else None,
                "source_ref": card.source_ref if card is not None else None,
                "model_requests": 0,
                "oauth_requests": 0,
                "first_useful_verified_ms": None,
                "note": "Local reviewed technical explanation only; "
                        "not verified user expertise or native Mac UI proof.",
            }, sort_keys=True, indent=2))
            return 0 if card is not None else 2
        if args.command == "live-qa":
            case = validate_live_case(args.case, args.model, args.effort)
            if not args.execute:
                print(json.dumps({
                    "dry_run": True, "requests_if_executed": 1,
                    "case_id": case["id"], "model": args.model,
                    "requested_reasoning_effort": args.effort,
                    "technical_card": args.technical_card,
                    "note": "No authentication, network or model inference was invoked.",
                }, sort_keys=True))
                return 0
            access_token = active_access_token()  # Requires validated plan scope.
            visible = visible_models(request_json(MODELS, token=access_token))
            if args.model not in {item["slug"] for item in visible}:
                raise StreamError("Selected model is not in the OAuth account catalog.")
            outcome = run_live_synthetic_case(
                access_token, case_id=case["id"], model=args.model,
                effort=args.effort, on_present=lambda _event: None,
                technical_card=args.technical_card,
            )
            assessed, presented = outcome.assessment, outcome.presentation
            print(json.dumps({
                "dry_run": False, "requests_executed": 1,
                "case_id": case["id"], "model": args.model,
                "requested_reasoning_effort": args.effort,
                "technical_card": args.technical_card,
                "technical_gate_reason": outcome.technical_gate_reason,
                "state": presented.state,
                "qa_status": assessed.qa.status if assessed.qa else None,
                "qa_reasons": list(assessed.qa.reasons) if assessed.qa else [],
                "stream_completed": assessed.completed,
                "first_text_ms": assessed.first_text_ms,
                "first_scannable_candidate_ms": assessed.first_scannable_candidate_ms,
                "completed_ms": assessed.completed_ms,
                "qa_decided_ms": assessed.qa_decided_ms,
                "presented_ms": presented.presented_ms,
                "first_useful_verified_ms": None,
                "second_review_recommended": bool(
                    assessed.qa and assessed.qa.second_review_recommended
                ),
                "second_review_executed": False,
                "answer": presented.text if presented.state == "final_unverified" else None,
                "note": "QA PASS only clears deterministic guards; technical "
                        "correctness and interview usefulness remain unverified.",
            }, sort_keys=True, indent=2))
            return 0 if presented.state == "final_unverified" else 2
        if args.command == "benchmark":
            models = tuple(x.strip() for x in args.models.split(","))
            case_ids = tuple(x.strip() for x in args.cases.split(","))
            effort_levels = tuple(x.strip() for x in args.efforts.split(","))
            plan = make_plan(models, case_ids, args.repeats, effort_levels)
            if not args.execute:
                print(json.dumps({
                    "dry_run": True, "requests_if_executed": len(plan),
                    "model_slugs": list(models), "synthetic_case_ids": list(case_ids),
                    "requested_efforts": list(effort_levels),
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

            def run_one(model, case, effort):
                fragments = []
                result = stream_answer(
                    token, model, case["question"],
                    instructions=instructions_for(case["role"]),
                    effort=effort, on_delta=fragments.append,
                )
                answer = "".join(fragments)
                if args.show_answers:
                    shown_answers.append({
                        "model": model, "case_id": case["id"],
                        "requested_reasoning_effort": effort or "default", "answer": answer
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
        # Reject unsupported explicit combinations before requesting model inference.
        if args.command == "infer" and args.model:
            validated_reasoning_effort(args.model, args.effort)
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
        effort = validated_reasoning_effort(model, args.effort)
        if len(args.question) > 1000:
            raise StreamError("This feasibility test limits questions to 1000 characters.")
        print(f"Model: {model} (requested reasoning effort: {args.effort})")
        print("Streaming answer: ", end="", flush=True)
        # Direct 'infer' uses general concise instructions unless role is explicit.
        result = stream_answer(token, model, args.question,
                               instructions=instructions_for(args.role),
                               effort=effort,
                               on_delta=lambda s: print(s, end="", flush=True))
        print()
        print("Verified stream completed (timings measured locally).")
        print(json.dumps({**result, "requested_reasoning_effort": args.effort},
                         sort_keys=True))
        return 0
    except (AuthError, StreamError, BenchmarkError) as exc:
        print("Relay spike failed: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
