#!/usr/bin/env bash
set -euo pipefail

SOURCE="$SRCROOT/converter/dist/cloverpdf-converter"
HELPERS_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
DESTINATION="$HELPERS_DIR/cloverpdf-converter"
SCRIPT_RESOURCE="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/cloverpdf_converter.py"

if [[ ! -x "$SOURCE" ]]; then
  if [[ "$CONFIGURATION" == "Release" ]]; then
    echo "error: Build the converter with scripts/build_converter.sh before a Release build" >&2
    exit 1
  fi
  echo "warning: converter helper is missing; Debug will use the bundled Python script"
  exit 0
fi

mkdir -p "$HELPERS_DIR"
ditto "$SOURCE" "$DESTINATION"
chmod 755 "$DESTINATION"

if [[ "$CONFIGURATION" == "Release" ]]; then
  rm -f "$SCRIPT_RESOURCE"
fi

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign \
    --force \
    --options runtime \
    --entitlements "$SRCROOT/converter/CloverPDFConverter.entitlements" \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    "$DESTINATION"
fi
