# Media Core spike (D4 — Media Worker PoC)

A minimal, end-to-end proof that the **validated** `RenderGraph` contract can be
executed to a real MP4 with FFmpeg, and that the produced pixels/audio match the
graph rather than merely "some video came out". It consumes
[rendergraph.example.json](../../docs/architecture/contracts/rendergraph.example.json)
unchanged (only media URIs/hashes are rebound to local fixtures) and is the
golden mapping to port into the native worker.

Not a product worker: no engine abstraction, no MLT, no C++, single-process
Python + FFmpeg. Everything it decides about the contract is recorded in
`out/receipt.json` so the mapping can be diffed later.

## Run

```bash
python3 -m venv tools/media-spike/.venv
tools/media-spike/.venv/bin/pip install blake3 numpy

tools/media-spike/.venv/bin/python tools/media-spike/spike.py all            # full run + determinism
tools/media-spike/.venv/bin/python tools/media-spike/spike.py all --force    # regenerate fixtures/output
tools/media-spike/.venv/bin/python tools/media-spike/spike.py all --skip-determinism
tools/media-spike/.venv/bin/python tools/media-spike/spike.py prepare        # fixtures + binding only
```

Exit codes: `0` = graph validated, rendered, and every behavioural check passed;
`1` = `SpikeError` (validation, compile, render, or verification failure).

Negative tests — the contract layer must refuse broken graphs, otherwise a
passing render proves nothing:

```bash
tools/media-spike/.venv/bin/python tools/media-spike/test_refusals.py
```

It pins the rejection codes for a tampered video/audio `source_hash`
(`RG_MISSING_SOURCE`, V-09), non-increasing keyframes (`RG_KEYFRAME_ORDER`,
V-13), a transition off the cut (`RG_TRANSITION_BOUNDARY`, V-14), a raster hash
mismatch (`RG_TEXT_RASTER`, V-15) and an undeclared field
(`RG_SCHEMA_INVALID`, V-16).

## Stages

| Stage | Module | Produces |
| --- | --- | --- |
| prepare | [media_fixtures.py](media_fixtures.py) | `out/fixtures/*` (4K intro, HD outro, WAV voice-over, raw RGBA lower-third) + `out/graph.bound.json` |
| validate | [graphcontract.py](graphcontract.py) | Schema + §A.12 semantics against the normative contract; refuses with contract error codes (`RG_*`) |
| plan | [compile_plan.py](compile_plan.py) | `out/plan.json`: inputs, one `filter_complex`, encode args — the inspectable mapping |
| render | [render.py](render.py) | `out/final.mp4` (atomic `.part` → rename) + `out/receipt.json` |
| verify | [verify.py](verify.py) | probe, pixel/audio evidence, QG-4 determinism (second render, framemd5 + PCM md5) |

## Contract mapping implemented

| Rule | Where | Notes |
| --- | --- | --- |
| D-RG-1 range/profile | `compile_graph` | One `color` base at profile size/rate for the whole range |
| D-RG-2 geometry | `transform_box` | integer crop → center/anchor fit → pad, all in integers with half-up rounding |
| D-RG-3 transition window | `_video_track` | `[at, at+d)`; outgoing clip is extended by `d` (handle frames), incoming starts at `source_in` at the window start, linear alpha |
| D-RG-4 easing | `easing_expression` | `linear`, `ease_in`, `ease_out`, `ease_in_out` = `u²(3−2u)`, `step` |
| D-RG-5 keyframe evaluation | `param_expression` | absolute-timeline `at_ticks`, first value before the first keyframe, **last value after the last**, strictly increasing pairs |
| D-RG-6 z-order | `_video_track` / `_overlay_track` | tracks by `position`, clips by `timeline_start_ticks`, one timeline-length `overlay` chain |
| D-RG-7 text rasters | `_overlay_track` | raster → pad at absolute PTS, fade-in/out on the layer clock, `overlay enable` = layer window |
| audio | `_audio` | `atrim` → gain (mB → dB) → fades → `adelay` → `amix=normalize=0` → 48 kHz stereo |

## What verification proves

Measured on the example graph (10 s, 1920×1080, 29.97 fps, 300 frames):

* `blur_ramp` — laplacian energy of the composited frame yields the effective
  gaussian amount; compared against the contract's `u²(3−2u)` curve at
  t = 0.4/1.2/3.2 s (graph: 0.05/0.32/0.50, measured 0.04/0.25/0.44).
* `text_layer` — the raster's opaque accent-bar colour appears exactly where the
  transform puts it while the layer is up, and is absent before/after its window.
* `text_fade_in` — least-squares fit of the alpha ramp over real frame PTS gives
  start/duration vs the graph's 1.000 s / 0.250 s.
* `crossfade_blend` — the 4.5 s frame is within 9/255 of `0.5·(outgoing blurred +
  incoming)`, and far from both endpoints.
* `audio_gain` — RMS ratio of the mixed voice-over vs source = −3.01 dB for
  `gain_mb = −3000`.
* `determinism_video` / `determinism_audio` — a second render reproduces every
  decoded frame (framemd5) and the PCM (md5), i.e. QG-4.

## Known limitations (deliberate)

* `mp4`/`h264` only; other presets are rejected (`RG_PRESET_CONFLICT`).
* `video` clips only; `rotation_quarter_turns != 0`, variable `speed` and
  non-zero `pan_ppm` are rejected, not approximated.
* `dissolve` is treated as `crossfade`; wipe/fade-black are rejected.
* Gaussian blur is `gblur` mixed by `blend` with a per-pixel expression — a
  linear operator, so mixed energy matches, but it is **not** the product's
  effect implementation.
* Frame-quantised animation: `overlay` framesync picks the nearest secondary
  frame, so layer animation is accurate to ±1 frame (visible as the fitted fade
  start being one frame early). The contract itself is defined at
  `frame_to_tick(f)`, so this is a renderer fidelity note, not a contract bug.
* Performance is ~0.15× realtime for 1080p with 4K sources on CPU; this spike
  makes no performance claim.
* Inputs are trusted by hash: fixtures are bound by `source_hash`/`raster_hash`
  and probed, but the spike does not decode arbitrary user media.
