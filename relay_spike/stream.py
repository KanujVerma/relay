"""Bounded, non-billable-by-key Responses streaming proof, using OAuth bearer only.

The stream completion event, not an output token or [DONE], proves success.
"""
from __future__ import annotations

import json
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .auth import AuthError, RESOURCE

RESPONSES = RESOURCE + "/responses"
MODELS = RESOURCE + "/models"


class StreamError(RuntimeError):
    """Sanitized response or transport error."""


# Only explicitly documented combinations may use a reasoning override.
# Unknown model slugs may still run using their default effort.
SUPPORTED_EFFORTS = {
    "gpt-6-luna": frozenset(("none", "low", "medium", "high", "xhigh", "max")),
    "gpt-6-sol": frozenset(("none", "low", "medium", "high", "xhigh", "max")),
    "gpt-6.1-sol": frozenset(("low", "medium", "high", "xhigh", "max")),
    "gpt-6-astra": frozenset(("low", "medium", "high", "xhigh", "max")),
}


def validated_reasoning_effort(model: str, effort: str | None) -> str | None:
    """Return an explicit valid effort, or None to omit and use model default."""
    if effort is None or effort == "default":
        return None
    if not isinstance(effort, str):
        raise StreamError("Reasoning effort must be a string or omitted.")
    allowed = SUPPORTED_EFFORTS.get(model)
    if allowed is None:
        raise StreamError("Explicit effort has not been verified for this model.")
    if effort not in allowed:
        raise StreamError("Unsupported reasoning effort for selected model.")
    return effort


def visible_models(catalog: dict) -> list[dict]:
    result = []
    rows = catalog.get("models", [])
    if not isinstance(rows, list):
        raise StreamError("Unexpected model catalog format.")
    for row in rows:
        if not isinstance(row, dict) or row.get("visibility") != "list":
            continue
        slug = row.get("slug")
        if isinstance(slug, str) and slug:
            result.append({
                "slug": slug,
                "display_name": row.get("display_name") or slug,
            })
    return result


def response_payload(model: str, question: str, *, instructions: str | None = None,
                     effort: str | None = None) -> dict:
    if not model.strip() or not question.strip():
        raise StreamError("Model and question must not be empty.")
    payload = {
        "model": model,
        "input": [{"role": "user", "content": question}],
        "store": False,
        "stream": True,
    }
    # The ChatGPT-plan preview supports top-level instructions; do not send a
    # system input item, max_output_tokens, temperature, or service_tier.
    if instructions is not None:
        if not isinstance(instructions, str) or not instructions.strip():
            raise StreamError("Instructions must be a nonempty string when provided.")
        payload["instructions"] = instructions
    selected_effort = validated_reasoning_effort(model, effort)
    if selected_effort is not None:
        payload["reasoning"] = {"effort": selected_effort}
    return payload


def sse_events(byte_lines):
    """Decode SSE frames. The caller is responsible for terminal semantics."""
    data_lines: list[str] = []
    event_type = None
    for raw in byte_lines:
        line = raw.decode("utf-8") if isinstance(raw, bytes) else raw
        line = line.rstrip("\r\n")
        if line == "":
            if data_lines:
                data = "\n".join(data_lines)
                if data != "[DONE]":
                    try:
                        parsed = json.loads(data)
                    except json.JSONDecodeError:
                        raise StreamError("Malformed JSON in response stream.") from None
                    if not isinstance(parsed, dict):
                        raise StreamError("Expected an object in response stream.")
                    yield event_type or parsed.get("type"), parsed
            data_lines = []
            event_type = None
            continue
        if line.startswith(":"):
            continue
        if line.startswith("event:"):
            event_type = line[6:].strip()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip(" "))
    if data_lines:
        # A truncated event is a protocol error, not successful output.
        raise StreamError("Response stream ended with an incomplete SSE frame.")


def consume_stream(byte_lines, *, started: float, clock=time.monotonic,
                   on_delta=None, should_continue=None) -> dict:
    first_output = None
    completed = False
    count = 0
    server_reported_effort = None
    seen_sequence: dict[int, dict] = {}
    for event_type, event in sse_events(byte_lines):
        # Optional caller-owned turn guard. Pure CLI behavior is unchanged.
        if should_continue is not None and not should_continue():
            raise StreamError("Stream was superseded.")
        sequence = event.get("sequence_number")
        if sequence is not None:
            if type(sequence) is not int or sequence < 0:
                raise StreamError("Invalid SSE sequence number.")
            previous = seen_sequence.get(sequence)
            if previous is not None:
                if previous != event:
                    raise StreamError("Conflicting duplicate SSE event.")
                continue  # Replay, not a second text fragment.
            seen_sequence[sequence] = event
        typ = event.get("type") or event_type
        if typ == "response.output_text.delta":
            text = event.get("delta")
            if isinstance(text, str) and text:
                if first_output is None:
                    first_output = clock() - started
                count += len(text)
                if on_delta is not None:
                    on_delta(text)
        elif typ in ("response.failed", "response.incomplete", "error"):
            response = event.get("response", {})
            error = response.get("error", {}) if isinstance(response, dict) else {}
            code = error.get("code") if isinstance(error, dict) else None
            known = {
                "subscription_sharing_usage_limit_exceeded",
                "subscription_sharing_usage_unavailable",
            }
            if code in known:
                raise StreamError(f"ChatGPT plan use is unavailable: {code}")
            raise StreamError("Response failed or was incomplete.")
        elif typ == "response.completed":
            response = event.get("response", {})
            if isinstance(response, dict):
                status = response.get("status", "completed")
                if status != "completed":
                    raise StreamError("Response completion did not report completed status.")
                reasoning = response.get("reasoning")
                if isinstance(reasoning, dict):
                    reported = reasoning.get("effort")
                    if isinstance(reported, str):
                        server_reported_effort = reported
            completed = True
            break
    if not completed:
        raise StreamError("Stream ended without response.completed.")
    if count == 0:
        raise StreamError("Stream completed but had no output text.")
    return {
        "first_text_ms": round(1000 * first_output) if first_output is not None else None,
        "total_ms": round(1000 * (clock() - started)),
        "output_chars": count,
        "completed": True,
        "server_reported_reasoning_effort": server_reported_effort,
    }


def stream_answer(access_token: str, model: str, question: str, *, on_delta=None,
                  timeout: float = 75.0, instructions: str | None = None,
                  effort: str | None = None) -> dict:
    # There is deliberately no support for OPENAI_API_KEY or API-key billing.
    body = json.dumps(response_payload(
        model, question, instructions=instructions, effort=effort
    )).encode("utf-8")
    req = Request(RESPONSES, data=body, headers={
        "Authorization": "Bearer " + access_token,
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }, method="POST")
    started = time.monotonic()
    try:
        with urlopen(req, timeout=timeout) as response:
            return consume_stream(
                iter(response.readline, b""), started=started, on_delta=on_delta
            )
    except HTTPError as exc:
        raise StreamError(f"Responses request rejected (HTTP {exc.code}).") from None
    except (URLError, TimeoutError):
        raise StreamError("Network or timeout failure while streaming response.") from None
