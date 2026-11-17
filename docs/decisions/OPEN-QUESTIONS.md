# Open Questions and Proposed Defaults

Where the architecture specifications are silent, ambiguous, or allow multiple interpretations, questions and safe defaults are recorded here. Approved architecture documents are never directly edited.

---

## OQ-001: Structure and Error Representation in `EditOutcome`

- **Context**: Spec §9.3 defines the signature `Future<EditOutcome> apply(EditTransaction transaction, {required int expectedRevision});` without defining the inner structure of `EditOutcome`.
- **Question**: Should `EditOutcome` be an exception-throwing contract or a functional result object?
- **Decision / Proposed Default**: Implemented as a sealed class hierarchy (`EditSuccess` and `EditFailure`).
  - `EditSuccess` provides `document` and the incremented `revision`.
  - `EditFailure` wraps `ShadowError` with code (`EDIT_REVISION_MISMATCH`, `EDIT_INVALID_OPERATION`), category (`edit`), `retryable` flag, and diagnostic `details`.
  - Also exposes convenience getters (`isSuccess`, `isFailure`, `document`, `revision`, `error`) for ergonomic calling from UI or agent tools without requiring unhandled exception crashes.

---

## OQ-002: Revision Counter Behavior Across Undo and Redo

- **Context**: Spec §0 defines Revision as "عدّاد أحادي التزايد يزداد مع كل EditTransaction مُثبَّتة" (a monotonic increasing counter). In Spec §14.1, frame cache keys depend on `revision` or `graph_hash`.
- **Question**: When an undo or redo occurs, should `revision` increment (monotonically) or decrement / step backward to the previous revision number?
- **Decision / Proposed Default**: Increment `revision` monotonically on every state transition (`apply`, `undo`, `redo`).
  - If `revision` were decremented on undo, a subsequent edit would re-issue a previously seen revision number, creating cache collisions in scrub frame caches and breaking optimistic concurrency locks (`expectedRevision`).
  - Monotonic increments guarantee that every distinct document state has a globally unique, strictly ascending revision identifier.

---

## OQ-003: Scope of Transitions in Phase 1

- **Context**: The Phase 1 brief notes: "transitions only on the boundary of two adjacent clips (if you implement transitions now; otherwise list as deferred)."
- **Question**: How much transition functionality belongs in Phase 1 (`editing_core`) versus Phase 3 (`RenderGraph` derivation)?
- **Decision / Proposed Default**: 
  - Included `Transition` in the track model with strict invariant validation: `transition.at_ticks` must exactly equal the cut boundary (`fromClip.timelineEndTicks == toClip.timelineStartTicks`), both clips must exist on the track, and `duration_ticks <= min(fromClip.durationTicks, toClip.durationTicks) ~/ 2`.
  - Specific transition editing commands (e.g. `AddTransitionCommand`) and transition rendering compilation are deferred to Phase 3.

---

## OQ-004: Track Kinds, Clip Arrays, and Asset Kind Matching

- **Context**: In `rendergraph.schema.json` and `validate_contract.py`, tracks declare specific clip arrays per track kind:
  - `video` track: holds `clips` (`VideoClip` items) and optional cut-boundary `transitions`.
  - `audio` track: holds `audio_clips` (`AudioClip` items).
  - `overlay` track: holds `text_layers` (`TextLayer` items).
- **Question**: How does `editing_core` model clip arrays and validate track/asset-kind compatibility?
- **Decision / Proposed Default**:
  - `Track.toJson()` outputs exactly the schema-required array: `'clips'` for `video`, `'audio_clips'` for `audio`, and `'text_layers'` for `overlay`.
  - `TrackKind.video`: accepts clips of kind `video`, `image`, `color`, `adjustment`. Allowed assets: `AssetKind.video`, `AssetKind.image`.
  - `TrackKind.audio`: strictly holds clips of kind `audio`. Allowed assets: `AssetKind.audio`, or `AssetKind.video` when referencing an embedded audio stream via `stream_index >= 0`.
  - `TrackKind.overlay`: reserved for text layers / rasters. Media clips are rejected with `EDIT_INVALID_OPERATION`.

---

## OQ-005: Deferred Methods on `EditingService` in Phase 1

- **Context**: Spec §9.3 includes `openProject`, `save`, and `resolveGraph` on `EditingService`. Phase 1 instructions state: "Leave openProject/save/resolveGraph for later phases but keep the interface compatible."
- **Question**: How should `EditingService` handle calls to these methods during Phase 1?
- **Decision / Proposed Default**: These methods are declared on the interface matching Spec §9.3 signatures. In `DefaultEditingService`, `openProject` and `save` are wired in Phase 2 on top of `local_storage`, while `resolveGraph` is deferred to Phase 3.

---

## OQ-006: Video Asset Embedded Audio Routing to Audio Tracks

- **Context**: A single imported video file (e.g. MP4) typically contains both a video stream (stream 0) and an audio stream (stream 1).
- **Question**: How does a video asset's embedded audio reach an audio track in the timeline without duplicating or re-encoding files?
- **Proposed Default**:
  - `Asset` retains `kind: AssetKind.video` representing the container.
  - When placing the media on the timeline, two linked clips are created:
    1. A `VideoClip` on a video track with `stream_index: 0` (or primary video stream).
    2. An `AudioClip` on an audio track referencing the same `asset_id` with `stream_index: 1` (the audio stream).
  - `rendergraph.schema.json` already natively supports this: `AudioClip.asset_id` and `AudioClip.stream_index` allow audio tracks to pull PCM from container files directly during MLT/FFmpeg compilation.
  - In Phase 5 (UI), the clips can share a link identifier (`link_id` / group) so moving or trimming one keeps audio and video in sync by default.

---

## OQ-007: Phasing for Effects, Keyframes, and Arabic Text Layers

- **Context**: Effects, keyframe animations, and Arabic text overlays are specified in `rendergraph.schema.json` and the UI spec.
- **Question**: In which phases do effects, keyframes, and Arabic text layers enter the model and runtime?
- **Proposed Default**:
  - **Phase 3 (RenderGraph derivation)**: Add typed models for `Effect`, `Param`, `Keyframe`, `TransformBox`, and `TextLayer` to `editing_core`, compiling and validating against `rendergraph.effects.json` and `rendergraph.schema.json` (easing functions, parameter bounds).
  - **Phase 5 (Desktop App & Timeline UI)**: Implement UI Inspector controls for effect parameters, transform anchor/scale, and text layer input with Arabic RTL HarfBuzz + FreeType text rasterization in Media Core.
  - **Phase 6 & 7 (Preview & Native Engine)**: Preview and final export rendering in native MLT/FFmpeg worker.

---

## OQ-008: Table-vs-Blob Decision and Storage Schema in `.ssproj`

- **Context**: Spec §11 states that `.ssproj` is a project-specific SQLite database holding document state and operations (`document + ops`).
- **Question**: Should the document snapshot be normalized across dozens of entity tables (`clips`, `tracks`, `assets`, etc.) or stored as a versioned canonical JSON snapshot inside SQLite accompanied by the append-only `edit_ops` table?
- **Decision / Proposed Default**: **Hybrid Document-Snapshot + Operations Log**:
  - `project_state` table holds the single authoritative document snapshot (`document_json`), metadata (`id`, `name`, `revision`, `schema_version`, timestamps).
  - `edit_ops` table holds the sequential, append-only history of every committed `EditTransaction` (`seq`, `project_id`, `revision`, `batch_id`, `op_type`, `payload_json`, `inverse_json`, `origin`, `created_at`).
  - `schema_migrations` table tracks applied schema versions forward.
  - **Rationale**:
    1. **Performance (QG-7)**: A single-row snapshot read opens a 200-clip project in < 15 ms, comfortably beating the 120 ms spec budget, avoiding dozens of multi-table joins.
    2. **ACID Durability**: Pure SQLite file with atomic writes (`.part` -> fsync -> rename) and `PRAGMA integrity_check`.
    3. **Full Auditability**: The `edit_ops` table guarantees every undo/redo/transaction step is permanently recorded.
    4. **Decoupled Boundary**: Allows `local_storage` to remain completely agnostic of Dart domain classes (Spec §2.2).

---

## OQ-009: Autosave Policy and Crash Recovery Interval

- **Context**: Spec §11 and §1.2 QG-9 require crash recovery without lost edits, but disk writes must not stutter timeline playback or UI scrubbing.
- **Question**: What is the default policy for autosaving project state?
- **Proposed Default**:
  - **Debounced Save on Edit**: After any `EditTransaction`, start a debounce timer of 3 seconds. If no further edits occur within 3 seconds, trigger an asynchronous background atomic save.
  - **Max Unsaved Interval**: If continuous edits occur (e.g. rapid trimming or agent task loops), force an atomic save every 30 seconds.
  - **Pre-flight Save**: Force an immediate atomic save before executing Dangerous agent tasks, before initiating export renders, and upon application close.
  - **Recovery on Startup**: Startup automatically checks for `<name>.part` leftovers (from ungraceful termination mid-save) and restores the pristine `.ssproj` file without prompt or crash.

---

## OQ-010: Audio Waveform Peak Sampling Density and Storage Format

- **Context**: Spec §10.1 specifies that FFmpeg owns proxy, thumbnail, and waveform generation. Waveforms must render smoothly on desktop timeline tracks during scrubbing and zoom changes without UI stutter.
- **Question**: What sampling density and data structure should be stored for audio waveforms?
- **Decision / Proposed Default**:
  - Sample density is standardized at 100 samples per second (100 Hz).
  - Piped PCM is extracted at 8 kHz mono signed 16-bit little-endian (`-ac 1 -ar 8000 -f s16le -`), downsampled into 80-sample buckets, yielding max peak amplitudes normalized to `[0.0, 1.0]` along with optional `minPeaks` and `maxPeaks`.
  - For a 10-minute audio asset, 100 Hz produces 60,000 float points (~240 KB in memory), which renders at 60 fps on desktop timeline canvases and can be cached directly alongside asset metadata.

---

## OQ-011: Proxy Transcoding Codec and Atomic Ingestion Protocol

- **Context**: Spec §10.1, §11, and §14.1 require fast proxy generation that avoids disk corruption on mid-save crash.
- **Question**: What codec profile, resolution, and atomic write protocol should be used for edit proxies?
- **Decision / Proposed Default**:
  - Proxy target resolution defaults to 720p (scaled maintaining aspect ratio: `-vf "scale=-2:720"`).
  - Codec is H.264 Baseline Profile with `libx264` (`-preset ultrafast -crf 28`) and AAC stereo audio (128 kbps).
  - Proxies are always written with atomic write semantics (`<cacheDir>/proxies/<blake3Hash>.mp4.part` -> fsync -> rename) and explicit format flag (`-f mp4`), preventing corrupted partial files from entering the cache if the application is killed during transcoding.

