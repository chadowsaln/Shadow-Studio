#!/usr/bin/env bash
# Local equivalent of the CI gate. Run from anywhere: tool/ci/verify.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DART_BIN="${DART_BIN:-dart}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

echo "==> environment"
"$DART_BIN" --version
"$FLUTTER_BIN" --version | head -1

echo "==> formatting (changed files vs HEAD)"
tool/ci/check_format.sh "HEAD"

echo "==> dependency resolution"
"$DART_BIN" pub get

echo "==> documentation contracts"
"$PYTHON_BIN" tool/ci/validate_docs.py

echo "==> static analysis (workspace + non-workspace packages)"
"$DART_BIN" analyze
for package in packages/contracts packages/context_engine packages/agent_runtime packages/tool_system packages/provider_gateway packages/permissions packages/render_pipeline; do
  echo "-- $package"
  (cd "$package" && "$DART_BIN" pub get >/dev/null && "$DART_BIN" analyze)
done

echo "==> tests"
for package in packages/contracts packages/context_engine packages/agent_runtime packages/tool_system packages/provider_gateway packages/permissions packages/local_storage packages/editing_core packages/media_core packages/render_pipeline; do
  echo "-- $package"
  (cd "$package" && "$DART_BIN" test)
done

echo "==> desktop widget tests"
(cd apps/desktop && "$FLUTTER_BIN" test)

echo "ALL CHECKS PASSED"