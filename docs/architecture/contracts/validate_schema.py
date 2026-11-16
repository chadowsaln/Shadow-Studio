#!/usr/bin/env python3
"""Validate Appendix هـ: the field-level RenderGraph schema.

This is the gate that makes the engine contract buildable without inventing
types. It enforces a four-way equality:

    rendergraph.schema.json  ==  rendergraph.manifest.json (graph.*)
                             ==  example graph instances
                             ==  Appendix هـ prose + IDL
                             ==  rendergraph.effects.json (registry)

It also validates the three RenderGraph instances in the example against the
schema with a small, dependency-free JSON Schema 2020-12 subset ($ref, type,
const, enum, pattern, minimum, maximum, maxItems, maxLength, required,
properties, additionalProperties, items, anyOf).

The binding between a schema `$defs` entry and its manifest parent is explicit
in DEF_PARENT: adding a new object type requires declaring where it attaches,
which is exactly the review we want.
"""

from __future__ import annotations

import json
import re

DEF_PARENT = {
    "RenderGraph": "graph",
    "Timebase": "graph.timebase",
    "Profile": "graph.profile",
    "Track": "graph.tracks[]",
    "VideoClip": "graph.tracks[].clips[]",
    "Effect": "graph.tracks[].clips[].effects[]",
    "Transition": "graph.tracks[].transitions[]",
    "TextLayer": "graph.tracks[].text_layers[]",
    "AudioClip": "graph.tracks[].audio_clips[]",
    "Range": None,  # shared RangeV1
    "Transform": None,  # shared TransformV1
    "Param": None,  # shared ParamV1
    "Keyframe": None,  # shared KeyframeV1
}

SHARED_FOR_DEF = {
    "Range": "RangeV1",
    "Transform": "TransformV1",
    "Param": "ParamV1",
    "Keyframe": "KeyframeV1",
}

TYPE_MAP = {
    "int": "integer",
    "string": "string",
    "bool": "boolean",
    "array": "array",
    "object": "object",
}

UNIT_DEF = {
    "uuid": "UuidV7",
    "blake3_hex": "Blake3Hex",
    "file_uri": "FileUri",
    "rgba_hex": "RgbaHex",
}

NUMERIC_UNITS = {
    "ppm",
    "millibel",
    "luma_ppm",
    "ticks",
    "px",
    "count",
    "index",
    "hz",
    "ratio",
    "kbps",
    "lufs",
    "revision",
}

STRUCTURAL_UNITS = {"none", "enum", "collection", "transform", "range", "registry_key"}


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def deref(schema: dict, node: dict) -> dict:
    seen = 0
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if not ref.startswith("#/$defs/"):
            raise ValueError(f"unsupported $ref {ref}")
        node = schema["$defs"][ref.rsplit("/", 1)[-1]]
        seen += 1
        if seen > 8:
            raise ValueError(f"$ref cycle at {ref}")
    return node


def ref_name(node: dict) -> str | None:
    if isinstance(node, dict) and "$ref" in node:
        return node["$ref"].rsplit("/", 1)[-1]
    return None


def allows_null(node: dict) -> bool:
    if not isinstance(node, dict):
        return False
    if node.get("type") == "null":
        return True
    if isinstance(node.get("type"), list) and "null" in node["type"]:
        return True
    return any(branch.get("type") == "null" for branch in node.get("anyOf", []))


def non_null_branch(schema: dict, node: dict) -> dict:
    if "anyOf" in node:
        for branch in node["anyOf"]:
            if branch.get("type") != "null":
                return deref(schema, branch)
        return node
    return deref(schema, node)


def schema_type_names(schema: dict, node: dict) -> set[str]:
    if "anyOf" in node:
        names: set[str] = set()
        for branch in node["anyOf"]:
            if branch.get("type") == "null":
                continue
            names |= schema_type_names(schema, branch)
        return names
    node = deref(schema, node)
    declared = node.get("type")
    if isinstance(declared, str):
        return {declared}
    if isinstance(declared, list):
        return {item for item in declared if item != "null"}
    if "const" in node:
        return {_json_kind(node["const"])}
    if "enum" in node:
        return {_json_kind(value) for value in node["enum"]}
    return set()


def resolve_manifest_path(schema: dict, path: str) -> dict | None:
    """Resolve graph.tracks[].clips[].x inside the schema, or None."""
    parts = path.split(".")
    if parts[0] != "graph":
        return None
    node = deref(schema, schema["$defs"]["RenderGraph"])
    for part in parts[1:]:
        is_array = part.endswith("[]")
        name = part[:-2] if is_array else part
        node = deref(schema, node)
        properties = node.get("properties", {})
        if name not in properties:
            return None
        child = properties[name]
        if is_array:
            if "array" not in schema_type_names(schema, child):
                return None
            array_node = deref(schema, non_null_branch(schema, child))
            if "items" not in array_node:
                return None
            child = array_node["items"]
        node = child
    return node


def required_at(schema: dict, parent_path: str) -> set[str] | None:
    """Required field names of the schema object at a manifest parent path."""
    node = resolve_manifest_path(schema, parent_path) if parent_path != "graph" else None
    if node is None and parent_path == "graph":
        node = {"$ref": "#/$defs/RenderGraph"}
    if node is None:
        return None
    resolved = non_null_branch(schema, node)
    if "properties" not in resolved:
        return None
    return set(resolved.get("required", []))


def parent_def_for(path: str) -> str | None:
    best: str | None = None
    for name, parent in DEF_PARENT.items():
        if not parent:
            continue
        if path == parent or path.startswith(parent + "."):
            if best is None or len(parent) > len(DEF_PARENT[best] or ""):
                best = name
    return best


def manifest_row_set(manifest: dict) -> set[str]:
    return {row["path"] for row in manifest["paths"]}


# --------------------------------------------------------------------------- #
# 1. the schema itself
# --------------------------------------------------------------------------- #
def check_schema_shape(schema: dict, ok, fail) -> None:
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        fail("SCHEMA: $schema is not JSON Schema 2020-12")
    else:
        ok("schema-dialect")
    if not str(schema.get("$id", "")).startswith("https://"):
        fail("SCHEMA: $id must be an absolute https URI")
    else:
        ok("schema-id")

    defs = schema.get("$defs") or {}
    if not defs:
        fail("SCHEMA: no $defs")
        return
    ok(f"schema-defs:{len(defs)}")

    for name, node in defs.items():
        if "pattern" in node and not isinstance(node["pattern"], str):
            fail(f"SCHEMA: {name}.pattern is not a string")
        if "enum" in node:
            values = node["enum"]
            if not values or len(values) != len(set(values)):
                fail(f"SCHEMA: {name}.enum is empty or has duplicates")
            else:
                ok(f"enum:{name}")
        if node.get("type") != "object":
            continue
        if node.get("additionalProperties") is not False:
            fail(f"SCHEMA: {name} is not closed (additionalProperties != false)")
        else:
            ok(f"closed:{name}")
        required = set(node.get("required", []))
        properties = node.get("properties", {})
        if not required <= set(properties):
            fail(f"SCHEMA: {name}.required has unknown properties {sorted(required - set(properties))}")
        for prop, spec in properties.items():
            if "anyOf" in spec:
                if len(spec["anyOf"]) != 2 or not allows_null(spec):
                    fail(f"SCHEMA: {name}.{prop} anyOf must be exactly '<type> | null'")
                for branch in spec["anyOf"]:
                    target = ref_name(branch)
                    if target and target not in defs:
                        fail(f"SCHEMA: {name}.{prop} $ref to unknown def {target}")
            target = ref_name(spec)
            if target and target not in defs:
                fail(f"SCHEMA: {name}.{prop} $ref to unknown def {target}")
            if "array" in schema_type_names(schema, spec):
                array_node = deref(schema, non_null_branch(schema, spec))
                if "maxItems" not in array_node:
                    fail(f"SCHEMA: {name}.{prop} array has no maxItems (Appendix A.13 limit)")
                elif "items" not in array_node:
                    fail(f"SCHEMA: {name}.{prop} array has no items")
                else:
                    ok(f"array:{name}.{prop}")


# --------------------------------------------------------------------------- #
# 2. manifest <-> schema
# --------------------------------------------------------------------------- #
def check_manifest_binding(schema: dict, manifest: dict, ok, fail) -> None:
    required_by_def = {
        name: set(node.get("required", []))
        for name, node in schema["$defs"].items()
        if node.get("type") == "object"
    }
    all_paths = manifest_row_set(manifest)

    for row in manifest["paths"]:
        path = row["path"]
        if not path.startswith("graph."):
            continue
        raw = resolve_manifest_path(schema, path)
        if raw is None:
            fail(f"BIND: manifest path {path} has no schema property")
            continue
        resolved = non_null_branch(schema, raw)
        declared = schema_type_names(schema, raw)
        expected = TYPE_MAP.get(row["type"])
        if row["type"] == "variant":
            if not declared or not declared <= {"integer", "boolean", "string"}:
                fail(f"BIND: {path} variant must map to integer|boolean|string, got {sorted(declared)}")
                continue
            ok(path)
        elif expected is None:
            fail(f"BIND: unknown manifest type {row['type']} at {path}")
            continue
        elif expected not in declared:
            fail(f"BIND: {path} declared {row['type']} but schema says {sorted(declared)}")
            continue
        else:
            ok(path)

        leaf = path.rsplit(".", 1)[-1]
        required = required_at(schema, path.rsplit(".", 1)[0])
        if required is None:
            fail(f"BIND: cannot resolve the parent object of {path}")
            continue
        optional = leaf not in required
        if row.get("nullable"):
            if not allows_null(raw) and not optional:
                fail(f"BIND: {path} nullable in manifest but required and non-null in schema")
            else:
                ok(f"null:{path}")
        else:
            if optional:
                fail(f"BIND: {path} is mandatory in manifest but optional in schema")
            elif allows_null(raw):
                fail(f"BIND: {path} is mandatory and must not accept null")
            else:
                ok(f"req:{path}")

        unit = row.get("unit")
        if unit in UNIT_DEF:
            target = UNIT_DEF[unit]
            names = {ref_name(branch) for branch in raw.get("anyOf", []) if ref_name(branch)}
            names.add(ref_name(raw))
            if target not in names:
                fail(f"BIND: {path} unit {unit} must use $defs.{target}")
            else:
                ok(f"unit:{path}")
        elif unit in ("ppm", "millibel"):
            if "minimum" not in resolved or "maximum" not in resolved:
                fail(f"BIND: {path} unit {unit} needs minimum and maximum")
            else:
                ok(f"bound:{path}")
        elif unit in NUMERIC_UNITS:
            if (
                "minimum" not in resolved
                and "const" not in resolved
                and path not in ("graph.timebase.sample_rate",)
            ):
                fail(f"BIND: {path} numeric field has no minimum")
            else:
                ok(f"numeric:{path}")
        elif unit == "registry_key":
            if "pattern" not in resolved:
                fail(f"BIND: {path} registry key has no pattern")
            else:
                ok(f"pattern:{path}")
        elif unit not in STRUCTURAL_UNITS:
            fail(f"BIND: unhandled manifest unit {unit!r} at {path}")

    # reverse: every schema field is either a manifest row or a shared-type field
    for def_name, parent in DEF_PARENT.items():
        node = schema["$defs"].get(def_name)
        if not node or node.get("type") != "object":
            continue
        for prop in node.get("properties", {}):
            if parent is not None:
                expected_path = f"graph.{prop}" if parent == "graph" else f"{parent}.{prop}"
                # An object field may be listed either as its own manifest row
                # (graph.range) or only through its leaves (graph.timebase.*).
                if expected_path not in all_paths and not any(
                    path.startswith(expected_path + ".") for path in all_paths
                ):
                    fail(f"BIND: schema {def_name}.{prop} has no manifest row {expected_path}")
                else:
                    ok(f"rev:{def_name}.{prop}")
            else:
                shared = SHARED_FOR_DEF[def_name]
                fields = {entry["field"] for entry in manifest["shared_types"][shared]["fields"]}
                if prop not in fields:
                    fail(f"BIND: schema {def_name}.{prop} is not a {shared} field")
                else:
                    ok(f"rev:{def_name}.{prop}")


# --------------------------------------------------------------------------- #
# 3. Appendix text <-> schema (IDL, patterns, enums, registry)
# --------------------------------------------------------------------------- #
IDL_TYPE_RE = re.compile(r"^type (\w+) = \{\s*$")
IDL_FIELD_RE = re.compile(r"^  ([a-z][a-z0-9_]*)(\?)?: (.+);\s*(?://.*)?$")


def parse_idl(appendix: str, fail) -> dict[str, dict[str, bool]]:
    blocks = re.findall(r"```ts\n(.*?)```", appendix, re.S)
    blocks = [block for block in blocks if "Appendix هـ" in block]
    if not blocks:
        fail("DOC: no normative IDL block found in Appendix هـ")
        return {}
    types: dict[str, dict[str, bool]] = {}
    current: str | None = None
    for line in blocks[0].splitlines():
        match = IDL_TYPE_RE.match(line)
        if match:
            current = match.group(1)
            if current in types:
                fail(f"DOC: duplicate IDL type {current}")
            types[current] = {}
            continue
        if line.strip() == "};":
            current = None
            continue
        if current is None:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        match = IDL_FIELD_RE.match(line)
        if not match:
            fail(f"DOC: unparseable IDL line in {current}: {line!r}")
            continue
        types[current][match.group(1)] = match.group(2) == "?"
    return types


def check_appendix(schema: dict, effects: dict, manifest: dict, appendix: str, ok, fail) -> None:
    for section in range(1, 11):
        marker = f"### ه.{section} "
        if marker not in appendix:
            fail(f"DOC: missing section {marker.strip()}")
        else:
            ok(f"section:ه.{section}")

    types = parse_idl(appendix, fail)
    for def_name, node in schema["$defs"].items():
        if node.get("type") != "object":
            continue
        if def_name not in types:
            fail(f"DOC: IDL has no type {def_name}")
            continue
        properties = node.get("properties", {})
        required = set(node.get("required", []))
        if set(types[def_name]) != set(properties):
            missing = set(properties) - set(types[def_name])
            extra = set(types[def_name]) - set(properties)
            fail(f"DOC: IDL type {def_name}: missing={sorted(missing)} extra={sorted(extra)}")
            continue
        mismatched = [
            name for name, optional in types[def_name].items() if optional != (name not in required)
        ]
        if mismatched:
            fail(f"DOC: IDL {def_name} optionality mismatch for {mismatched}")
            continue
        ok(f"idl:{def_name}")

    for name, node in schema["$defs"].items():
        if "pattern" in node:
            if node["pattern"] not in appendix:
                fail(f"DOC: pattern of {name} is not quoted in Appendix هـ")
            else:
                ok(f"doc-pattern:{name}")
        for literal in node.get("enum", []):
            if isinstance(literal, str):
                present = f"`{literal}`" in appendix or f'"{literal}"' in appendix
            else:
                present = str(literal) in appendix
            if not present:
                fail(f"DOC: enum literal {literal!r} of {name} missing from Appendix هـ")
            else:
                ok(f"doc-enum:{name}:{literal}")

    param_types = set(effects["param_types"])
    for key, entry in effects["filters"].items():
        if not key.startswith("shadow."):
            fail(f"REGISTRY: filter {key} lacks the shadow. prefix (V-11)")
        for param, spec in entry["params"].items():
            if f"`{key}.{param}`" not in appendix:
                fail(f"REGISTRY: {key}.{param} is not documented in Appendix هـ")
            else:
                ok(f"registry:{key}.{param}")
            if spec["type"] not in param_types:
                fail(f"REGISTRY: {key}.{param} type {spec['type']} not in ParamV1 types")
            if spec["min"] > spec["max"]:
                fail(f"REGISTRY: {key}.{param} min > max")
            if max(abs(spec["min"]), abs(spec["max"])) > 1_000_000_000:
                fail(f"REGISTRY: {key}.{param} domain is implausibly large")

    for kind, entry in effects["transitions"].items():
        if kind not in schema["$defs"]["Transition"]["properties"]["kind"]["enum"]:
            fail(f"REGISTRY: transition {kind} not in the Transition.kind enum")
        else:
            ok(f"registry:transition:{kind}")
        if entry["capability"] and "semantics" not in entry:
            fail(f"REGISTRY: transition {kind} has no semantics")


# --------------------------------------------------------------------------- #
# 4. example instances against the schema
# --------------------------------------------------------------------------- #
def _json_kind(value) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if value is None:
        return "null"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def validate_instance(schema: dict, node: dict, instance, path: str, fail, ok) -> None:
    if "anyOf" in node:
        if any(not _branch_errors(schema, branch, instance, path) for branch in node["anyOf"]):
            ok(path)
            return
        fail(f"INSTANCE: {path} matches none of anyOf")
        return
    if "$ref" in node:
        validate_instance(schema, deref(schema, node), instance, path, fail, ok)
        return
    if "const" in node:
        if instance != node["const"] or type(instance) is not type(node["const"]):
            fail(f"INSTANCE: {path} must equal {node['const']!r}, got {instance!r}")
        else:
            ok(path)
        return
    if "enum" in node:
        if instance not in node["enum"]:
            fail(f"INSTANCE: {path} = {instance!r} not in enum")
        else:
            ok(path)
        return

    declared = node.get("type")
    if declared is not None:
        names = declared if isinstance(declared, list) else [declared]
        actual = _json_kind(instance)
        if actual == "integer" and "number" in names:
            pass
        elif actual not in names:
            fail(f"INSTANCE: {path} expected {names}, got {actual}")
            return
        else:
            ok(f"type:{path}")

    if isinstance(instance, str):
        if "pattern" in node and not re.search(node["pattern"], instance):
            fail(f"INSTANCE: {path} = {instance!r} does not match {node['pattern']}")
        if "maxLength" in node and len(instance) > node["maxLength"]:
            fail(f"INSTANCE: {path} is longer than {node['maxLength']}")
    if isinstance(instance, int) and not isinstance(instance, bool):
        if "minimum" in node and instance < node["minimum"]:
            fail(f"INSTANCE: {path} = {instance} < minimum {node['minimum']}")
        if "maximum" in node and instance > node["maximum"]:
            fail(f"INSTANCE: {path} = {instance} > maximum {node['maximum']}")
    if isinstance(instance, list):
        if "maxItems" in node and len(instance) > node["maxItems"]:
            fail(f"INSTANCE: {path} has {len(instance)} items > {node['maxItems']}")
        if "items" in node:
            for index, item in enumerate(instance):
                validate_instance(schema, node["items"], item, f"{path}[{index}]", fail, ok)
    if isinstance(instance, dict):
        properties = node.get("properties", {})
        for name in node.get("required", []):
            if name not in instance:
                fail(f"INSTANCE: {path} missing required field {name!r}")
        for name, value in instance.items():
            if name in properties:
                validate_instance(schema, properties[name], value, f"{path}.{name}", fail, ok)
            elif node.get("additionalProperties") is False:
                fail(f"INSTANCE: {path}.{name} is not declared (closed object)")


def _branch_errors(schema: dict, branch: dict, instance, path: str) -> list[str]:
    errors: list[str] = []
    node = deref(schema, branch) if "$ref" in branch else branch
    if "type" in node:
        names = node["type"] if isinstance(node["type"], list) else [node["type"]]
        if _json_kind(instance) not in names:
            return [f"{path}: expected {names}"]
    if "const" in node and instance != node["const"]:
        errors.append(f"{path}: != const")
    if "enum" in node and instance not in node["enum"]:
        errors.append(f"{path}: not in enum")
    if isinstance(instance, str) and "pattern" in node:
        if not re.search(node["pattern"], instance):
            errors.append(f"{path}: pattern")
    return errors


def check_example_instances(schema: dict, example: dict, effects: dict, ok, fail) -> None:
    instances = [
        ("graph", example.get("graph")),
        ("preview_open_request.graph", (example.get("preview_open_request") or {}).get("graph")),
        ("render_start_request.graph", (example.get("render_start_request") or {}).get("graph")),
    ]
    for name, instance in instances:
        if instance is None:
            fail(f"INSTANCE: {name} is absent from the example")
            continue
        local: list[str] = []

        def local_ok(_msg: str) -> None:
            return None

        def local_fail(msg: str) -> None:
            local.append(msg)

        validate_instance(
            schema, {"$ref": "#/$defs/RenderGraph"}, instance, name, local_fail, local_ok
        )
        if local:
            fail(f"INSTANCE: {name} violates the schema: {local[0]}")
        else:
            ok(f"instance:{name}")

    hello = example.get("hello_request") or {}
    caps = hello.get("capabilities") or {}
    filters = set(caps.get("filters") or [])
    transitions = set(caps.get("transitions") or [])
    registry_filters = set(effects["filters"])
    registry_transitions = {k for k, v in effects["transitions"].items() if v["capability"]}
    if filters != registry_filters:
        fail(f"REGISTRY: capabilities.filters {sorted(filters)} != {sorted(registry_filters)}")
    else:
        ok("registry:capability-filters")
    if transitions != registry_transitions:
        fail(
            f"REGISTRY: capabilities.transitions {sorted(transitions)} "
            f"!= {sorted(registry_transitions)}"
        )
    else:
        ok("registry:capability-transitions")

    graph = example.get("graph") or {}
    for track in graph.get("tracks", []):
        for clip in track.get("clips") or []:
            for effect in clip.get("effects") or []:
                key = effect.get("effect_key")
                entry = effects["filters"].get(key)
                if entry is None:
                    fail(f"REGISTRY: example uses unknown effect {key}")
                    continue
                for param in effect.get("params") or []:
                    spec = entry["params"].get(param.get("name"))
                    if spec is None:
                        fail(f"REGISTRY: {key} has no param {param.get('name')!r}")
                        continue
                    values = [param.get("value")] + [
                        kf.get("value") for kf in param.get("keyframes") or []
                    ]
                    for value in values:
                        if value is None:
                            continue
                        if spec["type"] in ("int", "ppm"):
                            if not isinstance(value, int) or isinstance(value, bool):
                                fail(f"REGISTRY: {key}.{param['name']} value {value!r} is not int")
                            elif not (spec["min"] <= value <= spec["max"]):
                                fail(
                                    f"REGISTRY: {key}.{param['name']} value {value} outside "
                                    f"{spec['min']}..{spec['max']}"
                                )
                            else:
                                ok(f"registry-value:{key}.{param['name']}:{value}")
        for transition in track.get("transitions") or []:
            kind = transition.get("kind")
            if kind not in effects["transitions"]:
                fail(f"REGISTRY: transition kind {kind!r} is not registered")
            elif not effects["transitions"][kind]["capability"]:
                fail("REGISTRY: example uses a transition kind the registry marks unavailable")
            else:
                ok(f"registry-transition:{kind}")


# --------------------------------------------------------------------------- #
# entry points
# --------------------------------------------------------------------------- #
def run(schema: dict, effects: dict, manifest: dict, example: dict, appendix: str, ok, fail) -> None:
    check_schema_shape(schema, ok, fail)
    check_manifest_binding(schema, manifest, ok, fail)
    check_appendix(schema, effects, manifest, appendix, ok, fail)
    check_example_instances(schema, example, effects, ok, fail)


def load_inputs() -> tuple[dict, dict, dict, dict, str]:
    from pathlib import Path

    here = Path(__file__).resolve().parent
    schema = json.loads((here / "rendergraph.schema.json").read_text(encoding="utf-8"))
    effects = json.loads((here / "rendergraph.effects.json").read_text(encoding="utf-8"))
    manifest = json.loads((here / "rendergraph.manifest.json").read_text(encoding="utf-8"))
    example = json.loads((here / "rendergraph.example.json").read_text(encoding="utf-8"))
    spec = (here.parent / "SOFTWARE-ARCHITECTURE-SPEC-v1.0.md").read_text(encoding="utf-8")
    appendix = spec[spec.index("## ملحق هـ") : spec.index("*نهاية الوثيقة")]
    return schema, effects, manifest, example, appendix


def main() -> int:
    schema, effects, manifest, example, appendix = load_inputs()
    failures: list[str] = []
    counts = {"ok": 0}

    def ok(_msg: str) -> None:
        counts["ok"] += 1

    def fail(msg: str) -> None:
        failures.append(msg)

    run(schema, effects, manifest, example, appendix, ok, fail)
    if failures:
        print(f"FAIL — {len(failures)} problem(s), {counts['ok']} checks passed\n")
        for item in failures[:40]:
            print("  -", item)
        if len(failures) > 40:
            print(f"  ... and {len(failures) - 40} more")
        return 1
    print(f"PASS — {counts['ok']} schema checks, 0 failures")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
