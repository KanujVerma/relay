#!/usr/bin/env python3
"""Offline benchmark of the frozen synthetic PDF/DOCX fixtures.

The JSON report contains counts, statuses, timings and resource metadata only;
it never prints converted document text or parser exception bodies.
"""
from __future__ import annotations

from collections import Counter
from contextlib import ExitStack
from datetime import datetime, timezone
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import socket
import subprocess
import sys
import tempfile
from time import perf_counter
from unittest.mock import patch

try:
    import resource
except ImportError:  # pragma: no cover - Windows reports RSS as unavailable.
    resource = None


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
FIXTURES = ROOT / "tests" / "fixtures" / "documents"
MANIFEST = json.loads((FIXTURES / "manifest.json").read_text(encoding="utf-8"))
CASES = {
    "native_pdf": ("synthetic-two-page.pdf", "pdf", "native", "pdf_claims", "page"),
    "native_docx": ("synthetic-unicode.docx", "docx", "native", "docx_claims", "paragraph"),
    "native_duplicate_docx": ("synthetic-duplicate.docx", "docx", "native", "duplicate_claims", "paragraph"),
    "markitdown_pdf": ("synthetic-two-page.pdf", "pdf", "markitdown", "pdf_claims", None),
    "markitdown_docx": ("synthetic-unicode.docx", "docx", "markitdown", "docx_claims", None),
    "docling_docx": ("synthetic-unicode.docx", "docx", "docling", "docx_claims", None),
}


def _no_network(*args, **kwargs):
    raise AssertionError("network access is forbidden during conversion")


def _install_socket_guard(stack: ExitStack) -> None:
    for name in ("connect", "connect_ex"):
        stack.enter_context(patch.object(socket.socket, name, side_effect=_no_network))
    for name in ("create_connection", "getaddrinfo", "gethostbyname"):
        stack.enter_context(patch.object(socket, name, side_effect=_no_network))


def _peak_rss_bytes() -> int | None:
    if resource is None:
        return None
    try:
        value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    except (AttributeError, OSError):
        return None
    # Darwin reports bytes; Linux and other common Unix systems report KiB.
    return int(value if sys.platform == "darwin" else value * 1024)


def _run_case(case_id: str) -> tuple[dict, int]:
    filename, file_type, backend, claim_key, locator = CASES[case_id]
    raw = (FIXTURES / filename).read_bytes()
    expected = MANIFEST[claim_key]
    durations: list[float] = []
    last_result = None

    with tempfile.TemporaryDirectory() as cache, ExitStack() as stack:
        stack.enter_context(patch.dict(os.environ, {
            "HF_HOME": cache + "/hf",
            "HUGGINGFACE_HUB_CACHE": cache + "/hf/hub",
            "TORCH_HOME": cache + "/torch",
            "XDG_CACHE_HOME": cache + "/cache",
            "ORT_DISABLE_TELEMETRY": "1",
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
        }))
        _install_socket_guard(stack)
        if backend == "markitdown":
            # This adapter calls MarkItDown's explicit PDF/DOCX converters and
            # must not instantiate the generic Magika classifier.
            stack.enter_context(patch("magika.Magika", side_effect=AssertionError("Magika inference used")))
        from relay_spike.document_conversion import convert_document

        for _ in range(2):
            started = perf_counter()
            last_result = convert_document(raw, file_type=file_type, backend=backend)
            durations.append(perf_counter() - started)

    assert last_result is not None
    normalized = " ".join(last_result.text.split())
    text_occurrences = Counter(item["text"] for item in expected)
    recovered = sum(
        min(count, normalized.count(text))
        for text, count in text_occurrences.items()
    )

    no_source_locators = not any(
        segment.page is not None or segment.paragraph is not None
        for segment in last_result.segments
    )
    if locator is None:
        location_support = False
    else:
        expected_locations = Counter((item["text"], item[locator]) for item in expected)
        observed_locations = Counter(
            (item["text"], getattr(segment, locator))
            for item in expected
            for segment in last_result.segments
            if item["text"] in segment.text and getattr(segment, locator) is not None
        )
        location_support = all(
            observed_locations[key] >= count
            for key, count in expected_locations.items()
        )

    case_data = {
        "id": case_id,
        "file_type": file_type,
        "backend": backend,
        "status": last_result.status,
        "reason": last_result.reason,
        "recovered_claims": recovered,
        "expected_claims": len(expected),
        "source_location_support": location_support,
        "no_source_locators": no_source_locators,
        "cold_first_run_seconds": round(durations[0], 6),
        "warm_second_run_seconds": round(durations[1], 6),
        "process_peak_rss_bytes": _peak_rss_bytes(),
    }
    success = (
        (last_result.status == "converted" if locator is not None else last_result.status == "needs_review")
        and recovered == len(expected)
        and (location_support if locator is not None else no_source_locators)
    )
    return case_data, 0 if success else 1


def _host_info() -> dict:
    model = os.environ.get("RELAY_BENCHMARK_HOST_MODEL") or None
    memory_bytes = None
    raw_memory = os.environ.get("RELAY_BENCHMARK_MEMORY_BYTES")
    if raw_memory and raw_memory.isdecimal():
        memory_bytes = int(raw_memory)
    metadata_source = "controller_environment" if model or memory_bytes is not None else "platform_only"
    if sys.platform == "darwin":
        for key, command in (
            ("model", ["sysctl", "-n", "machdep.cpu.brand_string"]),
            ("memory_bytes", ["sysctl", "-n", "hw.memsize"]),
        ):
            if (key == "model" and model is not None) or (key == "memory_bytes" and memory_bytes is not None):
                continue
            try:
                value = subprocess.run(command, capture_output=True, text=True, check=True).stdout.strip()
                if key == "model":
                    model = value
                else:
                    memory_bytes = int(value)
                metadata_source = "read_only_sysctl"
            except (OSError, ValueError, subprocess.CalledProcessError):
                continue
    return {
        "platform": platform.platform(),
        "system": platform.system(),
        "machine": platform.machine(),
        "processor": platform.processor() or None,
        "model": model,
        "memory_bytes": memory_bytes,
        "hardware_metadata_source": metadata_source,
        "python": platform.python_version(),
    }


def _versions() -> dict[str, str | None]:
    packages = (
        "markitdown", "docling-slim", "docling-core", "docling-parse",
        "python-docx", "pypdfium2", "pdfminer.six", "pdfplumber",
        "magika", "onnxruntime",
    )
    result: dict[str, str | None] = {}
    for name in packages:
        try:
            result[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            result[name] = None
    return result


def _verify_manifest() -> None:
    from hashlib import sha256

    for filename, expected in MANIFEST["files"].items():
        if sha256((FIXTURES / filename).read_bytes()).hexdigest() != expected:
            raise RuntimeError("fixture_manifest_mismatch")


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) == 2 and argv[0] == "--worker":
        if argv[1] not in CASES:
            return 2
        row, status = _run_case(argv[1])
        print(json.dumps(row, sort_keys=True, separators=(",", ":")))
        return status
    if argv:
        print("Usage: python EVALS/benchmark_documents.py", file=sys.stderr)
        return 2

    try:
        _verify_manifest()
    except Exception:
        print("Synthetic fixture manifest validation failed.", file=sys.stderr)
        return 2

    rows: list[dict] = []
    failures = 0
    for case_id in CASES:
        completed = subprocess.run(
            [sys.executable, str(Path(__file__).resolve()), "--worker", case_id],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        try:
            row = json.loads(completed.stdout.strip().splitlines()[-1])
        except (IndexError, json.JSONDecodeError):
            row = {
                "id": case_id,
                "status": "unavailable",
                "reason": "benchmark_worker_failed",
                "stderr_line_count": len(completed.stderr.splitlines()),
            }
            failures += 1
        if completed.returncode != 0:
            failures += 1
        row["stderr_line_count"] = len(completed.stderr.splitlines())
        rows.append(row)

    report = {
        "benchmark": "synthetic document conversion",
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "host": _host_info(),
        "versions": _versions(),
        "cold_warm_scope": (
            "First conversion includes lazy converter imports; second reuses Python module caches "
            "but creates a new converter. RSS is per isolated case process and covers both runs."
        ),
        "rss_unit": "bytes",
        "source_text_emitted": False,
        "cases": rows,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
