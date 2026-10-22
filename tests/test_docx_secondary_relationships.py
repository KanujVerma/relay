"""Reject DOCX relationship-linked text layers regardless of filename.

Regression for PR #34's post-merge review finding. This suite uses synthetic
local OOXML ZIP bytes and does not require an installed PDF/DOCX parser.
"""
from __future__ import annotations

from io import BytesIO
from pathlib import Path
import unittest
from xml.etree import ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile

from relay_spike.document_conversion import convert_document, stage_converted
from relay_spike.document_docx import UnsupportedDocx, inspect_docx
from relay_spike.personal_brain import BrainStore, MissingEvidence
from relay_spike.resume_candidates import ReviewGateway


FIXTURE = Path(__file__).parent / "fixtures" / "documents" / "synthetic-unicode.docx"
WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
OFFICE_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
STRICT_REL_NS = "http://purl.oclc.org/ooxml/officeDocument/relationships"
WHEN = "2026-10-22T12:00:00-05:00"


def _linked_secondary_text(kind: str, *, rel_namespace: str = OFFICE_REL_NS) -> bytes:
    """Attach a synthetic qualifying/negating text part with an atypical name."""
    with ZipFile(BytesIO(FIXTURE.read_bytes())) as src:
        members = {name: src.read(name) for name in src.namelist()}

    part_name = f"word/context-qualifier-{kind}.xml"
    relationship_id = "rIdRelaySecondary"
    old_rels = members.get("word/_rels/document.xml.rels")
    relroot = (ET.fromstring(old_rels) if old_rels is not None
               else ET.Element(f"{{{PKG_REL_NS}}}Relationships"))
    ET.SubElement(relroot, f"{{{PKG_REL_NS}}}Relationship", {
        "Id": relationship_id, "Type": f"{rel_namespace}/{kind}",
        "Target": f"context-qualifier-{kind}.xml",
    })
    members["word/_rels/document.xml.rels"] = ET.tostring(
        relroot, encoding="utf-8", xml_declaration=True
    )

    document = ET.fromstring(members["word/document.xml"])
    body = document.find(f"{{{WORD_NS}}}body")
    if body is None:
        raise AssertionError("Fixture has no body")
    sections = body.findall(f"{{{WORD_NS}}}sectPr")
    section = sections[-1] if sections else ET.SubElement(body, f"{{{WORD_NS}}}sectPr")
    if kind in ("header", "footer"):
        ET.SubElement(section, f"{{{WORD_NS}}}{kind}Reference", {
            f"{{{WORD_NS}}}type": "default",
            f"{{{OFFICE_REL_NS}}}id": relationship_id,
        })
    members["word/document.xml"] = ET.tostring(
        document, encoding="utf-8", xml_declaration=True
    )

    secondary = ET.Element(f"{{{WORD_NS}}}{'hdr' if kind == 'header' else 'ftr'}")
    paragraph = ET.SubElement(secondary, f"{{{WORD_NS}}}p")
    run = ET.SubElement(paragraph, f"{{{WORD_NS}}}r")
    ET.SubElement(run, f"{{{WORD_NS}}}t").text = (
        "Correction: the teammate, not the user, implemented this feature."
    )
    members[part_name] = ET.tostring(
        secondary, encoding="utf-8", xml_declaration=True
    )

    content_types = ET.fromstring(members["[Content_Types].xml"])
    CT_BY_KIND = {
        "header": "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml",
        "footer": "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml",
    }
    if kind in CT_BY_KIND:
        ET.SubElement(content_types, f"{{{CT_NS}}}Override", {
            "PartName": "/" + part_name,
            "ContentType": CT_BY_KIND[kind],
        })
    members["[Content_Types].xml"] = ET.tostring(
        content_types, encoding="utf-8", xml_declaration=True
    )

    destination = BytesIO()
    with ZipFile(destination, "w", ZIP_DEFLATED) as out:
        for name, data in members.items():
            out.writestr(name, data)
    return destination.getvalue()


class SecondaryRelationshipSafetyTests(unittest.TestCase):
    def test_noncanonical_header_footer_relationships_fail_before_body_extraction(self):
        for kind in ("header", "footer"):
            with self.subTest(kind=kind):
                source = _linked_secondary_text(kind)
                # The part does not look like word/header*.xml or word/footer*.xml.
                with ZipFile(BytesIO(source)) as archive:
                    self.assertIn(f"word/context-qualifier-{kind}.xml", archive.namelist())
                    self.assertNotIn(f"word/{kind}1.xml", archive.namelist())
                with self.assertRaises(UnsupportedDocx) as failure:
                    inspect_docx(source)
                self.assertEqual(failure.exception.reason,
                                 "docx_secondary_text_relationship")
                converted = convert_document(source, file_type="docx", backend="native")
                self.assertEqual(converted.status, "unsupported")
                self.assertEqual(converted.reason, "docx_secondary_text_relationship")
                self.assertEqual(converted.text, "")
                self.assertEqual(converted.segments, ())

                with BrainStore() as brain:
                    host = object()
                    gateway = ReviewGateway(brain, host_capability=host)
                    with self.assertRaises(MissingEvidence):
                        stage_converted(
                            converted, gateway, observed_at=WHEN, capability=host
                        )
                    self.assertEqual(
                        brain.db.execute("SELECT COUNT(*) FROM source").fetchone()[0], 0
                    )

    def test_secondary_relationship_rejected_even_with_strict_office_type(self):
        for kind in ("header", "footer"):
            with self.subTest(kind=kind):
                source = _linked_secondary_text(
                    kind, rel_namespace=STRICT_REL_NS
                )
                with self.assertRaises(UnsupportedDocx) as failure:
                    inspect_docx(source)
                self.assertEqual(failure.exception.reason,
                                 "docx_secondary_text_relationship")


if __name__ == "__main__":
    unittest.main()
