#!/usr/bin/env python3
"""Fixed JSONL wrapper around pdf2docx for CloverPDF."""

from __future__ import annotations

import json
import os
import sys
import traceback
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Request:
    input: str
    output: str
    password: str | None
    pages: tuple[int, ...]
    ocr_pages: tuple[dict[str, Any], ...] | None


def emit(event_type: str, **values: Any) -> None:
    payload = {"type": event_type, **values}
    sys.stdout.write(json.dumps(payload, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def read_request() -> Request:
    line = sys.stdin.readline()
    if not line:
        raise ValueError("missing_request")
    payload = json.loads(line)
    return Request(
        input=str(payload["input"]),
        output=str(payload["output"]),
        password=payload.get("password"),
        pages=tuple(int(page) for page in payload.get("pages", [])),
        ocr_pages=(
            tuple(payload["ocrPages"])
            if payload.get("ocrPages") is not None
            else None
        ),
    )


def error_code(error: Exception) -> str:
    message = str(error).lower()
    if "require password" in message:
        return "password_required"
    if "incorrect password" in message:
        return "incorrect_password"
    if "no parsed pages" in message or "no_pages" in message:
        return "no_pages"
    if isinstance(error, FileNotFoundError):
        return "input_not_found"
    return "conversion_failed"


def convert(request: Request) -> None:
    if not os.path.isfile(request.input):
        raise FileNotFoundError(request.input)
    if not request.pages or any(page < 0 for page in request.pages):
        raise ValueError("no_pages")
    os.makedirs(os.path.dirname(request.output), exist_ok=True)
    emit("started")
    if request.ocr_pages is not None:
        convert_ocr(request)
        return
    from pdf2docx import Converter

    emit("progress", progress=0.05, phase="opening")
    converter = Converter(request.input, request.password or "")
    try:
        kwargs: dict[str, Any] = {"multi_processing": False}
        emit("progress", progress=0.15, phase="parsing")
        converter.convert(request.output, pages=list(request.pages), **kwargs)
    finally:
        converter.close()
    if not os.path.isfile(request.output) or os.path.getsize(request.output) == 0:
        raise RuntimeError("missing_output")
    emit("progress", progress=1.0, phase="completed")
    emit("completed", output=request.output)


def convert_ocr(request: Request) -> None:
    from docx import Document

    document = Document()
    pages = request.ocr_pages or ()
    for page_offset, page in enumerate(pages):
        for line in page.get("lines", []):
            document.add_paragraph(str(line))
        if page_offset < len(pages) - 1:
            document.add_page_break()
        emit(
            "progress",
            progress=0.7 + ((page_offset + 1) / max(len(pages), 1)) * 0.3,
            phase="writing_ocr",
        )
    document.save(request.output)
    if not os.path.isfile(request.output) or os.path.getsize(request.output) == 0:
        raise RuntimeError("missing_output")
    emit("completed", output=request.output)


def main() -> int:
    try:
        convert(read_request())
        return 0
    except Exception as error:
        emit("failed", code=error_code(error))
        traceback.print_exc(file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
