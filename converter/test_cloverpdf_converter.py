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
            )
            fake_module = SimpleNamespace(Converter=FakeConverter)
            with patch.dict(sys.modules, {"pdf2docx": fake_module}):
                cloverpdf_converter.convert(request)

        self.assertEqual(calls, [{"multi_processing": False, "pages": [0, 2]}])


if __name__ == "__main__":
    unittest.main()
