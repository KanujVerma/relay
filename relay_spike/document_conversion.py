"""Bytes-only document conversion and provenance-gated Relay staging."""
from __future__ import annotations

from dataclasses import dataclass, field
from hashlib import sha256
import hmac
import json
import re
import secrets
from typing import Iterable

from .personal_brain import BrainError, BrainStore, MissingEvidence, _observed
from .resume_candidates import ReviewCard, ReviewGateway, extract_synthetic_candidates


MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_OUTPUT_CHARS = 30_000
MAX_PDF_PAGES = 10
_SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
_EMPTY_SHA256 = sha256(b"").hexdigest()
_RESULT_KEY = secrets.token_bytes(32)


@dataclass(frozen=True)
class TextSegment:
    """One exact source-located fragment in canonical converted text."""

    text: str
    start: int
    end: int
    page: int | None = None
    paragraph: int | None = None


@dataclass(frozen=True)
class ConversionResult:
    """Immutable converter result; failures never carry source content."""

    status: str
    reason: str | None
    backend: str
    document_sha256: str
    text_sha256: str
    text: str
    segments: tuple[TextSegment, ...]
    _attestation: bytes = field(default=b"", repr=False, compare=False)


def _text_sha256(text: str) -> str:
    return sha256(text.encode("utf-8")).hexdigest()


def _attestation(
    status: str,
    reason: str | None,
    backend: str,
    document_sha256: str,
    text_sha256: str,
    text: str,
    segments: tuple[TextSegment, ...],
) -> bytes:
    payload = json.dumps(
        {
            "status": status,
            "reason": reason,
            "backend": backend,
            "document_sha256": document_sha256,
            "text_sha256": text_sha256,
            "text": text,
            "segments": [
                (item.text, item.start, item.end, item.page, item.paragraph)
                for item in segments
            ],
        },
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hmac.new(_RESULT_KEY, payload, sha256).digest()


def _result(
    status: str,
    reason: str | None,
    backend: str,
    document_sha256: str,
    text: str = "",
    segments: tuple[TextSegment, ...] = (),
) -> ConversionResult:
    text_sha256 = _text_sha256(text)
    attestation = _attestation(
        status,
        reason,
        backend,
        document_sha256,
        text_sha256,
        text,
        segments,
    )
    return ConversionResult(
        status=status,
        reason=reason,
        backend=backend,
        document_sha256=document_sha256,
        text_sha256=text_sha256,
        text=text,
        segments=segments,
        _attestation=attestation,
    )


def _failure(status: str, reason: str, backend: str, document_sha256: str) -> ConversionResult:
    return _result(status, reason, backend, document_sha256)


def _from_records(
    records: Iterable[tuple[str, int | None, int | None]],
    *,
    backend: str,
    document_sha256: str,
) -> ConversionResult:
    chunks: list[str] = []
    segments: list[TextSegment] = []
    offset = 0
    had_record = False
    for item_text, page, paragraph in records:
        if not isinstance(item_text, str):
            return _failure("invalid", "invalid_extracted_text", backend, document_sha256)
        if type(page) is not int and page is not None:
            return _failure("unsupported", "invalid_page_location", backend, document_sha256)
        if type(paragraph) is not int and paragraph is not None:
            return _failure("unsupported", "invalid_paragraph_location", backend, document_sha256)
        if (page is None) == (paragraph is None):
            return _failure("unsupported", "source_location_unavailable", backend, document_sha256)
        if ((page is not None and page < 1) or
                (paragraph is not None and paragraph < 1)):
            return _failure("unsupported", "source_location_unavailable", backend, document_sha256)
        if had_record:
            chunks.append("\n")
            offset += 1
        had_record = True
        if not item_text:
            continue
        start = offset
        end = start + len(item_text)
        chunks.append(item_text)
        segments.append(TextSegment(
            text=item_text,
            start=start,
            end=end,
            page=page,
            paragraph=paragraph,
        ))
        offset = end
        if offset > MAX_OUTPUT_CHARS:
            return _failure("invalid", "output_size_limit", backend, document_sha256)

    text = "".join(chunks)
    if len(text) > MAX_OUTPUT_CHARS:
        return _failure("invalid", "output_size_limit", backend, document_sha256)
    if not text.strip() or not segments:
        return _failure("unsupported", "no_extractable_text", backend, document_sha256)
    return _result("converted", None, backend, document_sha256, text, tuple(segments))


def _flattened_result(text: str, *, backend: str, document_sha256: str) -> ConversionResult:
    if not isinstance(text, str):
        return _failure("invalid", "invalid_extracted_text", backend, document_sha256)
    if len(text) > MAX_OUTPUT_CHARS:
        return _failure("invalid", "output_size_limit", backend, document_sha256)
    if not text.strip():
        return _failure("unsupported", "no_extractable_text", backend, document_sha256)
    # Comparator output is useful for text recovery measurements, but it has
    # no reliable source page/paragraph offsets and therefore cannot be staged.
    return _result("needs_review", "provenance_unavailable", backend, document_sha256, text)


def _missing_dependency(exc: BaseException) -> bool:
    return isinstance(exc, ImportError) or type(exc).__name__ == "MissingDependencyException"


def convert_document(data, *, file_type, backend="native") -> ConversionResult:
    """Convert only caller-supplied bytes through a closed local backend set."""
    valid_backend = backend if isinstance(backend, str) else ""
    if type(data) is not bytes:
        return _failure("invalid", "bytes_required", valid_backend, _EMPTY_SHA256)

    document_sha256 = sha256(data).hexdigest()
    if len(data) > MAX_INPUT_BYTES:
        return _failure("invalid", "input_size_limit", valid_backend, document_sha256)
    if not data:
        return _failure("invalid", "empty_input", valid_backend, document_sha256)
    if not isinstance(file_type, str) or file_type not in {"pdf", "docx"}:
        return _failure("unsupported", "unsupported_file_type", valid_backend, document_sha256)
    if not isinstance(backend, str) or backend not in {"native", "docling", "markitdown"}:
        return _failure("unsupported", "unsupported_backend", valid_backend, document_sha256)

    try:
        if file_type == "pdf":
            if backend == "docling":
                return _failure("unsupported", "docling_pdf_comparator_not_scoped", backend, document_sha256)
            from .document_docling import pdf_page_count

            page_count = pdf_page_count(data)
            if page_count > MAX_PDF_PAGES:
                return _failure("invalid", "pdf_page_limit", backend, document_sha256)
            if backend == "native":
                from .document_docling import native_pdf_records

                if page_count <= 0:
                    return _failure("invalid", "pdf_has_no_pages", backend, document_sha256)
                records = native_pdf_records(data, page_count=page_count)
                return _from_records(records, backend=backend, document_sha256=document_sha256)

            from .document_markitdown import convert as markitdown_convert

            return _flattened_result(
                markitdown_convert(data, file_type),
                backend=backend,
                document_sha256=document_sha256,
            )

        from .document_docx import inspect_docx

        paragraphs = inspect_docx(data)
        if not any(paragraph.text.strip() for paragraph in paragraphs):
            return _failure("unsupported", "no_extractable_text", backend, document_sha256)
        if backend == "native":
            records = [
                (paragraph.text, None, index)
                for index, paragraph in enumerate(paragraphs, start=1)
            ]
            return _from_records(records, backend=backend, document_sha256=document_sha256)
        if backend == "docling":
            from .document_docling import UnsupportedDoclingDocx, docx_text

            try:
                text = docx_text(data)
            except UnsupportedDoclingDocx as exc:
                return _failure("unsupported", exc.reason, backend, document_sha256)
            return _flattened_result(text, backend=backend, document_sha256=document_sha256)

        from .document_markitdown import convert as markitdown_convert

        return _flattened_result(
            markitdown_convert(data, file_type),
            backend=backend,
            document_sha256=document_sha256,
        )
    except Exception as exc:
        reason = getattr(exc, "reason", None)
        if isinstance(reason, str) and re.fullmatch(r"[a-z0-9_]{1,64}", reason):
            status = (
                "unsupported"
                if type(exc).__name__ in {"UnsupportedDocx", "UnsupportedPdf"}
                else "invalid"
            )
            return _failure(status, reason, valid_backend, document_sha256)
        if _missing_dependency(exc):
            return _failure("unavailable", "dependency_unavailable", valid_backend, document_sha256)
        return _failure("invalid", "conversion_failed", valid_backend, document_sha256)


def _validate_for_staging(result: ConversionResult) -> None:
    if not isinstance(result, ConversionResult):
        raise MissingEvidence("Conversion result is unavailable.")
    if (not isinstance(result.status, str) or
            not isinstance(result.backend, str) or
            (result.reason is not None and not isinstance(result.reason, str))):
        raise MissingEvidence("Conversion result metadata is invalid.")
    if result.status != "converted" or result.backend != "native":
        raise MissingEvidence("Only provenance-backed native conversions can be staged.")
    if (not isinstance(result.document_sha256, str) or
            _SHA256_RE.fullmatch(result.document_sha256) is None):
        raise BrainError("Invalid original document digest.")
    if (not isinstance(result.text_sha256, str) or
            _SHA256_RE.fullmatch(result.text_sha256) is None or
            not isinstance(result.text, str) or not result.text or
            len(result.text) > MAX_OUTPUT_CHARS or
            _text_sha256(result.text) != result.text_sha256):
        raise MissingEvidence("Converted text revision is invalid.")
    if not isinstance(result.segments, tuple) or not result.segments:
        raise MissingEvidence("Converted source locations are incomplete.")

    prior_end = -1
    for segment in result.segments:
        if not isinstance(segment, TextSegment):
            raise MissingEvidence("Converted source locations are invalid.")
        if (not isinstance(segment.text, str) or
                type(segment.start) is not int or type(segment.end) is not int or
                segment.start < 0 or segment.end <= segment.start or
                segment.end > len(result.text) or
                result.text[segment.start:segment.end] != segment.text):
            raise MissingEvidence("Converted source spans are invalid.")
        if (segment.start < prior_end or
                (segment.page is None) == (segment.paragraph is None) or
                (segment.page is not None and
                 (type(segment.page) is not int or segment.page < 1 or segment.page > MAX_PDF_PAGES)) or
                (segment.paragraph is not None and
                 (type(segment.paragraph) is not int or segment.paragraph < 1))):
            raise MissingEvidence("Converted source locations are ambiguous.")
        prior_end = segment.end

    candidates = extract_synthetic_candidates(result.text)
    if not candidates:
        raise MissingEvidence("Converted document has no reviewable evidence.")
    for candidate in candidates:
        if result.text[candidate.span_start:candidate.span_end] != candidate.snippet:
            raise MissingEvidence("Converted candidate source span is invalid.")
        matches = [
            segment for segment in result.segments
            if segment.start <= candidate.span_start and candidate.span_end <= segment.end
        ]
        if len(matches) != 1:
            raise MissingEvidence("Candidate source location is missing or ambiguous.")

    expected_attestation = _attestation(
        result.status,
        result.reason,
        result.backend,
        result.document_sha256,
        result.text_sha256,
        result.text,
        result.segments,
    )
    if (not isinstance(result._attestation, bytes) or
            not hmac.compare_digest(result._attestation, expected_attestation)):
        raise MissingEvidence("Conversion result was modified or was not produced here.")


def stage_converted(
    result: ConversionResult,
    gateway: ReviewGateway,
    *,
    observed_at: str,
    capability: object,
) -> tuple[str, tuple[ReviewCard, ...]]:
    """Atomically bind original bytes and stage only validated located text."""
    if not isinstance(gateway, ReviewGateway):
        raise TypeError("ReviewGateway is required.")
    gateway._require_host(capability)
    _observed(observed_at)
    _validate_for_staging(result)

    store: BrainStore = gateway._store
    with store._transaction():
        source_id = gateway.select_source(
            result.text,
            observed_at=observed_at,
            capability=capability,
            raw_document_sha256=result.document_sha256,
        )
        cards = gateway.stage(source_id, result.text, observed_at=observed_at)
    return source_id, cards
