/* Shadow Studio — UX-P1 prototype
 * core.js: state, helpers, preview, transport, inspector, undo/save.
 * All modules share the global `SS` namespace and are loaded in order. */
(function () {
  "use strict";

  const SS = (window.SS = window.SS || {});
  SS.FPS = 30;
  SS.ROW = 56;
  SS.RULER_H = 28;
  SS.MIN_CLIP = 0.1;
  SS.LADDER = [2, 5, 10, 20, 40, 80, 160, 320];
  SS.DEFAULT_DIR = "~/Videos/shadow-out";

  /* ------------------------------- helpers ------------------------------- */
  SS.clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  SS.uid = () => "c" + Math.random().toString(36).slice(2, 8);
  SS.round3 = (v) => Math.round(v * 1000) / 1000;

  SS.tc = function (seconds) {
    const t = Math.max(0, seconds);
    const total = Math.round(t * SS.FPS);
    const f = total % SS.FPS;
    const s = Math.floor(total / SS.FPS);
    const pad = (n) => String(n).padStart(2, "0");
    return (
      pad(Math.floor(s / 3600)) + ":" + pad(Math.floor(s / 60) % 60) + ":" + pad(s % 60) + ":" + pad(f)
    );
  };

  SS.tcShort = function (seconds) {
    const total = Math.max(0, Math.round(seconds * SS.FPS));
    const pad = (n) => String(n).padStart(2, "0");
    return pad(Math.floor(total / SS.FPS / 60) % 60) + ":" + pad(Math.floor(total / SS.FPS) % 60);
  };

  /* Signed frame offset, the label a snap guide shows in the timeline. */
  SS.offsetLabel = function (delta) {
    const frames = Math.round(Math.abs(delta) * SS.FPS);
    const sign = delta < 0 ? "-" : "+";
    return sign + "00:00:" + String(Math.floor(frames / SS.FPS) % 60).padStart(2, "0") + ":" + String(frames % SS.FPS).padStart(2, "0");
  };

  SS.esc = (s) =>
    String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  /* -------------------------------- state -------------------------------- */
  const seedAssets = [
    { id: "a-intro", name: "intro-4k.mp4", kind: "video", w: 3840, h: 2160, duration: 12, size: "412 MB", proxy: "ready", hue: 212 },
    { id: "a-broll", name: "broll-city.mp4", kind: "video", w: 1920, h: 1080, duration: 18, size: "186 MB", proxy: "ready", hue: 286 },
    { id: "a-vo", name: "vo-take3.wav", kind: "audio", duration: 22, size: "3.8 MB", hue: 164 },
    { id: "a-music", name: "music-bed.mp3", kind: "audio", duration: 70, size: "6.4 MB", hue: 118 },
  ];

  const seedTracks = [
    { id: "V2", kind: "video", label: "V2", locked: false, muted: false, solo: false, hidden: false },
    { id: "V1", kind: "video", label: "V1", locked: false, muted: false, solo: false, hidden: false },
    { id: "T1", kind: "overlay", label: "T1", locked: false, muted: false, solo: false, hidden: false },
    { id: "A1", kind: "audio", label: "A1", locked: false, muted: false, solo: false, hidden: false },
    { id: "A2", kind: "audio", label: "A2", locked: false, muted: false, solo: false, hidden: false },
  ];

  const seedClips = [
    { id: "c-intro", trackId: "V1", assetId: "a-intro", name: "intro-4k.mp4", start: 0, duration: 9.2, sourceIn: 0.4, speed: 1, enabled: true, opacity: 1 },
    { id: "c-broll", trackId: "V2", assetId: "a-broll", name: "broll-city.mp4", start: 2.2, duration: 6.4, sourceIn: 3.1, speed: 1.5, enabled: true, opacity: 1 },
    { id: "c-title", trackId: "T1", assetId: null, name: "عنوان الحلقة", start: 3.2, duration: 5.4, text: "الحلقة 12 — مقدمة", enabled: true, opacity: 1 },
    { id: "c-vo", trackId: "A1", assetId: "a-vo", name: "vo-take3.wav", start: 0.2, duration: 21, sourceIn: 0, gain: -3, fadeIn: 0.2, fadeOut: 0.4, enabled: true },
    { id: "c-music", trackId: "A2", assetId: "a-music", name: "music-bed.mp3", start: 0, duration: 24.5, sourceIn: 5, gain: -18, fadeIn: 1, fadeOut: 2, enabled: true },
  ];

  SS.state = {
    assets: structuredClone(seedAssets),
    tracks: structuredClone(seedTracks),
    clips: structuredClone(seedClips),
    selection: new Set(),
    playhead: 4.1,
    pps: 20,
    zoomIndex: 3,
    snapping: true,
    inPoint: null,
    outPoint: null,
    duration: 30,
    revision: 218,
    cacheGb: 3.2,
    playing: false,
    rate: 1,
    muted: false,
    volume: 80,
    safe: false,
    missingDemo: false,
    saveAt: Date.now(),
    lastSaveLabel: "الآن",
    exportJobs: [],
    exporting: null,
    export: {
      preset: "mp4-h264-1080p",
      fileName: "final-v3.mp4",
      dir: SS.DEFAULT_DIR,
      advanced: { videoBitrate: 12000, crf: null, audioBitrate: 192, loudness: -14, faststart: true, range: "full" },
      unsupportedEffects: false,
    },
    harness: { missing: false, disk: false, exists: false, crash: false, timeout: false, unsupported: false, queue: false, slow: false, interrupt: false },
    cursorTime: 0,
    notif: 0,
  };

  /* ------------------------------ selectors ------------------------------ */
  SS.assetsById = (id) => SS.state.assets.find((a) => a.id === id) || null;
  SS.trackById = (id) => SS.state.tracks.find((t) => t.id === id) || null;
  SS.clipsOn = (trackId) =>
    SS.state.clips.filter((c) => c.trackId === trackId).sort((a, b) => a.start - b.start);
  SS.contentEnd = () =>
    SS.state.clips.reduce((max, c) => Math.max(max, c.start + c.duration), 0);
  SS.sequenceDuration = () => Math.max(SS.state.duration, SS.contentEnd());
  SS.clipAt = (trackId, t) =>
    SS.clipsOn(trackId).find((c) => t >= c.start && t < c.start + c.duration) || null;
  SS.selectedClips = () => SS.state.clips.filter((c) => SS.state.selection.has(c.id));
  SS.kindOf = (clip) => {
    if (clip.kind) return clip.kind;
    if (typeof clip.text === "string") return "overlay";
    const track = SS.trackById(clip.trackId);
    if (track && track.kind === "overlay") return "overlay";
    const asset = SS.assetsById(clip.assetId);
    return asset ? asset.kind : "video";
  };
  SS.hasAudio = () => SS.state.clips.some((c) => SS.kindOf(c) === "audio");
  SS.trackAccepts = (track, kind) =>
    track.kind === "video" ? kind === "video" : track.kind === "overlay" ? kind === "overlay" : kind === "audio";
  SS.isLocked = (trackId) => {
    const track = SS.trackById(trackId);
    return !track || track.locked;
  };

  /* -------------------------------- toasts ------------------------------- */
  SS.toast = function (text, opts) {
    const box = document.getElementById("toasts");
    const node = document.createElement("div");
    node.className = "toast" + (opts && opts.kind ? " toast--" + opts.kind : "");
    node.innerHTML = "<span>" + SS.esc(text) + "</span>" + (opts && opts.key ? '<span class="toast__key">' + SS.esc(opts.key) + "</span>" : "");
    box.appendChild(node);
    setTimeout(() => node.remove(), (opts && opts.ms) || 4000);
  };

  /* --------------------------- history / saving -------------------------- */
  const history = { undo: [], redo: [] };

  SS.snapshot = () => ({
    clips: structuredClone(SS.state.clips),
    tracks: structuredClone(SS.state.tracks),
    selection: [...SS.state.selection],
  });

  SS.pushHistory = function (label) {
    history.undo.push({ label, snap: SS.snapshot() });
    if (history.undo.length > 60) history.undo.shift();
    history.redo.length = 0;
    SS.renderUndoState();
  };

  SS.mutate = function (label, fn, opts) {
    if (!opts || opts.history !== false) SS.pushHistory(label);
    fn();
    SS.state.revision += 1;
    SS.state.saveAt = Date.now();
    SS.state.lastSaveLabel = "الآن";
    SS.touchSaveUI();
    SS.renderAll();
    if (!opts || opts.toast !== false) SS.toast("تم: " + label, { ms: 2200 });
  };

  SS.undo = function () {
    const entry = history.undo.pop();
    if (!entry) return;
    history.redo.push({ label: entry.label, snap: SS.snapshot() });
    SS.state.clips = entry.snap.clips;
    SS.state.tracks = entry.snap.tracks;
    SS.state.selection = new Set(entry.snap.selection);
    SS.state.revision += 1;
    SS.renderAll();
    SS.renderUndoState();
    SS.toast("تم التراجع: " + entry.label, { key: "Ctrl+Z" });
  };

  SS.redo = function () {
    const entry = history.redo.pop();
    if (!entry) return;
    history.undo.push({ label: entry.label, snap: SS.snapshot() });
    SS.state.clips = entry.snap.clips;
    SS.state.tracks = entry.snap.tracks;
    SS.state.selection = new Set(entry.snap.selection);
    SS.state.revision += 1;
    SS.renderAll();
    SS.renderUndoState();
    SS.toast("تمت الإعادة: " + entry.label, { key: "Shift+Ctrl+Z" });
  };

  SS.renderUndoState = function () {
    const undo = document.getElementById("btn-undo");
    const redo = document.getElementById("btn-redo");
    if (undo) undo.disabled = history.undo.length === 0;
    if (redo) redo.disabled = history.redo.length === 0;
  };

  SS.touchSaveUI = function () {
    const node = document.getElementById("save-state");
    if (!node) return;
    node.innerHTML =
      'حفظ <span class="save__tick">✓</span> <span class="save__time">' +
      SS.esc(SS.state.lastSaveLabel) +
      "</span>";
  };

  SS.tickSaveLabel = function () {
    const seconds = Math.round((Date.now() - SS.state.saveAt) / 1000);
    SS.state.lastSaveLabel = seconds < 5 ? "الآن" : "قبل " + seconds + " ث";
    const label = document.querySelector("#save-state .save__time");
    if (label) label.textContent = SS.state.lastSaveLabel;
    const rev = document.getElementById("status-rev");
    if (rev) rev.textContent = "Rev " + SS.state.revision;
  };

  /* -------------------------------- preview ------------------------------ */
  const preview = { waitingUntil: 0, lastSeek: 0, timers: [] };

  SS.assetGradient = function (asset, angle) {
    if (!asset) return "linear-gradient(135deg,#101216,#07080a)";
    const h = asset.hue || 210;
    return (
      "linear-gradient(" + (angle || 135) + "deg, hsl(" + h + " 38% 26%), hsl(" + ((h + 32) % 360) + " 34% 13%))"
    );
  };

  /* The prototype never paints a synthetic "current frame" while the real one
     is late: the previous frame dims and a ◌ badge appears (spec §6.2). */
  SS.seekPreview = function (immediate) {
    const scene = document.getElementById("frame-scene");
    const wait = document.getElementById("wait-badge");
    const chip = document.getElementById("slow-chip");
    if (!scene) return;
    preview.timers.forEach(clearTimeout);
    preview.timers = [];
    if (immediate) {
      scene.classList.remove("is-waiting");
      wait.hidden = true;
      chip.hidden = true;
      return;
    }
    scene.classList.add("is-waiting");
    wait.hidden = false;
    chip.hidden = true;
    const latency = SS.state.harness.slow && SS.state.exporting ? 420 : 80 + Math.random() * 60;
    preview.timers.push(
      setTimeout(() => {
        scene.classList.remove("is-waiting");
        wait.hidden = true;
      }, latency)
    );
    preview.timers.push(setTimeout(() => { chip.hidden = false; }, 120));
    preview.timers.push(setTimeout(() => { chip.textContent = "المعاينة بطيئة"; }, 1500));
  };

  SS.renderPreview = function (opts) {
    const state = SS.state;
    const t = state.playhead;
    const scene = document.getElementById("frame-scene");
    const overlay = document.getElementById("frame-overlay");
    const missing = document.getElementById("missing-badge");
    const tcCurrent = document.getElementById("tc-current");
    const tcTotal = document.getElementById("tc-total");
    const tlTc = document.getElementById("tl-tc");
    if (!scene) return;

    const videoTracks = state.tracks.filter((tr) => tr.kind === "video" && !tr.hidden).reverse();
    let top = null;
    let topClip = null;
    for (const track of videoTracks) {
      const clip = SS.clipAt(track.id, t);
      if (clip && clip.enabled) {
        topClip = clip;
        break;
      }
    }
    if (topClip) {
      const asset = SS.assetsById(topClip.assetId);
      top = { asset, clip: topClip };
    }

    scene.style.background = top ? SS.assetGradient(top.asset) : "linear-gradient(135deg,#0b0c0f,#050608)";
    let inner = "";
    if (top) {
      const src = top.clip.sourceIn + (t - top.clip.start) * (top.clip.speed || 1);
      inner =
        '<div class="viewer__scene__label"><span>' + SS.esc(top.asset ? top.asset.name : "") + "</span><span>" + SS.tc(src) + "</span></div>";
    } else {
      inner = '<div class="viewer__scene__label"><span>لا شيء لعرضه</span></div>';
    }
    scene.innerHTML = inner;

    const visibleMissing = top && (top.clip.missing || SS.state.harness.missing) && !top.clip.relinked;
    missing.hidden = !visibleMissing;
    if (visibleMissing) scene.style.background = "linear-gradient(135deg,#140b0b,#080505)";

    const textClip = SS.state.tracks
      .filter((tr) => tr.kind === "overlay")
      .flatMap((tr) => SS.clipsOn(tr.id))
      .find((c) => c.enabled && c.text && t >= c.start && t < c.start + c.duration);
    if (textClip) {
      overlay.hidden = false;
      overlay.textContent = textClip.text;
      overlay.classList.toggle("is-approx", !!textClip.approx);
      overlay.style.insetBlockEnd = textClip.lane === "top" ? "auto" : "18%";
      overlay.style.insetBlockStart = textClip.lane === "top" ? "10%" : "auto";
    } else {
      overlay.hidden = true;
    }

    tcCurrent.textContent = SS.tc(t);
    tcTotal.textContent = SS.tc(SS.sequenceDuration());
    if (tlTc) tlTc.textContent = SS.tc(t);
    const io = document.getElementById("io-readout");
    if (io)
      io.innerHTML =
        "I — " + (state.inPoint == null ? "—" : SS.tc(state.inPoint)) + " · O — " + (state.outPoint == null ? "—" : SS.tc(state.outPoint));
    if (!opts || opts.wait !== false) SS.seekPreview(!!SS.state.playing);
  };

  /* ------------------------------- transport ----------------------------- */
  let rafId = 0;
  let lastTick = 0;

  SS.setPlayhead = function (t, opts) {
    SS.state.playhead = SS.clamp(t, 0, SS.sequenceDuration());
    if (opts && opts.wait === false) SS.renderPreview({ wait: false });
    else SS.renderPreview();
    SS.renderPlayhead();
  };

  SS.renderPlayhead = function () {
    const ph = document.getElementById("playhead");
    if (!ph) return;
    ph.style.left = SS.state.playhead * SS.state.pps + "px";
    const ruler = document.getElementById("ruler");
    if (ruler) ruler.setAttribute("aria-valuenow", String(Math.round(SS.state.playhead * SS.FPS)));
  };

  function frame(now) {
    const state = SS.state;
    if (!state.playing) return;
    const dt = (now - lastTick) / 1000 || 0;
    lastTick = now;
    let t = state.playhead + dt * state.rate;
    if (t >= SS.sequenceDuration()) {
      t = SS.sequenceDuration();
      state.playing = false;
      syncPlayButton();
    }
    state.playhead = Math.max(0, t);
    SS.renderPreview({ wait: false });
    SS.renderPlayhead();
    if (state.playing) rafId = requestAnimationFrame(frame);
  }

  function syncPlayButton() {
    const btn = document.getElementById("btn-play");
    if (btn) {
      btn.textContent = SS.state.playing ? "❚❚" : "▶";
      btn.setAttribute("aria-label", SS.state.playing ? "إيقاف" : "تشغيل");
    }
  }

  SS.play = function () {
    if (SS.state.playing) return;
    if (SS.state.playhead >= SS.sequenceDuration()) SS.state.playhead = 0;
    SS.state.playing = true;
    SS.state.rate = SS.state.rate || 1;
    lastTick = performance.now();
    rafId = requestAnimationFrame(frame);
    syncPlayButton();
  };

  SS.pause = function () {
    SS.state.playing = false;
    cancelAnimationFrame(rafId);
    syncPlayButton();
    SS.renderPreview();
  };

  SS.togglePlay = () => (SS.state.playing ? SS.pause() : SS.play());

  SS.nudge = function (seconds) {
    SS.pause();
    SS.setPlayhead(SS.state.playhead + seconds);
  };

  SS.ratePlay = function (rate) {
    SS.state.rate = rate;
    SS.play();
  };

  /* ------------------------------- inspector ----------------------------- */
  function field(label, control) {
    return '<div class="insp__row"><span>' + label + "</span>" + control + "</div>";
  }

  function slider(id, value, min, max, step) {
    return (
      '<input class="input" type="range" data-range="' + id + '" value="' + value + '" min="' + min + '" max="' + max +
      '" step="' + step + '" aria-label="' + id + '">'
    );
  }

  SS.renderInspector = function () {
    const host = document.getElementById("inspector");
    if (!host) return;
    const selected = SS.selectedClips();

    if (selected.length === 0) {
      const trackCount = SS.state.tracks.length;
      host.innerHTML =
        '<div class="insp"><div class="insp__head"><div><p class="insp__eyebrow">تسلسل</p>' +
        '<p class="insp__title">الحلقة 12</p></div><span class="badge">Rev ' + SS.state.revision + "</span></div>" +
        '<div class="insp__group"><h4>معلومات</h4>' +
        field("الدقة", '<span class="num">1920×1080</span>') +
        field("المعدل", '<span class="num">29.97 fps</span>') +
        field("المدة", '<span class="num">' + SS.tc(SS.sequenceDuration()) + "</span>") +
        field("المسارات", '<span class="num">' + trackCount + "</span>") +
        "</div>" +
        '<div class="insp__group"><h4>اختيار</h4><p class="insp__note">لا شيء محدد. انقر مقطعاً لعرض خصائصه، أو اسحب على فراغ المسار لتحديد عدة مقاطع.</p></div>' +
        '<div class="insp__group"><h4>مساحة العمل</h4><p class="insp__note">اسحب مقطعاً لتغيير موضعه، حافة لتقصيره، <span class="num">S</span> للقصّ عند رأس التشغيل.</p></div></div>';
      return;
    }

    if (selected.length > 1) {
      host.innerHTML =
        '<div class="insp"><div class="insp__head"><div><p class="insp__eyebrow">تحديد متعدد</p>' +
        '<p class="insp__title">' + selected.length + " مقاطع</p></div></div>" +
        '<div class="insp__group"><h4>خصائص مشتركة</h4>' +
        field("الشفافية", '<div class="ctl">' + slider("opacity", 100, 0, 100, 1) + '<span class="num">%</span></div>') +
        field("المدة", '<span class="num">' + SS.tc(selected.reduce((s, c) => s + c.duration, 0)) + "</span>") +
        '<p class="insp__note">أي تعديل هنا يُطبَّق كمعاملة واحدة (خطوة تراجع واحدة).</p></div></div>';
      return;
    }

    const clip = selected[0];
    const track = SS.trackById(clip.trackId);
    const kind = SS.kindOf(clip);
    const asset = SS.assetsById(clip.assetId);
    const head =
      '<div class="insp__head"><div><p class="insp__eyebrow">' + (track ? SS.esc(track.label) : "") + " · " +
      (kind === "audio" ? "صوت" : kind === "overlay" ? "نص" : "فيديو") + '</p><p class="insp__title">' +
      SS.esc(clip.name) + "</p></div></div>";

    let body = "";
    if (clip.missing && !clip.relinked) {
      body +=
        '<div class="danger-box"><strong>أصل مفقود</strong><span dir="ltr">' + SS.esc(clip.name) +
        "</span><br>الملف غير موجود في مساره الأصلي. المقاطع التابعة له لن تُصدَّر حتى يُعاد الربط." +
        '<div style="margin-top:8px"><button class="btn btn--ghost" data-action="relink">إعادة الربط</button></div></div>';
    }

    if (kind === "overlay") {
      body +=
        '<div class="insp__group"><h4>النص</h4>' +
        '<textarea class="input" rows="3" data-text="' + clip.id + '" aria-label="نص الطبقة">' + SS.esc(clip.text || "") + "</textarea>" +
        '<p class="insp__note">يُعاد رسم النص في الخلفية؛ حتى يصل الـ raster يظهر وسم «معاينة تقريبية».</p>' +
        field("الموضع", '<select class="select" data-field="lane"><option value="bottom"' + (clip.lane !== "top" ? " selected" : "") + '>أسفل</option><option value="top"' + (clip.lane === "top" ? " selected" : "") + ">أعلى</option></select>") +
        field("الدخول", '<span class="num">fade · 0.25s</span>') +
        "</div>";
    } else if (kind === "audio") {
      body +=
        '<div class="insp__group"><h4>الصوت</h4>' +
        field("Gain", '<div class="ctl">' + slider("gain", clip.gain || 0, -30, 12, 1) + '<span class="num">dB</span></div>') +
        field("Fade in", '<span class="num">' + (clip.fadeIn || 0).toFixed(2) + "s</span>") +
        field("Fade out", '<span class="num">' + (clip.fadeOut || 0).toFixed(2) + "s</span>") +
        field("Pan", '<span class="num">C</span>') +
        "</div>";
    } else {
      body +=
        '<div class="insp__group"><h4>Transform</h4>' +
        field("X / Y", '<span class="num">0 · 0</span>') +
        field("Scale", '<span class="num">100%</span>') +
        field("الشفافية", '<div class="ctl">' + slider("opacity", Math.round((clip.opacity ?? 1) * 100), 0, 100, 1) + '<span class="num">%</span></div>') +
        field("السرعة", '<select class="select" data-field="speed">' +
          [0.5, 1, 1.5, 2].map((s) => '<option value="' + s + '"' + ((clip.speed || 1) === s ? " selected" : "") + ">" + s + "×</option>").join("") +
          "</select>") +
        "</div>" +
        '<div class="insp__group"><h4>المؤثرات</h4>' +
        '<div class="effect"><span>shadow.blur.gaussian</span><span class="effect__val">r 12 · 0→0.5</span></div>' +
        '<p class="insp__note">منحنى المقدار: 0 عند 0s ← 0.5 عند 2s (ease_in_out)، ثم يثبت.</p>' +
        "</div>";
    }

    body +=
      '<div class="insp__group"><h4>المصدر</h4>' +
      field("In", '<span class="num">' + SS.tc(clip.sourceIn || 0) + "</span>") +
      field("Out", '<span class="num">' + SS.tc((clip.sourceIn || 0) + clip.duration * (clip.speed || 1)) + "</span>") +
      field("المدة", '<span class="num">' + SS.tc(clip.duration) + "</span>") +
      (asset ? field("الدقة", '<span class="num">' + asset.w + "×" + asset.h + "</span>") : "") +
      "</div>" +
      '<div class="insp__group" style="display:flex;gap:6px;flex-wrap:wrap">' +
      '<button class="btn btn--ghost" data-action="split">قصّ عند رأس التشغيل</button>' +
      '<button class="btn btn--ghost" data-action="delete">حذف</button></div>';

    host.innerHTML = '<div class="insp">' + head + body + "</div>";
  };

  /* Inspector delegation: every control reports through data attributes. */
  /* Panel drawers (spec §3.1): under 1280px the media bin is a drawer,
     under 1100px the inspector is one. Both are off-canvas by default and
     share a scrim; Escape and the scrim dismiss them. */
  SS.bindLayout = function () {
    const body = document.body;
    const binBtn = document.getElementById("btn-bin");
    const inspBtn = document.getElementById("btn-insp");
    const scrim = document.getElementById("drawer-scrim");

    const setOpen = function (which, open) {
      const cls = which === "bin" ? "is-bin-open" : "is-insp-open";
      const btn = which === "bin" ? binBtn : inspBtn;
      body.classList.toggle(cls, open);
      btn.setAttribute("aria-expanded", String(open));
    };
    const closeAll = function () {
      setOpen("bin", false);
      setOpen("insp", false);
    };
    const isOpen = function (which) {
      return body.classList.contains(which === "bin" ? "is-bin-open" : "is-insp-open");
    };

    /* Only one drawer at a time so the scrim never covers the other. */
    binBtn.addEventListener("click", function () {
      const open = !isOpen("bin");
      if (open) setOpen("insp", false);
      setOpen("bin", open);
    });
    inspBtn.addEventListener("click", function () {
      const open = !isOpen("insp");
      if (open) setOpen("bin", false);
      setOpen("insp", open);
    });
    scrim.addEventListener("click", closeAll);

    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;
      const dialog = document.getElementById("export-dialog");
      if (dialog && dialog.open) return;
      if (isOpen("bin") || isOpen("insp")) {
        /* Take Escape from the global shortcut handler: dismissing the drawer
           must not also clear the timeline selection. */
        event.stopImmediatePropagation();
        event.preventDefault();
        closeAll();
      }
    });

    /* Growing the window past a breakpoint returns the panel to the layout. */
    window.addEventListener("resize", function () {
      if (window.innerWidth > 1280) closeAll();
      else if (window.innerWidth > 1100) setOpen("insp", false);
    });
  };

  SS.bindInspector = function () {
    const host = document.getElementById("inspector");
    if (!host) return;
    host.addEventListener("input", (event) => {
      const target = event.target;
      const selected = SS.selectedClips();
      if (target.dataset.text) {
        const clip = SS.state.clips.find((c) => c.id === target.dataset.text);
        if (!clip) return;
        clip.text = target.value;
        clip.approx = true;
        SS.renderPreview({ wait: false });
        clearTimeout(clip._approxTimer);
        clip._approxTimer = setTimeout(() => {
          clip.approx = false;
          SS.renderPreview({ wait: false });
          SS.toast("تم تحديث raster النص");
        }, 300);
        return;
      }
      if (target.dataset.range && selected.length) {
        const value = Number(target.value);
        selected.forEach((clip) => {
          if (target.dataset.range === "opacity") clip.opacity = value / 100;
          if (target.dataset.range === "gain") clip.gain = value;
        });
        SS.renderPreview({ wait: false });
        SS.state.revision += 1;
        SS.touchSaveUI();
      }
    });
    host.addEventListener("change", (event) => {
      const target = event.target;
      const clip = SS.selectedClips()[0];
      if (!clip) return;
      if (target.dataset.field === "speed") {
        SS.mutate("تغيير السرعة", () => { clip.speed = Number(target.value); });
      }
      if (target.dataset.field === "lane") {
        SS.mutate("نقل النص", () => { clip.lane = target.value; });
      }
    });
    host.addEventListener("click", (event) => {
      const action = event.target.closest("[data-action]");
      if (!action) return;
      if (action.dataset.action === "delete") SS.deleteSelected();
      if (action.dataset.action === "split") SS.splitAtPlayhead();
      if (action.dataset.action === "relink") {
        SS.mutate("إعادة ربط الأصل", () => {
          SS.state.clips.forEach((c) => { if (c.missing) c.relinked = true; });
          SS.state.harness.missing = false;
        });
        SS.toast("تم ربط الملف من جديد");
      }
    });
  };

  /* --------------------------------- misc -------------------------------- */
  SS.setTheme = function (theme) {
    document.documentElement.dataset.theme = theme === "light" ? "light" : "dark";
    document.querySelectorAll("[data-theme-opt]").forEach((btn) => {
      btn.classList.toggle("is-active", btn.dataset.themeOpt === theme);
    });
  };
})();
