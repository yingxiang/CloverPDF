#!/usr/bin/env bash
set -euo pipefail

SOURCE="$SRCROOT/converter/dist/cloverpdf-converter"
HELPERS_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Converter"
DESTINATION="$HELPERS_DIR/cloverpdf-converter"
SCRIPT_RESOURCE="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/cloverpdf_converter.py"

if [[ ! -x "$SOURCE" ]]; then
  echo "error: Build the converter with scripts/build_converter.sh before building CloverPDF" >&2
  exit 1
fi

mkdir -p "$HELPERS_DIR"
rm -rf "$DESTINATION"
rm -rf "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/cloverpdf-converter"
ditto "$SOURCE" "$DESTINATION"
find "$DESTINATION" -type d -name _CodeSignature -prune -exec rm -rf {} +
chmod 755 "$DESTINATION/cloverpdf-converter"

rm -f "$SCRIPT_RESOURCE"
