#!/usr/bin/env python3
"""Validate documentation contracts required by the D1 CI gate.

Checks that the normative documents exist, remain non-trivial, and that the
architecture spec still carries the sections the build relies on (persistence,
internal contracts, and the D1/D2/D3 deliverable table). Exits non-zero when a
contract is broken so CI can fail loudly.
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

REQUIRED_DOCS = [
    "docs/README.md",
    "docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md",
    "docs/design/MVP-UI-UX-SPEC-v1.0.md",
    "docs/audit/PROJECT_AUDIT.md",
    "docs/audit/IMPLEMENTATION_MATRIX.md",
    "docs/audit/SECURITY_AUDIT.md",
    "docs/audit/TECHNICAL_DEBT.md",
]

REQUIRED_SPEC_MARKERS = [
    "## 11. Local Persistence",
    "## 13. ",
    "| D1 |",
    "| D2 |",
    "| D3 |",
]

REQUIRED_PACKAGES = [
    "packages/editing_core",
    "packages/local_storage",
    "packages/media_core",
    "packages/contracts",
    "packages/agent_runtime",
    "packages/context_engine",
    "packages/provider_gateway",
    "packages/tool_system",
    "packages/permissions",
]

MIN_DOC_CHARS = 500


def fail(message: str, errors: list[str]) -> None:
    errors.append(message)


def main() -> int:
    errors: list[str] = []

    for rel in REQUIRED_DOCS:
        path = ROOT / rel
        if not path.is_file():
            fail(f"missing required document: {rel}", errors)
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if len(text.strip()) < MIN_DOC_CHARS:
            fail(
                f"document looks truncated: {rel} ({len(text.strip())} chars)",
                errors,
            )

    spec = ROOT / "docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md"
    if spec.is_file():
        text = spec.read_text(encoding="utf-8", errors="replace")
        for marker in REQUIRED_SPEC_MARKERS:
            if marker not in text:
                fail(f"architecture spec missing marker: {marker!r}", errors)

    for rel in REQUIRED_PACKAGES:
        package = ROOT / rel
        if not (package / "pubspec.yaml").is_file():
            fail(f"missing pubspec.yaml: {rel}", errors)
            continue
        if not any((package / "lib").glob("*.dart")) and not any(
            (package / "lib").rglob("*.dart")
        ):
            fail(f"package has no Dart entry point: {rel}", errors)

    if errors:
        print("documentation contract check FAILED:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("documentation contract check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())