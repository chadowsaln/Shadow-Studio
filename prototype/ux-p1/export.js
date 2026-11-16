/* Shadow Studio — UX-P1 prototype
 * export.js: media bin, import, export dialog (S3 §7), status bar, harness. */
(function () {
  "use strict";

  const SS = window.SS;
  const $ = (id) => document.getElementById(id);

  /* -------------------------------- presets ------------------------------ */
  const PRESETS = [
    { id: "mp4-h264-1080p", name: "MP4 · H.264 · 1080p", spec: "1920×1080 · 12 Mbps · 30 fps", v: 12000, a: 192 },
    { id: "mp4-h264-720p", name: "MP4 · H.264 · 720p", spec: "1280×720 · 6 Mbps", v: 6000, a: 192 },
    { id: "mp4-h264-4k", name: "MP4 · H.264 · 4K", spec: "3840×2160 · 24 Mbps", v: 24000, a: 192, needs4k: true },
    { id: "webm-vp9", name: "WebM · VP9", spec: "1920×1080 · CRF 32", v: 9000, a: 128, crf: 32 },
    { id: "wav-pcm", name: "WAV · PCM", spec: "48 kHz · 24-bit · صوت فقط", v: 0, a: 0, audioOnly: true },
    { id: "mp3-320", name: "MP3 · 320", spec: "320 kbps · صوت فقط", v: 0, a: 320, audioOnly: true },
    { id: "gif", name: "GIF", spec: "640px · 15 ثانية كحد أقصى", v: 2400, a: 0, gif: true },
  ];

  const presetById = (id) => PRESETS.find((p) => p.id === id) || PRESETS[0];

  function rangeDuration() {
    const state = SS.state;
    if (state.export.advanced.range === "in-out" && state.inPoint != null && state.outPoint != null) {
      return Math.max(0.1, state.outPoint - state.inPoint);
    }
    return SS.sequenceDuration();
  }

  function estimateMb() {
    const preset = presetById(SS.state.export.preset);
    const adv = SS.state.export.advanced;
    if (preset.id === "wav-pcm") {
      /* 48 kHz · 24-bit · stereo = 2304 kbps */
      return Math.max(1, Math.round((2304 * 1000 * rangeDuration()) / 8 / 1024 / 1024));
    }
    const video = preset.crf ? 7000 : adv.videoBitrate || preset.v;
    const audio = preset.audioOnly || preset.a === 0 ? 0 : adv.audioBitrate || preset.a;
    return Math.round(((video + audio) * 1000 * rangeDuration()) / 8 / 1024 / 1024);
  }

  function storageEstimate(mb) {
    return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : mb + " MB";
  }

  /* ------------------------------ media bin ------------------------------ */
  SS.renderBin = function () {
    const list = $("bin-list");
    if (!list) return;
    const query = ($("bin-search")?.value || "").trim();
    list.innerHTML = SS.state.assets
      .filter((asset) => !query || asset.name.includes(query))
      .map((asset) => {
        const thumbStyle = "background:" + SS.assetGradient(asset, 120);
        const proxy =
          asset.proxy === "ready"
            ? '<span class="badge badge--done">proxy ✓</span>'
            : asset.proxy === "building"
              ? '<span class="badge badge--warn">proxy ◌</span>'
              : "";
        const kindLabel = asset.kind === "audio" ? "WAV" : (asset.w || 0) >= 3840 ? "4K" : "HD";
        return (
          '<li class="asset" draggable="true" data-asset="' + asset.id + '" title="اسحب إلى المسار أو انقر مزدوجاً">' +
          '<span class="asset__thumb" style="' + thumbStyle + '" data-kind="' + kindLabel + '"></span>' +
          '<div><div class="asset__name" dir="ltr">' + SS.esc(asset.name) + "</div>" +
          '<div class="asset__sub"><span class="num">' + SS.tc(asset.duration) + "</span><span>" + asset.size + "</span></div>" +
          (proxy ? '<div class="asset__badges">' + proxy + "</div>" : "") +
          "</div></li>"
        );
      })
      .join("");
  };

  function addAssetToTimeline(assetId) {
    const asset = SS.assetsById(assetId);
    if (!asset) return;
    const kind = asset.kind === "audio" ? "audio" : "video";
    const track = SS.state.tracks.find((tr) => tr.kind === kind && !tr.locked && tr.id !== "V2");
    if (!track) {
      SS.toast("لا مسار متاح لهذا النوع", { kind: "warn" });
      return;
    }
    const start = Math.round(SS.state.playhead * SS.FPS) / SS.FPS;
    SS.mutate("إضافة مقطع", () => {
      SS.state.clips.push({
        id: SS.uid(),
        trackId: track.id,
        assetId: asset.id,
        name: asset.name,
        start,
        duration: Math.min(asset.duration, kind === "audio" ? 8 : 6),
        sourceIn: 0,
        speed: 1,
        enabled: true,
        opacity: 1,
        gain: kind === "audio" ? -6 : undefined,
        fadeIn: 0,
        fadeOut: 0,
      });
      SS.state.selection = new Set([SS.state.clips[SS.state.clips.length - 1].id]);
    }, { toast: false });
    SS.toast("أُضيف " + asset.name + " إلى " + track.label);
  }

  SS.bindBin = function () {
    const list = $("bin-list");
    list.addEventListener("dblclick", (event) => {
      const row = event.target.closest("[data-asset]");
      if (row) addAssetToTimeline(row.dataset.asset);
    });
    list.addEventListener("dragstart", (event) => {
      const row = event.target.closest("[data-asset]");
      if (!row) return;
      event.dataTransfer.setData("text/asset", row.dataset.asset);
      event.dataTransfer.effectAllowed = "copy";
      row.classList.add("is-dragging");
    });
    list.addEventListener("dragend", (event) => {
      event.target.closest("[data-asset]")?.classList.remove("is-dragging");
    });

    $("lanes").addEventListener("dragover", (event) => {
      if (event.dataTransfer.types.includes("text/asset")) {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
      }
    });
    $("lanes").addEventListener("drop", (event) => {
      const assetId = event.dataTransfer.getData("text/asset");
      if (!assetId) return;
      event.preventDefault();
      const asset = SS.assetsById(assetId);
      const lane = event.target.closest(".lane");
      if (!asset || !lane) return;
      const track = SS.trackById(lane.dataset.lane);
      const kind = asset.kind === "audio" ? "audio" : "video";
      if (!SS.trackAccepts(track, kind)) {
        SS.toast("مسار " + track.label + " لا يقبل هذا النوع", { kind: "warn" });
        return;
      }
      if (track.locked) {
        SS.toast("المسار مقفل", { kind: "warn" });
        return;
      }
      const rect = lane.getBoundingClientRect();
      const start = Math.max(0, (event.clientX - rect.left) / SS.state.pps);
      SS.mutate("إضافة مقطع", () => {
        SS.state.clips.push({
          id: SS.uid(), trackId: track.id, assetId: asset.id, name: asset.name,
          start: Math.round(start * 100) / 100,
          duration: Math.min(asset.duration, kind === "audio" ? 8 : 6),
          sourceIn: 0, speed: 1, enabled: true, opacity: 1,
          gain: kind === "audio" ? -6 : undefined, fadeIn: 0, fadeOut: 0,
        });
      }, { toast: false });
      SS.toast("أُضيف " + asset.name);
    });

    $("bin-search").addEventListener("input", () => SS.renderBin());
    $("btn-import").addEventListener("click", () => SS.openImport());
    document.querySelector('[data-action="import"]')?.addEventListener("click", () => SS.openImport());
  };

  /* -------------------------------- import ------------------------------- */
  const IMPORT_ROWS = [
    { name: "interview-b.mp4", size: "1.2 GB", state: "queued", note: "" },
    { name: "roomtone.wav", size: "48 MB", state: "queued", note: "" },
    { name: "notes-iphone.mov", size: "310 MB", state: "queued", note: "VFR: سيُطبَّع إلى 30fps" },
    { name: "music-bed.mp3", size: "6.4 MB", state: "duplicate", note: "الملف موجود بالفعل" },
    { name: "screen-capture.mkv", size: "820 MB", state: "rejected", note: "ترميز غير مدعوم" },
  ];

  SS.openImport = function () {
    const dialog = $("import-dialog");
    const list = $("import-list");
    list.innerHTML = IMPORT_ROWS.map(
      (row, index) =>
        '<li class="import-row" data-row="' + index + '">' +
        '<span class="num">' + (index + 1) + "</span>" +
        '<div><div class="import-row__name" dir="ltr">' + SS.esc(row.name) + "</div>" +
        '<div class="import-row__bar"><span></span></div></div>' +
        '<span class="import-row__state">في الانتظار</span></li>'
    ).join("");
    $("import-note").textContent = "جارٍ فحص الملفات…";
    if (!dialog.open) dialog.showModal();
    $("btn-import-done").focus({ preventScroll: true });

    IMPORT_ROWS.forEach((row, index) => {
      const node = list.querySelector('[data-row="' + index + '"]');
      const bar = node.querySelector(".import-row__bar span");
      const stateEl = node.querySelector(".import-row__state");
      if (row.state === "duplicate") {
        stateEl.textContent = row.note;
        stateEl.className = "import-row__state is-dup";
        bar.style.width = "100%";
        return;
      }
      if (row.state === "rejected") {
        stateEl.textContent = row.note;
        stateEl.className = "import-row__state is-rejected";
        bar.style.width = "100%";
        return;
      }
      setTimeout(() => {
        stateEl.textContent = "فحص…";
        let pct = 0;
        const timer = setInterval(() => {
          pct = Math.min(100, pct + 18);
          bar.style.width = pct + "%";
          if (pct >= 100) {
            clearInterval(timer);
            stateEl.textContent = row.note || "جاهز";
            stateEl.className = "import-row__state is-ready";
            node.dataset.ready = "1";
          }
        }, 120);
      }, 120 * index);
    });

    setTimeout(() => {
      const ready = list.querySelectorAll('[data-ready="1"]').length;
      $("import-note").textContent = ready + " ملفات جاهزة · " + (IMPORT_ROWS.length - ready) + " تحتاج إجراء";
    }, 900);
  };

  SS.bindImport = function () {
    $("btn-import-done").addEventListener("click", (event) => {
      event.preventDefault();
      const additions = [
        { id: "a-interview", name: "interview-b.mp4", kind: "video", w: 1920, h: 1080, duration: 26, size: "1.2 GB", proxy: "building", hue: 24 },
        { id: "a-roomtone", name: "roomtone.wav", kind: "audio", duration: 60, size: "48 MB", hue: 196 },
        { id: "a-notes", name: "notes-iphone.mov", kind: "video", w: 1080, h: 1920, duration: 14, size: "310 MB", proxy: "building", hue: 340 },
      ];
      let added = 0;
      SS.mutate("استيراد", () => {
        additions.forEach((asset) => {
          if (!SS.state.assets.some((a) => a.id === asset.id || a.name === asset.name)) {
            SS.state.assets.push(asset);
            added += 1;
          }
        });
      }, { toast: false });
      SS.toast("أُضيف " + added + " أصلاً إلى المكتبة");
      $("import-dialog").close();
    });
  };

  /* ------------------------------- preflight ----------------------------- */
  function preflight() {
    const state = SS.state;
    const items = [];
    const preset = presetById(state.export.preset);
    const missing = state.clips.filter((c) => c.missing && !c.relinked);
    const hall = state.harness;

    if (state.clips.length === 0) {
      items.push({ severity: "block", text: "التسلسل فارغ — لا شيء لتصديره", action: "استيراد", act: "import" });
    } else if (missing.length || hall.missing) {
      items.push({
        severity: "block",
        text: "أصل مفقود: " + (missing[0]?.name || "intro-4k.mp4"),
        action: "إصلاح relink",
        act: "relink",
      });
    } else {
      items.push({ severity: "ok", text: "الأصول موجودة (" + state.assets.length + ")" });
    }

    if (hall.disk) {
      items.push({ severity: "block", text: "المساحة غير كافية (تحتاج 1.5× التقدير)", action: "تغيير المجلد", act: "folder" });
    } else {
      items.push({ severity: "ok", text: "مساحة كافية (3.2 GB متاحة)" });
    }

    if (hall.exists) {
      items.push({ severity: "block", text: "ملف بنفس الاسم موجود", action: "استبدال", act: "overwrite" });
    } else {
      items.push({ severity: "ok", text: "لا يوجد ملف بنفس الاسم" });
    }

    if (preset.id === "mp4-h264-4k") {
      const has4k = state.assets.some((a) => (a.w || 0) >= 3840);
      if (!has4k) items.push({ severity: "warn", text: "لا مصدر 4K — سيُكبَّر 1080p" });
    }
    if (hall.unsupported || state.export.unsupportedEffects) {
      items.push({ severity: "warn", text: "مؤثر لا يمكن تصديره (blur على مقطع معطّل)", action: "تجاهل المؤثر", act: "ignore-effect" });
    }
    if (preset.id === "webm-vp9" && hall.unsupported) {
      items.push({ severity: "warn", text: "VP9 غير متاح على هذا الجهاز", action: "استخدام H.264", act: "fallback" });
    }
    const building = state.assets.filter((a) => a.proxy === "building").length;
    if (building) items.push({ severity: "info", text: "proxy قيد البناء (" + building + ") — يُصدَّر من الأصل" });

    return items;
  }

  const blockers = () => preflight().filter((i) => i.severity === "block");

  /* ------------------------------- export view --------------------------- */
  SS.renderExport = function () {
    const state = SS.state;
    if (!$("export-dialog")?.open && !state.exporting) return;
    const preset = presetById(state.export.preset);
    const adv = state.export.advanced;
    const dur = rangeDuration();

    $("export-rev-line").textContent = "يعكس revision " + state.revision;

    $("preset-list").innerHTML = PRESETS.filter((p) => !p.audioOnly || SS.hasAudio())
      .map((p) => {
        const disabled = p.gif && dur > 15 ? "المدة تتجاوز 15 ثانية" : p.id === "mp4-h264-4k" && !state.assets.some((a) => (a.w || 0) >= 3840) ? null : null;
        const reason = disabled || (p.gif && dur > 15 ? "المدة تتجاوز 15 ثانية" : "");
        const audioKbps = p.audioOnly ? (p.id === "wav-pcm" ? 2304 : p.a) : adv.audioBitrate;
        const videoKbps = p.audioOnly ? 0 : p.crf ? 7000 : p.v;
        const mb = Math.max(1, Math.round(((videoKbps + audioKbps) * 1000 * dur) / 8 / 1024 / 1024));
        return (
          '<button class="preset' + (state.export.preset === p.id ? " is-active" : "") + '" data-preset="' + p.id + '"' +
          (reason ? " disabled" : "") + ">" +
          '<span class="preset__dot"></span>' +
          "<span><span class=\"preset__name\">" + p.name + "</span>" +
          '<span class="preset__spec" dir="ltr">' + p.spec + "</span>" +
          (reason ? '<span class="preset__why">' + reason + "</span>" : "") +
          "</span>" +
          "<span class=\"preset__est\"><span dir=\"ltr\">~" + storageEstimate(mb) + "</span><br>تقديري</span></button>"
        );
      })
      .join("");

    const fields = [];
    if (!preset.audioOnly) {
      fields.push(
        '<label>Video bitrate (Mbps)<input class="input" type="number" min="2" max="60" step="1" data-adv="videoBitrateMbps" value="' +
          (adv.videoBitrate / 1000).toFixed(0) + '"' + (adv.crf ? ' disabled' : "") + "></label>"
      );
      fields.push(
        '<label>CRF (يتعارض مع bitrate)<input class="input" type="number" min="18" max="40" step="1" data-adv="crf" value="' +
          (adv.crf ?? "") + '" placeholder="—"></label>'
      );
    }
    if (!preset.audioOnly || preset.a) {
      fields.push(
        '<label>Audio bitrate (kbps)<input class="input" type="number" min="64" max="320" step="16" data-adv="audioBitrate" value="' + adv.audioBitrate + '"></label>'
      );
      fields.push(
        '<label>Loudness (LUFS)<input class="input" type="number" min="-24" max="-9" step="1" data-adv="loudness" value="' + adv.loudness + '"></label>'
      );
    }
    fields.push(
      '<label>Range<select class="select" data-adv="range">' +
        '<option value="full"' + (adv.range === "full" ? " selected" : "") + ">التسلسل كاملاً</option>" +
        '<option value="in-out"' + (adv.range === "in-out" ? " selected" : "") + (state.inPoint == null || state.outPoint == null ? " disabled" : "") + ">In–Out</option>" +
        "</select></label>"
    );
    fields.push(
      '<label style="display:flex;align-items:center;gap:6px;margin-top:14px">Faststart' +
        '<input type="checkbox" data-adv="faststart"' + (adv.faststart ? " checked" : "") + "></label>"
    );
    $("advanced-fields").innerHTML = fields.join("");

    const stale = state.exporting && state.exporting.revision !== state.revision;
    $("summary").innerHTML =
      '<div class="summary__row"><dt>الملف</dt><dd dir="ltr">' + SS.esc(state.export.fileName) + "</dd></div>" +
      '<div class="summary__row"><dt>المجلد</dt><dd class="path">' + SS.esc(state.export.dir) + "</dd></div>" +
      '<div class="summary__row"><dt>المدى</dt><dd>' + (adv.range === "in-out" ? "In–Out · " : "التسلسل كاملاً · ") + '<span dir="ltr">' + SS.tc(dur) + "</span></dd></div>" +
      '<div class="summary__row"><dt>الفيديو</dt><dd dir="ltr">' + (preset.audioOnly ? "—" : "H.264 · 1920×1080 · 30fps") + "</dd></div>" +
      '<div class="summary__row"><dt>الصوت</dt><dd dir="ltr">' + (preset.a === 0 ? "—" : "AAC · " + adv.audioBitrate + " kbps") + "</dd></div>" +
      '<div class="summary__row"><dt>التطبيع</dt><dd dir="ltr">' + adv.loudness + " LUFS</dd></div>" +
      '<div class="summary__row"><dt>الحجم التقديري</dt><dd dir="ltr">~' + storageEstimate(estimateMb()) + "</dd></div>" +
      (stale ? '<div class="summary__rule"></div><div class="summary__row"><dt style="color:var(--warning)">تعديلاتك الجديدة لن تُضمَّن</dt><dd><button class="btn btn--ghost" id="btn-export-newer">تصدير نسخة محدثة</button></dd></div>' : "");

    const items = preflight();
    $("preflight-list").innerHTML = items
      .map(
        (item) =>
          '<li class="pf-item pf-item--' + item.severity + '">' +
          '<span class="pf-item__icon">' + (item.severity === "ok" ? "✓" : item.severity === "warn" ? "!" : item.severity === "block" ? "✕" : "i") + "</span>" +
          "<span>" + SS.esc(item.text) + "</span>" +
          (item.action ? '<button class="pf-item__action" data-pf="' + item.act + '">' + item.action + "</button>" : "<span></span>") +
          "</li>"
      )
      .join("");

    const blockList = blockers();
    const start = $("btn-export-start");
    start.disabled = blockList.length > 0 || !!state.exporting;
    $("export-blocked-note").textContent = blockList.length
      ? "لا يمكن البدء: " + blockList[0].text
      : state.exporting
        ? "التصدير جارٍ…"
        : "";

    $("advanced").hidden = !!state.exporting;
    $("export-run").hidden = !state.exporting;
    const result = $("export-result");
    if (blockers().length > 0) {
      /* A new blocker invalidates the previous run's outcome card. */
      result.hidden = true;
      result.innerHTML = "";
      return;
    }
    if (state.exportRunView) {
      if (result.innerHTML !== state.exportRunView) result.innerHTML = state.exportRunView;
      result.hidden = false;
    } else {
      result.innerHTML = "";
      result.hidden = true;
    }
  };

  /* ------------------------------- export run ---------------------------- */
  let runTimer = 0;

  function stageFor(progress) {
    if (progress < 4) return { key: "preparing", label: "تحضير" };
    if (progress < 94) return { key: "rendering", label: "رسم الإطارات" };
    if (progress < 99) return { key: "encoding", label: "ترميز" };
    return { key: "finalizing", label: "إنهاء الملف" };
  }

  function etaLabel(job) {
    const elapsed = (Date.now() - job.startedAt) / 1000;
    if (elapsed < 5 || job.progress < 10) return "—";
    if (SS.state.harness.slow && job.progress > 20) return "—";
    const rate = job.progress / elapsed;
    if (!rate) return "—";
    const remaining = Math.max(1, Math.round((100 - job.progress) / rate));
    const lo = Math.max(1, Math.round(remaining * 0.8));
    const hi = Math.max(lo + 1, Math.round(remaining * 1.3));
    return "~" + Math.floor(lo / 60) + "–" + Math.ceil(hi / 60) + " د";
  }

  function renderRun() {
    const job = SS.state.exporting;
    const run = $("export-run");
    if (!job) {
      run.hidden = true;
      return;
    }
    run.hidden = false;
    $("progress-fill").style.width = job.progress + "%";
    $("progress-stage").textContent = stageFor(job.progress).label;
    $("progress-eta").textContent = etaLabel(job);
    const frames = Math.round((job.progress / 100) * job.framesTotal);
    $("progress-frames").textContent = frames + " / " + job.framesTotal + " إطار · " + job.fileName;
    $("status-render").hidden = false;
    $("status-render").textContent =
      (stageFor(job.progress).key === "rendering" ? "Rendering " : stageFor(job.progress).label + " ") +
      Math.round(job.progress) + "%";
    $("export-blocked-note").textContent = "يمكنك متابعة التحرير؛ التصدير يعكس revision " + job.revision;
  }

  function finishJob(outcome) {
    const job = SS.state.exporting;
    if (!job) return;
    clearInterval(runTimer);
    SS.state.exporting = null;
    $("status-render").hidden = true;
    $("export-run").hidden = true;
    const filePath = SS.state.export.dir + "/" + job.fileName;

    if (outcome.type === "cancelled") {
      SS.state.exportRunView =
        '<div class="result"><div class="result__head result__head--bad">تم إلغاء التصدير</div>' +
        '<div class="result__body">حُذف الملف الجزئي. لم يُكتب أي ملف نهائي.</div>' +
        '<div class="result__actions"><button class="btn btn--primary" id="btn-export-again">تصدير من جديد</button></div></div>';
    } else if (outcome.type === "failed") {
      SS.state.exportRunView =
        '<div class="result"><div class="result__head result__head--bad">' + outcome.title + "</div>" +
        '<div class="result__body">' + outcome.reason + "</div>" +
        '<div class="result__actions"><button class="btn btn--primary" data-retry="1">' + outcome.action + "</button>" +
        '<button class="btn btn--ghost" data-details="1">التفاصيل ›</button></div>' +
        '<div class="result__details" hidden data-details-box><span>code: ' + outcome.code + "</span>" +
        "<span>correlation_id: 7f3c-9a21-4e0b</span><span>instance: media-worker/01</span></div></div>";
      SS.toast(outcome.title, { kind: "danger" });
      const jobRecord = { id: job.id, name: job.fileName, state: "failed" };
      SS.state.exportJobs.push(jobRecord);
    } else {
      SS.state.exportRunView =
        '<div class="result"><div class="result__head result__head--ok">تم التصدير</div>' +
        '<div class="result__body" dir="ltr">' + SS.esc(filePath) + "</div>" +
        '<div class="result__meta" dir="ltr">' + storageEstimate(estimateMb()) + " · " + SS.tc(rangeDuration()) + " · H.264/AAC</div>" +
        '<div class="result__actions"><button class="btn btn--primary" data-open="file">فتح الملف</button>' +
        '<button class="btn btn--ghost" data-open="folder">فتح المجلد</button>' +
        '<button class="btn btn--ghost" id="btn-export-again">تصدير آخر</button></div></div>';
      SS.state.exportJobs.push({ id: job.id, name: job.fileName, state: "succeeded" });
      SS.toast("تم التصدير · " + job.fileName);
    }
    if (SS.renderQueue) SS.renderQueue();
    SS.renderExport();
    SS.renderStatus();
  }

  function fail(kind) {
    const map = {
      crash: { title: "توقف محرك التصدير", reason: "لم يكتمل الرسم. الملف الجزئي محفوظ.", action: "إعادة المحاولة", code: "ENGINE_CRASH" },
      timeout: { title: "استغرق المحرك وقتاً أطول من المتوقع", reason: "تجاوز التصدير المهلة المسموحة.", action: "تقليل الدقة", code: "ENGINE_TIMEOUT" },
      unsupported: { title: "هذا الترميز غير مدعوم", reason: "المحرك لا يستطيع ترميز VP9 على هذا الجهاز.", action: "استخدام H.264", code: "MEDIA_UNSUPPORTED" },
      disk: { title: "المساحة غير كافية لإنهاء التصدير", reason: "المساحة المتاحة أقل من 1.5× الحجم التقديري.", action: "تغيير المجلد", code: "DISK_FULL" },
      exists: { title: "يوجد ملف بنفس الاسم", reason: "الملف الناتج موجود مسبقاً ولم يُفعّل الاستبدال.", action: "استبدال", code: "OUTPUT_EXISTS" },
      missing: { title: "ملف الوسائط مفقود", reason: "أصل مفقود: intro-4k.mp4", action: "إعادة الربط", code: "MEDIA_ASSET_MISSING" },
      queue: { title: "طابور التصدير ممتلئ", reason: "هناك مهمتان في الانتظار بالفعل. انتظر انتهاء إحداهما.", action: "عرض المهام", code: "RESOURCE_QUEUE_FULL" },
    };
    finishJob({ type: "failed", ...map[kind] });
  }

  SS.startExport = function () {
    const state = SS.state;
    if (state.exporting) {
      if (state.exportJobs.filter((j) => j.state === "queued").length >= 1 || state.harness.queue) {
        fail("queue");
        return;
      }
      state.exportJobs.push({ id: "j" + Date.now(), name: state.export.fileName, state: "queued" });
      SS.renderQueue();
      SS.toast("أُضيف إلى الطابور: " + state.export.fileName);
      return;
    }
    if (blockers().length) return;

    const dur = rangeDuration();
    const job = {
      id: "j" + Date.now(),
      fileName: state.export.fileName,
      preset: state.export.preset,
      revision: state.revision,
      progress: 0,
      startedAt: Date.now(),
      framesTotal: Math.round(dur * SS.FPS),
    };
    state.exporting = job;
    state.exportRunView = "";
    $("export-result").innerHTML = "";
    $("export-result").hidden = true;
    SS.renderExport();
    renderRun();

    clearInterval(runTimer);
    runTimer = setInterval(() => {
      const current = SS.state.exporting;
      if (!current) return;
      const step = (SS.state.harness.slow ? 0.35 : 1.1) * (0.8 + Math.random() * 0.5);
      current.progress = Math.min(100, current.progress + step);

      if (SS.state.harness.crash && current.progress > 55) {
        SS.state.harness.crash = false;
        fail("crash");
        return;
      }
      if (SS.state.harness.timeout && current.progress > 62) {
        SS.state.harness.timeout = false;
        fail("timeout");
        return;
      }
      if (SS.state.harness.disk && current.progress > 40) {
        SS.state.harness.disk = false;
        fail("disk");
        return;
      }
      if (SS.state.harness.unsupported && current.progress > 30) {
        SS.state.harness.unsupported = false;
        fail("unsupported");
        return;
      }
      if (SS.state.harness.exists && current.progress > 20) {
        SS.state.harness.exists = false;
        fail("exists");
        return;
      }
      if ((SS.state.harness.missing || SS.state.clips.some((c) => c.missing && !c.relinked)) && current.progress > 12) {
        SS.state.harness.missing = false;
        fail("missing");
        return;
      }

      renderRun();
      if (current.progress >= 100) finishJob({ type: "succeeded" });
    }, 220);
  };

  SS.renderQueue = function () {
    const state = SS.state;
    const wrap = $("export-queue");
    const list = $("queue-list");
    if (!wrap || !list) return;
    const rows = [...(state.exporting ? [{ name: state.exporting.fileName, state: "running", progress: state.exporting.progress }] : []), ...state.exportJobs];
    wrap.hidden = rows.length === 0;
    list.innerHTML = rows
      .map(
        (row) =>
          '<li class="queue-row"><span class="queue-row__name">' + SS.esc(row.name) + "</span>" +
          '<span class="queue-row__state' + (row.state === "succeeded" ? " queue-row__state--ok" : row.state === "failed" ? " queue-row__state--bad" : "") + '">' +
          (row.state === "running" ? "رسم " + Math.round(row.progress) + "%" : row.state === "queued" ? "في الانتظار" : row.state === "succeeded" ? "تم" : "فشل") +
          "</span>" +
          '<button class="pf-item__action" data-queue-cancel="' + row.name + '">' + (row.state === "running" ? "إلغاء" : "إزالة") + "</button></li>"
      )
      .join("");
  };

  SS.openExport = function () {
    const dialog = $("export-dialog");
    SS.state.exportRunView = SS.state.exportRunView || "";
    if (!dialog.open) dialog.showModal();
    SS.renderExport();
    if (SS.state.exporting) renderRun();
    /* showModal focuses the first control (the minimise button); the task is
       to choose a preset, so move focus there without trapping the user. */
    const active = document.querySelector("#preset-list .preset.is-active");
    if (active && !SS.state.exporting) active.focus({ preventScroll: true });
  };

  SS.closeExport = function () {
    const dialog = $("export-dialog");
    if (dialog.open) dialog.close();
  };

  SS.bindExport = function () {
    const dialog = $("export-dialog");

    $("btn-export").addEventListener("click", () => SS.openExport());
    $("btn-export-close").addEventListener("click", () => {
      if (SS.state.exporting) {
        SS.toast("التصدير يعمل في الخلفية — يمكنك متابعة التحرير", { ms: 2600 });
      }
      SS.closeExport();
    });
    $("btn-export-min").addEventListener("click", () => {
      SS.closeExport();
      SS.toast("التصدير صُغِّر إلى شريط الحالة", { ms: 2200 });
    });
    $("status-render").addEventListener("click", () => SS.openExport());

    $("preset-list").addEventListener("click", (event) => {
      const btn = event.target.closest("[data-preset]");
      if (!btn || btn.disabled) return;
      SS.state.export.preset = btn.dataset.preset;
      const preset = presetById(btn.dataset.preset);
      if (!preset.audioOnly) SS.state.export.advanced.videoBitrate = preset.v;
      if (preset.crf) SS.state.export.advanced.crf = preset.crf;
      SS.renderExport();
    });

    $("advanced-fields").addEventListener("input", (event) => {
      const key = event.target.dataset.adv;
      if (!key) return;
      const value = event.target.type === "checkbox" ? event.target.checked : event.target.value;
      if (key === "videoBitrateMbps") SS.state.export.advanced.videoBitrate = Number(value) * 1000;
      else if (key === "crf") SS.state.export.advanced.crf = value === "" ? null : Number(value);
      else if (key === "faststart") SS.state.export.advanced.faststart = value;
      else if (key === "range") SS.state.export.advanced.range = value;
      else SS.state.export.advanced[key] = Number(value);
      SS.renderExport();
    });

    $("preflight-list").addEventListener("click", (event) => {
      const btn = event.target.closest("[data-pf]");
      if (!btn) return;
      const act = btn.dataset.pf;
      if (act === "relink") {
        SS.mutate("إعادة ربط الأصل", () => {
          SS.state.clips.forEach((c) => { if (c.missing) c.relinked = true; });
          SS.state.harness.missing = false;
        });
        SS.toast("تم ربط الملف من جديد");
      }
      if (act === "folder") {
        SS.state.harness.disk = false;
        SS.state.export.dir = "~/Videos/shadow-out-2";
        SS.renderExport();
        SS.toast("تم تغيير مجلد التصدير");
      }
      if (act === "overwrite") {
        SS.state.harness.exists = false;
        SS.state.export.fileName = "final-v4.mp4";
        SS.renderExport();
        SS.toast("سيُستبدل الملف الموجود");
      }
      if (act === "ignore-effect") {
        SS.state.harness.unsupported = false;
        SS.state.export.unsupportedEffects = false;
        SS.renderExport();
        SS.toast("سيُتجاهل المؤثر غير المدعوم");
      }
      if (act === "fallback") {
        SS.state.export.preset = "mp4-h264-1080p";
        SS.state.harness.unsupported = false;
        SS.renderExport();
      }
      if (act === "import") SS.openImport();
    });

    $("btn-export-start").addEventListener("click", () => SS.startExport());
    $("btn-cancel-export").addEventListener("click", () => {
      const job = SS.state.exporting;
      if (!job) return;
      if (job.progress > 10) {
        $("export-blocked-note").textContent = "سيُحذف الملف الجزئي. أكّد الإلغاء.";
        const cancel = $("btn-cancel-export");
        cancel.textContent = "تأكيد الإلغاء";
        cancel.onclick = () => {
          finishJob({ type: "cancelled" });
          cancel.textContent = "إلغاء";
          cancel.onclick = null;
        };
        return;
      }
      finishJob({ type: "cancelled" });
    });

    $("export-result").addEventListener("click", (event) => {
      if (event.target.closest("[data-details]")) {
        const box = $("export-result").querySelector("[data-details-box]");
        if (box) box.hidden = !box.hidden;
        return;
      }
      if (event.target.closest("[data-retry]")) {
        SS.state.exportRunView = "";
        $("export-result").innerHTML = "";
        SS.renderExport();
        SS.startExport();
        return;
      }
      if (event.target.closest("[data-open]")) {
        SS.toast(event.target.closest("[data-open]").dataset.open === "file" ? "فتح الملف (خارج النموذج)" : "فتح المجلد (خارج النموذج)");
        return;
      }
      if (event.target.id === "btn-export-again") {
        SS.state.exportRunView = "";
        $("export-result").innerHTML = "";
        $("export-result").hidden = true;
        SS.renderExport();
      }
    });

    $("export-dialog").addEventListener("click", (event) => {
      if (event.target.id === "btn-export-newer") {
        SS.state.export.fileName = "final-v" + (parseInt(SS.state.export.fileName.match(/v(\d+)/)?.[1] || "3", 10) + 1) + ".mp4";
        SS.renderExport();
        SS.toast("حُدِّث اسم الملف للنسخة الجديدة");
      }
    });

    $("queue-list")?.addEventListener("click", (event) => {
      const btn = event.target.closest("[data-queue-cancel]");
      if (!btn) return;
      if (SS.state.exporting && SS.state.exporting.fileName === btn.dataset.queueCancel) {
        finishJob({ type: "cancelled" });
      } else {
        SS.state.exportJobs = SS.state.exportJobs.filter((j) => j.name !== btn.dataset.queueCancel);
        SS.renderQueue();
      }
    });
  };

  /* ------------------------------ status bar ----------------------------- */
  SS.renderStatus = function () {
    const state = SS.state;
    const proxy = $("status-proxy");
    if (proxy) {
      const building = state.assets.filter((a) => a.proxy === "building").length;
      proxy.textContent = building ? "4K proxy " + (state.assets.length - building) + "/" + state.assets.length : "4K proxy 4/4";
    }
    const cache = $("status-cache");
    if (cache) cache.textContent = "Cache " + state.cacheGb.toFixed(1) + " GB";
    const rev = $("status-rev");
    if (rev) rev.textContent = "Rev " + state.revision;
    const ai = $("status-ai");
    if (ai) ai.textContent = "AI: يحتاج مفتاحاً";
    if (state.exporting) {
      $("status-render").hidden = false;
      $("status-render").textContent = stageFor(state.exporting.progress).label + " " + Math.round(state.exporting.progress) + "%";
    } else {
      $("status-render").hidden = true;
    }
  };

  /* ------------------------------- proposals ----------------------------- */
  const PROPOSALS = [
    { id: "p1", kind: "captions", title: "تسميات تلقائية للنص المنطوق", meta: "0:00–0:21 · 14 تعديلاً", desc: "تقسيم الكلام إلى جُمل قصيرة وإضافتها كطبقة نص." },
    { id: "p2", kind: "silence", title: "قصّ الصمت الطويل", meta: "0:02–0:19 · 3 تعديلات", desc: "إزالة 2.4 ثانية من الصمت بين الجُمل." },
  ];

  SS.renderProposals = function () {
    const host = $("proposal-list");
    if (!host) return;
    host.innerHTML = PROPOSALS.map(
      (p) =>
        '<li class="proposal" data-proposal="' + p.id + '"><p class="proposal__kind">' +
        (p.kind === "captions" ? "نص" : "صوت") + '</p><p class="proposal__title">' + SS.esc(p.title) + "</p>" +
        '<p class="proposal__meta">' + SS.esc(p.meta) + " · " + SS.esc(p.desc) + "</p>" +
        '<div class="proposal__actions"><button class="btn btn--ghost" data-review="' + p.id + '">مراجعة</button></div></li>'
    ).join("");
    $("proposal-badge").textContent = String(PROPOSALS.length);
  };

  SS.bindProposals = function () {
    $("proposal-list").addEventListener("click", (event) => {
      const btn = event.target.closest("[data-review]");
      if (!btn) return;
      const id = btn.dataset.review;
      const proposal = PROPOSALS.find((p) => p.id === id);
      if (!proposal) return;
      if (proposal.kind === "captions") {
        SS.mutate("تطبيق مقترح التسميات", () => {
          ["مرحباً بكم في الحلقة الثانية عشرة من Shadow Studio.", "نبدأ بالمقدمة ثم ننتقل إلى العرض."].forEach((text, index) => {
            SS.state.clips.push({
              id: SS.uid(), trackId: "T1", assetId: null, name: "تسمية " + (index + 1),
              start: 1.5 + index * 6, duration: 5, text, enabled: true, opacity: 1,
            });
          });
        });
      } else {
        SS.state.selection = new Set(SS.state.clips.filter((c) => c.trackId === "A1").map((c) => c.id));
        SS.renderAll();
        SS.toast("المقترح محدّد على A1 — عدّل ثم طبّق", { ms: 2600 });
        return;
      }
      PROPOSALS.splice(PROPOSALS.indexOf(proposal), 1);
      SS.renderProposals();
    });
  };

  /* -------------------------------- settings ----------------------------- */
  SS.bindSettings = function () {
    const popover = $("settings-popover");
    $("btn-settings").addEventListener("click", (event) => {
      event.stopPropagation();
      popover.hidden = !popover.hidden;
    });
    popover.addEventListener("click", (event) => {
      const theme = event.target.closest("[data-theme-opt]");
      if (theme) SS.setTheme(theme.dataset.themeOpt);
      if (event.target.closest("[data-close-popover]")) popover.hidden = true;
      if (event.target.closest("#btn-ai-key")) {
        popover.hidden = true;
        SS.toast("إعداد مفتاح AI يفتح في الإعدادات (خارج نطاق النموذج)", { ms: 2600 });
      }
    });
    document.addEventListener("click", (event) => {
      if (!popover.hidden && !popover.contains(event.target) && !event.target.closest("#btn-settings")) popover.hidden = true;
    });
  };

  /* ---------------------------------- tabs -------------------------------- */
  SS.bindTabs = function () {
    document.querySelectorAll("[data-tab]").forEach((tab) => {
      tab.addEventListener("click", () => {
        document.querySelectorAll("[data-tab]").forEach((t) => {
          t.classList.toggle("is-active", t === tab);
          t.setAttribute("aria-selected", String(t === tab));
        });
        $("pane-bin").classList.toggle("is-hidden", tab.dataset.tab !== "bin");
        $("pane-proposals").classList.toggle("is-hidden", tab.dataset.tab !== "proposals");
      });
    });
  };

  /* -------------------------------- harness ------------------------------- */
  SS.bindHarness = function () {
    const panel = $("harness");
    document.addEventListener("keydown", (event) => {
      if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === "d") {
        event.preventDefault();
        panel.hidden = !panel.hidden;
      }
    });

    panel.addEventListener("click", (event) => {
      const btn = event.target.closest("[data-harness]");
      if (!btn) return;
      const action = btn.dataset.harness;
      const state = SS.state;

      if (action === "reset") {
        location.reload();
        return;
      }
      if (action === "missing") {
        state.harness.missing = true;
        state.clips.forEach((c) => { if (c.trackId === "V1") c.missing = true; });
        SS.renderAll();
        SS.toast("حالة: أصل مفقود", { kind: "warn" });
        return;
      }
      if (action === "slow") {
        state.harness.slow = !state.harness.slow;
        SS.toast(state.harness.slow ? "المحرك بطيء (محاكاة)" : "المحرك طبيعي", { kind: "warn" });
        return;
      }
      if (action === "interrupt") {
        state.harness.interrupt = true;
        showResumeBanner();
        return;
      }
      state.harness[action] = true;
      SS.toast("الحالة جاهزة: " + action + " — ابدأ التصدير", { kind: "warn" });
      if (action === "queue") SS.startExport();
      SS.renderExport();
    });
  };

  function showResumeBanner() {
    const banner = document.createElement("div");
    banner.className = "rec-banner";
    banner.innerHTML =
      '<span class="rec-banner__title">تصدير لم يكتمل</span>' +
      '<span class="rec-banner__body">أُغلق التطبيق أثناء تصدير <span dir="ltr">final-v3.mp4</span>.</span>' +
      '<div class="rec-banner__actions"><button class="btn btn--primary" data-resume>استئناف</button>' +
      '<button class="btn btn--ghost" data-ignore>تجاهل</button></div>';
    document.body.appendChild(banner);
    banner.addEventListener("click", (event) => {
      if (event.target.closest("[data-resume]")) {
        banner.remove();
        SS.openExport();
        SS.toast("استُؤنف التصدير (حد محاولتين)");
        SS.startExport();
      }
      if (event.target.closest("[data-ignore]")) banner.remove();
    });
  }

  /* ---------------------------------- boot -------------------------------- */
  SS.initUi = function () {
    SS.bindTabs();
    SS.bindBin();
    SS.bindImport();
    SS.bindTimeline();
    SS.bindKeys();
    SS.bindInspector();
    SS.bindExport();
    SS.bindSettings();
    SS.bindProposals();
    SS.bindHarness();
    SS.renderBin();
    SS.renderProposals();
    SS.setTheme("dark");
    SS.renderAll();
    SS.renderStatus();
    SS.renderQueue();
    setInterval(SS.tickSaveLabel, 5000);

    window.addEventListener("beforeunload", () => {});
    $("export-dialog").addEventListener("close", () => SS.renderStatus());
  };
})();
