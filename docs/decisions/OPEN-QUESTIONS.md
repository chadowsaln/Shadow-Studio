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
