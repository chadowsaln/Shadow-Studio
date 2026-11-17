# editing_core

Pure Dart core engine for **Shadow Studio** desktop video editor.

It implements the timeline data model, pure editing commands, atomic transactions with undo/redo, optimistic concurrency, and invariant validation.

## Principles & Hard Constraints

- **Pure Dart**: Zero Flutter dependency. Runs in pure Dart CLI, tests, background isolates, or embedded in desktop applications.
- **Integer Ticks**: All time values are integer ticks (`1 tick = 1/1,000,000 s`). Never uses `double` for time values.
- **Spec Section 0 Conversions**:
  - `tick -> frame`: `floor(tick * fps_num / (1e6 * fps_den))`
  - `frame -> tick`: `ceil(frame * 1e6 * fps_den / fps_num)`
  - Frame-boundary rounding and quantization happen exclusively in Editing Core.
- **Non-destructive**: Original media files are never modified.
- **Immutable State**: `ProjectDocument` is an immutable snapshot.
- **Pure Commands**: Commands are pure functions: `Document -> Document + inverse`.
- **Atomic Transactions**: Every change is an atomic `EditTransaction` (= 1 revision bump = 1 undo step).
- **Error Codes**: Unified `ShadowError` codes (`EDIT_REVISION_MISMATCH`, `EDIT_INVALID_OPERATION`, `MEDIA_ASSET_MISSING`).

---

## Public API Overview

### 1. Data Model

- **`ProjectDocument`**: Complete project snapshot containing `name`, `profile` (`ProjectProfile`), `timebase` (`Timebase`), `backgroundRgba`, `tracks` (`List<Track>`), and `assets` (`Map<String, Asset>`).
- **`Track`**: Timeline track with `kind` (`video`, `audio`, `overlay`), dense `position` (0..n-1), `name`, `enabled`, and sorted `clips`, `transitions`, and `textLayers`.
- **`Clip`**: Slice of media aligned with `rendergraph.schema.json`. Fields: `id`, `asset_id`, `kind`, `timeline_start_ticks`, `duration_ticks`, `source_in_ticks`, `speed_num`, `speed_den`, `enabled`, `label`, `stream_index`, `opacity_ppm`, `transform`, `effects`, `gain_mb`, `pan_ppm`, `fade_in_ticks`, `fade_out_ticks`.
- **`TransformBox`**: 2D transform definition: `x_px`, `y_px`, `scale_x_ppm`, `scale_y_ppm`, `rotation_quarter_turns` (0..3), `anchor` (`center` | `top_left`), `crop_left_px`, `crop_right_px`, `crop_top_px`, `crop_bottom_px`.
- **`Effect`**, **`Param`**, **`Keyframe`**: Effect pipeline models aligned with `rendergraph.effects.json` (e.g. `shadow.blur.gaussian`, `shadow.color_balance`), supporting easing curves (`linear`, `ease_in`, `ease_out`, `ease_in_out`, `step`).
- **`TextLayer`**, **`TextLayerAnimation`**: Overlay text layers carrying raster bindings (`raster_uri`, `raster_hash`, dimensions) and animations (`none`, `fade`, `slide`).
- **`Asset`**: Immutable descriptor of source media: `id`, `kind` (`video`, `audio`, `image`), `uri`, `duration_ticks`, optional BLAKE3 `hash`.
- **`Transition`**: Boundary transition: `id`, `kind`, `at_ticks`, `duration_ticks`, `from_clip_id`, `to_clip_id`.
- **`ProjectProfile`**: Resolution and color configuration: `width`, `height`, `pixel_format`, `color_space`, `interlaced: false`.
- **`Timebase`**: Clock specification: `ticks_per_second: 1000000`, `fps_num`, `fps_den`, `sample_rate`, `channels`.
- **`RenderGraph`**: Normative closed-schema contract structure (`RenderGraphTrack`, `RenderGraphVideoClip`, `RenderGraphAudioClip`), validating directly against `rendergraph.schema.json` and consumed by `tools/media-spike`.
- **`TimeTicks`**: Exact integer math for tick<->frame conversions and frame boundary quantization.
- **`UuidV7`**: Deterministic and secure RFC 9562 UUIDv7 generator.

### 2. Pure Commands

Every command implements `EditCommand` and produces a `CommandResult(document, inverse)` such that `inverse.execute(document)` restores the exact previous document:

- **`AddTrackCommand`** ↔ **`RemoveTrackCommand`**
- **`AddClipCommand`** ↔ **`RemoveClipCommand`**
- **`MoveClipCommand`** ↔ **`MoveClipCommand`**
- **`TrimClipCommand`** ↔ **`TrimClipCommand`**
- **`SplitClipCommand`** ↔ **`JoinClipCommand`**
- **`AddAssetCommand`** ↔ **`RemoveAssetCommand`**

### 3. Transactions & Service Port

- **`EditingService`** (Port per Spec §9.3):
  ```dart
  abstract interface class EditingService {
    int get revision;
    ProjectDocument get currentDocument;
    bool get canUndo;
    bool get canRedo;
    Future<ProjectDocument> openProject(String path);
    Future<EditOutcome> apply(EditTransaction transaction, {required int expectedRevision});
    Future<EditOutcome> undo({required int expectedRevision});
    Future<EditOutcome> redo({required int expectedRevision});
    Future<void> save();
    RenderGraph resolveGraph({required int revision, required RangeTicks range});
  }
  ```
- **`DefaultEditingService`**: Standard in-memory implementation providing atomic commit, rollback on failure, optimistic revision checking, and undo/redo stacks.
- **`EditOutcome`**: Sealed class pattern:
  - `EditSuccess(document, revision)`
  - `EditFailure(error)`

---

## Boundary with the AI Agent Side

Per Architecture Spec §2.2 (Module Dependencies) and §7.2 (Tool Execution):

1. **Isolation**: `editing_core` has zero awareness of AI models, providers, prompts, tokens, or network protocols.
2. **Execution Surface**: The AI agent side (`agent_runtime`, `tool_system`) interacts with the editor **strictly** by constructing an `EditTransaction` and calling:
   ```dart
   final outcome = await editingService.apply(transaction, expectedRevision: currentRevision);
   ```
3. **No Phantom Edits**: The agent cannot mutate documents directly or bypass the transaction pipeline. Every AI action is encapsulated in an `EditTransaction` with `origin: 'ai'`, ensuring it appears as an undoable step in the history.
4. **Optimistic Concurrency**: If the user or another operation modified the document concurrently, `expectedRevision` will mismatch, returning `EditFailure(EDIT_REVISION_MISMATCH)` with `retryable: true`. The agent can re-fetch the latest `ProjectDocument` state and regenerate its proposal.
5. **Invariant Rejections**: If an AI proposal attempts an invalid operation (e.g. overlapping clips, placing audio assets on video tracks, or exceeding source media length), `apply` performs an atomic rollback and returns `EditFailure(EDIT_INVALID_OPERATION)` with explicit violation details for the agent to self-correct.

---

## Running Tests & Static Analysis

```bash
dart test packages/editing_core
dart analyze packages/editing_core
```
