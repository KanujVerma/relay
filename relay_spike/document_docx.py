"""Bounded, bytes-only DOCX inspection for the synthetic import slice."""
from __future__ import annotations

from io import BytesIO
from pathlib import PurePosixPath
from urllib.parse import urlsplit
from zipfile import BadZipFile, ZipFile

from defusedxml import ElementTree as SafeET


MAX_DOCX_ENTRIES = 256
MAX_DOCX_UNCOMPRESSED_BYTES = 8 * 1024 * 1024
WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
_UNSUPPORTED_WORD_TAGS = frozenset({
    "tbl", "drawing", "pict", "object", "altChunk", "hyperlink",
    "footnoteReference", "endnoteReference", "commentRangeStart",
    "commentRangeEnd", "fldSimple", "instrText", "delText", "ins",
    "del", "moveFrom", "moveTo",
})


class InvalidDocx(ValueError):
    """Malformed or over-limit archive, with a non-content reason code."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class UnsupportedDocx(ValueError):
    """Valid DOCX containing structures this slice cannot locate exactly."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def inspect_docx(data: bytes):
    """Return python-docx top-level paragraphs after fail-closed preflight.

    No path is opened and no relationship target is followed. Only plain body
    paragraphs are supported; tables, embedded objects, external relations,
    and non-empty header/footer/note content are rejected.
    """
    try:
        with ZipFile(BytesIO(data)) as archive:
            entries = archive.infolist()
            if len(entries) > MAX_DOCX_ENTRIES:
                raise InvalidDocx("docx_entry_limit")

            names: set[str] = set()
            total_size = 0
            for entry in entries:
                name = entry.filename.replace("\\", "/")
                path = PurePosixPath(name)
                if (not name or name.startswith("/") or ":" in name or
                        ".." in path.parts or name in names):
                    raise InvalidDocx("docx_archive_path")
                names.add(name)
                if entry.flag_bits & 0x1:
                    raise UnsupportedDocx("docx_encrypted_member")
                mode = (entry.external_attr >> 16) & 0o170000
                if mode == 0o120000:
                    raise UnsupportedDocx("docx_link_member")
                if entry.file_size > MAX_DOCX_UNCOMPRESSED_BYTES:
                    raise InvalidDocx("docx_member_size_limit")
                total_size += entry.file_size
                if total_size > MAX_DOCX_UNCOMPRESSED_BYTES:
                    raise InvalidDocx("docx_uncompressed_size_limit")
                if name.startswith("word/embeddings/") or name.startswith("word/media/"):
                    raise UnsupportedDocx("docx_embedded_content")

            if "word/document.xml" not in names:
                raise InvalidDocx("docx_document_missing")

            for name in names:
                if not name.endswith(".rels"):
                    continue
                try:
                    relationships = SafeET.fromstring(archive.read(name))
                except Exception:
                    raise InvalidDocx("docx_relationships_invalid") from None
                for relationship in relationships.iter(f"{{{REL_NS}}}Relationship"):
                    target_mode = relationship.attrib.get("TargetMode", "").strip().casefold()
                    parsed_target = urlsplit(relationship.attrib.get("Target", ""))
                    if (target_mode == "external" or
                            bool(parsed_target.scheme or parsed_target.netloc)):
                        raise UnsupportedDocx("docx_external_relationship")

            try:
                body = SafeET.fromstring(archive.read("word/document.xml"))
            except Exception:
                raise InvalidDocx("docx_document_xml_invalid") from None

            for node in body.iter():
                if not isinstance(node.tag, str) or not node.tag.startswith("{"):
                    continue
                namespace, local_name = node.tag[1:].split("}", 1)
                if namespace == WORD_NS and local_name in _UNSUPPORTED_WORD_TAGS:
                    raise UnsupportedDocx("docx_unsupported_body_content")

            # The plain-paragraph path does not read these content layers.
            for name in names:
                is_secondary_text = (
                    name.startswith("word/header") or
                    name.startswith("word/footer") or
                    name in {"word/comments.xml", "word/footnotes.xml", "word/endnotes.xml"}
                )
                if not is_secondary_text or not name.endswith(".xml"):
                    continue
                try:
                    root = SafeET.fromstring(archive.read(name))
                except Exception:
                    raise InvalidDocx("docx_secondary_xml_invalid") from None
                for node in root.iter():
                    if not isinstance(node.tag, str) or not node.tag.startswith("{"):
                        continue
                    namespace, local_name = node.tag[1:].split("}", 1)
                    if namespace != WORD_NS:
                        continue
                    if local_name in _UNSUPPORTED_WORD_TAGS:
                        raise UnsupportedDocx("docx_secondary_structure")
                    if local_name == "t" and (node.text or ""):
                        raise UnsupportedDocx("docx_secondary_text")

        from docx import Document

        return Document(BytesIO(data)).paragraphs
    except (InvalidDocx, UnsupportedDocx):
        raise
    except ImportError:
        raise
    except BadZipFile:
        raise InvalidDocx("docx_archive_invalid") from None
    except Exception:
        raise InvalidDocx("docx_parse_failed") from None
