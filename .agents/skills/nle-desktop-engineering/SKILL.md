---
name: nle-desktop-engineering
description: Expert engineering guide for Flutter desktop non-linear video editors (NLEs), including atomic transactions, integer tick math, drag-and-drop, magnetic snapping, and RenderGraph contracts.
---

# NLE Desktop Engineering Skill

This skill provides best practices, mathematical formulas, and architectural guidelines for building and maintaining the Shadow Studio desktop video editor in Flutter and Dart.

## 1. Time Representation & Frame Conversions
- **Integer Ticks**: All time values on the timeline and within clips are strictly represented in integer microseconds (`1 tick = 1/1,000,000 s`). Never use `double` for time storage.
- **Conversion Formula**:
  $$\text{ticks} = \text{round}\left(\text{frame} \times \frac{\text{fpsDen} \times 1,000,000}{\text{fpsNum}}\right)$$
  $$\text{frame} = \text{round}\left(\text{ticks} \times \frac{\text{fpsNum}}{\text{fpsDen} \times 1,000,000}\right)$$
- **SMPTE Timecodes**: Format as `HH:MM:SS:FF`. In multilingual / Arabic contexts, always enclose timecodes with Unicode Left-to-Right Isolate markers (`\u2066...\u2069`) to prevent bidirectional text reordering.

## 2. Desktop Drag-and-Drop Architecture
1. **OS File Drop**:
   - Integrated via `package:desktop_drop/desktop_drop.dart`.
   - Wrap target panels (Media Bin, Timeline, App Shell) in `DropTarget`.
   - Process dropped file paths through `MediaLibraryService.importFile(...)`.
2. **Media Bin to Timeline Drop**:
   - Source: `Draggable<ImportedMediaAsset>` on `AssetCard`.
   - Target: `DragTarget<ImportedMediaAsset>` on `TrackLane`.
   - Drop position calculation:
     $$\text{seconds} = \frac{\text{localX}}{\text{pixelsPerSecond}}$$
     $$\text{ticks} = \text{round}(\text{seconds} \times 1,000,000)$$
   - Apply magnetic snapping before inserting via `controller.insertClipAt(...)`.
3. **Timeline Clip Movement & Trimming**:
   - Clips are moved using `MoveClipCommand(trackId, clipId, newTimelineStartTicks)`.
   - Edges are trimmed using `TrimClipCommand(trackId, clipId, newTimelineStartTicks, newDurationTicks, newSourceInTicks)`.
   - All mutations execute as atomic `EditTransaction` verifying `expectedRevision`.

## 3. Magnetic Snapping Logic
- Snapping threshold: Typically 8 to 12 screen pixels.
- Convert threshold pixels to ticks: $\text{thresholdTicks} = \text{round}\left(\frac{\text{thresholdPx}}{\text{pixelsPerSecond}} \times 1,000,000\right)$.
- Snap targets:
  1. Timeline origin (`0` ticks).
  2. Current playhead position (`playheadTicks`).
  3. Neighboring clip boundaries (start and end ticks of adjacent clips on all tracks).
- Choose the nearest snap target within the threshold window.

## 4. UI/UX Principles for Video Editors
- **3-Column Workspace**: Media Bin & Inspector sidebars, Preview Viewport center-top, Timeline center-bottom.
- **Audio Waveforms**: Render waveform peaks visually inside audio clips to allow beat and speech alignment.
- **Visual Feedback**: Hover borders, razor guide lines, selection rings, drop zone highlight overlays.
- **Keyboard Shortcuts**: Complete desktop shortcuts (Space for Play/Pause, C for Razor, V for Select, Delete for Remove, Ctrl+Z/Y for Undo/Redo, Arrow keys for frame stepping).
