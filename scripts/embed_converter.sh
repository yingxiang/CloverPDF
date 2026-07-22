#!/usr/bin/env bash
set -euo pipefail

SOURCE="$SRCROOT/converter/dist/cloverpdf-converter"
HELPERS_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Converter"
DESTINATION="$HELPERS_DIR/cloverpdf-converter"
SCRIPT_RESOURCE="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/cloverpdf_converter.py"
HELPER_EXECUTABLE="$DESTINATION/cloverpdf-converter"
HELPER_ENTITLEMENTS="$SRCROOT/converter/CloverPDFConverter.entitlements"

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

is_macho() {
  /usr/bin/file -b "$1" | /usr/bin/grep -q '^Mach-O'
}

sign_converter() {
  if [[ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" || -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    echo "Skipping converter signing because code signing is disabled"
    return
  fi

  while IFS= read -r -d '' binary_path; do
    if [[ "$binary_path" != "$HELPER_EXECUTABLE" ]] && is_macho "$binary_path"; then
      /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$binary_path"
    fi
  done < <(/usr/bin/find "$DESTINATION" -type f -print0)

  /usr/bin/codesign \
    --force \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --entitlements "$HELPER_ENTITLEMENTS" \
    --generate-entitlement-der \
    --timestamp=none \
    "$HELPER_EXECUTABLE"
}

generate_archive_dsyms() {
  if [[ "${ACTION:-}" != "install" || "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]]; then
    return
  fi

  /bin/mkdir -p "$DWARF_DSYM_FOLDER_PATH"
  while IFS= read -r -d '' binary_path; do
    if is_macho "$binary_path" && /usr/bin/dwarfdump --uuid "$binary_path" | /usr/bin/grep -q 'UUID:'; then
      dsym_path="$DWARF_DSYM_FOLDER_PATH/$(/usr/bin/basename "$binary_path").dSYM"
      xcrun dsymutil "$binary_path" -o "$dsym_path"
    fi
  done < <(/usr/bin/find "$DESTINATION" -type f -print0)
}

sign_converter
generate_archive_dsyms
