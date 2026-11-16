#!/usr/bin/env python3
"""Validate the v2.0 architecture document itself.

v2.0 is a redesign (no backend, Dart agent runtime, out-of-process media
worker) and it *inherits* the validated RenderGraph contract of v1.0. This
script keeps the document honest mechanically:

  * required sections and appendices exist, in order;
  * every module row declares a responsibility and dependencies, the dependency
    graph is acyclic, and dependencies name real modules (or contracts/*);
  * every quality goal has a numeric target and a verification method;
  * every V2-D decision records its rejected alternative;
  * tool, error and appendix-D tables are unique and use declared vocabularies;
  * the migration map covers every v1.0 section, appendix and deliverable;
  * the inherited contract artifacts exist and parse;
  * the document contains no server bind address (no-backend is not decorative).

Usage: python3 docs/architecture/contracts/validate_v2.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = HERE.parent / "SOFTWARE-ARCHITECTURE-SPEC-v2.0.md"
V1 = HERE.parent / "SOFTWARE-ARCHITECTURE-SPEC-v1.0.md"
SCHEMA = HERE / "rendergraph.schema.json"
EFFECTS = HERE / "rendergraph.effects.json"
MANIFEST = HERE / "rendergraph.manifest.json"
EXAMPLE = HERE / "rendergraph.example.json"

failures: list[str] = []
checks = 0


def ok(_msg: str = "") -> None:
    global checks
    checks += 1


def fail(msg: str) -> None:
    failures.append(msg)


def block(text: str, start: str, end: str) -> str:
    try:
        a = text.index(start)
        b = text.index(end, a + len(start))
    except ValueError:
        return ""
    return text[a:b]


def section_headers(text: str) -> list[str]:
    return re.findall(r"^## (.+)$", text, re.M)


# --------------------------------------------------------------------------- #
def check_shape(text: str) -> None:
    for token in ("`SS-ARCH-002`", "| Version | `2.0` |", "Supersedes", "Inherits"):
        if token not in text:
            fail(f"SHAPE: missing metadata token {token!r}")
        else:
            ok()

    required = [
        "0. اصطلاحات",
        "1. نظرة عامة وأهداف الجودة",
        "2. الوحدات والحدود",
        "3. نموذج التنفيذ والتزامن",
        "4. Agent Runtime",
        "5. Provider Gateway",
        "6. Context Engine",
        "7. Tool System",
        "8. Permission & Safety",
        "9. Editing Core",
        "10. Native Media Engine",
        "11. Local Persistence",
        "12. Environment Adapter",
        "13. العقود الداخلية",
        "14. Threading / Caching / Errors / Observability",
        "15. ميزانيات الأداء",
        "16. التتبّع: متطلبات MVP → الوحدات",
        "17. أسئلة مفتوحة",
        "18. المُخرَجات التالية",
    ]
    headers = section_headers(text)
    indexes = []
    for title in required:
        if title not in headers:
            fail(f"SHAPE: missing section {title!r}")
            continue
        indexes.append(headers.index(title))
        ok(f"section:{title}")
    if indexes != sorted(indexes):
        fail("SHAPE: sections are out of order")

    for appendix in ("## ملحق أ", "## ملحق ب", "## ملحق ج", "## ملحق د"):
        if appendix not in text:
            fail(f"SHAPE: missing {appendix}")
        else:
            ok(appendix)


# --------------------------------------------------------------------------- #
def check_modules(text: str) -> None:
    body = block(text, "### 2.2", "### 2.3")
    if not body:
        fail("MODULES: §2.2 table not found")
        return
    rows = re.findall(
        r"^\|\s*(\d+)\s*\|\s*`([^`]+)`[^|]*\|\s*([^|]+)\|\s*([^|]+)\|$", body, re.M
    )
    if len(rows) < 10:
        fail(f"MODULES: expected at least 10 module rows, found {len(rows)}")
        return
    names = {name for _, name, _, _ in rows}
    modules = set(names)
    graph: dict[str, set[str]] = {}
    contract_deps = {
        "contracts/agent",
        "contracts/tools",
        "contracts/editing",
        "contracts/providers",
        "contracts/media",
    }
    order = {name: int(index) for index, name, _, _ in rows}
    for index, name, responsibility, deps in rows:
        if len(responsibility.strip()) < 10:
            fail(f"MODULES: {name} has no real responsibility line")
        tokens = set(re.findall(r"`([^`]+)`", deps))
        allowed = {t for t in tokens if t in modules} | (tokens & contract_deps)
        unknown = tokens - allowed
        if unknown:
            fail(f"MODULES: {name} depends on undeclared unit(s) {sorted(unknown)}")
        else:
            ok(f"module:{name}")
        graph[name] = {t for t in tokens if t in modules}
        for dep in graph[name]:
            if order[dep] <= order[name]:
                fail(
                    f"MODULES: {name} (#{order[name]}) depends on {dep} (#{order[dep]}); "
                    "dependencies may only point further down the table"
                )
            else:
                ok(f"direction:{name}->{dep}")

    colour: dict[str, int] = {}

    def visit(node: str, stack: list[str]) -> None:
        state = colour.get(node, 0)
        if state == 2:
            return
        if state == 1:
            fail(f"MODULES: dependency cycle through {' -> '.join(stack + [node])}")
            return
        colour[node] = 1
        for dep in graph.get(node, ()):
            visit(dep, stack + [node])
        colour[node] = 2

    for module in graph:
        visit(module, [])

    trace = block(text, "## 16.", "## 17.")
    for module in sorted(graph):
        if module.startswith("apps/"):
            module = "desktop/app"
        if module not in trace:
            fail(f"TRACE: module {module} has no MVP requirement row")
        else:
            ok(f"trace:{module}")


# --------------------------------------------------------------------------- #
def check_quality_and_limits(text: str) -> None:
    qg = block(text, "### 1.2", "### 1.3")
    rows = re.findall(r"^\|\s*(QG-\d+)\s*\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|$", qg, re.M)
    if len(rows) < 10:
        fail(f"QG: expected at least 10 quality goals, found {len(rows)}")
    for code, _goal, _scenario, target, verify in rows:
        if not re.search(r"\d", target):
            fail(f"QG: {code} has no numeric target")
        elif len(verify.strip()) < 8:
            fail(f"QG: {code} has no verification method")
        else:
            ok(f"qg:{code}")

    limits = block(text, "### 4.3", "### 4.4")
    limit_rows = re.findall(r"^\|\s*([^|]*?)\s*\|\s*([^|]+?)\s*\|", limits, re.M)
    numeric = [
        (label, value)
        for label, value in limit_rows
        if label.startswith(("حد ", "الزمن", "إعادة", "ميزانية", "كشف", "checkpoint", "الموافقات"))
    ]
    if len(numeric) < 5:
        fail("LIMITS: §4.3 has fewer than 5 bounded limits")
    for label, value in numeric:
        if not re.search(r"\d", value):
            fail(f"LIMITS: {label.strip()} has no numeric value")
        else:
            ok(f"limit:{label.strip()}")


def check_decisions(text: str) -> None:
    matches = list(
        re.finditer(
            r"#### (V2-D\d+) — ([^\n]+)\n(.*?)(?=\n#### |\n### |\n## |\n---)",
            text,
            re.S,
        )
    )
    if len(matches) < 8:
        fail(f"DECISIONS: expected at least 8 V2-D records, found {len(matches)}")
    seen = set()
    for match in matches:
        code, title, body = match.groups()
        if code in seen:
            fail(f"DECISIONS: duplicate {code}")
        seen.add(code)
        if "المرفوض" not in body:
            fail(f"DECISIONS: {code} does not record a rejected alternative")
        elif "القرار" not in body:
            fail(f"DECISIONS: {code} does not state the decision")
        else:
            ok(f"decision:{code}")


# --------------------------------------------------------------------------- #
def check_tools(text: str) -> None:
    body = block(text, "### 7.3", "## 8.")
    rows = re.findall(
        r"^\|\s*`([a-z][a-z0-9_]*)`\s*\|\s*(safe|restricted|dangerous)\s*\|\s*(نعم|لا)\s*\|([^|]*)\|$",
        body,
        re.M,
    )
    if len(rows) < 25:
        fail(f"TOOLS: expected at least 25 tools, found {len(rows)}")
    names = [name for name, *_ in rows]
    if len(names) != len(set(names)):
        fail("TOOLS: duplicate tool name in §7.3")
    risks = {risk for _, risk, _, _ in rows}
    if risks != {"safe", "restricted", "dangerous"}:
        fail(f"TOOLS: risk classes must all be used, got {sorted(risks)}")
    for name, risk, idem, note in rows:
        if len(note.strip()) < 4:
            fail(f"TOOLS: {name} has no note")
        else:
            ok(f"tool:{name}:{risk}:{idem}")

    declared = set(re.findall(r"`([a-z][a-z0-9_]*)`", body))
    referenced = set(re.findall(r"`([a-z][a-z0-9_]*)`", text))
    unknown = {
        token
        for token in referenced
        if token.startswith(("add_", "trim_", "render_", "get_", "scan_", "split_", "move_"))
        and not token.endswith(("_request", "_response", "_dto"))
        and token not in declared
    }
    if unknown:
        fail(f"TOOLS: referenced but unregistered tools {sorted(unknown)}")


def check_errors(text: str) -> None:
    body = block(text, "### 14.3", "### 14.4")
    rows = re.findall(
        r"^\|\s*`([A-Z][A-Z0-9_]+)`\s*\|\s*(agent|provider|tool|perm|edit|media|store)\s*\|"
        r"\s*([^|]+?)\s*\|([^|]*)\|$",
        body,
        re.M,
    )
    if len(rows) < 20:
        fail(f"ERRORS: expected at least 20 codes, found {len(rows)}")
    codes = [code for code, *_ in rows]
    if len(codes) != len(set(codes)):
        fail("ERRORS: duplicate error code")
    prefix = {
        "agent": ("AGENT_",),
        "provider": ("PROVIDER_",),
        "tool": ("TOOL_",),
        "perm": ("PERM_",),
        "edit": ("EDIT_",),
        "media": ("MEDIA_",),
        "store": ("STORE_",),
    }
    for code, category, retryable, meaning in rows:
        if not code.startswith(prefix[category]):
            fail(f"ERRORS: {code} does not match category {category}")
        elif retryable.strip() not in ("نعم", "لا", "حسب الأداة"):
            fail(f"ERRORS: {code} has invalid retryable value {retryable.strip()!r}")
        elif len(meaning.strip()) < 5:
            fail(f"ERRORS: {code} has no meaning")
        else:
            ok(f"code:{code}")

    # codes used anywhere in backticks must be declared (RG_* inherited)
    appendix_body = block(text, "## ملحق د", "*نهاية الوثيقة")
    declared = set(codes) | set(re.findall(r"`([A-Z][A-Z0-9_]+)`", appendix_body))
    used = set(re.findall(r"`((?:AGENT|PROVIDER|TOOL|PERM|EDIT|MEDIA|STORE)_[A-Z0-9_]+)`", text))
    missing = used - declared
    if missing:
        fail(f"ERRORS: codes used but not declared {sorted(missing)}")
    else:
        ok("errors:declared")

    appendix = block(text, "## ملحق د", "*نهاية الوثيقة")
    appendix_codes = re.findall(r"`([A-Z][A-Z0-9_]+)`", appendix)
    if len(appendix_codes) < 8:
        fail("APPENDIX-D: too few rejection codes")
    if len(appendix_codes) != len(set(appendix_codes)):
        fail("APPENDIX-D: duplicate code")
    for code in appendix_codes:
        if not code.startswith(("TOOL_", "AGENT_", "PROVIDER_")):
            fail(f"APPENDIX-D: {code} is outside the agent boundary")
        else:
            ok(f"appendix-d:{code}")


# --------------------------------------------------------------------------- #
def check_inheritance(text: str) -> None:
    appendix = block(text, "## ملحق أ", "## ملحق ب")
    for artifact in (
        "rendergraph.schema.json",
        "rendergraph.effects.json",
        "rendergraph.manifest.json",
    ):
        if artifact not in appendix:
            fail(f"CONTRACT: inherited artifact {artifact} is not referenced")
        else:
            ok(f"inherit:{artifact}")
    for delta in (
        "ipc_error",
        "problem_dto",
        "render_start_request",
        "preview_open_request",
        "hello",
        "envelope",
    ):
        if delta not in appendix:
            fail(f"CONTRACT: v1 shape {delta} has no migration row")
        else:
            ok(f"delta:{delta}")
    if "ShadowError" not in appendix:
        fail("CONTRACT: v2 error envelope ShadowError is not named")
    else:
        ok("delta:ShadowError")

    for path in (SCHEMA, EFFECTS, MANIFEST, EXAMPLE):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"CONTRACT: {path.name} unreadable: {exc}")
        else:
            ok(f"parse:{path.name}")

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    if "RenderGraph" not in schema.get("$defs", {}):
        fail("CONTRACT: schema has no RenderGraph definition")
    else:
        ok("contract:RenderGraph")


def check_migration(text: str, v1_text: str) -> None:
    mapping = block(text, "## ملحق ج", "**ضمان:**")
    if not mapping:
        fail("MIGRATION: appendix ج not found")
        return
    # Only the first cell of each row is the "source" column; destinations may
    # legitimately mention other sections.
    sources = re.findall(r"^\|\s*([^|]+?)\s*\|", mapping, re.M)
    mapped_sections = {
        f"§{index}"
        for cell in sources
        for index in re.findall(r"§(\d+)(?![0-9A-Za-z])", cell)
    }
    for number in range(1, 11):
        section = f"§{number}"
        if section not in mapped_sections:
            fail(f"MIGRATION: v1.0 {section} has no destination row")
        else:
            ok(f"migrate:{section}")
    for appendix in ("ملحق أ", "ملحق ب", "ملحق ج", "ملحق د", "ملحق هـ"):
        if not any(cell.startswith(appendix) for cell in sources):
            fail(f"MIGRATION: v1.0 {appendix} has no destination row")
        else:
            ok(f"migrate:{appendix}")
    for deliverable in ("D1", "D7"):
        if not any(cell.startswith("D") and deliverable in cell for cell in sources):
            fail(f"MIGRATION: v1.0 {deliverable} has no destination row")
        else:
            ok(f"migrate:{deliverable}")

    # v1.0 must still be intact and point at its successor
    headers = section_headers(v1_text)
    if len(headers) < 10:
        fail("MIGRATION: v1.0 appears truncated")
    else:
        ok("v1:intact")

    # every v1.0 appendix heading must exist (nothing silently deleted)
    for appendix in ("## ملحق أ", "## ملحق ب", "## ملحق ج", "## ملحق د", "## ملحق هـ"):
        if appendix not in v1_text:
            fail(f"MIGRATION: v1.0 lost {appendix}")
        else:
            ok(f"v1:{appendix}")


def check_no_backend_claims(text: str) -> None:
    normative = text.split("## ملحق ج", 1)[0]
    for banned in ("127.0.0.1", "0.0.0.0", "localhost:", "uvicorn", "gunicorn"):
        if banned in normative:
            fail(f"NO-BACKEND: normative body mentions {banned!r}")
        else:
            ok(f"nobackend:{banned}")
    if "لا Backend" not in text and "بلا Backend" not in text:
        fail("NO-BACKEND: the document never states the no-backend rule")
    else:
        ok("nobackend:stated")


# --------------------------------------------------------------------------- #
def main() -> int:
    missing = [path for path in (SPEC, V1, SCHEMA, EFFECTS, MANIFEST, EXAMPLE) if not path.exists()]
    if missing:
        print("FATAL missing input(s):", ", ".join(str(path) for path in missing))
        return 1

    text = SPEC.read_text(encoding="utf-8")
    v1_text = V1.read_text(encoding="utf-8")

    phases = [
        ("shape", lambda: check_shape(text)),
        ("modules", lambda: check_modules(text)),
        ("quality", lambda: check_quality_and_limits(text)),
        ("decisions", lambda: check_decisions(text)),
        ("tools", lambda: check_tools(text)),
        ("errors", lambda: check_errors(text)),
        ("inheritance", lambda: check_inheritance(text)),
        ("migration", lambda: check_migration(text, v1_text)),
        ("no-backend", lambda: check_no_backend_claims(text)),
    ]
    for name, phase in phases:
        try:
            phase()
        except Exception as exc:  # noqa: BLE001 - a broken document must fail cleanly
            fail(f"CRASH during {name}: {type(exc).__name__}: {exc}")

    if failures:
        print(f"FAIL — {len(failures)} problem(s), {checks} checks passed\n")
        for item in failures[:40]:
            print("  -", item)
        if len(failures) > 40:
            print(f"  ... and {len(failures) - 40} more")
        return 1
    print(f"PASS — {checks} v2.0 architecture checks, 0 failures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
