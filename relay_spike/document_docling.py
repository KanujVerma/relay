"""Explicit model-free Docling PDF and flattened DOCX paths."""
from __future__ import annotations

from io import BytesIO


class InvalidPdf(ValueError):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class UnsupportedPdf(ValueError):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class UnsupportedDoclingDocx(ValueError):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def pdf_page_count(data: bytes) -> int:
    """Count pages and reject every PDF security handler before conversion."""
    try:
        import pypdfium2
        from pypdfium2 import raw
    except ImportError:
        raise
    document = None
    try:
        document = pypdfium2.PdfDocument(data)
        # PDFium opens an empty-user-password encrypted document without a
        # prompt, so successful opening alone does not prove it is unencrypted.
        # -1 means no security handler; every other value fails closed.
        if raw.FPDF_GetSecurityHandlerRevision(document.raw) != -1:
            raise UnsupportedPdf("pdf_encrypted")
        return len(document)
    except (InvalidPdf, UnsupportedPdf):
        raise
    except Exception:
        raise InvalidPdf("pdf_invalid_or_encrypted") from None
    finally:
        if document is not None:
            document.close()


def native_pdf_records(
    data: bytes,
    *,
    page_count: int,
) -> list[tuple[str, int | None, int | None]]:
    """Return Docling native text cells with their one-based PDF page."""
    from docling.datamodel.base_models import DocumentStream, InputFormat
    from docling.datamodel.pipeline_options import NativePdfPipelineOptions
    from docling.document_converter import DocumentConverter, NativePdfFormatOption
    from docling_core.types.doc.page import TextCellUnit

    from .document_conversion import MAX_INPUT_BYTES, MAX_PDF_PAGES

    if page_count <= 0:
        raise InvalidPdf("pdf_has_no_pages")

    options = NativePdfPipelineOptions(
        enable_remote_services=False,
        allow_external_plugins=False,
        do_picture_classification=False,
        do_picture_description=False,
        do_chart_extraction=False,
        generate_page_images=False,
        generate_picture_images=False,
        text_cell_unit=TextCellUnit.LINE,
    )
    converter = DocumentConverter(
        allowed_formats=[InputFormat.PDF],
        format_options={
            InputFormat.PDF: NativePdfFormatOption(pipeline_options=options),
        },
    )
    source = DocumentStream(name="selected.pdf", stream=BytesIO(data))
    result = converter.convert(
        source,
        raises_on_error=False,
        max_num_pages=MAX_PDF_PAGES,
        max_file_size=MAX_INPUT_BYTES,
    )
    status = getattr(result.status, "value", result.status)
    if status != "success":
        raise InvalidPdf("pdf_conversion_failed")

    records: list[tuple[str, int | None, int | None]] = []
    for item in result.document.texts:
        if not item.text:
            continue
        if len(item.prov) != 1:
            raise UnsupportedPdf("pdf_cell_location_unavailable")
        page_no = item.prov[0].page_no
        if type(page_no) is not int or page_no < 1 or page_no > page_count:
            raise UnsupportedPdf("pdf_page_location_unavailable")
        records.append((item.text, page_no, None))
    if not records:
        raise UnsupportedPdf("pdf_no_selectable_text")
    return records


def docx_text(data: bytes) -> str:
    """Convert DOCX through Docling SimplePipeline for comparison only."""
    from docling.datamodel.base_models import DocumentStream, InputFormat
    from docling.document_converter import DocumentConverter, WordFormatOption
    from docling.pipeline.simple_pipeline import SimplePipeline

    source = DocumentStream(name="selected.docx", stream=BytesIO(data))
    converter = DocumentConverter(
        allowed_formats=[InputFormat.DOCX],
        format_options={
            InputFormat.DOCX: WordFormatOption(pipeline_cls=SimplePipeline),
        },
    )
    result = converter.convert(source, raises_on_error=False)
    status = getattr(result.status, "value", result.status)
    if status != "success":
        raise UnsupportedDoclingDocx("docling_docx_conversion_failed")
    return result.document.export_to_text()
