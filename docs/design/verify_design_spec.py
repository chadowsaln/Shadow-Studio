#!/usr/bin/env python3
"""Verify SS-UX-001 against itself and against SS-ARCH-001.

Checks (exit 1 on any failure):
  1. structure   — sections 0..16 present and ordered, code fences balanced.
  2. states      — every state id used anywhere (TL-/PV-/EX-/IM-/AI-) is defined
                   as a table row in the state matrix.
  3. refs        — every `§…` reference points at a heading that exists in the
                   architecture spec (or at a section of this document).
  4. codes       — every error code cited exists in the architecture spec.
  5. commands    — every edit command cited exists in §3.5.1 of the architecture.
  6. presets     — every export preset cited exists in the architecture.
  7. contrast    — every claimed WCAG ratio is recomputed from the token table and
                   must match the claim (±0.02) and clear its threshold.
  8. traceability— the ten MVP requirements are all mapped, in order.

Usage: python3 docs/design/verify_design_spec.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOC = HERE / "MVP-UI-UX-SPEC-v1.0.md"
ARCH = HERE.parent / "architecture" / "SOFTWARE-ARCHITECTURE-SPEC-v1.0.md"

failures: list[str] = []
checks = 0


def fail(msg: str) -> None:
    failures.append(msg)


def ok() -> None:
    global checks
    checks += 1


# --------------------------------------------------------------------------- #
def check_structure(text: str) -> None:
    heads = ["## 0.", "## 1.", "## 2.", "## 3.", "## 4.", "## 5.",
             "## 6.", "## 7.", "## 8.", "## 9.", "## 10.", "## 11.",
             "## 12.", "## 13.", "## 14.", "## 15.", "## 16."]
    pos = [text.find(h) for h in heads]
    if not all(p >= 0 for p in pos):
        fail(f"structure: missing sections {[h for h, p in zip(heads, pos) if p < 0]}")
    elif pos != sorted(pos):
        fail("structure: sections out of order")
    else:
        ok()
    fences = text.count("```")
    if fences % 2:
        fail(f"structure: unbalanced code fences ({fences})")
    else:
        ok()
    if re.search(r"[\u4e00-\u9fff]", text):
        fail("structure: CJK characters leaked into the document")
    else:
        ok()


# --------------------------------------------------------------------------- #
STATE_ID = re.compile(r"\b((?:TL|PV|EX|IM|AI)-(?:EMPTY|ERR|OK|WARN|BUSY|LOCK|REC)-\d{2})\b")


def check_states(text: str) -> None:
    used = set(STATE_ID.findall(text))
    defined = set(re.findall(r"^\| `([A-Z]{2}-[A-Z]+-\d{2})` \|", text, re.M))
    if not used:
        fail("states: no state ids found at all")
    if not defined:
        fail("states: no state matrix rows found")
    # One direction only: every id that appears anywhere must be catalogued.
    # (The reverse is not checkable here — the matrix row itself is an occurrence,
    # so "defined but unused" would be vacuous rather than informative.)
    for sid in sorted(used - defined):
        fail(f"states: {sid} used but not defined in the matrix")
    for sid in sorted(used & defined):
        ok()


# --------------------------------------------------------------------------- #
def check_refs(text: str, arch: str) -> None:
    """A `§x.y` must resolve to a heading in either document: most point at the
    architecture, but a few legitimately point at this spec's own sections."""
    refs = set(re.findall(r"§([0-9]+(?:\.[0-9]+)?|[أ-ي]\.[0-9]+)", text))
    if not refs:
        fail("refs: no section references found")
    for ref in sorted(refs):
        pattern = rf"^#{{2,3}} {re.escape(ref)}\b"
        if re.search(pattern, arch, re.M) or re.search(pattern, text, re.M):
            ok()
        else:
            fail(f"refs: §{ref} resolves in neither document")


# --------------------------------------------------------------------------- #
def check_codes(text: str, arch: str) -> None:
    tokens = set(re.findall(r"`([A-Z][A-Z0-9_]{3,})`", text))
    codes = {t for t in tokens if "_" in t and not t.startswith("U+")}
    if not codes:
        fail("codes: no error codes cited")
    for code in sorted(codes):
        if code in arch:
            ok()
        else:
            fail(f"codes: {code} is not defined in the architecture spec")


# --------------------------------------------------------------------------- #
def check_commands(text: str, arch: str) -> None:
    cmds = set(
        re.findall(
            r"`((?:clip|track|effect|transition|text|marker|sequence)\.[a-z_]+(?:/[a-z_]+)?)`",
            text,
        )
    )
    if not cmds:
        fail("commands: no edit commands cited")
    for cmd in sorted(cmds):
        head = cmd.split("/")[0]
        if head in arch:
            ok()
        else:
            fail(f"commands: {head} is not an edit command in the architecture spec")


# --------------------------------------------------------------------------- #
def check_presets(text: str, arch: str) -> None:
    presets = set(re.findall(r"`(mp4-h264-[a-z0-9]+|webm-vp9|wav-pcm|mp3-320|gif)`", text))
    if not presets:
        fail("presets: no export presets cited")
    for p in sorted(presets):
        if p in arch:
            ok()
        else:
            fail(f"presets: {p} is not in the architecture preset list")


# --------------------------------------------------------------------------- #
def _lin(c: int) -> float:
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _lum(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def _ratio(a: str, b: str) -> float:
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return round((hi + 0.05) / (lo + 0.05), 2)


def token_maps(text: str) -> tuple[dict[str, str], dict[str, str]]:
    """Parse the token table: | `token` | `#dark` | `#light` | ..."""
    dark: dict[str, str] = {}
    light: dict[str, str] = {}
    for name, d_hex, l_hex in re.findall(
        r"^\| `([a-z0-9-]+)` \| `(#[0-9A-Fa-f]{6})` \| `(#[0-9A-Fa-f]{6})` \|", text, re.M
    ):
        dark[name] = d_hex
        light[name] = l_hex
    return dark, light


def check_contrast(text: str) -> None:
    dark, light = token_maps(text)
    if len(dark) < 15:
        fail(f"contrast: token table parsed only {len(dark)} rows")
        return
    ok()

    claims = {
        "dark": re.findall(
            r"`([a-z0-9-]+)/([a-z0-9-]+)` = ([0-9]+\.[0-9]+)", text.split("**(light):**")[0]
        ),
        "light": re.findall(
            r"`([a-z0-9-]+)/([a-z0-9-]+)` = ([0-9]+\.[0-9]+)", text.split("**(light):**")[-1]
        ),
    }
    if not claims["dark"] or not claims["light"]:
        fail("contrast: no ratio claims found for one of the themes")
        return

    graphical = {"playhead", "selection"}
    for theme, table in (("dark", dark), ("light", light)):
        for fg, bg, claimed in claims[theme]:
            if fg not in table or bg not in table:
                fail(f"contrast[{theme}]: unknown token pair {fg}/{bg}")
                continue
            actual = _ratio(table[fg], table[bg])
            if abs(actual - float(claimed)) > 0.02:
                fail(f"contrast[{theme}]: {fg}/{bg} claimed {claimed}, computed {actual}")
                continue
            threshold = 3.0 if fg in graphical else 4.5
            if actual < threshold:
                fail(f"contrast[{theme}]: {fg}/{bg} = {actual} below {threshold}")
            else:
                ok()

    # the muted-on-surface-2 prohibition must stay true
    if "text-muted" in dark and "surface-2" in dark:
        if _ratio(dark["text-muted"], dark["surface-2"]) >= 4.5:
            fail("contrast: the 'muted not allowed on surface-2' rule is now stale")
        else:
            ok()


# --------------------------------------------------------------------------- #
def check_traceability(text: str) -> None:
    rows = re.findall(r"^\| (\d+) \| (?:Import|Multi-track|Cut|Video preview|Text overlays|"
                      r"Transitions|Audio editing|Export|AI-assisted|Save/Load)", text, re.M)
    nums = [int(n) for n in rows]
    if nums != list(range(1, 11)):
        fail(f"traceability: expected requirements 1..10, found {nums}")
    else:
        ok()


# --------------------------------------------------------------------------- #
def main() -> int:
    for p in (DOC, ARCH):
        if not p.exists():
            print(f"FATAL missing input: {p}")
            return 1
    text = DOC.read_text(encoding="utf-8")
    arch = ARCH.read_text(encoding="utf-8")

    phases = [
        ("structure", lambda: check_structure(text)),
        ("states", lambda: check_states(text)),
        ("refs", lambda: check_refs(text, arch)),
        ("codes", lambda: check_codes(text, arch)),
        ("commands", lambda: check_commands(text, arch)),
        ("presets", lambda: check_presets(text, arch)),
        ("contrast", lambda: check_contrast(text)),
        ("traceability", lambda: check_traceability(text)),
    ]
    for name, fn in phases:
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 - report, never crash on bad input
            fail(f"CRASH during {name}: {type(exc).__name__}: {exc}")

    if failures:
        print(f"FAIL — {len(failures)} problem(s), {checks} checks passed\n")
        for item in failures[:40]:
            print("  -", item)
        if len(failures) > 40:
            print(f"  ... and {len(failures) - 40} more")
        return 1

    print(f"PASS — {checks} design checks, 0 failures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
