"""Consume the normative RenderGraph contract.

Phase 1 validates the graph instance against `rendergraph.schema.json`
(structural: closed objects, types, enums, bounds, patterns). Phase 2 applies
the rules a schema cannot express: §A.12 semantics plus the transition-handle
rule D-RG-3 and the effect registry. Nothing about this file is engine-specific.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from media_common import (
    CONTRACTS,
    EFFECTS_PATH,
    SCHEMA_PATH,
    SpikeError,
    blake3_file,
    uri_to_path,
)

if str(CONTRACTS) not in sys.path:
    sys.path.insert(0, str(CONTRACTS))

import validate_schema  # noqa: E402  (path injection must happen first)


def load_contract() -> tuple[dict, dict]:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    effects = json.loads(EFFECTS_PATH.read_text(encoding="utf-8"))
    return schema, effects


def _schema_errors(graph: dict, schema: dict) -> list[dict]:
    errors: list[dict] = []

    def fail(message: str) -> None:
        errors.append({"code": "RG_SCHEMA_INVALID", "detail": message})

    def ok(_message: str) -> None:
        return None

    validate_schema.validate_instance(
        schema, {"$ref": "#/$defs/RenderGraph"}, graph, "graph", fail, ok
    )
    return errors


def _semantic_errors(
    graph: dict,
    effects: dict,
    sources: dict[str, dict],
    rasters: dict[str, dict] | None,
) -> list[dict]:
    errors: list[dict] = []

    def bad(code: str, path: str, detail: str) -> None:
        errors.append({"code": code, "path": path, "detail": detail})

    timebase = graph["timebase"]
    if timebase["ticks_per_second"] != 1_000_000:
        bad("RG_TIMEBASE_INVALID", "timebase.ticks_per_second", "must be 1000000")
    fps = timebase["fps_num"] / timebase["fps_den"]
    if fps <= 0 or fps > 120:
        bad("RG_TIMEBASE_INVALID", "timebase", "fps out of (0, 120]")
    if timebase["sample_rate"] not in (44100, 48000, 96000):
        bad("RG_TIMEBASE_INVALID", "timebase.sample_rate", "unsupported sample rate")
    if not 1 <= timebase["channels"] <= 8:
        bad("RG_TIMEBASE_INVALID", "timebase.channels", "1..8")

    profile = graph["profile"]
    if profile["interlaced"]:
        bad("RG_UNSUPPORTED_PROFILE", "profile.interlaced", "interlaced rejected in v1")
    if profile["pixel_format"] == "yuv420p" and (
        profile["width"] % 2 or profile["height"] % 2
    ):
        bad("RG_UNSUPPORTED_PROFILE", "profile", "odd dimensions with yuv420p")

    start = graph["range"]["start_ticks"]
    duration = graph["range"]["duration_ticks"]
    if duration <= 0 or start < 0:
        bad("RG_RANGE_INVALID", "range", "invalid range")
    end = start + duration

    tracks = graph["tracks"]
    if sorted(t["position"] for t in tracks) != list(range(len(tracks))):
        bad("RG_TRACK_POSITION", "tracks", "positions must be unique 0..n-1")

    for track in tracks:
        track_path = f"tracks[{track['position']}]"
        kind = track["kind"]
        clips = track.get("clips") or []
        ordered = sorted(clips, key=lambda c: c["timeline_start_ticks"])
        previous_end = None
        by_id = {clip["id"]: clip for clip in clips}
        for index, clip in enumerate(ordered):
            path = f"{track_path}.clips[{index}]"
            clip_start = clip["timeline_start_ticks"]
            clip_end = clip_start + clip["duration_ticks"]
            if clip["duration_ticks"] <= 0 or clip_start < start or clip_end > end:
                bad("RG_RANGE_INVALID", path, "clip outside range")
            if previous_end is not None and clip_start < previous_end:
                bad("RG_CLIP_OVERLAP", path, "clips overlap on the same track")
            previous_end = clip_end
            if clip["kind"] == "color":
                info = None  # §A.4: color clips carry no asset, hence no hash
            else:
                info = sources.get(clip.get("source_uri"))
                if info is None:
                    bad("RG_MISSING_SOURCE", path, "source not bound")
                    continue
                # V-09: a render must reject a source whose content no longer
                # matches the graph's BLAKE3, not silently render other media.
                if clip.get("source_hash") != info.get("blake3"):
                    bad("RG_MISSING_SOURCE", path, "source_hash mismatch")
                    continue
            speed = clip["speed_num"] / clip["speed_den"]
            needed = clip["source_in_ticks"] + int(clip["duration_ticks"] * speed)
            if (
                clip["kind"] in ("video", "image", "adjustment")
                and needed > info["duration_ticks"] + 40_000
            ):
                bad(
                    "RG_SOURCE_TOO_SHORT",
                    path,
                    f"needs {needed} ticks, source has {info['duration_ticks']}",
                )
            for effect_index, effect in enumerate(clip.get("effects") or []):
                entry = effects["filters"].get(effect["effect_key"])
                if entry is None or not effect["effect_key"].startswith("shadow."):
                    bad("RG_UNKNOWN_EFFECT", f"{path}.effects[{effect_index}]", "unknown effect")
                    continue
                previous_keyframe = None
                for param in effect["params"]:
                    spec = entry["params"].get(param["name"])
                    if spec is None:
                        bad(
                            "RG_UNKNOWN_PARAM",
                            f"{path}.effects[{effect_index}].params",
                            f"{effect['effect_key']} has no param {param['name']}",
                        )
                        continue
                    if param["type"] != spec["type"]:
                        bad("RG_UNKNOWN_PARAM", f"{path}.effects[{effect_index}]", "param type mismatch")
                    for keyframe in param["keyframes"]:
                        at = keyframe["at_ticks"]
                        if previous_keyframe is not None and at <= previous_keyframe:
                            bad("RG_KEYFRAME_ORDER", f"{path}.effects[{effect_index}]", "keyframes not increasing")
                        previous_keyframe = at
                        if not (clip_start <= at < clip_end):
                            bad("RG_KEYFRAME_ORDER", f"{path}.effects[{effect_index}]", "keyframe outside clip")
                        if not (spec["min"] <= keyframe["value"] <= spec["max"]):
                            bad("RG_PARAM_DOMAIN", f"{path}.effects[{effect_index}]", "keyframe outside domain")
                    if not (spec["min"] <= param["value"] <= spec["max"]):
                        bad("RG_PARAM_DOMAIN", f"{path}.effects[{effect_index}]", "value outside domain")

        for index, transition in enumerate(track.get("transitions") or []):
            path = f"{track_path}.transitions[{index}]"
            from_clip = by_id.get(transition["from_clip_id"])
            to_clip = by_id.get(transition["to_clip_id"])
            if from_clip is None or to_clip is None:
                bad("RG_TRANSITION_BOUNDARY", path, "endpoint missing")
                continue
            cut = from_clip["timeline_start_ticks"] + from_clip["duration_ticks"]
            if transition["at_ticks"] != cut:
                bad("RG_TRANSITION_BOUNDARY", path, "at_ticks != end of from clip")
            if to_clip["timeline_start_ticks"] != cut:
                bad("RG_TRANSITION_BOUNDARY", path, "to clip does not start at the cut")
            shortest = min(from_clip["duration_ticks"], to_clip["duration_ticks"])
            if transition["duration_ticks"] * 2 > shortest:
                bad("RG_TRANSITION_BOUNDARY", path, "duration > half of the shortest clip")
            info = sources.get(from_clip.get("source_uri"))
            if info and info.get("duration_ticks"):
                speed = from_clip["speed_num"] / from_clip["speed_den"]
                needed = from_clip["source_in_ticks"] + int(
                    (from_clip["duration_ticks"] + transition["duration_ticks"]) * speed
                )
                if needed > info["duration_ticks"]:
                    bad(
                        "RG_TRANSITION_NO_HANDLES",
                        path,
                        f"needs {needed} ticks of the outgoing source, has {info['duration_ticks']}",
                    )
            if transition["kind"] not in effects["transitions"]:
                bad("RG_UNSUPPORTED_TRANSITION", path, "unknown transition kind")

        for layer_index, layer in enumerate(track.get("text_layers") or []):
            path = f"{track_path}.text_layers[{layer_index}]"
            if layer["start_ticks"] < start or layer["start_ticks"] + layer["duration_ticks"] > end:
                bad("RG_RANGE_INVALID", path, "text layer outside range")
            if (
                layer["animation_in"]["duration_ticks"] + layer["animation_out"]["duration_ticks"]
                > layer["duration_ticks"]
            ):
                bad("RG_RANGE_INVALID", path, "animations exceed layer duration")
            raster_path = uri_to_path(layer["raster_uri"])
            if not raster_path.exists():
                bad("RG_TEXT_RASTER", path, "raster missing")
                continue
            if blake3_file(raster_path) != layer["raster_hash"]:
                bad("RG_TEXT_RASTER", path, "raster_hash mismatch")
            if rasters is not None:
                info = rasters.get(layer["raster_uri"], {})
                if (info.get("width"), info.get("height")) != (
                    layer["raster_width"],
                    layer["raster_height"],
                ):
                    bad("RG_TEXT_RASTER", path, "declared raster size mismatch")

        for index, clip in enumerate(track.get("audio_clips") or []):
            path = f"{track_path}.audio_clips[{index}]"
            if (
                clip["timeline_start_ticks"] < start
                or clip["timeline_start_ticks"] + clip["duration_ticks"] > end
            ):
                bad("RG_RANGE_INVALID", path, "audio clip outside range")
            if clip["fade_in_ticks"] + clip["fade_out_ticks"] > clip["duration_ticks"]:
                bad("RG_CLIP_BOUNDS", path, "fades exceed duration")
            info = sources.get(clip.get("source_uri"))
            if info is None:
                bad("RG_MISSING_SOURCE", path, "source not bound")
            elif clip.get("source_hash") != info.get("blake3"):
                bad("RG_MISSING_SOURCE", path, "source_hash mismatch")
            elif not info.get("has_audio"):
                bad("RG_MISSING_SOURCE", path, "source has no audio stream")

    return errors


def check(graph: dict, sources: dict[str, dict], rasters: dict | None = None) -> dict:
    """Raise on the first violation; otherwise return a validation summary."""
    schema, effects = load_contract()
    errors = _schema_errors(graph, schema)
    stage = "schema"
    if not errors:
        stage = "semantics"
        errors = _semantic_errors(graph, effects, sources, rasters)
    if errors:
        first = errors[0]
        raise SpikeError(first["code"], first["detail"], first.get("path"))
    return {
        "stage": stage,
        "schema": SCHEMA_PATH.name,
        "effects": EFFECTS_PATH.name,
        "tracks": len(graph["tracks"]),
        "clips": sum(len(t.get("clips") or []) for t in graph["tracks"]),
        "transitions": sum(len(t.get("transitions") or []) for t in graph["tracks"]),
        "text_layers": sum(len(t.get("text_layers") or []) for t in graph["tracks"]),
        "audio_clips": sum(len(t.get("audio_clips") or []) for t in graph["tracks"]),
    }
