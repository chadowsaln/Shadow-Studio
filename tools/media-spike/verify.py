"""Prove the render is what the graph asked for.

Structural probe (resolution/fps/codecs/duration), then pixel and audio
evidence for the three features the example exercises (blur ramp, text overlay,
crossfade), then QG-4 determinism by re-rendering and comparing framemd5.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

import numpy as np

from media_common import SpikeError, ffprobe_json, run, ticks_to_seconds
from render import render


def _frame(
    path: Path,
    seconds: float,
    width: int,
    height: int,
    *,
    scale: bool,
    filters: str | None = None,
) -> np.ndarray:
    command = ["ffmpeg", "-v", "error", "-ss", f"{seconds:.6f}", "-i", str(path)]
    chain = []
    if scale:
        chain.append(f"scale={width}:{height}:flags=lanczos")
    if filters:
        chain.append(filters)
    if chain:
        command += ["-vf", ",".join(chain)]
    command += ["-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    proc = subprocess.run(command, capture_output=True, check=False)
    if proc.returncode != 0 or not proc.stdout:
        raise SpikeError("VERIFY_FRAME_FAILED", f"cannot read frame at {seconds}s from {path.name}")
    return np.frombuffer(proc.stdout, dtype=np.uint8).reshape(height, width, 3).astype(np.int16)


def _sharpness(frame: np.ndarray, *, content_only: bool = True) -> float:
    """Laplacian energy: falls with blur, unlike mean |gradient|.

    With `content_only` the band occupied by the lower-third (y 820..1000) is
    excluded so the crisp text bars cannot pollute a blur measurement.
    """
    gray = frame[:, :, :3].astype(np.float32).mean(axis=2)
    crop = gray[120:780, 120:1800] if content_only else gray[80:1000, 80:1840]
    lap = (
        4 * crop[1:-1, 1:-1]
        - crop[:-2, 1:-1]
        - crop[2:, 1:-1]
        - crop[1:-1, :-2]
        - crop[1:-1, 2:]
    )
    return float((lap * lap).mean())


def _mean_abs_diff(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.abs(a - b).mean())


def _burst(path: Path, start: float, duration: float, width: int, height: int) -> tuple[list[float], np.ndarray]:
    """Decode a contiguous run once, returning real PTS times and frames.

    Encoding is frame-quantised (D-RG-4: a value applies at frame_to_tick(f)),
    so animation checks need the timestamps of the frames actually produced
    rather than the time that was requested from a seek.
    """
    proc = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "info",
            "-ss",
            f"{start:.6f}",
            "-t",
            f"{duration:.6f}",
            "-i",
            str(path),
            "-vf",
            f"scale={width}:{height}:flags=lanczos,showinfo",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ],
        capture_output=True,
        check=False,
    )
    frame_bytes = width * height * 3
    if proc.returncode != 0 or len(proc.stdout) < frame_bytes:
        raise SpikeError("VERIFY_FRAME_FAILED", f"cannot read burst from {path.name}")
    raw = np.frombuffer(proc.stdout, dtype=np.uint8)
    count = raw.size // frame_bytes
    frames = raw[: count * frame_bytes].reshape(count, height, width, 3).astype(np.int16)
    times = [start + float(value) for value in re.findall(r"pts_time:([0-9.]+)", proc.stderr.decode())]
    return times[:count], frames


def _fit_linear(times: list[float], values: list[float], low: float = 0.05, high: float = 0.95) -> tuple[float, float]:
    """Least-squares slope/intercept over unsaturated samples."""
    points = [(t, v) for t, v in zip(times, values) if low < v < high]
    if len(points) < 2:
        return float("nan"), float("nan")
    xs = np.array([p[0] for p in points])
    ys = np.array([p[1] for p in points])
    slope, intercept = np.polyfit(xs, ys, 1)
    return float(slope), float(intercept)


def _pcm(path: Path, start: float, duration: float, rate: int = 48000) -> np.ndarray:
    proc = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-ss",
            f"{start:.6f}",
            "-t",
            f"{duration:.6f}",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-f",
            "s16le",
            "-ac",
            "2",
            "-ar",
            str(rate),
            "-",
        ],
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0 or not proc.stdout:
        raise SpikeError("VERIFY_AUDIO_FAILED", f"cannot read audio from {path.name}")
    return np.frombuffer(proc.stdout, dtype=np.int16).astype(np.float64) / 32768.0


def _rms(samples: np.ndarray) -> float:
    return float(np.sqrt(np.mean(samples**2))) if samples.size else 0.0


def _stream_md5(path: Path, kind: str) -> str:
    command = ["ffmpeg", "-v", "error", "-i", str(path)]
    command += ["-map", "0:v:0", "-f", "framemd5", "-"] if kind == "video" else [
        "-map",
        "0:a:0",
        "-f",
        "md5",
        "-",
    ]
    proc = subprocess.run(command, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise SpikeError("VERIFY_HASH_FAILED", proc.stderr.strip()[-1000:])
    lines = [line for line in proc.stdout.splitlines() if line and not line.startswith("#")]
    if kind == "audio":
        return lines[-1].strip() if lines else ""
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def verify(
    out_path: Path,
    plan: dict,
    *,
    graph: dict,
    sources: dict[str, dict],
    fixtures: dict[str, str],
    raster: dict,
    determinism: bool = True,
) -> dict:
    probe = ffprobe_json(out_path)
    video = next(s for s in probe["streams"] if s["codec_type"] == "video")
    audio = next((s for s in probe["streams"] if s["codec_type"] == "audio"), None)
    preset_width = plan["profile"]["width"]
    preset_height = plan["profile"]["height"]
    fps = plan["fps"]
    num, den = (int(part) for part in fps.split("/"))
    duration = ticks_to_seconds(plan["range"]["duration_ticks"])
    expected_frames = int(round(duration * num / den))

    checks: list[dict] = []

    def check(name: str, passed: bool, detail: str) -> None:
        checks.append({"check": name, "pass": bool(passed), "detail": detail})

    check("container", probe["format"]["format_name"].startswith("mov"), probe["format"]["format_name"])
    check(
        "resolution",
        (video["width"], video["height"]) == (preset_width, preset_height),
        f"{video['width']}x{video['height']}",
    )
    check("pixel_format", video["pix_fmt"] == "yuv420p", video["pix_fmt"])
    check("frame_rate", video["r_frame_rate"] == fps, video["r_frame_rate"])
    frame_count = int(video.get("nb_frames") or 0)
    check("frame_count", frame_count == expected_frames, f"{frame_count} vs {expected_frames}")
    check(
        "duration",
        abs(float(probe["format"]["duration"]) - duration) < 0.05,
        f"{float(probe['format']['duration']):.3f}s vs {duration:.3f}s",
    )
    check("video_codec", video["codec_name"] == "h264", video["codec_name"])
    if audio is None:
        check("audio_stream", False, "missing")
    else:
        check("audio_codec", audio["codec_name"] == "aac", audio["codec_name"])
        check("audio_rate", int(audio["sample_rate"]) == 48000, audio["sample_rate"])
        check("audio_channels", int(audio["channels"]) == 2, str(audio["channels"]))

    # --- blur ramp (D-RG-4/5: amount 0 -> 0.5 over 2s, ease_in_out) --------
    # Blur mixes a source with its own gaussian (radius 12 px). A laplacian
    # energy of `k` for the mix tracks (1-a)^2 * k_source, so the rendered
    # frames yield the effective amount, which is compared to the contract's
    # keyframe curve instead of a hand-picked threshold.
    intro_path = Path(fixtures["intro"])
    # The rendered frame at t=0.2 is the unblurred baseline (graph amount 0.014,
    # below quantisation), so it absorbs the encode's own sharpening bias.
    baseline_energy = _sharpness(_frame(out_path, 0.2, preset_width, preset_height, scale=False))
    source_energy = _sharpness(
        _frame(
            intro_path,
            3.7,
            preset_width,
            preset_height,
            scale=True,
            filters=f"scale={preset_width}:{preset_height}:flags=lanczos",
        )
    )

    def blurred_amount(seconds: float) -> float:
        energy = _sharpness(_frame(out_path, seconds, preset_width, preset_height, scale=False))
        return 1.0 - (energy / baseline_energy) ** 0.5

    def contract_amount(seconds: float) -> float:
        # keyframes: (0, 0) -> (2s, 0.5), ease_in_out = u^2(3-2u).
        if seconds <= 0:
            return 0.0
        if seconds >= 2:
            return 0.5
        u = seconds / 2
        return 0.5 * u * u * (3 - 2 * u)

    early_amount = blurred_amount(0.4)
    mid_amount = blurred_amount(1.2)
    late_amount = blurred_amount(3.2)
    ramp_errors = [
        abs(early_amount - contract_amount(0.4)),
        abs(mid_amount - contract_amount(1.2)),
        abs(late_amount - contract_amount(3.2)),
    ]
    check(
        "blur_ramp",
        abs(baseline_energy / source_energy - 1) < 0.2
        and early_amount < mid_amount < late_amount
        and abs(late_amount - 0.5) < 0.08
        and max(ramp_errors) < 0.12,
        "amount {:.3f}/{:.3f}/{:.3f} vs graph {:.3f}/{:.3f}/{:.3f} (baseline/source {:.2f})".format(
            early_amount,
            mid_amount,
            late_amount,
            contract_amount(0.4),
            contract_amount(1.2),
            contract_amount(3.2),
            baseline_energy / source_energy,
        ),
    )

    # --- text overlay: the raster's opaque accent bar, on its own clock ----
    # Raster pixel (20, 900-820=80) is solid (64,196,255) with alpha 255, so the
    # composited frame must show exactly that colour while the layer is up.
    accent = np.array([64, 196, 255], dtype=np.float64)
    patch_y, patch_x = slice(832, 988), slice(13, 27)

    def accent_patch(seconds: float) -> np.ndarray:
        return _frame(
            out_path, seconds, preset_width, preset_height, scale=False
        )[patch_y, patch_x].reshape(-1, 3).mean(axis=0)

    before = accent_patch(0.5)
    full = accent_patch(3.0)
    after = accent_patch(4.2)
    present_err = float(np.abs(full - accent).mean())
    absent_before = float(np.abs(before - accent).mean())
    absent_after = float(np.abs(after - accent).mean())
    check(
        "text_layer",
        present_err < 12 and absent_before > 40 and absent_after > 40,
        f"present_err={present_err:.2f} before={absent_before:.2f} after={absent_after:.2f}",
    )

    # fade-in is linear over 250 ms from t=1s: coverage(t) = (t - 1) / 0.25.
    span = full - before
    denom = float((span * span).sum())
    times, burst = _burst(out_path, 0.9, 0.5, preset_width, preset_height)
    coverages = [
        float(
            (
                (frame[patch_y, patch_x].reshape(-1, 3).mean(axis=0) - before) * span
            ).sum()
            / denom
        )
        for frame in burst
    ]
    slope, intercept = _fit_linear(times, coverages)
    fade_start = -intercept / slope if slope else float("nan")
    fade_duration = 1.0 / slope if slope else float("nan")
    check(
        "text_fade_in",
        abs(fade_start - 1.0) < 0.04
        and abs(fade_duration - 0.25) < 0.04
        and max(coverages) > 0.95
        and min(coverages) < 0.05,
        f"start={fade_start:.3f}s (graph 1.000) duration={fade_duration:.3f}s (graph 0.250)",
    )

    # --- crossfade: 50/50 of the outgoing (blurred, amount 0.5) and incoming -
    outro_path = Path(fixtures["outro"])
    blur = "gblur=sigma=12:steps=3"
    outgoing = np.array(
        _frame(intro_path, 5.0, preset_width, preset_height, scale=True, filters=blur),
        dtype=np.float64,
    )
    incoming = np.array(
        _frame(outro_path, 0.5, preset_width, preset_height, scale=True), dtype=np.float64
    )
    predicted = 0.5 * (outgoing + incoming)
    rendered = _frame(out_path, 4.5, preset_width, preset_height, scale=False).astype(np.float64)
    d_pred = _mean_abs_diff(rendered, predicted)
    d_a = _mean_abs_diff(rendered, outgoing)
    d_b = _mean_abs_diff(rendered, incoming)
    check(
        "crossfade_blend",
        d_pred < 12 and d_pred < min(d_a, d_b) * 0.75,
        f"to_blend={d_pred:.2f} to_outgoing={d_a:.2f} to_incoming={d_b:.2f}",
    )

    # --- audio gain: -3 dB (gain_mb = -3000) ------------------------------
    out_audio = _rms(_pcm(out_path, 6.0, 3.0))
    src_audio = _rms(_pcm(Path(fixtures["audio"]), 6.0, 3.0))
    measured_db = 20 * np.log10(out_audio / src_audio) if out_audio and src_audio else float("nan")
    check(
        "audio_gain",
        abs(measured_db - (-3.0)) < 0.35,
        f"{measured_db:.2f} dB (expected -3.00)",
    )

    # --- QG-4 determinism -------------------------------------------------
    if determinism:
        second = out_path.with_name(out_path.stem + ".determinism" + out_path.suffix)
        render(plan, second, raster=raster, overwrite=True, progress=False)
        check(
            "determinism_video",
            _stream_md5(out_path, "video") == _stream_md5(second, "video"),
            "framemd5 of all video frames",
        )
        check(
            "determinism_audio",
            _stream_md5(out_path, "audio") == _stream_md5(second, "audio"),
            "md5 of decoded PCM",
        )
        second.unlink(missing_ok=True)

    passed = all(item["pass"] for item in checks)
    return {
        "pass": passed,
        "checks": checks,
        "measured": {
            "blur_amount_early": round(early_amount, 3),
            "blur_amount_mid": round(mid_amount, 3),
            "blur_amount_late": round(late_amount, 3),
            "text_present_err": round(present_err, 3),
            "text_absent_before": round(absent_before, 3),
            "text_absent_after": round(absent_after, 3),
            "fade_start_s": round(fade_start, 4),
            "fade_duration_s": round(fade_duration, 4),
            "crossfade_to_blend": round(d_pred, 3),
            "audio_gain_db": round(float(measured_db), 3),
        },
    }
