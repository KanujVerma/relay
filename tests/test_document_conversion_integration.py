"""Opt-in regressions for the pinned real document libraries."""
from __future__ import annotations

from dataclasses import replace
from io import BytesIO
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile

from relay_spike.document_conversion import convert_document, stage_converted
from relay_spike.personal_brain import BrainError, BrainStore
from relay_spike.resume_candidates import ReviewGateway


INTEGRATION = os.environ.get("RELAY_DOCUMENT_INTEGRATION") == "1"
ROOT = Path(__file__).parent
FIXTURES = ROOT / "fixtures" / "documents"
WORKER_FIXTURES = ROOT / "fixtures" / "document-worker"
WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
OFFICE_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
CONTENT_TYPES_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
MARKUP_COMPAT_NS = "http://schemas.openxmlformats.org/markup-compatibility/2006"
XML_NS = "http://www.w3.org/XML/1998/namespace"
MAIN_REL_TYPE = OFFICE_REL_NS + "/officeDocument"
MAIN_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
TARGET_PARAGRAPH = "I implemented a synthetic SQL reporting service."
WHEN = "2026-10-22T12:00:00-05:00"

for prefix, namespace in (
    ("w", WORD_NS),
    ("r", OFFICE_REL_NS),
    ("mc", MARKUP_COMPAT_NS),
):
    ET.register_namespace(prefix, namespace)


def _serialize(root: ET.Element) -> bytes:
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def _rewrite_docx(
    data: bytes,
    *,
    replacements: dict[str, bytes] | None = None,
    additions: dict[str, bytes] | None = None,
) -> bytes:
    replacements = replacements or {}
    additions = additions or {}
    output = BytesIO()
    with ZipFile(BytesIO(data)) as source, ZipFile(output, "w", ZIP_DEFLATED) as target:
        for info in source.infolist():
            content = replacements.get(info.filename, source.read(info.filename))
            target.writestr(info, content)
        for name, content in additions.items():
            target.writestr(name, content)
    return output.getvalue()


def _read_part(data: bytes, part_name: str) -> bytes:
    with ZipFile(BytesIO(data)) as archive:
        return archive.read(part_name)


def _find_target_paragraph(root: ET.Element) -> tuple[ET.Element, int, ET.Element]:
    body = root.find(f".//{{{WORD_NS}}}body")
    if body is None:
        raise AssertionError("fixture has no Word body")
    for index, child in enumerate(body):
        if child.tag != f"{{{WORD_NS}}}p":
            continue
        text = "".join(node.text or "" for node in child.iter(f"{{{WORD_NS}}}t"))
        if text == TARGET_PARAGRAPH:
            return body, index, child
    raise AssertionError("target paragraph not found in fabricated fixture")


def _with_malformed_word_text(data: bytes, content_kind: str) -> bytes:
    root = ET.fromstring(_read_part(data, "word/document.xml"))
    body, _, paragraph = _find_target_paragraph(root)

    def new_run() -> ET.Element:
        return ET.Element(f"{{{WORD_NS}}}r")

    def replace_runs(run: ET.Element) -> None:
        for item in list(paragraph):
            if item.tag == f"{{{WORD_NS}}}r":
                paragraph.remove(item)
        paragraph.append(run)

    if content_kind == "text_under_break":
        run = new_run()
        ET.SubElement(run, f"{{{WORD_NS}}}t").text = "I built visible evidence."
        hidden = ET.SubElement(run, f"{{{WORD_NS}}}br")
        ET.SubElement(hidden, f"{{{WORD_NS}}}t").text = "I built dropped evidence."
        replace_runs(run)
    elif content_kind == "text_under_text":
        run = new_run()
        outer = ET.SubElement(run, f"{{{WORD_NS}}}t")
        outer.text = "I built visible evidence."
        ET.SubElement(outer, f"{{{WORD_NS}}}t").text = "I built dropped evidence."
        replace_runs(run)
    elif content_kind == "direct_break_text":
        run = new_run()
        ET.SubElement(run, f"{{{WORD_NS}}}t").text = "I built visible evidence."
        ET.SubElement(run, f"{{{WORD_NS}}}br").text = "I built dropped evidence."
        replace_runs(run)
    elif content_kind == "direct_paragraph_text":
        paragraph.text = "I built dropped evidence."
    elif content_kind == "direct_run_text":
        run = next(item for item in paragraph if item.tag == f"{{{WORD_NS}}}r")
        run.text = "I built dropped evidence."
    elif content_kind == "direct_body_text":
        body.text = "I built dropped evidence."
    else:
        raise AssertionError("unknown malformed content kind")

    return _rewrite_docx(
        data,
        replacements={"word/document.xml": _serialize(root)},
    )


def _with_valid_break_tab_and_unicode(data: bytes) -> tuple[bytes, str]:
    root = ET.fromstring(_read_part(data, "word/document.xml"))
    _, _, paragraph = _find_target_paragraph(root)
    for item in list(paragraph):
        if item.tag == f"{{{WORD_NS}}}r":
            paragraph.remove(item)

    run = ET.Element(f"{{{WORD_NS}}}r")
    ET.SubElement(run, f"{{{WORD_NS}}}t").text = TARGET_PARAGRAPH
    ET.SubElement(run, f"{{{WORD_NS}}}br")
    ET.SubElement(run, f"{{{WORD_NS}}}t").text = "café résumé"
    ET.SubElement(run, f"{{{WORD_NS}}}tab")
    ET.SubElement(run, f"{{{WORD_NS}}}t").text = "ordinary text"
    ET.SubElement(run, f"{{{WORD_NS}}}br")
    ET.SubElement(run, f"{{{WORD_NS}}}t").text = "after the line break"
    paragraph.append(run)
    expected = TARGET_PARAGRAPH + "\ncafé résumé\tordinary text\nafter the line break"
    mutated = _rewrite_docx(
        data,
        replacements={"word/document.xml": _serialize(root)},
    )
    return mutated, expected


def _with_block_wrapper(data: bytes, wrapper_kind: str) -> bytes:
    root = ET.fromstring(_read_part(data, "word/document.xml"))
    body, index, paragraph = _find_target_paragraph(root)
    if wrapper_kind == "content_control":
        wrapper = ET.Element(f"{{{WORD_NS}}}sdt")
        ET.SubElement(wrapper, f"{{{WORD_NS}}}sdtContent").append(paragraph)
    elif wrapper_kind == "custom_xml":
        wrapper = ET.Element(
            f"{{{WORD_NS}}}customXml",
            {f"{{{WORD_NS}}}element": "SyntheticProof"},
        )
        wrapper.append(paragraph)
    elif wrapper_kind == "alternate_content":
        wrapper = ET.Element(f"{{{MARKUP_COMPAT_NS}}}AlternateContent")
        ET.SubElement(wrapper, f"{{{MARKUP_COMPAT_NS}}}Choice", {"Requires": "w"}).append(paragraph)
        ET.SubElement(wrapper, f"{{{MARKUP_COMPAT_NS}}}Fallback")
    elif wrapper_kind == "text_box":
        wrapper = ET.Element(f"{{{WORD_NS}}}txbxContent")
        wrapper.append(paragraph)
    else:
        raise AssertionError("unknown synthetic wrapper")
    body.remove(paragraph)
    body.insert(index, wrapper)
    return _rewrite_docx(
        data,
        replacements={"word/document.xml": _serialize(root)},
    )


def _with_inline_content_control(data: bytes) -> bytes:
    root = ET.fromstring(_read_part(data, "word/document.xml"))
    _, _, paragraph = _find_target_paragraph(root)
    for child in list(paragraph):
        if child.tag == f"{{{WORD_NS}}}r":
            paragraph.remove(child)

    def add_run(text: str, *, preserve_space: bool = False) -> ET.Element:
        run = ET.Element(f"{{{WORD_NS}}}r")
        text_node = ET.SubElement(run, f"{{{WORD_NS}}}t")
        if preserve_space:
            text_node.set(f"{{{XML_NS}}}space", "preserve")
        text_node.text = text
        return run

    paragraph.append(add_run("I ", preserve_space=True))
    content_control = ET.SubElement(paragraph, f"{{{WORD_NS}}}sdt")
    content = ET.SubElement(content_control, f"{{{WORD_NS}}}sdtContent")
    content.append(add_run("never ", preserve_space=True))
    paragraph.append(add_run("implemented a synthetic SQL reporting service."))
    return _rewrite_docx(
        data,
        replacements={"word/document.xml": _serialize(root)},
    )


def _redirect_main_part_with_inline_control(data: bytes) -> bytes:
    mutated = _with_inline_content_control(data)
    alternate_main = _read_part(mutated, "word/document.xml")

    relationships = ET.fromstring(_read_part(data, "_rels/.rels"))
    for relation in relationships.findall(f"{{{REL_NS}}}Relationship"):
        if relation.attrib.get("Type") == MAIN_REL_TYPE:
            relation.set("Target", "word/alternate.xml")
            break
    else:
        raise AssertionError("fixture has no officeDocument relationship")

    content_types = ET.fromstring(_read_part(data, "[Content_Types].xml"))
    ET.SubElement(
        content_types,
        f"{{{CONTENT_TYPES_NS}}}Override",
        {"PartName": "/word/alternate.xml", "ContentType": MAIN_CONTENT_TYPE},
    )
    return _rewrite_docx(
        data,
        replacements={
            "_rels/.rels": _serialize(relationships),
            "[Content_Types].xml": _serialize(content_types),
        },
        additions={"word/alternate.xml": alternate_main},
    )


def _with_duplicate_main_relationship(data: bytes) -> bytes:
    relationships = ET.fromstring(_read_part(data, "_rels/.rels"))
    main = next(
        relation for relation in relationships.findall(f"{{{REL_NS}}}Relationship")
        if relation.attrib.get("Type") == MAIN_REL_TYPE
    )
    duplicate = ET.fromstring(ET.tostring(main, encoding="utf-8"))
    duplicate.set("Id", "duplicate-office-document")
    relationships.append(duplicate)
    return _rewrite_docx(
        data,
        replacements={"_rels/.rels": _serialize(relationships)},
    )


@unittest.skipUnless(INTEGRATION, "run with RELAY_DOCUMENT_INTEGRATION=1 and pinned document dependencies")
class DocumentConversionIntegrationTests(unittest.TestCase):
    def assert_failed_conversion_is_not_stageable(self, result) -> None:
        self.assertIn(result.status, {"invalid", "unsupported", "unavailable"})
        self.assertEqual(result.text, "")
        self.assertEqual(result.segments, ())
        with BrainStore() as brain:
            host = object()
            gateway = ReviewGateway(brain, host_capability=host)
            with self.assertRaises((BrainError, ValueError)):
                stage_converted(result, gateway, observed_at=WHEN, capability=host)
            self.assertEqual(brain.db.execute("SELECT COUNT(*) FROM source").fetchone()[0], 0)
            self.assertEqual(brain.db.execute("SELECT COUNT(*) FROM candidate_fact").fetchone()[0], 0)

    def test_integration_gate_is_active_when_optional_cases_run(self):
        self.assertEqual(os.environ.get("RELAY_DOCUMENT_INTEGRATION"), "1")

    def test_markitdown_comparator_bypasses_generic_constructor(self):
        from markitdown import MarkItDown

        source = (FIXTURES / "synthetic-two-page.pdf").read_bytes()
        with patch.dict(os.environ, {"ORT_DISABLE_TELEMETRY": "0"}):
            with patch.object(
                MarkItDown,
                "__init__",
                side_effect=AssertionError("generic Magika classifier constructor used"),
            ):
                result = convert_document(source, file_type="pdf", backend="markitdown")
            self.assertEqual(os.environ["ORT_DISABLE_TELEMETRY"], "1")

        self.assertEqual(result.status, "needs_review")
        self.assertTrue(result.text)
        self.assertEqual(result.segments, ())

    def test_ambiguous_overlapping_locations_fail_before_source_write(self):
        source = (FIXTURES / "synthetic-two-page.pdf").read_bytes()
        converted = convert_document(source, file_type="pdf")
        self.assertEqual(converted.status, "converted")
        self.assertGreaterEqual(len(converted.segments), 2)
        result = replace(
            converted,
            segments=(converted.segments[0], converted.segments[0], *converted.segments[1:]),
        )
        with BrainStore() as brain:
            host = object()
            gateway = ReviewGateway(brain, host_capability=host)
            with self.assertRaises((BrainError, ValueError)):
                stage_converted(result, gateway, observed_at=WHEN, capability=host)
            self.assertEqual(brain.db.execute("SELECT COUNT(*) FROM source").fetchone()[0], 0)
            self.assertEqual(brain.db.execute("SELECT COUNT(*) FROM candidate_fact").fetchone()[0], 0)

    def test_docx_block_wrappers_fail_closed_without_dropping_text(self):
        source = (FIXTURES / "synthetic-unicode.docx").read_bytes()
        for wrapper_kind in ("content_control", "custom_xml", "alternate_content", "text_box"):
            with self.subTest(wrapper=wrapper_kind):
                mutated = _with_block_wrapper(source, wrapper_kind)
                result = convert_document(mutated, file_type="docx")
                self.assert_failed_conversion_is_not_stageable(result)

    def test_malformed_leaf_and_container_text_fail_before_python_docx_or_staging(self):
        source = (FIXTURES / "synthetic-unicode.docx").read_bytes()
        for content_kind in (
            "text_under_break",
            "text_under_text",
            "direct_break_text",
            "direct_paragraph_text",
            "direct_run_text",
            "direct_body_text",
        ):
            with self.subTest(content=content_kind):
                mutated = _with_malformed_word_text(source, content_kind)
                with patch(
                    "docx.Document",
                    side_effect=AssertionError("python-docx ran before XML grammar rejection"),
                ) as parser:
                    result = convert_document(mutated, file_type="docx")
                    self.assertFalse(parser.called, "python-docx parsed malformed Word XML")
                self.assertIn(result.status, {"invalid", "unsupported"})
                self.assert_failed_conversion_is_not_stageable(result)

    def test_valid_empty_break_tab_unicode_and_intra_paragraph_newlines_are_preserved(self):
        source = (FIXTURES / "synthetic-unicode.docx").read_bytes()
        mutated, expected = _with_valid_break_tab_and_unicode(source)
        result = convert_document(mutated, file_type="docx")
        self.assertEqual(result.status, "converted", result.reason)
        segment = next(item for item in result.segments if item.paragraph == 2)
        self.assertEqual(segment.text, expected)
        self.assertEqual(result.text[segment.start:segment.end], expected)

    def test_inline_content_control_cannot_erase_negation_or_stage_positive_claim(self):
        source = (FIXTURES / "synthetic-unicode.docx").read_bytes()
        mutated = _with_inline_content_control(source)
        result = convert_document(mutated, file_type="docx")
        self.assert_failed_conversion_is_not_stageable(result)

    def test_redirected_office_document_main_part_is_not_inspected_as_an_orphan(self):
        source = (FIXTURES / "synthetic-unicode.docx").read_bytes()
        mutated = _redirect_main_part_with_inline_control(source)
        result = convert_document(mutated, file_type="docx")
        self.assert_failed_conversion_is_not_stageable(result)

    def test_duplicate_office_document_relationship_is_ambiguous_and_rejected(self):
        source = (FIXTURES / "synthetic-unicode.docx").read_bytes()
        mutated = _with_duplicate_main_relationship(source)
        result = convert_document(mutated, file_type="docx")
        self.assert_failed_conversion_is_not_stageable(result)

    def test_empty_user_password_encrypted_pdf_rejected_before_conversion_and_staging(self):
        from pypdfium2 import PdfDocument, raw

        source = (WORKER_FIXTURES / "encrypted-empty-user-password.pdf").read_bytes()
        pdf = PdfDocument(source)
        try:
            self.assertGreaterEqual(raw.FPDF_GetSecurityHandlerRevision(pdf.raw), 0)
            self.assertEqual(len(pdf), 1)
        finally:
            pdf.close()

        with patch(
            "relay_spike.document_docling.native_pdf_records",
            side_effect=AssertionError("native converter ran before encryption rejection"),
        ) as native_converter:
            native_result = convert_document(source, file_type="pdf", backend="native")
            native_converter.assert_not_called()
        self.assert_failed_conversion_is_not_stageable(native_result)

        with patch(
            "relay_spike.document_markitdown.convert",
            side_effect=AssertionError("MarkItDown ran before encryption rejection"),
        ) as comparator:
            comparator_result = convert_document(source, file_type="pdf", backend="markitdown")
            comparator.assert_not_called()
        self.assert_failed_conversion_is_not_stageable(comparator_result)


if __name__ == "__main__":
    unittest.main()
