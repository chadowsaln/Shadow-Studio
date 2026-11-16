#!/usr/bin/env python3
"""Negative tests: the contract layer must *refuse* broken graphs.

A validator that accepts everything looks identical to a passing render, so the
spike pins the rejection codes it relies on (V-09, V-13, V-14, V-15, V-16).

    tools/media-spike/.venv/bin/python tools/media-spike/test_refusals.py
"""

from __future__ import annotations

import copy
import sys
from pathlib import Path

from graphcontract import check
from media_common import SpikeError
from media_fixtures import prepare

SPIKE_DIR = Path(__file__).resolve().parent


def _mutations() -> list[tuple[str, str, str, callable]]:
    def video_hash(graph: dict) -> None:
        graph["tracks"][0]["clips"][0]["source_hash"] = "0" * 64

    def audio_hash(graph: dict) -> None:
        graph["tracks"][2]["audio_clips"][0]["source_hash"] = "0" * 64

    def keyframe_order(graph: dict) -> None:
        param = graph["tracks"][0]["clips"][0]["effects"][0]["params"][1]
        param["keyframes"].reverse()

    def unknown_field(graph: dict) -> None:
        graph["mlt_fragment"] = "leaked"

    def transition_boundary(graph: dict) -> None:
        graph["tracks"][0]["transitions"][0]["at_ticks"] = 3_000_000

    def raster_hash(graph: dict) -> None:
        graph["tracks"][1]["text_layers"][0]["raster_hash"] = "0" * 64

    return [
        ("video source_hash", "RG_MISSING_SOURCE", "tracks[0].clips[0]", video_hash),
        ("audio source_hash", "RG_MISSING_SOURCE", "tracks[2].audio_clips[0]", audio_hash),
        ("keyframe order", "RG_KEYFRAME_ORDER", "tracks[0].clips[0].effects[0]", keyframe_order),
        ("unknown field", "RG_SCHEMA_INVALID", "graph", unknown_field),
        ("transition boundary", "RG_TRANSITION_BOUNDARY", "tracks[0].transitions[0]", transition_boundary),
        ("raster hash", "RG_TEXT_RASTER", "tracks[1].text_layers[0]", raster_hash),
    ]


def main() -> int:
    payload = prepare(SPIKE_DIR / "out", force=False)
    graph = payload["graph"]
    sources = payload["sources"]
    rasters = {
        layer["raster_uri"]: payload["raster"]
        for track in graph["tracks"]
        for layer in (track.get("text_layers") or [])
    }

    failures = 0
    try:
        check(graph, sources, rasters=rasters)
        print("  ok   canonical graph is accepted")
    except SpikeError as error:
        failures += 1
        print(f"  FAIL canonical graph rejected: {error}")

    for name, expected, path, mutate in _mutations():
        broken = copy.deepcopy(graph)
        mutate(broken)
        try:
            check(broken, sources, rasters=rasters)
        except SpikeError as error:
            if error.code == expected:
                print(f"  ok   {name:<20} -> {error.code}")
            else:
                failures += 1
                print(f"  FAIL {name:<20} -> {error.code} (expected {expected})")
        else:
            failures += 1
            print(f"  FAIL {name:<20} -> accepted (expected {expected}, path {path})")

    if failures:
        print(f"FAIL — {failures} refusal case(s) did not behave")
        return 1
    print("PASS — every broken graph is refused with its contract code")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
