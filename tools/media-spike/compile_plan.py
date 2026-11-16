"""RenderGraph -> FFmpeg plan.

This is the spike's `media/graph` module: it consumes the validated graph and
emits a concrete, inspectable plan (inputs, filter_complex, encode args). In the
product this emitter becomes MLT XML inside the C++ worker; the mapping rules
are the ones pinned by Appendix هـ (D-RG-2..7).
"""

from __future__ import annotations

from dataclasses import dataclass, field

from media_common import SpikeError, ticks_to_seconds, uri_to_path

SUPPORTED_CLIP_KINDS = {"video"}
SUPPORTED_EFFECTS = {"shadow.blur.gaussian"}
SUPPORTED_TRANSITIONS = {"crossfade", "dissolve"}
SUPPORTED_ANIMATIONS = {"fade", "none"}


def esc(expression: str) -> str:
    """Escape the characters the filtergraph parser treats as separators."""
    return expression.replace("\\", "\\\\").replace(",", "\\,").replace(":", "\\:")


def _n(value: float) -> str:
    return f"{value:.9f}".rstrip("0").rstrip(".") or "0"


@dataclass
class Plan:
    profile: dict
    range: dict
    fps: str = "30000/1001"
    inputs: list[dict] = field(default_factory=list)
    filters: list[str] = field(default_factory=list)
    encode_args: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def input_index(self, uri: str) -> int:
        for entry in self.inputs:
            if entry["uri"] == uri:
                return entry["index"]
        index = len(self.inputs)
        self.inputs.append({"index": index, "uri": uri, "path": str(uri_to_path(uri))})
        return index

    def to_dict(self) -> dict:
        return {
            "profile": self.profile,
            "range": self.range,
            "fps": self.fps,
            "inputs": self.inputs,
            "filter_complex": ";".join(self.filters),
            "maps": ["[vout]", "[aout]"] if self.has_audio else ["[vout]"],
            "encode_args": self.encode_args,
            "warnings": self.warnings,
            "notes": self.notes,
        }

    has_audio: bool = False


# --------------------------------------------------------------------------- #
# geometry (D-RG-2)
# --------------------------------------------------------------------------- #
def transform_box(
    transform: dict,
    *,
    source_width: int,
    source_height: int,
    profile_width: int,
    profile_height: int,
    intrinsic: bool,
) -> tuple[int, int, int, int, int, int]:
    """Return (cw, ch, dw, dh, left, top) per Appendix هـ D-RG-2."""
    left_crop = transform["crop_left_px"]
    top_crop = transform["crop_top_px"]
    cw = source_width - left_crop - transform["crop_right_px"]
    ch = source_height - top_crop - transform["crop_bottom_px"]
    if cw <= 0 or ch <= 0:
        raise SpikeError("RG_FIELD_RANGE", "crop consumes the whole source")

    if intrinsic:
        dw = (cw * transform["scale_x_ppm"] + 500_000) // 1_000_000
        dh = (ch * transform["scale_y_ppm"] + 500_000) // 1_000_000
    else:
        fit_num = min(profile_width * 1_000_000 // cw, profile_height * 1_000_000 // ch)
        dw = (cw * fit_num * transform["scale_x_ppm"] + 500_000) // 1_000_000_000_000
        dh = (ch * fit_num * transform["scale_y_ppm"] + 500_000) // 1_000_000_000_000

    dw = max(dw, 1)
    dh = max(dh, 1)
    if transform["anchor"] == "center":
        left = (profile_width - dw + 1) // 2 + transform["x_px"]
        top = (profile_height - dh + 1) // 2 + transform["y_px"]
    else:
        left = transform["x_px"]
        top = transform["y_px"]
    return cw, ch, dw, dh, left, top


# --------------------------------------------------------------------------- #
# keyframes (D-RG-4 / D-RG-5)
# --------------------------------------------------------------------------- #
def easing_expression(easing: str, u: str) -> str:
    if easing == "linear":
        return u
    if easing == "ease_in":
        return f"({u})*({u})"
    if easing == "ease_out":
        return f"(1-(1-({u}))*(1-({u})))"
    if easing == "ease_in_out":
        return f"({u})*({u})*(3-2*({u}))"
    if easing == "step":
        return "0"
    raise SpikeError("RG_KEYFRAME_ORDER", f"unknown easing {easing!r}")


def param_expression(param: dict, scale: float = 1.0) -> str:
    keyframes = param["keyframes"]
    if not keyframes:
        return _n(param["value"] * scale)

    # D-RG-5: before the first keyframe the first value holds, after the last
    # keyframe the last value holds; the nested `if` chain below is evaluated
    # from the newest pair outwards, so the default branch is the last value.
    last = keyframes[-1]
    expression = _n(last["value"] * scale)
    for index in range(len(keyframes) - 1):
        start = keyframes[index]
        end = keyframes[index + 1]
        span = end["at_ticks"] - start["at_ticks"]
        if span <= 0:
            raise SpikeError("RG_KEYFRAME_ORDER", "keyframes are not strictly increasing")
        u = f"((T-{_n(ticks_to_seconds(start['at_ticks']))})/{_n(ticks_to_seconds(span))})"
        eased = easing_expression(start["easing"], u)
        value = f"({_n(start['value'] * scale)}+({_n((end['value'] - start['value']) * scale)})*({eased}))"
        expression = f"if(lt(T,{_n(ticks_to_seconds(end['at_ticks']))}),{value},{expression})"
    return expression


# --------------------------------------------------------------------------- #
# compile
# --------------------------------------------------------------------------- #
def compile_graph(
    graph: dict,
    *,
    preset: dict,
    sources: dict[str, dict],
    rasters: dict[str, dict] | None = None,
) -> dict:
    profile = graph["profile"]
    width, height = profile["width"], profile["height"]
    timebase = graph["timebase"]
    fps = f"{timebase['fps_num']}/{timebase['fps_den']}"
    start_ticks = graph["range"]["start_ticks"]
    duration = graph["range"]["duration_ticks"]
    duration_s = ticks_to_seconds(duration)

    plan = Plan(profile=profile, range=graph["range"], fps=fps)
    background = graph["background_rgba"]
    rgb = background[1:7]
    alpha = int(background[7:9], 16) / 255
    plan.filters.append(
        f"color=c=0x{rgb}@{_n(alpha)}:size={width}x{height}:rate={fps}:"
        f"d={_n(duration_s)},format=rgba,setsar=1[base]"
    )
    last = "[base]"

    video_tracks = [t for t in graph["tracks"] if t["enabled"] and t["kind"] == "video"]
    overlay_tracks = [t for t in graph["tracks"] if t["enabled"] and t["kind"] == "overlay"]
    audio_tracks = [t for t in graph["tracks"] if t["enabled"] and t["kind"] == "audio"]

    for position, track in enumerate(video_tracks):
        last = _video_track(plan, track, last, graph, sources, fps, width, height, start_ticks)

    for position, track in enumerate(overlay_tracks):
        last = _overlay_track(plan, track, last, graph, fps, width, height)

    plan.filters.append(f"{last}null[vout]")

    if audio_tracks:
        _audio(plan, audio_tracks, graph, fps)
        plan.has_audio = True

    _encode_args(plan, preset, graph)
    if profile["pixel_format"] not in ("yuv420p", "yuv422p", "yuv444p"):
        plan.warnings.append(f"pixel_format {profile['pixel_format']} is approximated by yuv420p")
    return plan.to_dict()


def _video_track(plan, track, last, graph, sources, fps, width, height, start_ticks) -> str:
    clips = sorted(
        (c for c in (track.get("clips") or []) if c["enabled"]),
        key=lambda c: c["timeline_start_ticks"],
    )
    if not clips:
        return last
    transitions = track.get("transitions") or []
    by_from = {t["from_clip_id"]: t for t in transitions}
    by_to = {t["to_clip_id"]: t for t in transitions}

    # Each clip stream is consumed once per use, so plan the uses up front and
    # split accordingly. Windows are absolute timeline seconds.
    uses: dict[str, list[tuple[str, float, float]]] = {c["id"]: [] for c in clips}
    for clip in clips:
        start = ticks_to_seconds(clip["timeline_start_ticks"])
        end = start + ticks_to_seconds(clip["duration_ticks"])
        incoming = by_to.get(clip["id"])
        own_end = end - (ticks_to_seconds(incoming["duration_ticks"]) if incoming else 0)
        if own_end > start + 1e-9:
            uses[clip["id"]].append(("own", start, own_end))
        if incoming:
            post_start = ticks_to_seconds(incoming["at_ticks"] + incoming["duration_ticks"])
            if end > post_start + 1e-9:
                uses[clip["id"]].append(("post", post_start, end))
    for index, transition in enumerate(transitions):
        cut = ticks_to_seconds(transition["at_ticks"])
        length = ticks_to_seconds(transition["duration_ticks"])
        uses[transition["from_clip_id"]].append((f"xfrom{index}", cut, cut + length))
        uses[transition["to_clip_id"]].append((f"xto{index}", cut, cut + length))

    for clip_index, clip in enumerate(clips):
        if clip["kind"] not in SUPPORTED_CLIP_KINDS:
            raise SpikeError(
                "SPIKE_UNSUPPORTED_CLIP_KIND",
                f"clip kind {clip['kind']!r} is not implemented in this spike",
            )
        if clip["speed_num"] != clip["speed_den"]:
            raise SpikeError("SPIKE_UNSUPPORTED_SPEED", "variable speed is not implemented")
        if clip["transform"]["rotation_quarter_turns"] != 0:
            raise SpikeError("SPIKE_UNSUPPORTED_ROTATION", "rotation is not implemented")

        source = sources.get(clip["source_uri"])
        if source is None:
            raise SpikeError("RG_MISSING_SOURCE", f"unbound source {clip['source_uri']}")
        input_index = plan.input_index(clip["source_uri"])
        outgoing = by_from.get(clip["id"])
        incoming = by_to.get(clip["id"])
        handle = outgoing["duration_ticks"] if outgoing else 0

        seek = ticks_to_seconds(clip["source_in_ticks"])
        span = ticks_to_seconds(clip["duration_ticks"] + handle)
        label = f"c{track['position']}_{clip_index}"
        chain = [
            f"trim=start={_n(seek)}:duration={_n(span)}",
            "setpts=PTS-STARTPTS",
            f"fps={fps}",
            "setsar=1",
        ]
        chain.extend(
            _geometry_filters(
                clip["transform"],
                source_width=source["width"],
                source_height=source["height"],
                profile_width=width,
                profile_height=height,
                intrinsic=False,
            )
        )
        chain.append("format=rgba")
        # Timeline absolute PTS so keyframes and enable windows share one clock.
        chain.append(f"setpts=PTS-STARTPTS+{_n(ticks_to_seconds(clip['timeline_start_ticks']))}/TB")
        plan.filters.append(f"[{input_index}:v]" + ",".join(chain) + f"[{label}]")

        current = f"[{label}]"
        for effect_index, effect in enumerate(clip.get("effects") or []):
            if not effect["enabled"]:
                continue
            if effect["effect_key"] not in SUPPORTED_EFFECTS:
                raise SpikeError(
                    "SPIKE_UNSUPPORTED_EFFECT",
                    f"{effect['effect_key']} is not implemented in this spike",
                )
            params = {p["name"]: p for p in effect["params"]}
            radius = params.get("radius_px")
            amount = params.get("amount_ppm")
            if radius is None or amount is None:
                raise SpikeError("RG_UNKNOWN_PARAM", "blur needs radius_px and amount_ppm")
            amount_expression = param_expression(amount, scale=1 / 1_000_000)
            mixed = f"m{track['position']}_{clip_index}_{effect_index}"
            plan.filters.append(
                f"{current}split=2[{mixed}a][{mixed}b];"
                f"[{mixed}b]gblur=sigma={radius['value']}:steps=3[{mixed}blur]"
            )
            plan.filters.append(
                f"[{mixed}a][{mixed}blur]blend=all_expr="
                f"'A*(1-({esc(amount_expression)}))+B*({esc(amount_expression)})'[{mixed}]"
            )
            current = f"[{mixed}]"

        opacity = clip["opacity_ppm"]
        if opacity != 1_000_000:
            opaque = f"o{track['position']}_{clip_index}"
            plan.filters.append(
                f"{current}colorchannelmixer=aa={_n(opacity / 1_000_000)}[{opaque}]"
            )
            current = f"[{opaque}]"

        planned = uses[clip["id"]]
        if not planned:
            continue
        if len(planned) == 1:
            plan.filters.append(f"{current}null[use{track['position']}_{clip_index}_0]")
            labels = [f"use{track['position']}_{clip_index}_0"]
        else:
            split_labels = [
                f"use{track['position']}_{clip_index}_{index}"
                for index in range(len(planned))
            ]
            plan.filters.append(
                f"{current}split={len(planned)}"
                + "".join(f"[{label}]" for label in split_labels)
            )
            labels = split_labels
        for (kind, start, end), label in zip(planned, labels):
            plan.filters.append(
                f"[{label}]trim=start={_n(start)}:end={_n(end)}[{label}t]"
            )
        for (kind, start, end), label in zip(planned, labels):
            if kind.startswith("xfrom") or kind.startswith("xto"):
                continue
            last = _overlay(plan, last, f"[{label}t]", start, end)

    for transition_index, transition in enumerate(transitions):
        if transition["kind"] not in SUPPORTED_TRANSITIONS:
            raise SpikeError(
                "SPIKE_UNSUPPORTED_TRANSITION",
                f"{transition['kind']} is not implemented in this spike",
            )
        cut = ticks_to_seconds(transition["at_ticks"])
        length = ticks_to_seconds(transition["duration_ticks"])
        label = f"x{track['position']}_{transition_index}"
        from_index = next(i for i, c in enumerate(clips) if c["id"] == transition["from_clip_id"])
        to_index = next(i for i, c in enumerate(clips) if c["id"] == transition["to_clip_id"])
        from_label = (
            f"use{track['position']}_{from_index}_"
            f"{_use_index(uses[clips[from_index]['id']], f'xfrom{transition_index}')}"
        )
        to_label = (
            f"use{track['position']}_{to_index}_"
            f"{_use_index(uses[clips[to_index]['id']], f'xto{transition_index}')}"
        )
        plan.filters.append(
            f"[{from_label}t]setpts=PTS-STARTPTS[{label}a]"
        )
        plan.filters.append(f"[{to_label}t]setpts=PTS-STARTPTS[{label}b]")
        plan.filters.append(
            f"[{label}a][{label}b]blend=all_expr='A*(1-(T/{_n(length)}))+B*(T/{_n(length)})'"
            f"[{label}raw]"
        )
        plan.filters.append(f"[{label}raw]setpts=PTS+{_n(cut)}/TB[{label}]")
        last = _overlay(plan, last, f"[{label}]", cut, cut + length)
    return last


def _use_index(planned: list[tuple[str, float, float]], prefix: str) -> int:
    for index, (kind, _, _) in enumerate(planned):
        if kind.startswith(prefix):
            return index
    raise SpikeError("SPIKE_PLAN_INTERNAL", f"missing use {prefix}")


def _overlay(plan, main: str, secondary: str, start: float, end: float) -> str:
    label = f"ov{len(plan.filters)}"
    plan.filters.append(
        f"{main}{secondary}overlay=x=0:y=0:eof_action=pass:shortest=0:"
        f"enable='between(t,{_n(start)},{_n(end)})'[{label}]"
    )
    return f"[{label}]"


def _geometry_filters(
    transform: dict,
    *,
    source_width: int,
    source_height: int,
    profile_width: int,
    profile_height: int,
    intrinsic: bool,
) -> list[str]:
    cw, ch, dw, dh, left, top = transform_box(
        transform,
        source_width=source_width,
        source_height=source_height,
        profile_width=profile_width,
        profile_height=profile_height,
        intrinsic=intrinsic,
    )
    filters: list[str] = []
    if (
        transform["crop_left_px"]
        or transform["crop_top_px"]
        or transform["crop_right_px"]
        or transform["crop_bottom_px"]
    ):
        filters.append(
            f"crop={cw}:{ch}:{transform['crop_left_px']}:{transform['crop_top_px']}"
        )
    filters.append(f"scale={dw}:{dh}:flags=lanczos")
    filters.append(
        f"pad={profile_width}:{profile_height}:{left}:{top}:color=0x00000000"
    )
    return filters


def _overlay_track(plan, track, last, graph, fps, width, height) -> str:
    for index, layer in enumerate(track.get("text_layers") or []):
        if layer["animation_in"]["kind"] not in SUPPORTED_ANIMATIONS:
            raise SpikeError(
                "SPIKE_UNSUPPORTED_ANIMATION",
                f"animation {layer['animation_in']['kind']!r} is not implemented",
            )
        if layer["animation_out"]["kind"] not in SUPPORTED_ANIMATIONS | {"none"}:
            raise SpikeError(
                "SPIKE_UNSUPPORTED_ANIMATION",
                f"animation {layer['animation_out']['kind']!r} is not implemented",
            )
        input_index = plan.input_index(layer["raster_uri"])
        start = ticks_to_seconds(layer["start_ticks"])
        duration = ticks_to_seconds(layer["duration_ticks"])
        frames = int(round(duration * graph["timebase"]["fps_num"] / graph["timebase"]["fps_den"]))
        label = f"t{track['position']}_{index}"
        cw, ch, dw, dh, left, top = transform_box(
            layer["transform"],
            source_width=layer["raster_width"],
            source_height=layer["raster_height"],
            profile_width=width,
            profile_height=height,
            intrinsic=True,
        )
        chain = [
            "format=rgba",
            f"loop=loop={max(frames - 1, 0)}:size=1:start=0",
            f"fps={fps}",
            f"trim=duration={_n(duration)}",
            "setpts=PTS-STARTPTS",
        ]
        if cw != layer["raster_width"] or ch != layer["raster_height"]:
            chain.append(f"crop={cw}:{ch}:{layer['transform']['crop_left_px']}:{layer['transform']['crop_top_px']}")
        chain.append(f"scale={dw}:{dh}:flags=lanczos")
        chain.append(f"pad={width}:{height}:{left}:{top}:color=0x00000000")
        if layer["opacity_ppm"] != 1_000_000:
            chain.append(f"colorchannelmixer=aa={_n(layer['opacity_ppm'] / 1_000_000)}")
        plan.filters.append(f"[{input_index}:v]" + ",".join(chain) + f"[{label}base]")

        current = f"[{label}base]"
        animation_in = layer["animation_in"]
        if animation_in["kind"] == "fade" and animation_in["duration_ticks"] > 0:
            label_in = f"{label}_in"
            plan.filters.append(
                f"{current}fade=t=in:st=0:d={_n(ticks_to_seconds(animation_in['duration_ticks']))}:"
                f"alpha=1[{label_in}]"
            )
            current = f"[{label_in}]"
        animation_out = layer["animation_out"]
        if animation_out["kind"] == "fade" and animation_out["duration_ticks"] > 0:
            label_out = f"{label}_out"
            fade_out_start = duration - ticks_to_seconds(animation_out["duration_ticks"])
            plan.filters.append(
                f"{current}fade=t=out:st={_n(fade_out_start)}:"
                f"d={_n(ticks_to_seconds(animation_out['duration_ticks']))}:alpha=1[{label_out}]"
            )
            current = f"[{label_out}]"
        # The fade window is relative to the layer start, so the animation runs
        # on the layer's own clock; the layer is then placed on the absolute
        # timeline so overlay framesync sees it at start_ticks (D-RG-5: text
        # layers are timed on the same absolute clock as keyframes).
        plan.filters.append(
            f"{current}setpts=PTS+{_n(start)}/TB[{label}]"
        )
        current = f"[{label}]"
        last = _overlay(plan, last, current, start, start + duration)
    return last


def _audio(plan, tracks, graph, fps) -> None:
    mixed: list[str] = []
    for track_index, track in enumerate(tracks):
        if track.get("pan_ppm") not in (None, 0):
            raise SpikeError("SPIKE_UNSUPPORTED_PAN", "non-zero pan is not implemented")
        track_gain = _gain(track.get("gain_mb") or 0)
        clips = [c for c in (track.get("audio_clips") or []) if c["enabled"]]
        parts: list[str] = []
        for clip_index, clip in enumerate(clips):
            if clip["speed_num"] != clip["speed_den"]:
                raise SpikeError("SPIKE_UNSUPPORTED_SPEED", "audio speed change is not implemented")
            input_index = plan.input_index(clip["source_uri"])
            label = f"a{track_index}_{clip_index}"
            chain = [
                f"atrim=start={_n(ticks_to_seconds(clip['source_in_ticks']))}:"
                f"duration={_n(ticks_to_seconds(clip['duration_ticks']))}",
                "asetpts=PTS-STARTPTS",
                f"volume={_n(clip['gain_mb'] / 1000)}dB",
            ]
            if clip["fade_in_ticks"]:
                chain.append(f"afade=t=in:st=0:d={_n(ticks_to_seconds(clip['fade_in_ticks']))}")
            if clip["fade_out_ticks"]:
                start = ticks_to_seconds(clip["duration_ticks"] - clip["fade_out_ticks"])
                chain.append(
                    f"afade=t=out:st={_n(start)}:d={_n(ticks_to_seconds(clip['fade_out_ticks']))}"
                )
            delay_ms = int(round(ticks_to_seconds(clip["timeline_start_ticks"]) * 1000))
            chain.append(f"adelay={delay_ms}|{delay_ms}")
            plan.filters.append(f"[{input_index}:a]" + ",".join(chain) + f"[{label}]")
            parts.append(f"[{label}]")
        if not parts:
            continue
        if len(parts) > 1:
            joined = "".join(parts)
            label = f"amix{track_index}"
            plan.filters.append(f"{joined}amix=inputs={len(parts)}:normalize=0[{label}]")
            parts = [f"[{label}]"]
        if track_gain != "0":
            label = f"again{track_index}"
            plan.filters.append(f"{parts[0]}volume={track_gain}dB[{label}]")
            parts = [f"[{label}]"]
        mixed.extend(parts)

    if not mixed:
        return
    if len(mixed) > 1:
        joined = "".join(mixed)
        plan.filters.append(f"{joined}amix=inputs={len(mixed)}:normalize=0[amixed]")
        tail = "[amixed]"
    else:
        tail = mixed[0]
    plan.filters.append(
        f"{tail}aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[aout]"
    )


def _gain(millibel: int) -> str:
    return _n(millibel / 1000)


def _encode_args(plan: Plan, preset: dict, graph: dict) -> None:
    if preset["container"] != "mp4" or preset["video_codec"] != "h264":
        raise SpikeError("RG_PRESET_CONFLICT", "this spike only encodes mp4/h264")
    width = preset["width"] or plan.profile["width"]
    height = preset["height"] or plan.profile["height"]
    fps = f"{preset['fps_num']}/{preset['fps_den']}"
    args = [
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-pix_fmt",
        "yuv420p",
        "-s",
        f"{width}x{height}",
        "-r",
        fps,
        "-colorspace",
        "bt709",
        "-color_primaries",
        "bt709",
        "-color_trc",
        "bt709",
    ]
    if preset.get("crf") is not None:
        args += ["-crf", str(preset["crf"])]
    else:
        args += ["-b:v", f"{preset['video_bitrate_kbps']}k"]
    if plan.has_audio:
        args += [
            "-c:a",
            "aac",
            "-b:a",
            f"{preset['audio_bitrate_kbps']}k",
            "-ar",
            str(graph["timebase"]["sample_rate"]),
            "-ac",
            str(graph["timebase"]["channels"]),
        ]
    if preset.get("faststart"):
        args += ["-movflags", "+faststart"]
    args += [
        "-map_metadata",
        "-1",
        "-fflags",
        "+bitexact",
        "-flags:v",
        "+bitexact",
        "-flags:a",
        "+bitexact",
        "-threads",
        "4",
    ]
    plan.encode_args = args
