---
name: flutter-desktop-experience
description: Guidelines and patterns for high-performance Flutter desktop creative tools, custom timeline painters, keyboard navigation, and theme tokens.
---

# Flutter Desktop Experience Skill

## 1. High Performance Timeline Rendering
- Keep timeline track widgets modular.
- Avoid rebuilding entire track stacks during playhead scrubbing; isolate playhead widgets using `AnimatedBuilder` or specialized controllers.
- Use `RepaintBoundary` around high-frequency repainting components like audio meters and playheads.
- Custom painters (`CustomPainter`) should be used for timecode rulers, audio waveforms, and VU meter bars.

## 2. Desktop Keyboard Navigation
- Use `Focus` / `KeyboardListener` at the top app shell level.
- Map professional NLE hotkeys:
  - `Space`: Toggle Playback
  - `V`: Selection Tool
  - `C`: Razor / Split Tool
  - `Delete` / `Backspace`: Remove selected clip
  - `Ctrl + Z`: Undo transaction
  - `Ctrl + Y` or `Ctrl + Shift + Z`: Redo transaction
  - `Ctrl + S`: Atomic save
  - `Left` / `Right`: Frame step (-1 / +1)
  - `Shift + Left` / `Shift + Right`: Second step (-1s / +1s)
  - `Home` / `End`: Jump to start / end of timeline
  - `+` / `-`: Zoom in / Zoom out timeline

## 3. Theming & Typography
- Semantic tokens: `surface0` (deep background), `surface1` (panel background), `surface2` (cards/lanes), `accent` (brand focus `#6366F1`).
- Fonts: Cairo for Arabic UI/text labels, IBM Plex Mono for numeric timecodes.
- Ensure high-contrast selection highlights (`colors.selection`) and clear tool cursors (`SystemMouseCursors.click`, `SystemMouseCursors.grab`, `SystemMouseCursors.resizeLeftRight`).
