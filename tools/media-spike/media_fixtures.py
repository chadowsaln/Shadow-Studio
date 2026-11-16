"""Deterministic fixtures + graph binding for the Media Core spike.

The canonical example points at `file:///media/user/...`, which cannot exist on
this machine. The spike therefore binds *only* `source_uri`, `source_hash`,
`raster_uri` and `raster_hash` to generated fixtures and records every
substitution. No structural field of the graph is touched.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from copy import deepcopy
from pathlib import Path

import numpy as np

from media_common import (
    EXAMPLE_GRAPH_PATH,
    SpikeError,
    blake3_file,
    ffprobe_json,
    path_to_uri,
    run,
)

FIXTURE_FPS = "30000/1001"


def _ffmpeg(args: list[str]) -> None:
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args])


def make_raster(path: Path, width: int = 1200, height: int = 180) -> None:
    """A deterministic lower-third: translucent panel, solid bars, alpha edges."""
    yy, xx = np.mgrid[0:height, 0:width]
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    # Panel with a 12 px transparent margin and a soft rounded feel.
    inside = (xx >= 12) & (xx < width - 12) & (yy >= 12) & (yy < height - 12)
    rgba[inside] = (16, 20, 28, 210)
    # Accent bar on the left.
    accent = inside & (xx >= 12) & (xx < 28)
    rgba[accent] = (64, 196, 255, 255)
    # Three "text" bars of decreasing length.
    for index, (row, length) in enumerate(((46, 760), (92, 620), (138, 480))):
        band = inside & (yy >= row) & (yy < row + 18) & (xx >= 56) & (xx < 56 + length)
        rgba[band] = (245, 247, 250, 235 if index == 0 else 190)
    # Hard alpha edge on the panel border (fade tests rely on it).
    border = inside & ~((xx >= 13) & (xx < width - 13) & (yy >= 13) & (yy < height - 13))
    rgba[border, 3] = 160
    path.write_bytes(rgba.tobytes())


def build_fixtures(fixture_dir: Path, *, force: bool = False) -> dict[str, Path]:
    fixture_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "intro": fixture_dir / "intro-4k.mp4",
        "outro": fixture_dir / "outro-hd.mp4",
        "audio": fixture_dir / "vo-take3.wav",
        "raster": fixture_dir / "lower-third.rgba",
    }
    if force or not paths["intro"].exists():
        _ffmpeg(
            [
                "-f",
                "lavfi",
                "-i",
                f"smptebars=size=3840x2160:rate={FIXTURE_FPS}:duration=6",
                "-c:v",
                "libx264",
                "-preset",
                "ultrafast",
                "-crf",
                "30",
                "-pix_fmt",
                "yuv420p",
                str(paths["intro"]),
            ]
        )
    if force or not paths["outro"].exists():
        _ffmpeg(
            [
                "-f",
                "lavfi",
                "-i",
                f"testsrc=size=1920x1080:rate={FIXTURE_FPS}:duration=12",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-crf",
                "22",
                "-pix_fmt",
                "yuv420p",
                str(paths["outro"]),
            ]
        )
    if force or not paths["audio"].exists():
        _ffmpeg(
            [
                "-f",
                "lavfi",
                "-i",
                "aevalsrc=0.18*sin(2*PI*440*t)|0.18*sin(2*PI*660*t):s=48000:d=10",
                "-c:a",
                "pcm_s16le",
                str(paths["audio"]),
            ]
        )
    if force or not paths["raster"].exists():
        make_raster(paths["raster"])
    return paths


def probe_fixtures(paths: dict[str, Path]) -> dict[str, dict]:
    info: dict[str, dict] = {}
    for name, path in paths.items():
        if path.suffix == ".rgba":
            info[path_to_uri(path)] = {
                "exists": path.exists(),
                "width": 1200,
                "height": 180,
                "blake3": blake3_file(path),
                "duration_ticks": None,
                "has_audio": False,
            }
            continue
        data = ffprobe_json(path)
        streams = data.get("streams", [])
        video = next((s for s in streams if s.get("codec_type") == "video"), None)
        info[path_to_uri(path)] = {
            "exists": True,
            "width": video.get("width") if video else None,
            "height": video.get("height") if video else None,
            "blake3": blake3_file(path),
            "duration_ticks": int(round(float(data["format"]["duration"]) * 1_000_000)),
            "has_audio": any(s.get("codec_type") == "audio" for s in streams),
        }
    return info


def bind_graph(paths: dict[str, Path]) -> tuple[dict, dict]:
    example = json.loads(EXAMPLE_GRAPH_PATH.read_text(encoding="utf-8"))
    graph = deepcopy(example["graph"])
    by_name = {
        "intro-4k.mp4": paths["intro"],
        "outro-hd.mp4": paths["outro"],
        "vo-take3.wav": paths["audio"],
    }
    substitutions: list[dict] = []

    def rebind(node: dict, field: str, key: str, value: Path) -> None:
        old = node.get(field)
        node[field] = path_to_uri(value)
        node[key] = blake3_file(value)
        substitutions.append({"field": field, "from": old, "to": node[field]})

    for track in graph["tracks"]:
        for clip in track.get("clips") or []:
            name = (clip.get("source_uri") or "").rsplit("/", 1)[-1]
            if name in by_name:
                target = by_name[name]
                rebind(clip, "source_uri", "source_hash", target)
            elif clip.get("source_uri"):
                raise SpikeError("SPIKE_FIXTURE_MISSING", f"no fixture for {clip['source_uri']}")
        for clip in track.get("audio_clips") or []:
            name = (clip.get("source_uri") or "").rsplit("/", 1)[-1]
            if name not in by_name:
                raise SpikeError("SPIKE_FIXTURE_MISSING", f"no fixture for {clip.get('source_uri')}")
            rebind(clip, "source_uri", "source_hash", by_name[name])
        for layer in track.get("text_layers") or []:
            rebind(layer, "raster_uri", "raster_hash", paths["raster"])

    preset = deepcopy(example["render_start_request"]["preset"])
    binding = {
        "source": str(EXAMPLE_GRAPH_PATH.relative_to(EXAMPLE_GRAPH_PATH.parents[3])),
        "substitutions": substitutions,
        "note": "only source_uri/source_hash/raster_uri/raster_hash were rebound",
    }
    return graph, {"graph": graph, "preset": preset, "binding": binding}


def prepare(out_dir: Path, *, force: bool = False) -> dict:
    fixture_dir = out_dir / "fixtures"
    paths = build_fixtures(fixture_dir, force=force)
    graph, payload = bind_graph(paths)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "graph.bound.json").write_text(
        json.dumps(graph, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    payload["sources"] = probe_fixtures(paths)
    payload["fixtures"] = {name: str(path) for name, path in paths.items()}
    payload["raster"] = {"width": 1200, "height": 180}
    return payload


def ensure_tools() -> None:
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            raise SpikeError("SPIKE_TOOL_MISSING", f"{tool} is not on PATH")
