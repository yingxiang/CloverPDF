from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from converter import cloverpdf_converter


class ConverterWorkerTests(unittest.TestCase):
    def test_read_request_accepts_non_contiguous_pages(self) -> None:
        payload = '{"input":"in.pdf","output":"out.docx","password":null,"pages":[0,2]}\n'
        with patch.object(sys, "stdin", io.StringIO(payload)):
            request = cloverpdf_converter.read_request()

        self.assertEqual(request.pages, (0, 2))
        self.assertIsNone(request.ocr_pages)

    def test_convert_passes_selected_pages_to_pdf2docx(self) -> None:
        calls: list[dict[str, object]] = []

        class FakeConverter:
            def __init__(self, input_path: str, password: str) -> None:
                self.input_path = input_path
                self.password = password

            def convert(self, output_path: str, **kwargs: object) -> None:
                calls.append(kwargs)
                with open(output_path, "wb") as output:
                    output.write(b"docx")

            def close(self) -> None:
                pass

        with tempfile.TemporaryDirectory() as directory:
            input_path = os.path.join(directory, "input.pdf")
            output_path = os.path.join(directory, "output.docx")
            with open(input_path, "wb") as source:
                source.write(b"pdf")
            request = cloverpdf_converter.Request(
                input=input_path,
                output=output_path,
                password=None,
                pages=(0, 2),
                ocr_pages=None,
            )
            fake_module = SimpleNamespace(Converter=FakeConverter)
            with patch.dict(sys.modules, {"pdf2docx": fake_module}):
                cloverpdf_converter.convert(request)

        self.assertEqual(calls, [{"multi_processing": False, "pages": [0, 2]}])

    def test_convert_ocr_writes_each_recognized_page(self) -> None:
        saved: list[tuple[str, list[str]]] = []

        class FakeDocument:
            def __init__(self) -> None:
                self.entries: list[str] = []

            def add_paragraph(self, text: str) -> None:
                self.entries.append(text)

            def add_page_break(self) -> None:
                self.entries.append("<page-break>")

            def save(self, path: str) -> None:
                saved.append((path, self.entries))
                with open(path, "wb") as output:
                    output.write(b"docx")

        with tempfile.TemporaryDirectory() as directory:
            input_path = os.path.join(directory, "input.pdf")
            output_path = os.path.join(directory, "output.docx")
            with open(input_path, "wb") as source:
                source.write(b"pdf")
            request = cloverpdf_converter.Request(
                input=input_path,
                output=output_path,
                password=None,
                pages=(0, 2),
                ocr_pages=(
                    {"page": 0, "lines": ["First", "Page"]},
                    {"page": 2, "lines": ["Third page"]},
                ),
            )
            fake_module = SimpleNamespace(Document=FakeDocument)
            with patch.dict(sys.modules, {"docx": fake_module}):
                cloverpdf_converter.convert(request)

        self.assertEqual(
            saved,
            [(output_path, ["First", "Page", "<page-break>", "Third page"])],
        )


if __name__ == "__main__":
    unittest.main()
