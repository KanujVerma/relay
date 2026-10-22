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


def response_payload(model: str, question: str, *, instructions: str | None = None) -> dict:
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
                   on_delta=None) -> dict:
    first_output = None
    completed = False
    count = 0
    for event_type, event in sse_events(byte_lines):
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
    }


def stream_answer(access_token: str, model: str, question: str, *, on_delta=None,
                  timeout: float = 75.0, instructions: str | None = None) -> dict:
    # There is deliberately no support for OPENAI_API_KEY or API-key billing.
    body = json.dumps(response_payload(model, question, instructions=instructions)).encode("utf-8")
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
