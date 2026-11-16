"""Execute a compiled plan with FFmpeg (spike stand-in for the native worker)."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import time
from pathlib import Path

from media_common import SpikeError, ffprobe_json, ticks_to_seconds


def _input_args(entry: dict, profile: dict, fps: str, raster: dict) -> list[str]:
    path = entry["path"]
    if path.endswith(".rgba"):
        return [
            "-f",
            "rawvideo",
            "-pixel_format",
            "rgba",
            "-video_size",
            f"{raster['width']}x{raster['height']}",
            "-framerate",
            fps,
            "-i",
            path,
        ]
    return ["-i", path]


def render(
    plan: dict,
    out_path: Path,
    *,
    raster: dict,
    overwrite: bool = False,
    progress: bool = True,
) -> dict:
    if out_path.exists() and not overwrite:
        raise SpikeError("OUTPUT_EXISTS", f"{out_path} already exists (use --force)")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    part = out_path.with_suffix(out_path.suffix + ".part")
    fps = plan["fps"]

    command = [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-nostats",
        "-loglevel",
        "error",
        "-y",
        "-progress",
        "pipe:1",
    ]
    for entry in plan["inputs"]:
        command += _input_args(entry, plan["profile"], fps, raster)
    command += ["-filter_complex", plan["filter_complex"]]
    for mapping in plan["maps"]:
        command += ["-map", mapping]
    command += plan["encode_args"]
    # The atomic temp name ends in `.part`, so the muxer must be explicit.
    command += ["-f", "mp4", str(part)]

    duration_ticks = plan["range"]["duration_ticks"]
    started = time.monotonic()
    last_progress = 0.0
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        if not progress or not line.startswith("out_time_us="):
            continue
        try:
            elapsed_media = int(line.split("=", 1)[1]) / 1_000_000
        except ValueError:
            continue
        ppm = min(int(elapsed_media / ticks_to_seconds(duration_ticks) * 1_000_000), 1_000_000)
        if ppm - last_progress >= 100_000:
            last_progress = ppm
            print(f"  progress {ppm // 10_000:3d}%", flush=True)
    stderr = process.stderr.read() if process.stderr else ""
    code = process.wait()
    wall = time.monotonic() - started
    if code != 0:
        part.unlink(missing_ok=True)
        raise SpikeError(
            "MEDIA_RENDER_FAILED",
            f"ffmpeg exited {code}: {stderr.strip()[-3000:]}",
        )

    with open(part, "rb") as handle:
        os.fsync(handle.fileno())
    os.replace(part, out_path)

    probe = ffprobe_json(out_path)
    media_seconds = float(probe["format"]["duration"])
    video = next(s for s in probe["streams"] if s["codec_type"] == "video")
    audio = next((s for s in probe["streams"] if s["codec_type"] == "audio"), None)
    receipt = {
        "output": str(out_path),
        "bytes": out_path.stat().st_size,
        "sha256": hashlib.sha256(out_path.read_bytes()).hexdigest(),
        "plan_sha256": hashlib.sha256(
            json.dumps(plan, sort_keys=True).encode("utf-8")
        ).hexdigest(),
        "wall_seconds": round(wall, 3),
        "media_seconds": round(media_seconds, 3),
        "realtime_factor": round(media_seconds / wall, 3) if wall else None,
        "video": {
            "codec": video["codec_name"],
            "width": video["width"],
            "height": video["height"],
            "pix_fmt": video["pix_fmt"],
            "r_frame_rate": video["r_frame_rate"],
            "nb_frames": int(video.get("nb_frames", 0)),
        },
        "audio": None
        if audio is None
        else {
            "codec": audio["codec_name"],
            "sample_rate": int(audio["sample_rate"]),
            "channels": audio["channels"],
            "bit_rate": int(audio.get("bit_rate", 0)),
        },
        "command": command,
    }
    return receipt
