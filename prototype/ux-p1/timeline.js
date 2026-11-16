/* Shadow Studio — UX-P1 prototype
 * timeline.js: rendering + direct manipulation for S1 (§5).
 * Time axis is LTR inside an RTL interface (UX-1). */
(function () {
  "use strict";

  const SS = window.SS;
  const $ = (id) => document.getElementById(id);

  /* ------------------------------- waveforms ----------------------------- */
  function wavePath(seedText) {
    let seed = 0;
    for (let i = 0; i < seedText.length; i += 1) seed = (seed * 31 + seedText.charCodeAt(i)) % 100000;
    const rand = () => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    };
    const points = [];
    for (let x = 0; x <= 1000; x += 8) {
      const base = 0.25 + 0.6 * Math.abs(Math.sin(x / 180 + seed % 7));
      const amp = base * (0.55 + 0.45 * rand());
      points.push(x + "," + (50 - amp * 46).toFixed(1));
    }
    for (let x = 1000; x >= 0; x -= 8) {
      const base = 0.25 + 0.6 * Math.abs(Math.cos(x / 210 + seed % 5));
      const amp = base * (0.55 + 0.45 * rand());
      points.push(x + "," + (50 + amp * 46).toFixed(1));
    }
    return points.join(" ");
  }

  const waveCache = {};
  function wavePoints(assetId) {
    if (!waveCache[assetId]) waveCache[assetId] = wavePath(assetId || "clip");
    return waveCache[assetId];
  }

  /* -------------------------------- render ------------------------------- */
  SS.renderTimeline = function () {
    const state = SS.state;
    const lanes = $("lanes");
    const canvas = $("tl-canvas");
    const ruler = $("ruler");
    if (!lanes || !canvas || !ruler) return;

    const length = Math.max(state.duration, SS.contentEnd() + 2);
    const width = Math.max(length * state.pps + 240, 480);
    canvas.style.width = width + "px";
    lanes.style.width = width + "px";

    renderRuler(ruler, length, state.pps);
    renderHeaders();
    renderLanes(lanes);
    SS.renderPlayhead();
    SS.renderUndoState();
    SS.tickSaveLabel();
    if (SS.renderStatus) SS.renderStatus();

    const empty = $("tl-empty");
    if (empty) empty.hidden = state.clips.length > 0;
    const zoomVal = $("zoom-value");
    if (zoomVal) zoomVal.textContent = Math.round(state.pps) + " px/s";
    const zoomRange = $("zoom-range");
    if (zoomRange && document.activeElement !== zoomRange) zoomRange.value = String(nearestLadder(state.pps));
    const snapBtn = $("btn-snap");
    if (snapBtn) snapBtn.setAttribute("aria-pressed", String(state.snapping));
    const io = $("ruler-io");
    if (io) {
      const inP = state.inPoint;
      const outP = state.outPoint;
      io.hidden = inP == null || outP == null;
      if (inP != null && outP != null) {
        io.style.left = inP * state.pps + "px";
        io.style.width = Math.max(0, (outP - inP) * state.pps) + "px";
      }
    }
  };

  function renderRuler(ruler, length, pps) {
    const steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120];
    const step = steps.find((s) => s * pps >= 64) || 120;
    let html = "";
    for (let t = 0; t <= length + step; t += step) {
      const x = t * pps;
      html += '<span class="ruler__tick ruler__tick--major" style="left:' + x + "px;height:10px\"></span>";
      html +=
        '<span class="ruler__label" style="left:' + x + "px" + (t === 0 ? ";translate:0 0" : "") + '">' + SS.tcShort(t) + "</span>";
      // minor ticks at quarter steps when there is room
      if (step * pps >= 120) {
        for (let k = 1; k < 4; k += 1) {
          html += '<span class="ruler__tick" style="left:' + (t + (step * k) / 4) * pps + 'px;height:5px"></span>';
        }
      }
    }
    const io = '<div class="ruler__inout" id="ruler-io" hidden></div>';
    ruler.innerHTML = html + io;
    ruler.style.width = Math.max(length * pps + 240, 480) + "px";
    ruler.setAttribute("aria-valuemax", String(Math.round(length * SS.FPS)));
  }

  function renderHeaders() {
    const host = $("track-headers");
    if (!host) return;
    host.innerHTML = SS.state.tracks
      .map((track) => {
        const flags = [];
        if (track.kind === "video") {
          flags.push('<button class="flag" data-flag="hidden" aria-pressed="' + String(track.hidden) + '" title="إخفاء المسار" aria-label="إخفاء ' + track.label + '">' + (track.hidden ? "◌" : "▣") + "</button>");
          flags.push('<button class="flag" data-flag="muted" aria-pressed="' + String(track.muted) + '" title="كتم" aria-label="كتم ' + track.label + '">' + (track.muted ? "M" : "🔊") + "</button>");
        } else {
          flags.push('<button class="flag" data-flag="muted" aria-pressed="' + String(track.muted) + '" title="كتم" aria-label="كتم ' + track.label + '">' + (track.muted ? "M" : "🔊") + "</button>");
          flags.push('<button class="flag" data-flag="solo" aria-pressed="' + String(track.solo) + '" title="عزل" aria-label="عزل ' + track.label + '">S</button>');
        }
        flags.push('<button class="flag flag--lock" data-flag="locked" aria-pressed="' + String(track.locked) + '" title="قفل المسار" aria-label="قفل ' + track.label + '">' + (track.locked ? "🔒" : "🔓") + "</button>");
        return (
          '<div class="thead' + (track.locked ? " is-locked" : "") + '" data-head="' + track.id + '">' +
          '<div class="thead__name"><span class="thead__swatch" style="background:var(--track-' + track.kind + ')"></span>' +
          '<span class="thead__kind">' + track.label + "</span></div>" +
          '<div class="thead__flags">' + flags.join("") + "</div></div>"
        );
      })
      .join("");
  }

  function clipMarkup(clip) {
    const state = SS.state;
    const track = SS.trackById(clip.trackId);
    const kind = SS.kindOf(clip);
    const asset = SS.assetsById(clip.assetId);
    const left = clip.start * state.pps;
    const width = Math.max(2, clip.duration * state.pps);
    const selected = state.selection.has(clip.id);
    const cls = [
      "clip",
      kind === "audio" ? "clip--audio" : kind === "overlay" ? "clip--overlay" : "",
      selected ? "is-selected" : "",
      clip.enabled === false ? "is-disabled" : "",
      clip.missing && !clip.relinked ? "is-missing" : "",
    ]
      .filter(Boolean)
      .join(" ");

    let inner = '<div class="clip__body">';
    inner += '<span class="clip__name">' + SS.esc(clip.name) + "</span>";

    if (kind === "audio") {
      if (state.pps >= 8) {
        inner +=
          '<svg class="clip__wave" viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true">' +
          '<polygon points="' + wavePoints(clip.assetId) + '" fill="color-mix(in srgb, var(--success) 55%, transparent)"/></svg>';
      }
    } else if (kind === "overlay") {
      inner += '<div class="clip__film" style="background-image:repeating-linear-gradient(90deg, color-mix(in srgb, var(--on-accent) 12%, transparent) 0 3px, transparent 3px 22px)"></div>';
      if (width > 90) inner += '<span class="clip__sub" style="position:absolute;inset-block-end:4px;inset-inline-start:6px;font-size:9.5px;opacity:.75">' + SS.esc(clip.text || "") + "</span>";
    } else if (state.pps >= 8) {
      const frame = state.pps >= 80 ? Math.max(6, state.pps * 0.5) : Math.max(10, state.pps * 2);
      const h = asset ? asset.hue : 210;
      inner +=
        '<div class="clip__film" style="background-image:repeating-linear-gradient(90deg, hsl(' + h + ' 30% 42%) 0 ' +
        Math.max(2, frame - 1) + "px, hsl(" + h + " 30% 22%) " + Math.max(2, frame - 1) + "px " + frame + 'px)"></div>';
    }

    const badges = [];
    if ((clip.speed || 1) !== 1) badges.push((clip.speed || 1) + "×");
    if (asset && asset.proxy === "building") badges.push("◌");
    if (clip.missing && !clip.relinked) badges.push("⚠");
    if (badges.length) inner += '<span class="clip__badges">' + badges.map((b) => '<span class="clip__badge">' + b + "</span>").join("") + "</span>";

    if (clip.sourceIn > 0.001) inner += '<span class="clip__bound clip__bound--in" aria-hidden="true"></span>';
    if (asset && clip.sourceIn + clip.duration * (clip.speed || 1) >= asset.duration - 0.02) {
      inner += '<span class="clip__bound clip__bound--out" aria-hidden="true"></span>';
    }
    if (clip.sourceIn > 0.001) inner += '<span class="clip__trimmed" style="inset-inline-start:0;width:3px"></span>';
    inner += "</div>";

    const label =
      SS.esc(clip.name) + " من " + SS.tc(clip.start) + " إلى " + SS.tc(clip.start + clip.duration) + "، مسار " + (track ? track.label : "");

    return (
      '<div class="' + cls + '" data-clip="' + clip.id + '" style="left:' + left + "px;width:" + width + 'px" role="button" tabindex="0" aria-label="' + label + '">' +
      inner +
      '<div class="clip__edge clip__edge--in" data-edge="in" title="قصّ البداية"></div>' +
      '<div class="clip__edge clip__edge--out" data-edge="out" title="قصّ النهاية"></div>' +
      "</div>"
    );
  }

  function renderLanes(host) {
    const state = SS.state;
    host.innerHTML = state.tracks
      .map((track) => {
        const clips = SS.clipsOn(track.id).map(clipMarkup).join("");
        return (
          '<div class="track" data-track="' + track.id + '">' +
          '<div class="lane" data-lane="' + track.id + '">' + clips + "</div></div>"
        );
      })
      .join("");
  }

  SS.renderAll = function () {
    SS.renderTimeline();
    SS.renderPreview();
    SS.renderInspector();
    SS.renderUndoState();
    if (SS.renderBin) SS.renderBin();
  };

  /* --------------------------------- zoom -------------------------------- */
  function nearestLadder(pps) {
    let best = 0;
    SS.LADDER.forEach((v, i) => {
      if (Math.abs(v - pps) < Math.abs(SS.LADDER[best] - pps)) best = i;
    });
    return best;
  }

  SS.setZoom = function (index, anchorClientX) {
    const state = SS.state;
    const next = SS.clamp(index, 0, SS.LADDER.length - 1);
    const scroll = $("tl-scroll");
    const rect = $("lanes").getBoundingClientRect();
    const anchorX = anchorClientX == null ? scroll.clientWidth / 2 : anchorClientX - rect.left;
    const anchorTime = anchorX / state.pps;
    state.zoomIndex = next;
    state.pps = SS.LADDER[next];
    SS.renderAll();
    if (scroll) {
      const newRect = $("lanes").getBoundingClientRect();
      const delta = anchorTime * state.pps - (anchorClientX == null ? 0 : anchorClientX - newRect.left);
      scroll.scrollLeft += delta;
    }
  };

  SS.fit = function () {
    const scroll = $("tl-scroll");
    const duration = Math.max(1, SS.sequenceDuration());
    const pps = SS.clamp((scroll.clientWidth - 32) / duration, 2, 320);
    SS.state.pps = Math.round(pps * 10) / 10;
    SS.renderAll();
    if (scroll) scroll.scrollLeft = 0;
  };

  SS.zoomToSelection = function () {
    const selected = SS.selectedClips();
    if (!selected.length) return SS.fit();
    const start = Math.min(...selected.map((c) => c.start));
    const end = Math.max(...selected.map((c) => c.start + c.duration));
    const scroll = $("tl-scroll");
    SS.state.pps = SS.clamp((scroll.clientWidth - 64) / Math.max(0.5, end - start), 2, 320);
    SS.renderAll();
    scroll.scrollLeft = Math.max(0, start * SS.state.pps - 32);
  };

  /* ------------------------------ coordinates ---------------------------- */
  function lanesRect() {
    return $("lanes").getBoundingClientRect();
  }
  function timeAt(clientX) {
    return (clientX - lanesRect().left) / SS.state.pps;
  }
  function trackAt(clientY) {
    const index = Math.floor((clientY - lanesRect().top) / SS.ROW);
    return SS.state.tracks[index] || null;
  }

  function snapCandidates(excludeIds) {
    const state = SS.state;
    const values = [0, state.playhead, SS.sequenceDuration()];
    if (state.inPoint != null) values.push(state.inPoint);
    if (state.outPoint != null) values.push(state.outPoint);
    state.clips.forEach((clip) => {
      if (excludeIds && excludeIds.has(clip.id)) return;
      values.push(clip.start, clip.start + clip.duration);
    });
    if (state.pps >= 60) {
      const frame = 1 / SS.FPS;
      const near = Math.round(state.playhead / frame) * frame;
      values.push(near);
    }
    return values.sort((a, b) => a - b);
  }

  function snap(time, candidates, thresholdSeconds, enabled) {
    if (!enabled) return { time, guide: null };
    let best = null;
    candidates.forEach((value) => {
      const delta = Math.abs(value - time);
      if (delta <= thresholdSeconds && (!best || delta < best.delta)) best = { value, delta };
    });
    return best ? { time: best.value, guide: best } : { time, guide: null };
  }

  /* -------------------------------- overlays ----------------------------- */
  let guideEl = null;
  let ghostEl = null;
  let marqueeEl = null;

  function showGuide(time, raw) {
    if (!guideEl) {
      guideEl = document.createElement("div");
      guideEl.className = "snap-line";
      $("tl-canvas").appendChild(guideEl);
    }
    guideEl.style.left = time * SS.state.pps + "px";
    guideEl.dataset.offset = SS.offsetLabel(time - raw);
    guideEl.hidden = false;
  }
  function hideGuide() {
    if (guideEl) guideEl.hidden = true;
  }
  function showGhost(box, label, variant) {
    if (!ghostEl) {
      ghostEl = document.createElement("div");
      $("tl-canvas").appendChild(ghostEl);
    }
    ghostEl.className = "ghost" + (variant ? " ghost--" + variant : "");
    ghostEl.style.left = box.left + "px";
    ghostEl.style.top = box.top + "px";
    ghostEl.style.width = Math.max(2, box.width) + "px";
    ghostEl.style.height = box.height + "px";
    ghostEl.textContent = label || "";
    ghostEl.hidden = false;
  }
  function hideGhost() {
    if (ghostEl) ghostEl.hidden = true;
    document.querySelectorAll(".track--drop-ok,.track--drop-bad").forEach((n) => n.classList.remove("track--drop-ok", "track--drop-bad"));
  }

  /* --------------------------------- drag -------------------------------- */
  let drag = null;

  function beginDrag(event, clip, mode) {
    const state = SS.state;
    if (mode !== "marquee") {
      if (SS.isLocked(clip.trackId)) {
        SS.toast("المسار مقفل — افتح القفل للتحرير", { kind: "warn" });
        return null;
      }
      if (clip.missing && !clip.relinked) {
        /* allowed: missing media stays editable, only preview/export is blocked */
      }
    }
    const ids = state.selection.has(clip.id) ? new Set(state.selection) : new Set([clip.id]);
    return {
      mode,
      clip,
      ids,
      startX: event.clientX,
      startY: event.clientY,
      origin: state.clips.filter((c) => ids.has(c.id)).map((c) => ({ clip: c, start: c.start, duration: c.duration, sourceIn: c.sourceIn })),
      started: false,
      pointerId: event.pointerId,
      insert: false,
      forbidden: null,
      alt: event.altKey,
    };
  }

  function beginMarquee(event) {
    const rect = lanesRect();
    marqueeEl = document.createElement("div");
    marqueeEl.className = "marquee";
    $("tl-canvas").appendChild(marqueeEl);
    return {
      mode: "marquee",
      startX: event.clientX,
      startY: event.clientY,
      rect,
      scrollLeft: $("tl-scroll").scrollLeft,
      additive: event.shiftKey,
      base: new Set(event.shiftKey ? SS.state.selection : []),
      started: true,
    };
  }

  function onPointerDown(event) {
    if (event.button !== 0) return;
    const target = event.target;
    const clipEl = target.closest(".clip");
    const lane = target.closest(".lane");

    if (clipEl) {
      const clip = SS.state.clips.find((c) => c.id === clipEl.dataset.clip);
      if (!clip) return;
      const edge = target.closest("[data-edge]");
      const state = SS.state;
      if (edge) {
        drag = beginDrag(event, clip, "trim-" + edge.dataset.edge);
      } else if (event.altKey) {
        drag = beginDrag(event, clip, "slip");
      } else {
        if (event.shiftKey) {
          if (state.selection.has(clip.id)) state.selection.delete(clip.id);
          else state.selection.add(clip.id);
        } else if (!state.selection.has(clip.id)) {
          state.selection = new Set([clip.id]);
        }
        drag = beginDrag(event, clip, "move");
      }
      if (drag) {
        drag.originIds = new Set(drag.origin.map((o) => o.clip.id));
        drag.candidates = snapCandidates(drag.originIds).filter((v) => Number.isFinite(v));
        event.preventDefault();
        SS.renderAll();
      }
      return;
    }

    if (lane) {
      const track = SS.trackById(lane.dataset.lane);
      const t = Math.max(0, timeAt(event.clientX));
      if (!event.shiftKey) SS.state.selection = new Set();
      SS.state.cursorTime = t;
      SS.setPlayhead(t);
      if (!event.shiftKey && track) {
        drag = beginMarquee(event);
      }
      SS.renderAll();
    }
  }

  function onPointerMove(event) {
    const state = SS.state;
    state.cursorTime = Math.max(0, timeAt(event.clientX));
    if (!drag) return;

    if (drag.mode === "marquee") {
      if (!drag.started) return;
      const x1 = Math.min(drag.startX, event.clientX);
      const x2 = Math.max(drag.startX, event.clientX);
      const y1 = Math.min(drag.startY, event.clientY);
      const y2 = Math.max(drag.startY, event.clientY);
      marqueeEl.style.left = x1 - drag.rect.left + drag.scrollLeft + "px";
      marqueeEl.style.top = y1 - drag.rect.top + SS.RULER_H + "px";
      marqueeEl.style.width = x2 - x1 + "px";
      marqueeEl.style.height = y2 - y1 + "px";
      const t1 = (x1 - drag.rect.left) / state.pps;
      const t2 = (x2 - drag.rect.left) / state.pps;
      const row1 = Math.floor((y1 - drag.rect.top) / SS.ROW);
      const row2 = Math.floor((y2 - drag.rect.top) / SS.ROW);
      const hit = new Set(drag.base);
      state.clips.forEach((clip) => {
        const row = state.tracks.findIndex((tr) => tr.id === clip.trackId);
        if (row < row1 || row > row2) return;
        if (clip.start + clip.duration >= t1 && clip.start <= t2) hit.add(clip.id);
      });
      state.selection = hit;
      document.querySelectorAll(".clip").forEach((el) => el.classList.toggle("is-selected", hit.has(el.dataset.clip)));
      return;
    }

    if (!drag.started) {
      if (Math.abs(event.clientX - drag.startX) < 3 && Math.abs(event.clientY - drag.startY) < 3) return;
      drag.started = true;
      if (drag.mode === "move") drag.clipEl.classList.add("is-dragging");
    }

    const rawTime = timeAt(event.clientX);
    const threshold = 8 / state.pps;
    const allowSnap = state.snapping && !event.altKey;

    if (drag.mode === "trim-in" || drag.mode === "trim-out") {
      const clip = drag.clip;
      const track = SS.trackById(clip.trackId);
      const asset = SS.assetsById(clip.assetId);
      const speed = clip.speed || 1;
      const sourceDuration = asset ? asset.duration : clip.sourceIn + clip.duration * speed;
      const neighbours = SS.clipsOn(clip.trackId).filter((c) => c.id !== clip.id);
      const prevEnd = Math.max(0, ...neighbours.filter((c) => c.start + c.duration <= clip.start + 1e-4).map((c) => c.start + c.duration));
      const nextStart = Math.min(
        SS.sequenceDuration() + 30,
        ...neighbours.filter((c) => c.start >= clip.start + clip.duration - 1e-4).map((c) => c.start)
      );

      let edgeTime = drag.mode === "trim-in" ? clip.start : clip.start + clip.duration;
      const snapped = snap(rawTime, drag.candidates, threshold, allowSnap);
      if (snapped.guide) showGuide(snapped.time, rawTime);
      else hideGuide();
      edgeTime = snapped.time;

      if (drag.mode === "trim-in") {
        const minStart = Math.max(prevEnd, clip.start - clip.sourceIn / speed);
        const maxStart = clip.start + clip.duration - SS.MIN_CLIP;
        const newStart = SS.clamp(edgeTime, Math.max(0, minStart), maxStart);
        clip.sourceIn = Math.max(0, clip.sourceIn + (newStart - clip.start) * speed);
        clip.duration += clip.start - newStart;
        clip.start = newStart;
        if (clip.sourceIn < 1e-6) clip.sourceIn = 0;
        if (clip.assetId && prevEnd >= clip.start - 1e-6) {
          /* hit the neighbour: stop, no error (spec §5.6) */
        }
      } else {
        const maxEnd = Math.min(nextStart, clip.start + (sourceDuration - clip.sourceIn) / speed);
        const newEnd = SS.clamp(edgeTime, clip.start + SS.MIN_CLIP, maxEnd);
        clip.duration = newEnd - clip.start;
        if (track && asset) clip.duration = Math.min(clip.duration, (asset.duration - clip.sourceIn) / speed);
      }
      SS.renderTimeline();
      SS.renderPreview({ wait: false });
      SS.renderInspector();
      return;
    }

    if (drag.mode === "slip") {
      const clip = drag.clip;
      const asset = SS.assetsById(clip.assetId);
      const speed = clip.speed || 1;
      if (!asset) return;
      const delta = (event.clientX - drag.startX) / state.pps;
      const maxIn = Math.max(0, asset.duration - clip.duration * speed);
      clip.sourceIn = SS.clamp(drag.origin[0].sourceIn + delta * speed, 0, maxIn);
      SS.renderTimeline();
      SS.renderPreview({ wait: false });
      return;
    }

    /* move (and insert-on-existing-clip) */
    const targetTrack = trackAt(event.clientY) || SS.trackById(drag.clip.trackId);
    const kind = SS.kindOf(drag.clip);
    const delta = rawTime - timeAt(drag.startX);
    let newStart = drag.origin[0].start + delta;
    newStart = Math.max(0, newStart);

    const snapped = snap(newStart, drag.candidates, threshold, allowSnap);
    let start = snapped.time;
    if (snapped.guide) showGuide(start, newStart);
    else hideGuide();

    const forbidden = !SS.trackAccepts(targetTrack, kind)
      ? "مسار " + (kind === "audio" ? "فيديو" : "صوت") + " لا يقبل " + (kind === "audio" ? "صوتاً" : "فيديو")
      : SS.isLocked(targetTrack.id)
        ? "المسار مقفل"
        : null;

    const row = Math.max(0, state.tracks.findIndex((tr) => tr.id === targetTrack.id));
    const box = {
      left: start * state.pps,
      top: SS.RULER_H + row * SS.ROW + 6,
      width: drag.clip.duration * state.pps,
      height: SS.ROW - 12,
    };
    const over = SS.clipAt(targetTrack.id, start + 0.02) || SS.clipAt(targetTrack.id, start + drag.clip.duration - 0.02);
    const overOther = over && over.id !== drag.clip.id;

    document.querySelectorAll(".track").forEach((el) => {
      el.classList.toggle("track--drop-ok", el.dataset.track === targetTrack.id && !forbidden);
      el.classList.toggle("track--drop-bad", el.dataset.track === targetTrack.id && !!forbidden);
    });

    drag.target = { track: targetTrack, start, forbidden, insert: !!overOther };
    drag.origin.forEach((o) => {
      /* live ghost preview keeps the real clips in place */
    });

    if (forbidden) {
      showGhost(box, "✕ " + forbidden, "forbidden");
    } else if (overOther) {
      showGhost(box, "إدراج وإزاحة", "insert");
    } else {
      showGhost(box, Math.abs(snapped.time - newStart) > 0.001 ? SS.offsetLabel(snapped.time - newStart) : "", "");
    }
  }

  function endDrag(event) {
    const state = SS.state;
    if (!drag) return;

    if (drag.mode === "marquee") {
      marqueeEl?.remove();
      marqueeEl = null;
      drag = null;
      SS.renderAll();
      return;
    }

    hideGuide();
    hideGhost();
    drag.clipEl?.classList.remove("is-dragging");

    if (!drag.started) {
      drag = null;
      return;
    }

    if (drag.mode === "trim-in" || drag.mode === "trim-out") {
      const clip = drag.clip;
      const before = drag.origin[0];
      const changed = Math.abs(before.start - clip.start) > 1e-3 || Math.abs(before.duration - clip.duration) > 1e-3;
      if (!changed) {
        drag = null;
        return;
      }
      const snapshot = SS.snapshot();
      SS.pushHistory("قصّ");
      state.clips = snapshot.clips;
      const live = state.clips.find((c) => c.id === clip.id);
      Object.assign(live, {
        start: clip.start,
        duration: clip.duration,
        sourceIn: clip.sourceIn,
      });
      state.revision += 1;
      SS.touchSaveUI();
      drag = null;
      SS.renderAll();
      SS.toast("تم: قصّ");
      return;
    }

    if (drag.mode === "slip") {
      const clip = drag.clip;
      const before = drag.origin[0];
      const snapshot = SS.snapshot();
      SS.pushHistory("إزاحة المصدر");
      state.clips = snapshot.clips;
      const live = state.clips.find((c) => c.id === clip.id);
      live.sourceIn = clip.sourceIn;
      state.revision += 1;
      SS.touchSaveUI();
      drag = null;
      SS.renderAll();
      SS.toast("تم: إزاحة المصدر (slip)");
      return;
    }

    /* move / insert */
    const target = drag.target;
    if (!target) {
      drag = null;
      SS.renderAll();
      return;
    }
    if (target.forbidden) {
      SS.toast(target.forbidden, { kind: "warn" });
      drag = null;
      SS.renderAll();
      return;
    }

    const snapshot = SS.snapshot();
    const origin = drag.origin;
    const primary = origin[0];
    const delta = target.start - primary.start;
    const sameTrack = target.track.id === drag.clip.trackId;

    SS.pushHistory(target.insert ? "إدراج وإزاحة" : "نقل مقطع");
    state.clips = snapshot.clips;

    if (target.insert) {
      /* Dropping on top of a clip is never a silent overwrite (V-07 / UX-4).
         The drop point becomes a boundary: split the host clip there (the
         existing `clip.split` command), then shift everything after it by the
         inserted duration (`clip.move`). */
      const insertAt = SS.round3(target.start);
      const shiftBy = drag.clip.duration;
      const host = state.clips.find(
        (clip) =>
          clip.trackId === target.track.id &&
          !drag.ids.has(clip.id) &&
          insertAt > clip.start + 1e-4 &&
          insertAt < clip.start + clip.duration - 1e-4
      );
      if (host) {
        const speed = host.speed || 1;
        const left = SS.round3(insertAt - host.start);
        const tail = structuredClone(host);
        tail.id = SS.uid();
        tail.start = insertAt;
        tail.duration = SS.round3(host.duration - left);
        tail.sourceIn = SS.round3((host.sourceIn || 0) + left * speed);
        host.duration = left;
        state.clips.push(tail);
      }
      state.clips.forEach((clip) => {
        if (clip.trackId === target.track.id && clip.start >= insertAt - 1e-6 && !drag.ids.has(clip.id)) {
          clip.start = SS.round3(clip.start + shiftBy);
        }
      });
    }

    origin.forEach((o) => {
      const live = state.clips.find((c) => c.id === o.clip.id);
      if (!live) return;
      /* The primary lands exactly where the ghost promised (snapped target). */
      live.start = o.clip.id === primary.clip.id ? target.start : SS.round3(Math.max(0, o.start + delta));
    });
    const moved = state.clips.find((c) => c.id === primary.clip.id);
    if (moved && !sameTrack) {
      if (!SS.trackAccepts(target.track, SS.kindOf(moved))) {
        state.clips = snapshot.clips;
        drag = null;
        SS.renderAll();
        SS.toast("النوع لا يطابق المسار", { kind: "warn" });
        return;
      }
      moved.trackId = target.track.id;
    }
    state.revision += 1;
    SS.touchSaveUI();
    drag = null;
    SS.renderAll();
    SS.toast(target.insert ? "تم: إدراج وإزاحة" : "تم: نقل");
  }

  /* ------------------------------ operations ----------------------------- */
  SS.splitAtPlayhead = function () {
    const t = SS.state.playhead;
    const selected = SS.selectedClips();
    const targets = (selected.length ? selected : SS.state.clips.filter((c) => !SS.isLocked(c.trackId)))
      .filter((c) => t > c.start + 1e-4 && t < c.start + c.duration - 1e-4);
    if (!targets.length) {
      SS.toast("لا مقطع تحت رأس التشغيل", { kind: "warn" });
      return;
    }
    SS.mutate("قصّ", () => {
      targets.forEach((clip) => {
        const speed = clip.speed || 1;
        const leftDuration = SS.round3(t - clip.start);
        const right = structuredClone(clip);
        right.id = SS.uid();
        right.start = SS.round3(t);
        right.duration = SS.round3(clip.duration - leftDuration);
        right.sourceIn = SS.round3((clip.sourceIn || 0) + leftDuration * speed);
        clip.duration = leftDuration;
        SS.state.clips.push(right);
      });
    });
    SS.state.selection = new Set();
  };

  SS.splitAtCursor = function () {
    SS.state.playhead = SS.state.cursorTime;
    SS.splitAtPlayhead();
  };

  SS.joinSelected = function () {
    const selected = SS.selectedClips();
    if (selected.length !== 2) {
      SS.toast("حدّد مقطعين متجاورين من نفس الأصل", { kind: "warn" });
      return;
    }
    const sorted = [...selected].sort((a, b) => a.start - b.start);
    const [a, b] = sorted;
    const adjacent = Math.abs(a.start + a.duration - b.start) < 1 / SS.FPS + 0.001;
    const sameSource = a.assetId === b.assetId && (a.speed || 1) === (b.speed || 1);
    if (!adjacent || !sameSource) {
      SS.toast("لا يمكن الوصل: الأصل أو السرعة مختلفان", { kind: "warn" });
      return;
    }
    SS.mutate("وصل", () => {
      a.duration = SS.round3(a.duration + b.duration);
      SS.state.clips = SS.state.clips.filter((c) => c.id !== b.id);
      SS.state.selection = new Set([a.id]);
    });
  };

  SS.deleteSelected = function () {
    if (!SS.state.selection.size) return;
    SS.mutate("حذف", () => {
      SS.state.clips = SS.state.clips.filter((c) => !SS.state.selection.has(c.id));
      SS.state.selection = new Set();
    });
  };

  SS.selectAll = function () {
    SS.state.selection = new Set(SS.state.clips.map((c) => c.id));
    SS.renderAll();
  };

  SS.toggleClipEnabled = function (id) {
    const clip = SS.state.clips.find((c) => c.id === id);
    if (!clip) return;
    SS.mutate("تعطيل مقطع", () => { clip.enabled = !clip.enabled; });
  };

  /* -------------------------------- binding ------------------------------ */
  SS.bindTimeline = function () {
    const lanes = $("lanes");
    const ruler = $("ruler");
    const scroll = $("tl-scroll");

    lanes.addEventListener("pointerdown", onPointerDown);
    lanes.addEventListener("dblclick", (event) => {
      const clipEl = event.target.closest(".clip");
      if (clipEl) SS.toggleClipEnabled(clipEl.dataset.clip);
    });

    ruler.addEventListener("pointerdown", (event) => {
      const scrub = (e) => SS.setPlayhead(Math.max(0, timeAt(e.clientX)));
      scrub(event);
      const move = (e) => scrub(e);
      const up = () => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
      };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", up);
    });

    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", endDrag);
    window.addEventListener("pointercancel", endDrag);

    $("track-headers").addEventListener("click", (event) => {
      const flag = event.target.closest("[data-flag]");
      const head = event.target.closest("[data-head]");
      if (!head) return;
      const track = SS.trackById(head.dataset.head);
      if (!track) return;
      if (flag) {
        const name = flag.dataset.flag;
        SS.mutate("حالة المسار", () => { track[name] = !track[name]; }, { toast: false });
        SS.toast("تم تحديث المسار " + track.label, { ms: 1800 });
        return;
      }
      SS.state.selection = new Set(SS.clipsOn(track.id).map((c) => c.id));
      SS.renderAll();
    });

    scroll.addEventListener("scroll", () => {
      const headers = $("track-headers");
      if (headers) headers.style.transform = "translateY(" + -scroll.scrollTop + "px)";
    });

    scroll.addEventListener(
      "wheel",
      (event) => {
        if (!(event.ctrlKey || event.metaKey)) return;
        event.preventDefault();
        SS.setZoom(SS.state.zoomIndex + (event.deltaY < 0 ? 1 : -1), event.clientX);
      },
      { passive: false }
    );

    /* toolbar + zoom */
    $("btn-zoom-in").addEventListener("click", () => SS.setZoom(SS.state.zoomIndex + 1));
    $("btn-zoom-out").addEventListener("click", () => SS.setZoom(SS.state.zoomIndex - 1));
    $("zoom-range").addEventListener("input", (event) => SS.setZoom(Number(event.target.value)));
    $("btn-fit").addEventListener("click", () => SS.fit());
    $("btn-snap").addEventListener("click", () => {
      SS.state.snapping = !SS.state.snapping;
      SS.renderTimeline();
      SS.toast(SS.state.snapping ? "التصاق مفعّل" : "التصاق معطّل", { key: "N", ms: 1600 });
    });
    $("btn-split").addEventListener("click", () => SS.splitAtPlayhead());
    $("btn-undo").addEventListener("click", () => SS.undo());
    $("btn-redo").addEventListener("click", () => SS.redo());

    /* transport */
    document.querySelectorAll("[data-transport]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const what = btn.dataset.transport;
        SS.pause();
        if (what === "start") SS.setPlayhead(0);
        if (what === "end") SS.setPlayhead(SS.sequenceDuration());
        if (what === "back") SS.setPlayhead(SS.state.playhead - 1 / SS.FPS);
        if (what === "fwd") SS.setPlayhead(SS.state.playhead + 1 / SS.FPS);
      });
    });
    $("btn-play").addEventListener("click", () => SS.togglePlay());
    $("btn-safe").addEventListener("click", (event) => {
      SS.state.safe = !SS.state.safe;
      event.currentTarget.setAttribute("aria-pressed", String(SS.state.safe));
      $("safe-area").hidden = !SS.state.safe;
    });
    $("btn-mute").addEventListener("click", (event) => {
      SS.state.muted = !SS.state.muted;
      event.currentTarget.setAttribute("aria-pressed", String(SS.state.muted));
      event.currentTarget.firstChild.textContent = SS.state.muted ? "🔇 " : "🔊 ";
    });
    $("btn-fullscreen").addEventListener("click", () => {
      const viewer = $("viewer");
      if (document.fullscreenElement) document.exitFullscreen();
      else viewer.requestFullscreen?.();
    });
    $("preview-quality").addEventListener("change", (event) => {
      SS.toast("جودة المعاينة: " + event.target.options[event.target.selectedIndex].text, { ms: 1600 });
    });
    $("preview-zoom").addEventListener("change", (event) => {
      const frame = $("frame-bg");
      const value = event.target.value;
      frame.style.width = value === "fit" ? "" : "min(100%, " + Math.round(Number(value) * 46) + "vw)";
    });
  };

  /* -------------------------------- keyboard ----------------------------- */
  SS.bindKeys = function () {
    document.addEventListener("keydown", (event) => {
      const tag = (event.target.tagName || "").toLowerCase();
      const typing = tag === "input" || tag === "textarea" || tag === "select";
      const dialogOpen = !!document.querySelector("dialog[open]");
      const mod = event.ctrlKey || event.metaKey;

      if (event.key === "Escape") {
        if (dialogOpen) return;
        SS.state.selection = new Set();
        SS.renderAll();
        return;
      }
      if (typing) return;
      if (dialogOpen && event.key !== "Escape") {
        if (!(mod && event.key.toLowerCase() === "e")) return;
      }

      if (mod && event.key.toLowerCase() === "e") {
        event.preventDefault();
        SS.openExport?.();
        return;
      }
      if (mod && event.key.toLowerCase() === "z") {
        event.preventDefault();
        event.shiftKey ? SS.redo() : SS.undo();
        return;
      }
      if (mod && event.key.toLowerCase() === "j") {
        event.preventDefault();
        SS.joinSelected();
        return;
      }
      if (mod && event.key.toLowerCase() === "a") {
        event.preventDefault();
        SS.selectAll();
        return;
      }

      switch (event.key) {
        case " ":
          event.preventDefault();
          SS.togglePlay();
          break;
        case "ArrowLeft":
          event.preventDefault();
          SS.nudge(event.shiftKey ? -1 : -1 / SS.FPS);
          break;
        case "ArrowRight":
          event.preventDefault();
          SS.nudge(event.shiftKey ? 1 : 1 / SS.FPS);
          break;
        case "ArrowUp":
        case "ArrowDown": {
          event.preventDefault();
          const selected = SS.selectedClips()[0];
          if (!selected) break;
          const list = SS.clipsOn(selected.trackId);
          const index = list.findIndex((c) => c.id === selected.id);
          const next = list[index + (event.key === "ArrowDown" ? 1 : -1)];
          if (next) {
            SS.state.selection = new Set([next.id]);
            SS.renderAll();
          }
          break;
        }
        case "Home":
          event.preventDefault();
          SS.pause();
          SS.setPlayhead(0);
          break;
        case "End":
          event.preventDefault();
          SS.pause();
          SS.setPlayhead(SS.sequenceDuration());
          break;
        case "Delete":
        case "Backspace":
          event.preventDefault();
          SS.deleteSelected();
          break;
        case "s":
        case "S":
          event.preventDefault();
          event.shiftKey ? SS.splitAtCursor() : SS.splitAtPlayhead();
          break;
        case "i":
        case "I":
          SS.state.inPoint = SS.state.playhead;
          SS.renderAll();
          break;
        case "o":
        case "O":
          SS.state.outPoint = SS.state.playhead;
          SS.renderAll();
          break;
        case "n":
        case "N":
          SS.state.snapping = !SS.state.snapping;
          SS.renderAll();
          break;
        case "z":
        case "Z":
          event.shiftKey ? SS.zoomToSelection() : SS.fit();
          break;
        case "=":
        case "+":
          SS.setZoom(SS.state.zoomIndex + 1);
          break;
        case "-":
          SS.setZoom(SS.state.zoomIndex - 1);
          break;
        case "j":
          SS.ratePlay(-2);
          break;
        case "k":
          SS.pause();
          SS.state.rate = 1;
          break;
        case "l":
          SS.ratePlay(2);
          break;
        case "m":
          SS.state.muted = !SS.state.muted;
          $("btn-mute").setAttribute("aria-pressed", String(SS.state.muted));
          break;
        case "f":
        case "F":
          $("btn-fullscreen").click();
          break;
        default:
          break;
      }
    });
  };
})();
