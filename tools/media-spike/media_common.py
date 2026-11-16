"""Shared helpers for the Media Core spike (contract consumption, not a product)."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

TICKS_PER_SECOND = 1_000_000

SPIKE_DIR = Path(__file__).resolve().parent
REPO_ROOT = SPIKE_DIR.parents[1]
CONTRACTS = REPO_ROOT / "docs" / "architecture" / "contracts"
EXAMPLE_GRAPH_PATH = CONTRACTS / "rendergraph.example.json"
SCHEMA_PATH = CONTRACTS / "rendergraph.schema.json"
EFFECTS_PATH = CONTRACTS / "rendergraph.effects.json"


class SpikeError(RuntimeError):
    def __init__(self, code: str, detail: str, path: str | None = None) -> None:
        self.code = code
        self.detail = detail
        self.path = path
        super().__init__(f"{code}: {detail}" + (f" ({path})" if path else ""))

    def as_dict(self) -> dict:
        payload = {"code": self.code, "detail": self.detail}
        if self.path:
            payload["path"] = self.path
        return payload


def ticks_to_seconds(ticks: int) -> float:
    return ticks / TICKS_PER_SECOND


def frame_to_tick(frame: int, fps_num: int, fps_den: int) -> int:
    numerator = frame * TICKS_PER_SECOND * fps_den
    return -(-numerator // fps_num)


def path_to_uri(path: Path) -> str:
    return "file://" + str(path.resolve())


def uri_to_path(uri: str) -> Path:
    if not uri.startswith("file:///"):
        raise SpikeError("RG_SOURCE_URI_SCHEME", f"not an absolute file URI: {uri}")
    return Path(uri[len("file://") :])


def blake3_file(path: Path) -> str:
    try:
        import blake3  # type: ignore[import-not-found]
    except ModuleNotFoundError as exc:
        raise SpikeError(
            "SPIKE_BLAKE3_MISSING",
            "BLAKE3 is required by the contract; run: "
            "python3 -m venv tools/media-spike/.venv && "
            "tools/media-spike/.venv/bin/pip install blake3",
        ) from exc
    digest = blake3.blake3()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
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
        raise SpikeError("MEDIA_PROBE_FAILED", proc.stderr.strip()[-2000:])
    return json.loads(proc.stdout)


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(command, capture_output=True, text=True, check=False)
    if check and proc.returncode != 0:
        raise SpikeError(
            "PROCESS_FAILED",
            f"{Path(command[0]).name} exited {proc.returncode}: {proc.stderr.strip()[-3000:]}",
        )
    return proc
