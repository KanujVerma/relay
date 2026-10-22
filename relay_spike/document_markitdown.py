"""Explicit MarkItDown built-in comparators without generic format sniffing."""
from __future__ import annotations

from io import BytesIO
import os


def convert(data: bytes, file_type: str) -> str:
    """Return flattened Markdown from the pinned PDF or DOCX converter.

    Do not instantiate ``MarkItDown`` here: its constructor creates Magika,
    which runs a bundled ONNX classifier during stream sniffing. The caller
    already supplied a closed file type, so use only the exported built-in
    converter classes with explicit stream metadata. Set ONNX Runtime's
    documented telemetry opt-out before importing MarkItDown/Magika; if the
    runtime was loaded earlier, disable future telemetry through its API too.
    """
    os.environ["ORT_DISABLE_TELEMETRY"] = "1"
    from markitdown import StreamInfo
    from markitdown.converters import DocxConverter, PdfConverter
    import onnxruntime

    disable_telemetry = getattr(onnxruntime, "disable_telemetry_events", None)
    if callable(disable_telemetry):
        disable_telemetry()

    if file_type == "pdf":
        converter = PdfConverter()
        extension = ".pdf"
        mimetype = "application/pdf"
    elif file_type == "docx":
        converter = DocxConverter()
        extension = ".docx"
        mimetype = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    else:
        raise ValueError("unsupported_file_type")

    result = converter.convert(
        BytesIO(data),
        StreamInfo(extension=extension, mimetype=mimetype),
    )
    return result.markdown
