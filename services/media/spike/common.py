"""Shared helpers for the Media Core spike.

One unit rule (Appendix A.2): all positions and durations are integer ticks of
1/1,000,000 second. Nothing in this spike stores time as float except at the
FFmpeg boundary, where seconds are unavoidable.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

TICKS_PER_SECOND = 1_000_000

REPO_ROOT = Path(__file__).resolve().parents[3]
SPIKE_DIR = Path(__file__).resolve().parent
CONTRACTS_DIR = REPO_ROOT / "docs" / "architecture" / "contracts"
EXAMPLE_GRAPH_PATH = CONTRACTS_DIR / "rendergraph.example.json"
MANIFEST_PATH = CONTRACTS_DIR / "rendergraph.manifest.json"


class SpikeError(RuntimeError):
    """A failure with a contract code and a human-readable detail."""

    def __init__(self, code: str, detail: str, path: str | None = None) -> None:
        self.code = code
        self.detail = detail
        self.path = path
        super().__init__(f"{code}: {detail}" + (f" (at {path})" if path else ""))

    def as_dict(self) -> dict:
        out = {"code": self.code, "detail": self.detail}
        if self.path:
            out["path"] = self.path
        return out


def ticks_to_seconds(ticks: int) -> float:
    return ticks / TICKS_PER_SECOND


def seconds_to_ticks(seconds: float) -> int:
    return int(round(seconds * TICKS_PER_SECOND))


def ticks_to_frames(ticks: int, fps_num: int, fps_den: int) -> int:
    """frame = floor(tick * fps_num / (1e6 * fps_den)) — Appendix A.2."""
    return (ticks * fps_num) // (TICKS_PER_SECOND * fps_den)


def frames_to_ticks(frames: int, fps_num: int, fps_den: int) -> int:
    """tick = ceil(frame * 1e6 * fps_den / fps_num) — Appendix A.2."""
    numerator = frames * TICKS_PER_SECOND * fps_den
    return -(-numerator // fps_num)


def uri_to_path(uri: str) -> Path:
    if not uri.startswith("file://"):
        raise SpikeError("RG_SOURCE_URI_SCHEME", f"not a file:// URI: {uri}")
    parsed = urlparse(uri)
    if parsed.netloc not in ("", "localhost"):
        # file:///abs/path parses with an empty netloc; a host means a UNC path
        # that this spike does not resolve.
        raise SpikeError("RG_SOURCE_URI_SCHEME", f"unsupported file URI host: {uri}")
    return Path(unquote(parsed.path))


def path_to_uri(path: Path) -> str:
    return "file://" + quote(str(path.resolve()))


def blake3_file(path: Path) -> str:
    try:
        import blake3  # type: ignore[import-not-found]
    except ModuleNotFoundError as exc:  # pragma: no cover - environment check
        raise SpikeError(
            "SPIKE_BLAKE3_MISSING",
            "blake3 is required by Appendix A (64 hex chars); run "
            "`.venv/bin/pip install blake3`",
        ) from exc
    digest = blake3.blake3()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ffprobe_json(path: Path) -> dict:
    proc = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SpikeError("MEDIA_PROBE_FAILED", proc.stderr.strip() or "ffprobe failed")
    return json.loads(proc.stdout)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if check and proc.returncode != 0:
        raise SpikeError(
            "PROCESS_FAILED",
            f"{cmd[0]} exited {proc.returncode}: {proc.stderr.strip()[-2000:]}",
        )
    return proc
