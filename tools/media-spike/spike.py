#!/usr/bin/env python3
"""Media Core spike: canonical RenderGraph -> MP4, end to end.

    python3 tools/media-spike/spike.py all

Phases: prepare (fixtures + bind) -> validate (schema + §A.12) -> plan
(RenderGraph -> FFmpeg) -> render -> verify (probe, pixels, audio, framemd5).

This is a contract spike, not the product worker: the plan JSON is the golden
mapping to port into `native/cpp/media_engine`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from compile_plan import compile_graph
from graphcontract import check as validate_graph
from media_common import SpikeError
from media_fixtures import ensure_tools, prepare
from render import render
from verify import verify

SPIKE_DIR = Path(__file__).resolve().parent
DEFAULT_OUT = SPIKE_DIR / "out"


def _write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def run_all(out_dir: Path, *, force: bool, determinism: bool) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    print("[1/5] prepare fixtures + bind graph")
    payload = prepare(out_dir, force=force)
    graph = payload["graph"]
    sources = payload["sources"]
    raster = payload["raster"]
    print(f"      sources={len(sources)} tracks={len(graph['tracks'])}")

    print("[2/5] validate against the normative contract")
    summary = validate_graph(
        graph,
        sources,
        rasters={layer_uri: raster for layer_uri in _raster_uris(graph)},
    )
    print(f"      {summary['stage']} checks passed (schema {summary['schema']})")

    print("[3/5] compile plan")
    plan = compile_graph(graph, preset=payload["preset"], sources=sources, rasters=raster)
    _write(out_dir / "plan.json", plan)
    print(f"      inputs={len(plan['inputs'])} filters={plan['filter_complex'].count(';') + 1}")

    print("[4/5] render with ffmpeg")
    out_path = out_dir / "final.mp4"
    receipt = render(plan, out_path, raster=raster, overwrite=force, progress=True)
    if not force and out_path.exists():
        pass
    print(
        f"      {receipt['video']['width']}x{receipt['video']['height']} "
        f"{receipt['video']['nb_frames']} frames, {receipt['realtime_factor']}x realtime"
    )

    print("[5/5] verify")
    result = verify(
        out_path,
        plan,
        graph=graph,
        sources=sources,
        fixtures=payload["fixtures"],
        raster=raster,
        determinism=determinism,
    )

    receipt["graph_sha256"] = hashlib.sha256(
        json.dumps(graph, sort_keys=True).encode("utf-8")
    ).hexdigest()
    receipt["binding"] = payload["binding"]
    receipt["validation"] = summary
    receipt["verification"] = result
    _write(out_dir / "receipt.json", receipt)

    for item in result["checks"]:
        mark = "ok  " if item["pass"] else "FAIL"
        print(f"      {mark} {item['check']:<20} {item['detail']}")
    print(f"      measured: {json.dumps(result['measured'], ensure_ascii=False)}")

    if not result["pass"]:
        print("FAIL — real MP4 produced, but behaviour does not match the graph")
        return 1
    print(f"PASS — {out_path} ({receipt['bytes']} bytes), receipt=out/receipt.json")
    return 0


def _raster_uris(graph: dict) -> list[str]:
    uris: list[str] = []
    for track in graph["tracks"]:
        for layer in track.get("text_layers") or []:
            uris.append(layer["raster_uri"])
    return uris


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["all", "prepare"], default="all", nargs="?")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--force", action="store_true", help="overwrite output and fixtures")
    parser.add_argument(
        "--skip-determinism",
        action="store_true",
        help="skip the second render used for framemd5 comparison",
    )
    args = parser.parse_args(argv)

    ensure_tools()
    try:
        if args.phase == "prepare":
            payload = prepare(args.out, force=args.force)
            _write(args.out / "binding.json", payload["binding"])
            print(f"prepared {len(payload['sources'])} sources in {args.out}")
            return 0
        return run_all(args.out, force=args.force, determinism=not args.skip_determinism)
    except SpikeError as error:
        print(f"FAIL — {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
