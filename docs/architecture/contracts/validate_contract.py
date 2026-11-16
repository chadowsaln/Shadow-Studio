#!/usr/bin/env python3
"""Validate the RenderGraph / boundary wire contract of SS-ARCH-001 Appendix A.

Checks performed (all must pass; exit code 1 on any failure):

  1. Types      — every declared path in rendergraph.manifest.json exists in the
                  example with the declared JSON type (null only when nullable),
                  and required fields are present in every parent instance.
  2. No extras  — the example contains no field that is not declared in the
                  manifest (primary paths or shared types).
  3. Semantics  — the invariants a Media Core must reject are exercised on the
                  example (ticks/second, fps, track order, overlap, keyframe
                  order, transition boundary, hashes, palette of enums).
  4. Doc sync   — every manifest path and shared-type field literally appears in
                  Appendix A, so the prose and the machine list cannot drift.
  5. DDL align  — every `table:column` token in Appendix A's alignment table
                  exists in the SQLite schema embedded in the spec, and the DDL
                  itself loads into sqlite3 with a clean integrity_check.
  6. No leakage — no key or enum-ish value smuggles an `mlt` service name.
  7. Schema     — Appendix هـ: rendergraph.schema.json agrees with the manifest,
                  the IDL block, the example instances and the effect registry
                  (delegated to validate_schema.py).

Usage: python3 docs/architecture/contracts/validate_contract.py
"""

from __future__ import annotations

import json
import re
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = HERE.parent / "SOFTWARE-ARCHITECTURE-SPEC-v1.0.md"
EXAMPLE = HERE / "rendergraph.example.json"
MANIFEST = HERE / "rendergraph.manifest.json"
SCHEMA = HERE / "rendergraph.schema.json"
EFFECTS = HERE / "rendergraph.effects.json"

failures: list[str] = []
checks = 0


def fail(msg: str) -> None:
    failures.append(msg)


def ok(msg: str) -> None:
    global checks
    checks += 1


# --------------------------------------------------------------------------- #
# path walking
# --------------------------------------------------------------------------- #
def split_pattern(pattern: str) -> list[str]:
    return pattern.split(".")


def walk(node, parts, concrete):
    """Yield (concrete_path, value) for every instance matching the pattern."""
    if not parts:
        yield ".".join(concrete), node
        return
    seg = parts[0]
    rest = parts[1:]
    is_arr = seg.endswith("[]")
    key = seg[:-2] if is_arr else seg
    if not isinstance(node, dict) or key not in node:
        return
    value = node[key]
    if is_arr:
        if not isinstance(value, list):
            return
        for item in value:
            yield from walk(item, rest, concrete + [f"{key}[]"])
    else:
        yield from walk(value, rest, concrete + [key])


def type_name(value) -> str:
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    return type(value).__name__


def type_ok(value, declared: str) -> bool:
    actual = type_name(value)
    if declared == "variant":
        return actual in {"int", "string", "bool", "float"}
    if declared in {"graph_ref", "object_open"}:
        return actual == "object"
    return actual == declared


def flatten(node, prefix="") -> list[str]:
    """Concrete paths of every leaf/object node (arrays keep the [] marker)."""
    out: list[str] = []
    if isinstance(node, dict):
        if not node:
            out.append(prefix + "{}")
        for key, value in node.items():
            child = f"{prefix}{key}"
            if isinstance(value, list):
                out.append(child + "[]")
                for item in value:
                    out.extend(flatten(item, child + "[]."))
            elif isinstance(value, dict):
                out.append(child)
                out.extend(flatten(value, child + "."))
            else:
                out.append(child)
    elif isinstance(node, list):
        out.append(prefix + "[]")
        for item in node:
            out.extend(flatten(item, prefix + "[]."))
    return out


# --------------------------------------------------------------------------- #
# 1 + 2: types, required-ness, undeclared fields
# --------------------------------------------------------------------------- #
def check_types(example, manifest) -> None:
    entries = manifest["paths"]
    for entry in entries:
        path, declared, nullable = entry["path"], entry["type"], entry["nullable"]
        parts = split_pattern(path)

        if nullable:
            matches = list(walk(example, parts, []))
            if not matches:
                continue  # legitimately absent (per-parent optional)
            for concrete, value in matches:
                if value is not None and not type_ok(value, declared):
                    fail(f"TYPE {concrete}: expected {declared}, got {type_name(value)}")
                else:
                    ok(concrete)
            continue

        parents = list(walk(example, parts[:-1], [])) if len(parts) > 1 else [("", example)]
        if not parents:
            fail(f"MISSING {path}: no parent instance in example")
            continue
        for parent_path, parent in parents:
            matches = list(walk(parent, [parts[-1]], []))
            if not matches:
                where = parent_path or "<root>"
                fail(f"MISSING {path}: absent under {where}")
                continue
            for concrete, value in matches:
                if value is None:
                    fail(f"NULL {concrete}: field is not nullable")
                elif not type_ok(value, declared):
                    fail(f"TYPE {concrete}: expected {declared}, got {type_name(value)}")
                else:
                    ok(concrete)


def declared_sets(manifest) -> tuple[set[str], list[re.Pattern]]:
    """Declared concrete paths (graph_ref prefixes expanded) + shared-type matchers.

    Concrete paths emitted by flatten() keep the literal `[]` marker, so the
    declarations are compared literally, not as index-bearing regexes.
    """
    declared: set[str] = set()
    for entry in manifest["paths"]:
        path = entry["path"]
        declared.add(path)
        if path.startswith("graph."):
            for root in ("preview_open_request.graph", "render_start_request.graph"):
                declared.add(root + path[len("graph"):])

    matchers: list[re.Pattern] = []
    for spec in manifest["shared_types"].values():
        for key in spec["applies_to_key"].split("|"):
            fields = "|".join(re.escape(f["field"]) for f in spec["fields"])
            # fields of the shared type, anywhere in the tree
            matchers.append(
                re.compile(r"(?:^|\.)" + re.escape(key) + r"(?:\[\])?\.(?:" + fields + r")$")
            )
            # the shared container itself (object or array of such objects)
            matchers.append(re.compile(r"(?:^|\.)" + re.escape(key) + r"(?:\[\])?$"))
    return declared, matchers


def check_no_extras(example, manifest) -> None:
    declared, matchers = declared_sets(manifest)

    prefixes: set[str] = set()
    for path in declared:
        parts = path.split(".")
        for i in range(1, len(parts)):
            prefixes.add(".".join(parts[:i]))

    # `object_open` = free-form map (diagnostics/context/options): children are
    # unconstrained by design, but the object itself must still be declared.
    open_objects = [e["path"] for e in manifest["paths"] if e["type"] == "object_open"]

    for path in flatten(example):
        if path.endswith("{}"):
            continue  # empty object placeholder
        base = path[:-2] if path.endswith("[]") else path
        if (
            path in declared
            or base in declared
            or path in prefixes
            or base in prefixes
            or any(path == o or path.startswith(o + ".") for o in open_objects)
            or any(m.search(path) or m.search(base) for m in matchers)
        ):
            ok(path)
        else:
            fail(f"UNDECLARED field in example: {path}")


# --------------------------------------------------------------------------- #
# 3: semantic invariants (the Appendix A.12 rejection rules)
# --------------------------------------------------------------------------- #
def iter_graphs(example):
    for root in ("graph", "preview_open_request.graph", "render_start_request.graph"):
        node = example
        for part in root.split("."):
            node = node.get(part) if isinstance(node, dict) else None
        if isinstance(node, dict):
            yield root, node


def sem(name: str, cond: bool, detail: str = "") -> None:
    if cond:
        ok(name)
    else:
        fail(f"SEMANTICS {name}: {detail}")


def n(node, key, default=0):
    """Numeric accessor that never raises: a missing/ill-typed field fails the
    single rule under test instead of aborting the whole phase."""
    value = node.get(key, default) if isinstance(node, dict) else default
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else default


def s(node, key, default="?"):
    value = node.get(key) if isinstance(node, dict) else None
    return value if isinstance(value, str) else default


def rows(node, key):
    value = node.get(key) if isinstance(node, dict) else None
    return [r for r in value if isinstance(r, dict)] if isinstance(value, list) else []


def obj(example, key):
    value = example.get(key)
    return value if isinstance(value, dict) else {}


def iso(value) -> bool:
    return isinstance(value, str) and bool(
        re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", value)
    )


JOB_STATES = {"queued", "running", "succeeded", "failed", "cancelled", "interrupted", "expired"}
TERMINAL = {"succeeded", "failed", "cancelled", "expired"}


def check_semantics_d(example) -> None:
    """Appendix D: IPC messages, project/import/asset, job lifecycle, AI, problem."""

    hello, ack = obj(example, "hello_request"), obj(example, "hello_ack")
    sem("d.hello_versions", 0 < n(hello, "protocol_version") and n(hello, "min_supported") <= n(hello, "protocol_version"))
    sem("d.hello_ack", ack.get("accepted") is True)
    caps = obj(hello, "capabilities")
    sem("d.hello_caps", all(rows(caps, k) or isinstance(caps.get(k), list) for k in ("filters", "transitions")))
    sem("d.hello_filter_ns", all(str(f).startswith("shadow.") for f in (caps.get("filters") or [])), str(caps.get("filters")))

    err = obj(example, "ipc_error")
    sem("d.ipc_error_category", s(err, "category", "") in {"protocol", "validation", "media", "engine", "resource", "internal"})
    sem("d.ipc_error_code_ns", re.match(r"^[A-Z]+_[A-Z_]+", s(err, "code", "")) is not None, s(err, "code"))

    probe = obj(example, "probe_result")
    sem("d.probe_duration", n(probe, "duration_ticks") > 0)
    sem("d.probe_hash", len(s(probe, "asset_hash", "")) == 64)
    streams = rows(probe, "streams")
    sem("d.probe_stream_index", [n(x, "index", -1) for x in streams] == list(range(len(streams))))
    for st in streams:
        mt = s(st, "media_type", "")
        sem("d.stream_type", mt in {"video", "audio", "subtitle", "data"}, mt)
        sem("d.stream_rotation", 0 <= n(st, "rotation", -1) <= 3)
        sem("d.stream_duration", n(st, "duration_ticks") > 0)
        if mt == "video":
            sem("d.stream_video_dims", n(st, "width") > 0 and n(st, "height") > 0 and n(st, "fps_num") > 0)
        if mt == "audio":
            sem("d.stream_audio_params", n(st, "sample_rate") > 0 and n(st, "channels") > 0)

    der = obj(example, "ensure_derived_request")
    sem("d.derived_cache", len(s(der, "cache_key", "")) == 64)
    sem("d.derived_kind", s(der, "kind", "") in {"proxy", "thumbnail", "sprite", "waveform", "text_raster"})
    sem("d.derived_priority", 0 <= n(der, "priority", -1) <= 9)
    if s(der, "kind", "") == "proxy":
        sem("d.derived_proxy_target", n(der, "target_width") > 0 and n(der, "target_height") > 0)

    jsr = obj(example, "job_status_result")
    sem("d.job_status_state", s(jsr, "state", "") in JOB_STATES, s(jsr, "state"))
    sem("d.job_status_progress", 0 <= n(jsr, "progress_ppm", -1) <= 1_000_000)
    sem("d.job_status_failed_error", s(jsr, "state", "") != "failed" or jsr.get("error_code") is not None)

    health = obj(example, "health_result")
    sem("d.health_jobs", n(health, "active_jobs", -1) >= 0)
    sem("d.health_protocol", n(health, "protocol_version") >= 1)

    proj = obj(example, "project_dto")
    pp = obj(proj, "profile")
    fps = n(pp, "fps_num") / n(pp, "fps_den") if n(pp, "fps_den") else 0
    sem("d.project_fps", 0 < fps <= 120, f"{fps}")
    sem("d.project_sample_rate", n(pp, "sample_rate") in {44100, 48000, 96000})
    sem("d.project_dims", n(pp, "width", 1) > 0 and n(pp, "width", 1) % 2 == 0 and n(pp, "height", 1) % 2 == 0)
    sem("d.project_sequences", n(proj, "sequence_count") >= 1)
    sem("d.project_timestamps", iso(proj.get("created_at")) and iso(proj.get("updated_at")))
    sem("d.project_revision", n(proj, "revision") >= 0)
    sem("d.project_schema", n(proj, "schema_version") >= 1)
    save = obj(example, "project_save_result")
    sem("d.project_save", iso(save.get("saved_at")) and n(save, "snapshot_bytes") > 0)

    imp = obj(example, "import_request")
    sem("d.import_paths", len(imp.get("paths") or []) >= 1)
    sem("d.import_proxy_policy", s(obj(imp, "options"), "proxy_policy", "") in {"auto", "never", "always"})
    acc = obj(example, "import_accepted")
    sem("d.import_batch", isinstance(acc.get("accepted"), list) and isinstance(acc.get("rejected"), list))
    sem("d.import_submitted", iso(acc.get("submitted_at")))
    for rej in rows(acc, "rejected"):
        sem("d.import_reject_code", s(rej, "code", "").startswith(("MEDIA_", "VALIDATION_")), s(rej, "code"))

    ist = obj(example, "import_status_dto")
    sem("d.import_state", s(ist, "state", "") in JOB_STATES, s(ist, "state"))
    sem("d.import_progress", 0 <= n(ist, "progress_ppm", -1) <= 1_000_000)
    for a in rows(ist, "assets"):
        sem("d.import_asset_status", s(a, "status", "") in {"probing", "derived_pending", "ready", "failed"}, s(a, "status"))
    sem(
        "d.import_finished_consistency",
        (s(ist, "state", "") in TERMINAL) == (ist.get("finished_at") is not None),
        f"state={s(ist, 'state')} finished_at={ist.get('finished_at')}",
    )

    asset = obj(example, "asset_dto")
    sem("d.asset_hash", len(s(asset, "source_hash", "")) == 64)
    sem("d.asset_duration", n(asset, "duration_ticks") > 0)
    sem("d.asset_imported", iso(asset.get("imported_at")))

    jsd = obj(example, "job_status_dto")
    sem("d.job_dto_state", s(jsd, "state", "") in JOB_STATES, s(jsd, "state"))
    sem("d.job_dto_progress", 0 <= n(jsd, "progress_ppm", -1) <= 1_000_000)
    sem("d.job_dto_terminal_finished", (s(jsd, "state", "") in TERMINAL) == (jsd.get("finished_at") is not None))
    sem(
        "d.job_dto_success_invariants",
        s(jsd, "state", "") != "succeeded"
        or (n(jsd, "progress_ppm", -1) == 1_000_000 and jsd.get("error_code") is None),
    )
    sem(
        "d.job_dto_failed_error",
        s(jsd, "state", "") != "failed" or jsd.get("error_code") is not None,
    )

    sub = obj(example, "subscribe_request")
    topics = sub.get("topics") or []
    sem("d.subscribe_topics", 1 <= len(topics) <= 16, str(topics))
    sem(
        "d.subscribe_known",
        set(topics) <= {"timeline", "project", "assets", "render.jobs", "ai.jobs", "ai.proposals", "engine"},
        str(topics),
    )

    ai = obj(example, "ai_submit_request")
    sem(
        "d.ai_capability",
        s(ai, "capability", "") in {"auto_cut", "captions", "audio_clean", "smart_reframe", "scene_detect", "transcribe"},
        s(ai, "capability"),
    )
    sem("d.ai_idempotency", len(s(ai, "idempotency_key", "")) == 64)
    for inp in rows(ai, "inputs"):
        k = s(inp, "kind", "")
        sem("d.ai_input_kind", k in {"asset_range", "text", "transcript"}, k)
        if k == "asset_range":
            sem(
                "d.ai_input_range",
                inp.get("asset_id") is not None
                and n(inp, "end_ticks") > n(inp, "start_ticks", -1),
                "asset_range incomplete",
            )
        if k == "text":
            sem("d.ai_input_text", len(s(inp, "text", "")) > 0)

    job = obj(example, "ai_job_dto")
    sem("d.ai_job_state", s(job, "state", "") in JOB_STATES, s(job, "state"))
    sem("d.ai_attempts", 1 <= n(job, "attempts") <= 3)
    sem("d.ai_progress_coarse", n(job, "progress_ppm", -1) in {0, 500_000, 1_000_000}, str(n(job, "progress_ppm", -1)))
    sem("d.ai_cost", job.get("cost_microusd") is None or n(job, "cost_microusd", -1) >= 0)
    sem("d.ai_timestamps", iso(job.get("created_at")) and iso(job.get("updated_at")))
    sem(
        "d.ai_error_pair",
        (job.get("error_code") is None) == (job.get("error_retryable") is None),
    )
    for art in rows(job, "artifacts"):
        sem("d.ai_artifact_kind", s(art, "kind", "") in {"audio", "image", "transcript", "scene_list"}, s(art, "kind"))

    prop = obj(example, "ai_proposal_dto")
    sem(
        "d.ai_proposal_kind",
        s(prop, "kind", "") in {"cuts", "captions", "audio_clean", "smart_reframe", "markers"},
        s(prop, "kind"),
    )
    sem("d.ai_proposal_range", n(prop, "preview_end_ticks") > n(prop, "preview_start_ticks", -1))
    sem("d.ai_proposal_ops", n(prop, "ops_count", -1) >= 0)
    sem("d.ai_proposal_base", n(prop, "base_revision") >= 0)

    res = obj(example, "ai_accept_result")
    sem("d.ai_accept_revision", n(res, "revision") > n(prop, "base_revision", -1))
    sem(
        "d.ai_accept_ops",
        n(res, "applied_ops") == n(prop, "ops_count", -1),
        f"{n(res, 'applied_ops')} vs {n(prop, 'ops_count', -1)}",
    )

    prob = obj(example, "problem_dto")
    sem("d.problem_status", 400 <= n(prob, "status", 0) <= 599, str(n(prob, "status", 0)))
    sem("d.problem_detail", len(s(prob, "detail", "")) > 0)
    sem("d.problem_code", s(prob, "code", "").isupper(), s(prob, "code"))


def check_semantics(example) -> None:
    for root, g in iter_graphs(example):
        tb = g.get("timebase") or {}
        sem(f"{root}.ticks_per_second", n(tb, "ticks_per_second") == 1_000_000, str(n(tb, "ticks_per_second")))
        fps = n(tb, "fps_num") / n(tb, "fps_den") if n(tb, "fps_den") else 0
        sem(f"{root}.fps_range", 0 < fps <= 120, f"{fps}")
        sem(f"{root}.schema", g.get("graph_schema") == "shadow.rendergraph/1", str(g.get("graph_schema")))

        rng = g.get("range") or {}
        start, dur = n(rng, "start_ticks"), n(rng, "duration_ticks")
        sem(f"{root}.range_positive", dur > 0, str(dur))
        range_end = start + dur

        tracks = rows(g, "tracks")
        positions = [n(t, "position", -1) for t in tracks]
        sem(f"{root}.track_positions", sorted(positions) == list(range(len(positions))), str(positions))

        for track in tracks:
            kind = track.get("kind")
            expected_field = {"video": "clips", "audio": "audio_clips", "overlay": "text_layers"}.get(kind)
            sem(
                f"{root}.{s(track, 'name')}.kind_field",
                expected_field is not None and isinstance(track.get(expected_field), list),
                f"kind={kind}",
            )

            clips = rows(track, "clips")
            intervals = sorted((n(c, "timeline_start_ticks"), n(c, "duration_ticks"), s(c, "id")) for c in clips)
            for i in range(len(intervals) - 1):
                begin, length, cid = intervals[i]
                nxt = intervals[i + 1][0]
                sem(f"{root}.{cid}.no_overlap", begin + length <= nxt, f"ends {begin + length} > next {nxt}")

            for c in clips:
                cid = s(c, "id")
                begin, length = n(c, "timeline_start_ticks"), n(c, "duration_ticks")
                sem(f"{root}.{cid}.duration", length > 0, str(length))
                sem(f"{root}.{cid}.in_range", begin >= start and begin + length <= range_end, "clip outside range")
                sem(f"{root}.{cid}.speed", n(c, "speed_num") > 0 and n(c, "speed_den") > 0, "speed")
                sem(f"{root}.{cid}.opacity", 0 <= n(c, "opacity_ppm", -1) <= 1_000_000, str(n(c, "opacity_ppm", -1)))
                kind_c, uri, digest = c.get("kind"), c.get("source_uri"), c.get("source_hash")
                sem(
                    f"{root}.{cid}.source_fields",
                    (kind_c == "color" and uri is None)
                    or (isinstance(uri, str) and isinstance(digest, str)),
                    f"kind={kind_c}",
                )
                if isinstance(digest, str):
                    sem(f"{root}.{cid}.hash_len", len(digest) == 64, str(len(digest)))

                tr = c.get("transform") or {}
                sem(
                    f"{root}.{cid}.transform",
                    0 <= n(tr, "rotation_quarter_turns", -1) <= 3
                    and n(tr, "scale_x_ppm") > 0
                    and n(tr, "scale_y_ppm") > 0
                    and s(tr, "anchor") in {"top_left", "center"},
                    "transform bounds",
                )

                for eff in rows(c, "effects"):
                    eid, key = s(eff, "id"), s(eff, "effect_key", "")
                    sem(
                        f"{root}.{cid}.{eid}.effect_key",
                        key.startswith("shadow.") and "mlt" not in key.lower(),
                        key,
                    )
                    params = rows(eff, "params")
                    names = [s(p, "name") for p in params]
                    sem(f"{root}.{cid}.{eid}.param_unique", len(names) == len(set(names)), str(names))
                    for p in params:
                        pname = s(p, "name")
                        sem(
                            f"{root}.{cid}.{pname}.param_type",
                            s(p, "type", "") in {"int", "ppm", "color", "enum", "string", "bool"},
                            s(p, "type"),
                        )
                        kfs = rows(p, "keyframes")
                        ats = [n(k, "at_ticks", -1) for k in kfs]
                        sem(f"{root}.{cid}.{pname}.keyframe_order", ats == sorted(set(ats)), str(ats))
                        for k in kfs:
                            at = n(k, "at_ticks", -1)
                            sem(
                                f"{root}.{cid}.{pname}.keyframe_bounds",
                                begin <= at < begin + length,
                                str(at),
                            )
                            sem(
                                f"{root}.{cid}.{pname}.easing",
                                s(k, "easing", "") in {"linear", "ease_in", "ease_out", "ease_in_out", "step"},
                                s(k, "easing"),
                            )

            by_id = {s(c, "id"): c for c in clips}
            for trans in rows(track, "transitions"):
                tid = s(trans, "id")
                frm = by_id.get(s(trans, "from_clip_id", ""))
                to = by_id.get(s(trans, "to_clip_id", ""))
                at = n(trans, "at_ticks", -1)
                sem(
                    f"{root}.{tid}.boundary",
                    frm is not None
                    and to is not None
                    and at == n(frm, "timeline_start_ticks") + n(frm, "duration_ticks")
                    and n(to, "timeline_start_ticks", -1) == at,
                    "transition not on clip boundary",
                )
                if frm is not None and to is not None:
                    shortest = min(n(frm, "duration_ticks"), n(to, "duration_ticks"))
                    sem(
                        f"{root}.{tid}.duration",
                        0 < n(trans, "duration_ticks") <= shortest / 2,
                        f"{n(trans, 'duration_ticks')} vs {shortest}",
                    )
                sem(
                    f"{root}.{tid}.kind",
                    s(trans, "kind", "") in {"crossfade", "dissolve", "wipe_left", "wipe_right", "fade_black"},
                    s(trans, "kind"),
                )

            for layer in rows(track, "text_layers"):
                lid = s(layer, "id")
                rh = s(layer, "raster_hash", "")
                sem(f"{root}.{lid}.raster_hash", len(rh) == 64, rh[:8])
                sem(
                    f"{root}.{lid}.raster_dim",
                    n(layer, "raster_width") > 0 and n(layer, "raster_height") > 0,
                    "dims",
                )
                anim_in = layer.get("animation_in") or {}
                anim_out = layer.get("animation_out") or {}
                sem(
                    f"{root}.{lid}.duration",
                    n(layer, "duration_ticks") > 0
                    and n(anim_in, "duration_ticks") + n(anim_out, "duration_ticks") <= n(layer, "duration_ticks"),
                    "animation longer than layer",
                )

            for ac in rows(track, "audio_clips"):
                aid = s(ac, "id")
                sem(f"{root}.{aid}.gain", -60000 <= n(ac, "gain_mb", -99999) <= 24000, str(n(ac, "gain_mb", -99999)))
                sem(
                    f"{root}.{aid}.fades",
                    n(ac, "fade_in_ticks") + n(ac, "fade_out_ticks") <= n(ac, "duration_ticks"),
                    "fades",
                )
                sem(
                    f"{root}.{aid}.in_range",
                    n(ac, "timeline_start_ticks") >= start
                    and n(ac, "timeline_start_ticks") + n(ac, "duration_ticks") <= range_end,
                    "audio clip outside range",
                )

    for req_name in ("render_start_request", "render_http_request"):
        preset = (example.get(req_name) or {}).get("preset") or {}
        sem(
            f"{req_name}.preset_conflict",
            not (preset.get("crf") is not None and preset.get("video_bitrate_kbps") is not None),
            "crf+bitrate",
        )
        sem(f"{req_name}.container", s(preset, "container", "") in {"mp4", "webm", "wav", "mp3", "gif"}, s(preset, "container"))
        sem(
            f"{req_name}.codec_for_container",
            preset.get("video_codec") is not None or preset.get("audio_codec") is not None,
            "no codec at all",
        )


# --------------------------------------------------------------------------- #
# 4 + 5 + 6: document sync, DDL alignment, left-over leakage
# --------------------------------------------------------------------------- #
def appendix_text(spec: str) -> str:
    start = spec.index("## ملحق أ — عقد RenderGraph")
    end = spec.index("## ملحق ب — قاموس سريع")
    return spec[start:end], spec[start:]


def check_doc_sync(manifest, appendix: str) -> None:
    for entry in manifest["paths"]:
        if f"`{entry['path']}`" not in appendix:
            fail(f"DOC appendix does not document path {entry['path']}")
        else:
            ok(entry["path"])
    for name, spec in manifest["shared_types"].items():
        for field in spec["fields"]:
            token = f"`{name}.{field['field']}`"
            if token not in appendix:
                fail(f"DOC appendix does not document shared field {name}.{field['field']}")
            else:
                ok(token)


def parse_ddl(spec: str) -> dict[str, set[str]]:
    blocks = re.findall(r"```sql\n(.*?)```", spec, re.S)
    ddl = max(blocks, key=len)
    tables: dict[str, set[str]] = {}
    for name, body in re.findall(r"CREATE TABLE (\w+) \((.*?)\n\) STRICT;", ddl, re.S):
        cols: set[str] = set()
        for line in body.splitlines():
            code = line.split("--")[0]
            if not code.strip() or not code.startswith("  "):
                continue
            for chunk in code.split(","):
                m = re.match(r"^\s+(\w+)\s+", chunk)
                if m:
                    cols.add(m.group(1))
        tables[name] = cols
    return tables


def check_ddl_alignment(spec: str, appendix: str) -> None:
    tables = parse_ddl(spec)
    if len(tables) < 15:
        fail(f"DDL parse produced only {len(tables)} tables")
    ok("ddl-parsed")

    # every `table:column` token in the appendix must exist
    tokens = set(re.findall(r"`([a-z_][a-z0-9_]*):([a-z_][a-z0-9_]*)`", appendix))
    if not tokens:
        fail("DDL ALIGNMENT: no `table:column` tokens found in appendix")
    for table, column in sorted(tokens):
        if table not in tables:
            fail(f"DDL ALIGNMENT: unknown table {table}")
        elif column not in tables[table]:
            fail(f"DDL ALIGNMENT: {table} has no column {column}")
        else:
            ok(f"{table}:{column}")

    # the contract's graph roots must all appear in the alignment table
    alignment = appendix.split("جدول التطابق", 1)[-1].split("قواعد إسقاط ملزمة", 1)[0]
    for root_field in (
        "graph_schema",
        "sequence_id",
        "project_revision",
        "timebase",
        "profile",
        "range",
        "background_rgba",
        "tracks",
    ):
        if root_field not in alignment:
            fail(f"DDL ALIGNMENT: root field {root_field} has no row in alignment table")
        else:
            ok(f"align:{root_field}")

    # the DDL itself must load
    if sqlite3.sqlite_version_info < (3, 37):
        fail(f"sqlite {sqlite3.sqlite_version} too old for STRICT tables")
        return
    conn = sqlite3.connect(":memory:")
    try:
        blocks = re.findall(r"```sql\n(.*?)```", spec, re.S)
        conn.executescript(max(blocks, key=len))
        conn.execute("PRAGMA foreign_keys = ON")
        result = conn.execute("PRAGMA integrity_check").fetchone()[0]
        if result != "ok":
            fail(f"DDL integrity_check: {result}")
        else:
            ok("ddl-integrity")
        count = conn.execute(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ).fetchone()[0]
        if count != 18:
            fail(f"DDL table count {count} != 18")
        else:
            ok("ddl-table-count")
    except sqlite3.Error as exc:  # noqa: BLE001 - surface engine error verbatim
        fail(f"DDL did not load: {exc}")
    finally:
        conn.close()


def check_schema(spec: str, example, manifest) -> None:
    """Appendix هـ: the field-level schema must agree with everything else."""
    import validate_schema  # same directory

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    effects = json.loads(EFFECTS.read_text(encoding="utf-8"))
    appendix = spec[spec.index("## ملحق هـ") : spec.index("*نهاية الوثيقة")]
    validate_schema.run(schema, effects, manifest, example, appendix, ok, fail)


def check_no_leakage(example) -> None:
    def walkall(node, path=""):
        if isinstance(node, dict):
            for key, value in node.items():
                if "mlt" in key.lower():
                    fail(f"LEAK key {path}.{key} mentions mlt")
                else:
                    ok(f"key:{key}")
                walkall(value, f"{path}.{key}")
        elif isinstance(node, list):
            for item in node:
                walkall(item, path + "[]")
        elif isinstance(node, str):
            # engine_version is an opaque build string for diagnostics only; it
            # may name the engine, but no behavioural field may select on it.
            if "mlt" in node.lower() and not path.endswith("engine_version"):
                fail(f"LEAK value {path} = {node!r}")

    walkall(example)


# --------------------------------------------------------------------------- #
def main() -> int:
    for required in (SPEC, EXAMPLE, MANIFEST):
        if not required.exists():
            print(f"FATAL missing input: {required}")
            return 1

    example = json.loads(EXAMPLE.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    spec = SPEC.read_text(encoding="utf-8")
    appendix, appendix_tail = appendix_text(spec)

    phases = [
        ("types", lambda: check_types(example, manifest)),
        ("no-extras", lambda: check_no_extras(example, manifest)),
        ("semantics", lambda: check_semantics(example)),
        ("semantics-d", lambda: check_semantics_d(example)),
        ("doc-sync", lambda: check_doc_sync(manifest, appendix_tail)),
        ("ddl-alignment", lambda: check_ddl_alignment(spec, appendix_tail)),
        ("leakage", lambda: check_no_leakage(example)),
        ("schema", lambda: check_schema(spec, example, manifest)),
    ]
    for name, phase in phases:
        try:
            phase()
        except Exception as exc:  # noqa: BLE001 - a broken example must fail cleanly, not crash
            fail(f"CRASH during {name}: {type(exc).__name__}: {exc}")

    if failures:
        print(f"FAIL — {len(failures)} problem(s), {checks} checks passed\n")
        for item in failures[:40]:
            print("  -", item)
        if len(failures) > 40:
            print(f"  ... and {len(failures) - 40} more")
        return 1

    print(f"PASS — {checks} contract checks, 0 failures")
    print(f"       example={EXAMPLE.name} manifest={MANIFEST.name} paths={len(manifest['paths'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
