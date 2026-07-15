#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
SKILL_DIR="$ROOT_DIR/.codex/skills/cloverpdf"
APP_DIR="$ROOT_DIR/CloverPDF"

required=(
  "$SKILL_DIR/SKILL.md"
  "$SKILL_DIR/agents/openai.yaml"
  "$SKILL_DIR/references/architecture.md"
  "$SKILL_DIR/references/pdf-workflows.md"
  "$SKILL_DIR/references/purchases-localization.md"
  "$SKILL_DIR/references/finder-sandbox.md"
  "$SKILL_DIR/scripts/check_source_limits.py"
  "$APP_DIR/App/Info.plist"
  "$APP_DIR/Resources/Localizable.xcstrings"
  "$APP_DIR/Resources/InfoPlist.xcstrings"
)

for path in "${required[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "[ERROR] missing $path" >&2
    exit 1
  fi
done

if ! rg -q 'com\.lingchen\.cloverpdf' "$ROOT_DIR/project.yml"; then
  echo "[ERROR] bundle identifier is missing from project.yml" >&2
  exit 1
fi

for value in 'com.adobe.pdf' '<string>Viewer</string>' '<string>Alternate</string>'; do
  if ! rg -q "$value" "$APP_DIR/App/Info.plist"; then
    echo "[ERROR] PDF document registration is incomplete: $value" >&2
    exit 1
  fi
done

for locale in zh-Hans en ko ja de ru; do
  if ! rg -q "\"$locale\"" "$APP_DIR/Resources/Localizable.xcstrings"; then
    echo "[ERROR] missing locale $locale in Localizable.xcstrings" >&2
    exit 1
  fi
done

python3 - "$APP_DIR/Resources/Localizable.xcstrings" "$APP_DIR/Resources/InfoPlist.xcstrings" <<'PY'
import json
import sys

required = {"zh-Hans", "en", "ko", "ja", "de", "ru"}
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as handle:
        strings = json.load(handle).get("strings", {})
    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        missing = required - set(localizations)
        if missing:
            raise SystemExit(f"[ERROR] {key!r} misses locales: {sorted(missing)}")
        for locale in required:
            unit = localizations[locale].get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                raise SystemExit(f"[ERROR] {key!r} has incomplete locale {locale}")
PY

shared_dir="$APP_DIR/Features/Purchases/Shared"
for file in MacPaywallPresenter.swift MacPurchaseManager.swift; do
  path="$shared_dir/$file"
  if [[ ! -L "$path" ]]; then
    echo "[ERROR] $path must be a symlink to the common purchase source" >&2
    exit 1
  fi
done

if ! rg -q '"ru"' "$shared_dir/MacPaywallPresenter.swift"; then
  echo "[ERROR] shared paywall is missing Russian strings" >&2
  exit 1
fi

if rg -n '(^|[[:space:]])(class|struct)[[:space:]]+MacPaywall(Presenter|Product)' "$APP_DIR" --glob '*.swift' --glob '!Features/Purchases/Shared/*' >/dev/null; then
  echo "[ERROR] found a duplicate paywall implementation" >&2
  exit 1
fi

python3 "$SKILL_DIR/scripts/check_source_limits.py"
echo "[OK] CloverPDF project skill and quality gates verified"
