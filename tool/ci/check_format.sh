#!/usr/bin/env bash
# Verifies formatting of Dart files changed against a base ref.
#
# Usage: tool/ci/check_format.sh <base-ref>
# Falls back to the previous commit when the base ref is empty or unknown.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DART_BIN="${DART_BIN:-dart}"
BASE="${1:-}"

if [[ -z "$BASE" || "$BASE" =~ ^0+$ ]]; then
  BASE="HEAD~1"
fi

if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
  echo "format: base '$BASE' not found, checking HEAD" >&2
  BASE="HEAD"
fi

mapfile -t changed < <(
  git diff --name-only --diff-filter=ACMR "$BASE" -- '*.dart' | sort -u
)

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "format: no changed Dart files"
  exit 0
fi

existing=()
for file in "${changed[@]}"; do
  [[ -f "$file" ]] && existing+=("$file")
done

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "format: no existing Dart files to check"
  exit 0
fi

echo "format: checking ${#existing[@]} changed Dart file(s)"
"$DART_BIN" format --output=none --set-exit-if-changed "${existing[@]}"