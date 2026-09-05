"""
PDF parser implementation using PyMuPDF (fitz) with pypdf fallback.

Extracts text and metadata from PDF documents.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

try:
    import fitz  # PyMuPDF
    _FITZ_AVAILABLE = True
except ImportError:
    fitz = None  # type: ignore
    _FITZ_AVAILABLE = False

logger = logging.getLogger(__name__)


class PDFParser:
    """Parser for PDF documents using PyMuPDF with pypdf fallback."""

    def can_parse(self, file_path: Path) -> bool:
        """
        Check if this parser can handle PDF files.

        Args:
            file_path: Path to the file to check.

        Returns:
            True if file has .pdf extension.
        """
        return file_path.suffix.lower() == ".pdf"

    def extract_text(self, file_path: Path) -> str:
        """
        Extract text content from PDF.

        Args:
            file_path: Path to the PDF file.

        Returns:
            Extracted text from all pages, joined by newlines.
        """
        if fitz is not None:
            try:
                doc = fitz.open(file_path)
            except Exception as e:
                logger.error(f"Failed to open PDF {file_path}: {e}")
                return ""
            try:
                text_parts = []
                for page in doc:
                    text_parts.append(page.get_text())
                return "\n".join(text_parts)
            finally:
                doc.close()

        # Fallback to pypdf if fitz is not available
        try:
            import pypdf
            reader = pypdf.PdfReader(str(file_path))
            text_parts = [page.extract_text() or "" for page in reader.pages]
            return "\n".join(text_parts)
        except Exception as e:
            logger.error(f"Failed to read PDF with pypdf {file_path}: {e}")
            return ""

    def extract_metadata(self, file_path: Path) -> dict[str, Any]:
        """
        Extract metadata from PDF.

        Args:
            file_path: Path to the PDF file.

        Returns:
            Dictionary with page_count, title (if available), and type.
        """
        if fitz is not None:
            try:
                doc = fitz.open(file_path)
            except Exception as e:
                logger.error(f"Failed to open PDF {file_path}: {e}")
                return {"page_count": 0, "type": "pdf"}
            try:
                metadata = doc.metadata or {}
                return {
                    "page_count": len(doc),
                    "title": metadata.get("title", ""),
                    "author": metadata.get("author", ""),
                    "type": "pdf",
                }
            finally:
                doc.close()

        # Fallback to pypdf if fitz is not available
        try:
            import pypdf
            reader = pypdf.PdfReader(str(file_path))
            metadata = reader.metadata or {}
            title = getattr(metadata, "title", None) or metadata.get("/Title", "") if hasattr(metadata, "get") else ""
            author = getattr(metadata, "author", None) or metadata.get("/Author", "") if hasattr(metadata, "get") else ""
            return {
                "page_count": len(reader.pages),
                "title": str(title),
                "author": str(author),
                "type": "pdf",
            }
        except Exception as e:
            logger.error(f"Failed to extract PDF metadata with pypdf {file_path}: {e}")
            return {"page_count": 0, "type": "pdf"}
