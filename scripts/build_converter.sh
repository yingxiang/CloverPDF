#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$ROOT_DIR/converter/.venv"
DIST_DIR="$ROOT_DIR/converter/dist"
PYTHON_BIN="${PYTHON_BIN:-python3}"

"$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' || {
  echo "error: Python 3.11 or newer is required to build the converter helper" >&2
  exit 1
}
rm -rf "$VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --timeout 120 --retries 5 -r "$ROOT_DIR/converter/requirements.in"
"$VENV_DIR/bin/pyinstaller" \
  --noconfirm \
  --clean \
  --onedir \
  --name cloverpdf-converter \
  --collect-all pdf2docx \
  --collect-all fitz \
  --collect-all cv2 \
  --distpath "$DIST_DIR" \
  --workpath "$ROOT_DIR/converter/build" \
  --specpath "$ROOT_DIR/converter" \
  "$ROOT_DIR/converter/cloverpdf_converter.py"
"$VENV_DIR/bin/pip" freeze > "$ROOT_DIR/converter/requirements.lock"
echo "Built $DIST_DIR/cloverpdf-converter"
