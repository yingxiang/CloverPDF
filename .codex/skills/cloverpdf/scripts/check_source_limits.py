#!/usr/bin/env python3
"""Check CloverPDF source file and function line limits."""

from __future__ import annotations

import ast
import re
import sys
from dataclasses import dataclass
from pathlib import Path


FILE_WARNING = 800
FILE_LIMIT = 1000
FUNCTION_WARNING = 80
FUNCTION_LIMIT = 120
ROOT = Path(__file__).resolve().parents[4]
EXCLUDED_PARTS = {
    ".build",
    ".deriveddata",
    ".git",
    ".swiftpm",
    ".venv",
    "DerivedData",
    "Pods",
    "build",
    "dist",
    "site-packages",
    "vendor",
}
SWIFT_DECLARATION = re.compile(
    r"^\s*(?:@[\w().,\s]+\s+)*(?:(?:public|private|fileprivate|internal|open|static|class|final|mutating|nonmutating|override|required|convenience)\s+)*(func|init|deinit|subscript)\b"
)


@dataclass(frozen=True)
class Finding:
    severity: str
    path: Path
    message: str


def source_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if path.suffix not in {".swift", ".py"} or not path.is_file() or path.is_symlink():
            continue
        if any(part in EXCLUDED_PARTS for part in path.parts):
            continue
        if ".codex/skills" in path.as_posix():
            continue
        files.append(path)
    return sorted(files)


def check_file(path: Path, lines: list[str]) -> list[Finding]:
    count = len(lines)
    if count > FILE_LIMIT:
        return [Finding("ERROR", path, f"file has {count} lines (limit {FILE_LIMIT})")]
    if count > FILE_WARNING:
        return [Finding("WARN", path, f"file has {count} lines (warning {FILE_WARNING})")]
    return []


def swift_function_spans(lines: list[str]) -> list[tuple[str, int, int]]:
    spans: list[tuple[str, int, int]] = []
    index = 0
    while index < len(lines):
        match = SWIFT_DECLARATION.match(lines[index])
        if not match:
            index += 1
            continue
        start = index
        name = match.group(1)
        signature = lines[index].strip()
        balance = 0
        saw_open = False
        cursor = index
        while cursor < len(lines):
            code = re.sub(r'"(?:\\.|[^"\\])*"', '""', lines[cursor].split("//", 1)[0])
            balance += code.count("{") - code.count("}")
            saw_open = saw_open or "{" in code
            if saw_open and balance <= 0:
                spans.append((signature or name, start + 1, cursor + 1))
                index = cursor + 1
                break
            cursor += 1
        else:
            index += 1
    return spans


def python_function_spans(path: Path) -> list[tuple[str, int, int]]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except (SyntaxError, UnicodeDecodeError):
        return []
    spans: list[tuple[str, int, int]] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.end_lineno:
            spans.append((node.name, node.lineno, node.end_lineno))
    return spans


def check_functions(path: Path, lines: list[str]) -> list[Finding]:
    spans = swift_function_spans(lines) if path.suffix == ".swift" else python_function_spans(path)
    findings: list[Finding] = []
    for name, start, end in spans:
        count = end - start + 1
        detail = f"{name} spans lines {start}-{end} ({count} lines)"
        if count > FUNCTION_LIMIT:
            findings.append(Finding("ERROR", path, f"{detail}; limit {FUNCTION_LIMIT}"))
        elif count > FUNCTION_WARNING:
            findings.append(Finding("WARN", path, f"{detail}; warning {FUNCTION_WARNING}"))
    return findings


def main() -> int:
    findings: list[Finding] = []
    files = source_files()
    for path in files:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        findings.extend(check_file(path, lines))
        findings.extend(check_functions(path, lines))
    for finding in findings:
        relative = finding.path.relative_to(ROOT)
        print(f"[{finding.severity}] {relative}: {finding.message}")
    errors = sum(finding.severity == "ERROR" for finding in findings)
    print(f"Checked {len(files)} source files; {errors} error(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
