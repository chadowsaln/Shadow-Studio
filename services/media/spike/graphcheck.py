"""Validate a RenderGraph against the Appendix A field manifest.

This is deliberately *manifest-driven*: every field, type and nullability comes
from `docs/architecture/contracts/rendergraph.manifest.json`, so a graph that
passes here is a graph the pinned contract describes. Semantic rules from
§A.12 that are checkable without media are implemented below; media-dependent
rules (V-09, V-15) run when `sources` / `rasters` are supplied.

What this module is not: a replacement for the 2,151-check contract validator.
That validates the *documents*; this validates a concrete graph instance.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from common import (
    MANIFEST_PATH,
    SpikeError,
    TICKS_PER_SECOND,
    blake3_file,
    uri_to_path,
)

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
RGBA_RE = re.compile(r"^#[0-9A-Fa-f]{8}$")

MAX_TRACKS = 32
MAX_CLIPS_PER_TRACK = 2000
MAX_EFFECTS_PER_CLIP = 16
MAX_PARAMS_PER_EFFECT = 32
MAX_KEYFRAMES_PER_PARAM = 240
MAX_TEXT_LAYERS = 200
MAX_RANGE_TICKS = 6 * 3600 * TICKS_PER_SECOND
MAX_GRAPH_BYTES = 4 * 1024 * 1024

TRACK_KIND_FIELDS = {
    "video": ("clips", "transitions"),
    "overlay": ("text_layers",),
    "audio": ("audio_clips", "transitions"),
}

EASINGS = {"linear", "ease_in", "ease_out", "ease_in_out", "step"}
TRANSITION_KINDS = {"crossfade", "dissolve", "wipe_left", "wipe_right", "fade_black"}


# --------------------------------------------------------------------------- #
# Schema tree built from the manifest
# --------------------------------------------------------------------------- #


class Field:
    """One manifest row (path suffix already stripped to `graph`)."""

    __slots__ = ("type", "unit", "nullable", "shared_type")

    def __init__(self, row: dict) -> None:
        self.type = row["type"]
        self.unit = row.get("unit", "none")
        self.nullable = bool(row.get("nullable", False))
        self.shared_type = None


def _new_node(kind: str) -> dict:
    return {"kind": kind}


def _insert(node: dict, segments: list[tuple[str, bool]], row: dict) -> None:
    for index, (name, is_array) in enumerate(segments):
        last = index == len(segments) - 1
        fields = node.setdefault("fields", {})
        if is_array:
            field = fields.setdefault(name, {"kind": "array", "items": _new_node("object")})
            if last:
                field["field"] = Field(row)
                return
            node = field["items"]
        elif last:
            fields[name] = {"kind": "leaf", "field": Field(row)}
            return
        else:
            node = fields.setdefault(name, _new_node("object"))


def _shared_node(manifest: dict, name: str) -> dict:
    spec = manifest["shared_types"][name]
    node = _new_node("object")
    node["shared"] = name
    for entry in spec["fields"]:
        field = Field(
            {
                "type": entry["type"],
                "unit": entry.get("unit", "none"),
                "nullable": entry.get("nullable", False),
            }
        )
        if entry["type"] == "array":
            items = _new_node("object")
            # `keyframes` inside ParamV1 has its own shared type; resolved later.
            node.setdefault("fields", {})[entry["field"]] = {
                "kind": "array",
                "items": items,
                "field": field,
            }
        elif entry["type"] == "object":
            node.setdefault("fields", {})[entry["field"]] = {
                "kind": "object",
                "fields": {},
                "field": field,
            }
        else:
            node.setdefault("fields", {})[entry["field"]] = {
                "kind": "leaf",
                "field": field,
            }
    return node


def build_graph_schema(manifest: dict) -> dict:
    root = _new_node("object")
    rows = [row for row in manifest["paths"] if row["path"].startswith("graph.")]
    for row in rows:
        segments = []
        for segment in row["path"].split(".")[1:]:
            is_array = segment.endswith("[]")
            segments.append((segment[:-2] if is_array else segment, is_array))
        _insert(root, segments, row)

    # Expand shared types referenced by unit or by well-known key.
    def expand(node: dict) -> None:
        for name, field in list(node.get("fields", {}).items()):
            if field["kind"] == "array":
                unit = field.get("field").unit if field.get("field") else None
                if name == "params":
                    field["items"] = _shared_node(manifest, "ParamV1")
                elif name == "keyframes":
                    field["items"] = _shared_node(manifest, "KeyframeV1")
                elif name == "streams":
                    field["items"] = _shared_node(manifest, "ProbeStreamV1")
                expand(field["items"])
            elif field["kind"] == "object":
                unit = field.get("field").unit if field.get("field") else None
                if unit in manifest["shared_types"]:
                    field.clear()
                    field.update(_shared_node(manifest, unit))
                expand(field)
            elif field["kind"] == "leaf":
                unit = field["field"].unit
                if unit == "transform":
                    field.clear()
                    field.update(_shared_node(manifest, "TransformV1"))
                elif unit == "range":
                    field.clear()
                    field.update(_shared_node(manifest, "RangeV1"))

    expand(root)
    return root


def load_schema() -> dict:
    return build_graph_schema(json.loads(MANIFEST_PATH.read_text(encoding="utf-8")))


# --------------------------------------------------------------------------- #
# Structural validation
# --------------------------------------------------------------------------- #


def _check_unit(unit: str, value, path: str, errors: list[SpikeError]) -> None:
    if not isinstance(value, str):
        return
    if unit == "uuid" and not UUID_RE.match(value):
        errors.append(SpikeError("RG_FIELD_FORMAT", f"not a uuidv7: {value!r}", path))
    elif unit == "blake3_hex" and not HEX64_RE.match(value):
        errors.append(SpikeError("RG_FIELD_FORMAT", f"not 64 lowercase hex: {value!r}", path))
    elif unit == "rgba_hex" and not RGBA_RE.match(value):
        errors.append(SpikeError("RG_FIELD_FORMAT", f"not #RRGGBBAA: {value!r}", path))
    elif unit == "file_uri" and not value.startswith("file://"):
        errors.append(SpikeError("RG_FIELD_FORMAT", f"not a file:// URI: {value!r}", path))


def _check_ranges(node: dict, value, path: str, errors: list[SpikeError]) -> None:
    for name, field in node.get("fields", {}).items():
        if field["kind"] != "leaf" or not isinstance(value, dict):
            continue
        field_spec: Field = field["field"]
        if name not in value or value[name] is None:
            continue
        item = value[name]
        if field_spec.unit == "ppm" and not (0 <= item <= 1_000_000):
            errors.append(SpikeError("RG_FIELD_RANGE", f"ppm out of 0..1e6: {item}", f"{path}.{name}"))
        elif field_spec.unit == "millibel" and not (-60_000 <= item <= 24_000):
            errors.append(
                SpikeError("RG_FIELD_RANGE", f"millibel out of -60000..24000: {item}", f"{path}.{name}")
            )
        elif field_spec.unit == "px" and item < 0:
            errors.append(SpikeError("RG_FIELD_RANGE", f"negative px: {item}", f"{path}.{name}"))


def _walk(node: dict, value, path: str, errors: list[SpikeError]) -> None:
    if value is None:
        return
    kind = node["kind"]
    if kind == "leaf":
        field_spec: Field = node["field"]
        expected = field_spec.type
        ok = {
            "int": isinstance(value, int) and not isinstance(value, bool),
            "bool": isinstance(value, bool),
            "string": isinstance(value, str),
            "object": isinstance(value, dict),
            "array": isinstance(value, list),
            "variant": True,
        }.get(expected, True)
        if not ok:
            errors.append(
                SpikeError("RG_FIELD_TYPE", f"expected {expected}, got {type(value).__name__}", path)
            )
            return
        _check_unit(field_spec.unit, value, path, errors)
        return
    if kind == "array":
        if not isinstance(value, list):
            errors.append(SpikeError("RG_FIELD_TYPE", "expected array", path))
            return
        for index, item in enumerate(value):
            _walk(node["items"], item, f"{path}[]", errors)
        return
    if not isinstance(value, dict):
        errors.append(SpikeError("RG_FIELD_TYPE", "expected object", path))
        return
    fields = node.get("fields", {})
    for name, field in fields.items():
        field_spec = field.get("field")
        if name not in value:
            if field_spec is not None and not field_spec.nullable:
                errors.append(SpikeError("RG_FIELD_MISSING", "required field absent", f"{path}.{name}"))
            continue
        item = value[name]
        if item is None and not field_spec.nullable:
            errors.append(SpikeError("RG_FIELD_NULL", "null in a non-nullable field", f"{path}.{name}"))
            continue
        _walk(field, item, f"{path}.{name}", errors)
    for name in value:
        if name not in fields:
            hint = " (MLT leakage)" if name.startswith("mlt") else ""
            errors.append(SpikeError("RG_UNKNOWN_FIELD", f"undeclared field {name!r}{hint}", f"{path}.{name}"))
    _check_ranges(node, value, path, errors)


# --------------------------------------------------------------------------- #
# Semantic rules (§A.12)
# --------------------------------------------------------------------------- #


def _validate_effect(effect: dict, path: str, registry: dict, errors: list[SpikeError]) -> None:
    key = effect.get("effect_key", "")
    spec = registry["filters"].get(key)
    if not key.startswith("shadow.") or spec is None:
        errors.append(SpikeError("RG_UNKNOWN_EFFECT", f"unknown effect {key!r}", f"{path}.effect_key"))
        return
    params = effect.get("params") or []
    if len(params) > MAX_PARAMS_PER_EFFECT:
        errors.append(SpikeError("RG_LIMITS", f"{len(params)} params > {MAX_PARAMS_PER_EFFECT}", path))
    known = spec["params"]
    for index, param in enumerate(params):
        name = param.get("name")
        definition = known.get(name)
        if definition is None:
            errors.append(
                SpikeError("RG_UNKNOWN_PARAM", f"{key} has no param {name!r}", f"{path}.params[{index}]")
            )
            continue
        expected_type = definition["type"]
        if param.get("type") != expected_type:
            errors.append(
                SpikeError(
                    "RG_UNKNOWN_PARAM",
                    f"param {name!r} declared {param.get('type')!r}, registry says {expected_type!r}",
                    f"{path}.params[{index}]",
                )
            )
        keyframes = param.get("keyframes") or []
        if len(keyframes) > MAX_KEYFRAMES_PER_PARAM:
            errors.append(SpikeError("RG_LIMITS", "too many keyframes", f"{path}.params[{index}]"))
        previous = None
        for kf_index, kf in enumerate(keyframes):
            at = kf.get("at_ticks")
            if at is None:
                continue
            if previous is not None and at <= previous:
                errors.append(
                    SpikeError(
                        "RG_KEYFRAME_ORDER",
                        f"at_ticks {at} is not strictly after {previous}",
                        f"{path}.params[{index}].keyframes[{kf_index}]",
                    )
                )
            previous = at
            if kf.get("easing") not in EASINGS:
                errors.append(
                    SpikeError(
                        "RG_KEYFRAME_ORDER",
                        f"unknown easing {kf.get('easing')!r}",
                        f"{path}.params[{index}].keyframes[{kf_index}]",
                    )
                )
        if param.get("value") is not None and expected_type == "ppm":
            value = param["value"]
            if not (0 <= value <= 1_000_000):
                errors.append(
                    SpikeError("RG_FIELD_RANGE", f"ppm param out of 0..1e6: {value}", f"{path}.params[{index}]")
                )


def check_semantics(
    graph: dict,
    *,
    registry: dict,
    sources: dict[str, dict] | None = None,
    rasters: dict[str, dict] | None = None,
) -> list[SpikeError]:
    errors: list[SpikeError] = []

    if graph.get("graph_schema") != "shadow.rendergraph/1":
        return [SpikeError("RG_SCHEMA_VERSION", "graph_schema must be shadow.rendergraph/1", "graph_schema")]

    timebase = graph.get("timebase") or {}
    fps_num = timebase.get("fps_num", 0)
    fps_den = timebase.get("fps_den", 0)
    if timebase.get("ticks_per_second") != TICKS_PER_SECOND:
        errors.append(SpikeError("RG_TIMEBASE_INVALID", "ticks_per_second must be 1000000"))
    if fps_num <= 0 or fps_den <= 0 or fps_num / fps_den > 120:
        errors.append(SpikeError("RG_TIMEBASE_INVALID", "fps must be > 0 and <= 120"))
    if timebase.get("sample_rate") not in (44100, 48000, 96000):
        errors.append(SpikeError("RG_TIMEBASE_INVALID", "sample_rate not in 44100/48000/96000"))
    channels = timebase.get("channels")
    if not isinstance(channels, int) or not (1 <= channels <= 8):
        errors.append(SpikeError("RG_TIMEBASE_INVALID", "channels must be 1..8"))

    profile = graph.get("profile") or {}
    width, height = profile.get("width"), profile.get("height")
    if profile.get("interlaced"):
        errors.append(SpikeError("RG_UNSUPPORTED_PROFILE", "interlaced=true is rejected in v1"))
    if profile.get("pixel_format") == "yuv420p" and (
        isinstance(width, int) and isinstance(height, int) and (width % 2 or height % 2)
    ):
        errors.append(SpikeError("RG_UNSUPPORTED_PROFILE", "odd dimensions with yuv420p"))
    if profile.get("color_space") not in ("bt709", "bt2020", "srgb"):
        errors.append(SpikeError("RG_UNSUPPORTED_PROFILE", "unknown color_space"))

    rng = graph.get("range") or {}
    start = rng.get("start_ticks", 0)
    duration = rng.get("duration_ticks", 0)
    if duration <= 0:
        errors.append(SpikeError("RG_RANGE_INVALID", "range.duration_ticks must be > 0"))
    if start < 0:
        errors.append(SpikeError("RG_RANGE_INVALID", "range.start_ticks must be >= 0"))
    if duration > MAX_RANGE_TICKS:
        errors.append(SpikeError("RG_LIMITS", "range longer than 6 hours"))
    end = start + duration

    tracks = graph.get("tracks") or []
    if len(tracks) > MAX_TRACKS:
        errors.append(SpikeError("RG_LIMITS", f"{len(tracks)} tracks > {MAX_TRACKS}"))
    positions = sorted(t.get("position") for t in tracks)
    if positions != list(range(len(tracks))):
        errors.append(SpikeError("RG_TRACK_POSITION", f"positions not 0..n-1: {positions}"))

    for track in tracks:
        kind = track.get("kind")
        allowed = TRACK_KIND_FIELDS.get(kind, ())
        track_path = f"tracks[{track.get('position')}]"
        for name in ("clips", "audio_clips", "text_layers", "transitions"):
            if name in track and track[name] is not None and name not in allowed:
                errors.append(
                    SpikeError("RG_TRACK_KIND_FIELD", f"{name} is invalid on kind={kind}", f"{track_path}.{name}")
                )
        if kind == "video" and not track.get("clips"):
            errors.append(SpikeError("RG_TRACK_KIND_FIELD", "video track needs clips", track_path))
        if kind == "audio" and not track.get("audio_clips"):
            errors.append(SpikeError("RG_TRACK_KIND_FIELD", "audio track needs audio_clips", track_path))
        if kind == "overlay" and not track.get("text_layers"):
            errors.append(SpikeError("RG_TRACK_KIND_FIELD", "overlay track needs text_layers", track_path))
        for name in ("gain_mb", "pan_ppm"):
            if kind != "audio" and track.get(name) is not None:
                errors.append(
                    SpikeError("RG_TRACK_KIND_FIELD", f"{name} is audio-only", f"{track_path}.{name}")
                )

        clips = [c for c in (track.get("clips") or [])]
        if len(clips) > MAX_CLIPS_PER_TRACK:
            errors.append(SpikeError("RG_LIMITS", "too many clips on a track", track_path))
        ordered = sorted(clips, key=lambda c: c.get("timeline_start_ticks", 0))
        previous_end = None
        for index, clip in enumerate(ordered):
            clip_path = f"{track_path}.clips[{index}]"
            clip_start = clip.get("timeline_start_ticks", 0)
            clip_duration = clip.get("duration_ticks", 0)
            clip_end = clip_start + clip_duration
            if clip_duration <= 0 or clip_start < 0 or clip.get("source_in_ticks", 0) < 0:
                errors.append(SpikeError("RG_CLIP_BOUNDS", "negative or zero clip timing", clip_path))
            speed_num, speed_den = clip.get("speed_num", 0), clip.get("speed_den", 0)
            if speed_num <= 0 or speed_den <= 0:
                errors.append(SpikeError("RG_CLIP_BOUNDS", "speed must be > 0", clip_path))
            if clip_start < start or clip_end > end:
                errors.append(SpikeError("RG_RANGE_INVALID", "clip outside range", clip_path))
            if previous_end is not None and clip_start < previous_end:
                errors.append(SpikeError("RG_CLIP_OVERLAP", "clips overlap on the same track", clip_path))
            previous_end = clip_end
            if len(clip.get("effects") or []) > MAX_EFFECTS_PER_CLIP:
                errors.append(SpikeError("RG_LIMITS", "too many effects", clip_path))
            for effect_index, effect in enumerate(clip.get("effects") or []):
                _validate_effect(effect, f"{clip_path}.effects[{effect_index}]", registry, errors)
            if clip.get("kind") in ("video", "image", "adjustment"):
                uri = clip.get("source_uri")
                if not uri or not clip.get("source_hash"):
                    errors.append(SpikeError("RG_MISSING_SOURCE", "clip needs source_uri and source_hash", clip_path))
                elif sources is not None:
                    info = sources.get(uri)
                    if info is None or not info.get("exists", True):
                        errors.append(SpikeError("RG_MISSING_SOURCE", f"source not readable: {uri}", clip_path))
                    else:
                        speed = speed_num / speed_den if speed_num and speed_den else 1
                        needed = clip.get("source_in_ticks", 0) + clip_duration * speed
                        if info.get("duration_ticks") and needed > info["duration_ticks"] + 40_000:
                            errors.append(
                                SpikeError(
                                    "RG_SOURCE_TOO_SHORT",
                                    f"needs {needed} ticks, source has {info['duration_ticks']}",
                                    clip_path,
                                )
                            )

        clip_ids = {c.get("id") for c in clips}
        for index, transition in enumerate(track.get("transitions") or []):
            t_path = f"{track_path}.transitions[{index}]"
            if transition.get("kind") not in TRANSITION_KINDS:
                errors.append(SpikeError("RG_TRANSITION_BOUNDARY", "unknown transition kind", t_path))
            from_id, to_id = transition.get("from_clip_id"), transition.get("to_clip_id")
            if from_id not in clip_ids or to_id not in clip_ids:
                errors.append(SpikeError("RG_TRANSITION_BOUNDARY", "transition endpoint missing", t_path))
                continue
            from_clip = next(c for c in clips if c.get("id") == from_id)
            to_clip = next(c for c in clips if c.get("id") == to_id)
            cut = from_clip.get("timeline_start_ticks", 0) + from_clip.get("duration_ticks", 0)
            if transition.get("at_ticks") != cut:
                errors.append(SpikeError("RG_TRANSITION_BOUNDARY", "at_ticks != end of from_clip", t_path))
            if to_clip.get("timeline_start_ticks") != cut:
                errors.append(SpikeError("RG_TRANSITION_BOUNDARY", "to_clip does not start at the cut", t_path))
            t_duration = transition.get("duration_ticks", 0)
            shortest = min(from_clip.get("duration_ticks", 0), to_clip.get("duration_ticks", 0))
            if t_duration <= 0 or t_duration * 2 > shortest:
                errors.append(
                    SpikeError(
                        "RG_TRANSITION_BOUNDARY",
                        f"duration {t_duration} must be > 0 and <= half of {shortest}",
                        t_path,
                    )
                )

        layers = track.get("text_layers") or []
        if len(layers) > MAX_TEXT_LAYERS:
            errors.append(SpikeError("RG_LIMITS", "too many text layers", track_path))
        for index, layer in enumerate(layers):
            l_path = f"{track_path}.text_layers[{index}]"
            l_start = layer.get("start_ticks", 0)
            l_duration = layer.get("duration_ticks", 0)
            if l_duration <= 0 or l_start < start or l_start + l_duration > end:
                errors.append(SpikeError("RG_RANGE_INVALID", "text layer outside range", l_path))
            anim_in = (layer.get("animation_in") or {}).get("duration_ticks", 0)
            anim_out = (layer.get("animation_out") or {}).get("duration_ticks", 0)
            if anim_in + anim_out > l_duration:
                errors.append(SpikeError("RG_RANGE_INVALID", "animations exceed layer duration", l_path))
            if rasters is not None:
                uri = layer.get("raster_uri")
                info = rasters.get(uri)
                if info is None or not info.get("exists", True):
                    errors.append(SpikeError("RG_TEXT_RASTER", f"raster not readable: {uri}", l_path))
                else:
                    if info.get("blake3") != layer.get("raster_hash"):
                        errors.append(SpikeError("RG_TEXT_RASTER", "raster_hash mismatch", l_path))
                    if (info.get("width"), info.get("height")) != (
                        layer.get("raster_width"),
                        layer.get("raster_height"),
                    ):
                        errors.append(SpikeError("RG_TEXT_RASTER", "declared raster size mismatch", l_path))

        for index, clip in enumerate(track.get("audio_clips") or []):
            a_path = f"{track_path}.audio_clips[{index}]"
            a_start = clip.get("timeline_start_ticks", 0)
            a_duration = clip.get("duration_ticks", 0)
            if a_duration <= 0 or a_start < start or a_start + a_duration > end:
                errors.append(SpikeError("RG_RANGE_INVALID", "audio clip outside range", a_path))
            if clip.get("fade_in_ticks", 0) + clip.get("fade_out_ticks", 0) > a_duration:
                errors.append(SpikeError("RG_CLIP_BOUNDS", "fades exceed clip duration", a_path))
            if not isinstance(clip.get("gain_mb"), int):
                errors.append(SpikeError("RG_CLIP_BOUNDS", "audio gain_mb must be an int", a_path))
            if clip.get("speed_num", 0) <= 0 or clip.get("speed_den", 0) <= 0:
                errors.append(SpikeError("RG_CLIP_BOUNDS", "audio speed must be > 0", a_path))
            uri = clip.get("source_uri")
            if clip.get("asset_id") is not None:
                if not uri or not clip.get("source_hash"):
                    errors.append(SpikeError("RG_MISSING_SOURCE", "audio clip needs source", a_path))
                elif sources is not None:
                    info = sources.get(uri)
                    if info is None or not info.get("exists", True):
                        errors.append(SpikeError("RG_MISSING_SOURCE", f"source not readable: {uri}", a_path))
                    elif not info.get("has_audio"):
                        errors.append(SpikeError("RG_MISSING_SOURCE", "source has no audio stream", a_path))

    size = len(json.dumps(graph).encode("utf-8"))
    if size > MAX_GRAPH_BYTES:
        errors.append(SpikeError("RG_LIMITS", f"graph is {size} bytes > 4 MiB"))
    return errors


def validate_graph(
    graph: dict,
    *,
    schema: dict | None = None,
    registry: dict,
    sources: dict | None = None,
    rasters: dict | None = None,
) -> None:
    """Raise on the first structural error; return semantic errors as a whole."""
    schema = schema or load_schema()
    errors: list[SpikeError] = []
    _walk(schema, graph, "graph", errors)
    if errors:
        raise errors[0]
    semantic = check_semantics(graph, registry=registry, sources=sources, rasters=rasters)
    if semantic:
        raise semantic[0]
