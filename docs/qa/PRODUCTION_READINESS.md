# Shadow Studio — Production Readiness Verification

**Date:** 2026-11-17
**Role:** Principal QA verification
**Scope:** the working tree in this repository (uncommitted changes included).
**Rule applied:** a feature is marked PASS only when the exact path was executed in this session. Source inspection alone is marked FAIL, PARTIAL, or BLOCKED, never PASS.

---

## 1. Verdict

**Not production ready.**

The **engine-level foundation is credible and now has a real video/audio export path**. The **desktop product is still a prototype**: preview is a mock, the Export dialog simulates progress without encoding, and Arabic localization is not implemented. The **AI product path is now wired** (provider settings, encrypted key, consent, plan, approvals, cancellation, real editing tools), but only with a scripted brain in tests; no live provider call was executed.

This verification also found and fixed **two real export defects** that made any production render fail or produce a malformed command:

1. `RenderQueue` wrote to `<output>.part`; FFmpeg could not infer the muxer format and every real export failed with exit 234.
2. `RenderPlanner` emitted a duplicate `-c:a` and an invalid `-ar` position for audio-only presets, corrupting WAV export commands.

Both are fixed and covered by real FFmpeg tests.

**Status counts for the 13 requested areas:**

| Status | Count |
| --- | --- |
| PASS (headless engine) | 6 |
| PARTIAL | 5 |
| FAIL | 2 |

| Desktop/product capability (not only engine) | Status |
| --- | --- |
| AI request → plan → real tools through the desktop UI | **PARTIAL** (scripted brain; live provider unverified) |
| Real preview of decoded frames | **FAIL** |
| Arabic UI localization | **FAIL** |

---

## 2. Environment and commands executed

| Item | Value |
| --- | --- |
| OS / runtime | Linux x64 |
| Dart | 3.14.0 stable |
| Flutter | 3.50.0 stable |
| FFmpeg / FFprobe | 7.0.2 static, both on PATH |
| Repository | `/home/shadow/Shadow-Studio` |
| Full gate | `./tool/ci/verify.sh` → **ALL CHECKS PASSED** (`VERIFY_EXIT=0`) |
| Desktop analysis | `cd apps/desktop && flutter analyze` → **No issues found** |
| Desktop release build | `cd apps/desktop && flutter build linux --release` → **BUILD_EXIT=0** |
| Ad scenario | `cd packages/agent_runtime && dart test test/acceptance_ad_test.dart` → **2/2 passed** |

The full gate covered formatting, dependency resolution, documentation contracts, static analysis for every package, every package test suite, and desktop widget tests.

---

## 3. Requested areas

| # | Area | Status | Executed evidence | What is still missing |
| --- | --- | --- | --- | --- |
| 1 | Agent planning and execution | **PASS (headless) / PARTIAL (desktop)** | `agent_runtime` 61/61; state-machine, budgets/loops/retries, provider brain, multi-agent, and the acceptance scenario. Desktop tests run the real runtime, tools, and permissions through a scripted brain. | No real LLM call; acceptance and desktop tests use a scripted brain/provider. |
| 2 | Tool registration and invocation | **PASS (implemented tools)** | `tool_system` 28/28; registry validation, real `media_analysis` and `timeline_edit` calls in acceptance | Spec lists 27 v1 tools; implementation exposes 10 MVP built-ins plus media/timeline tools. Full 27-tool coverage is not met. |
| 3 | Provider switching | **PARTIAL** | `provider_gateway` 24/24; model selection, capability downgrade, fallback on retryable errors, no fallback on 401/403, streamed tool calls | No live OpenAI/Anthropic/Gemini/OpenRouter request was executed (no credentials). Local HTTP/SSE server and retry transport were exercised. |
| 4 | API failures and retries | **PARTIAL** | Real local HTTP tests: SSE decode, 401 mapping, 503 mapping, retry-until-success, no replay after partial stream, no retry on auth | No provider-side rate-limit/network test against a live endpoint; no end-to-end retry budget test across a real provider. |
| 5 | Permission enforcement | **PASS (engine + desktop)** | `permissions` 57/57; forged tokens, expiry, revocation, replay, risk downscoping, unknown tools, shell blocking, audit. Desktop test approves/rejects a restricted `timeline_edit` through the real engine. | No OS sandbox; approval card is not exercised on a live provider session. |
| 6 | Filesystem security | **PASS (engine)** | `permissions` plus `tool_system/security_integration_test.dart`: traversal, symlink escape, absolute paths, `assetPath` smuggling, control chars, canonicalization | TOCTOU is not eliminated; there is no OS sandbox. |
| 7 | Checkpoint creation | **PASS** | `agent_runtime` checkpoint tests and `local_storage` 30/30; schema v3, history, latest-per-task, corrupt-row fail-closed | No retention/compaction policy. |
| 8 | Recovery after crashes | **PASS (engine)** | 18 crash/restart tests, process-restart SQLite test, interrupted detection, safe resume, non-idempotent replay guard, cancellation checkpoint | Recovery is manual and has no desktop UI; no automatic startup detection. |
| 9 | Timeline editing | **PARTIAL — core passes, UI incomplete** | `editing_core` 59/59; desktop 21/21; add/split/trim/delete/undo/redo and save through the controller | Desktop lacks project open/save-as flows, move/ripple/join UI, marquee, and full keyboard coverage. |
| 10 | Media rendering | **PARTIAL** | Real `ProcessRenderBackend` produced MP4 and WAV; 30s ad render succeeded | Desktop preview is still a mock (`PreviewCanvas` draws an icon/label/timecode). No frame-accurate preview pipeline. |
| 11 | Video and audio export | **PASS (engine) / FAIL (desktop UI)** | 30s H.264/AAC MP4 verified with FFprobe; 1s PCM WAV verified | `ExportDialog` is a timer simulation. The app does not depend on `render_pipeline`; it writes no file. |
| 12 | Arabic localization | **FAIL** | Source inspection: no `supportedLocales`, no `localizationsDelegates`, no localization resources; only 3 Arabic literals, all in the text inspector; app shell defaults to LTR | Full Arabic microcopy, locale switching, RTL shell, translated errors/status, and Arabic font asset are missing. |
| 13 | Desktop packaging | **PARTIAL** | Linux release bundle built; ELF binary; no missing shared libraries via `ldd` | Not launched (no display/Xvfb available); no installer, no Windows build, no signing. |

---

## 4. Mandatory end-to-end scenario

**Input:** generated 30-second 640×360/30fps H.264 + AAC source video.
**Instruction:** “Create a professional 30-second advertisement.”

The test is [acceptance_ad_test.dart](../../packages/agent_runtime/test/acceptance_ad_test.dart).

| Requirement | Result | Evidence |
| --- | --- | --- |
| AI understands the request | **PARTIAL** | The scripted `MockProvider` returns a plan and tool decisions. No live model was called. |
| Valid editing plan generated | **PASS** | Two-step plan: analyze source, build 30s timeline. Plan advances through the real agent loop. |
| Real tools invoked | **PASS** | `MediaAnalysisTool` runs real FFmpeg analysis; `TimelineEditTool` mutates the real `DefaultEditingService`. |
| Permission checks work | **PASS** | `PermissionManager` issues one bound token per restricted call; both `media_analysis` and `timeline_edit` required approval. |
| Editing operations applied | **PASS** | Two 15s clips assembled; timeline duration exactly 30,000,000 ticks; revision 1. |
| Output is a valid video | **PASS** | Rendered with `ProcessRenderBackend` to MP4; FFprobe: H.264, 1280×720, AAC audio, duration ≈30.0s; >100 KB; no `.part` leftover. |
| User can preview it | **FAIL** | The test decodes a frame at 5s to a 1280×720 PNG, proving the output is decodable, but the desktop preview never displays decoded frames. |
| User can modify it | **PASS (engine)** | After export, a `TrimClipCommand` transaction succeeded, revision advanced to 2, and the edited graph still resolved. The desktop UI exposes trim but not this exact post-export workflow. |
| Recovery after interruption | **PARTIAL** | Recovery is verified separately by the 18 crash/restart tests and a SQLite process-restart test, not inside this single ad run. Interrupted-task detection and safe resume are real. |

**Scenario verdict:** the **headless pipeline works end to end through a valid MP4**, but the **product scenario fails** because preview and desktop export are not wired and the “AI” is a scripted mock.

---

## 5. Tests and fixes delivered in this verification

### 5.1 New/expanded coverage

- Expanded [acceptance_ad_test.dart](../../packages/agent_runtime/test/acceptance_ad_test.dart) from a timeline-only scenario to a full **plan → tools → permissions → edit → RenderGraph → real FFmpeg MP4 → FFprobe → frame decode → post-export trim** scenario. It now generates an audio track, verifies H.264/AAC/1280×720/30s, checks atomic output, and verifies the export remains editable.
- Added [process_render_backend_test.dart](../../packages/render_pipeline/test/process_render_backend_test.dart): real 1s MP4 encode and real 1s WAV audio export, atomic temp naming, FFprobe codec/container/duration checks.
- Added [render_benchmark_test.dart](../../packages/render_pipeline/test/render_benchmark_test.dart): measures closed-schema parse and FFmpeg planning for a 300-clip timeline against a 2s CPU budget.
- Added a render-pipeline dev dependency to [pubspec.yaml](../../packages/agent_runtime/pubspec.yaml) so the cross-package scenario can run in the existing integration suite.

### 5.2 Production defects found and fixed

| Defect | Impact | Fix | Regression test |
| --- | --- | --- | --- |
| FFmpeg could not mux `out.mp4.part` | **All real exports failed** with `Unable to choose an output format` | [render_queue.dart](../../packages/render_pipeline/lib/src/render_queue.dart) now writes `out.part.mp4` and renames atomically | Real MP4 test; updated queue unit tests |
| Duplicate `-c:a` for bitrate-less audio presets | WAV export passed `48000` as the output filename | [render_plan.dart](../../packages/render_pipeline/lib/src/render_plan.dart) builds audio args once, adding `-b:a` only when a bitrate exists | Real WAV test |

### 5.3 Existing suites used as evidence

| Suite | Tests |
| --- | --- |
| `contracts` | 26 |
| `context_engine` | 5 |
| `agent_runtime` | 61 |
| `tool_system` | 28 |
| `provider_gateway` | 24 |
| `permissions` | 57 |
| `local_storage` | 30 |
| `editing_core` | 59 |
| `media_core` | 20 |
| `render_pipeline` | 31 |
| `apps/desktop` (Flutter) | 21 |
| **Total** | **362 passing** |

No test was skipped in the final verified run. FFmpeg-dependent tests use `markTestSkipped` only when FFmpeg is unavailable; on this machine FFmpeg was present and the real paths ran.

---

## 6. Security assessment

**Verified controls (engine):**

- Closed-schema argument validation and output validation.
- Deny-by-default permission policy; unknown tools require approval.
- Single-use, engine-issued, tool+args-bound, TTL-limited approval tokens.
- Path validation with lexical traversal rejection, symlink resolution, nearest-existing-ancestor handling, control-character rejection, and canonical path handoff.
- Shell command guard: argv-only, allowlisted media binaries, metacharacter blocking, workspace-bound CWD.
- Encrypted file secret store with authenticated encryption and fail-closed corruption behavior.
- Hash-chained, redacting audit log; authorization fails closed if the audit sink cannot write.

**Residual risks:**

- No OS-level sandbox; TOCTOU remains between validation and use.
- Approval UI and desktop permission wiring are absent; destructive product actions are not surfaced through `PermissionManager`.
- Audit log is tamper-evident, not tamper-proof; no rotation/anchor.
- File secret store is not an OS keyring; the device key sits next to the ciphertext.

---

## 7. Performance results

| Benchmark | Threshold | Result |
| --- | --- | --- |
| 300-clip document invariant validation | < 100 ms | **PASS** |
| 3-command edit transaction on 300 clips | < 100 ms | **PASS** |
| Undo / redo on 300 clips | < 100 ms / < 50 ms | **PASS** |
| Open 200-clip project | < 120 ms | **PASS** |
| Atomic save of 300-clip project | < 250 ms | **PASS** |
| RenderGraph parse — 300 clips | < 2 s combined | **PASS — 99 ms** |
| FFmpeg plan build — 300 clips | < 2 s combined | **PASS — 29 ms** |
| Real 30s 720p ad export (incl. source generation, render, FFprobe, frame decode, trim) | no SLA asserted | **Observed ≈16 s** in the acceptance test |
| Real 1s MP4 / WAV encode | no SLA asserted | **≈1 s each** |

There is **no preview latency/scrub benchmark** because no real preview pipeline exists.

---

## 8. Release blockers

1. **Desktop export is fake.** [export_dialog.dart](../../apps/desktop/lib/src/ui/export/export_dialog.dart) runs a `Timer.periodic` progress bar and writes no file. Wire `render_pipeline` into the dialog and add cancel/progress/failure handling.
2. **Preview is fake.** [preview_canvas.dart](../../apps/desktop/lib/src/ui/preview/preview_canvas.dart) draws an icon, label, and timecode. Implement frame decode and frame-accurate seek before claiming preview readiness.
3. **AI product path is wired but not live-verified.** [pubspec.yaml](../../apps/desktop/pubspec.yaml) now depends on the agent, provider, tool, permission, and contracts packages, and the AI panel exposes settings, consent, plan, approvals, activity, and cancellation. Remaining gap: no live provider request was executed without credentials.
4. **Arabic localization is absent.** No locale configuration, no localization resources, only three Arabic strings. The app shell is not an Arabic-first RTL product.
5. **Packaging is build-only.** Linux release builds, but no installer, launch smoke test, Windows build, or signing exists.
6. **Real provider call is unverified.** Transport and routing are tested locally, and the desktop controller is tested with a scripted brain, but no live provider request/tool loop was executed. The desktop path also rejects media files outside the project workspace by design.

---

## 9. Reproduction

```bash
# Full gate (format, analyze, docs, all package tests, desktop widget tests)
./tool/ci/verify.sh

# Real 30s advertisement scenario
cd packages/agent_runtime
dart test test/acceptance_ad_test.dart --reporter=expanded

# Real FFmpeg backend (MP4 + WAV)
cd ../render_pipeline
dart test test/process_render_backend_test.dart --reporter=expanded

# Desktop analysis and packaging
cd ../../apps/desktop
flutter analyze
flutter build linux --release
```

---

## 10. Sign-off

**Engine:** conditionally ready for further product integration, with 362 passing tests and a verified real MP4/WAV export path. The two export defects found here are fixed.

**Desktop product:** **not production ready.** Do not represent AI editing, preview, export, Arabic support, or installable packaging as delivered until the blockers in §8 are implemented and re-verified.
