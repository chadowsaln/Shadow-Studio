# Shadow Studio - Desktop Application (`apps/desktop`)

Desktop frontend application for the **Shadow Studio** non-destructive video editor, built with Flutter for Linux (and Windows).

---

## 1. Overview & Architecture Boundary

Per the Software Architecture Specification v2.0 (`docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md`) and MVP UI/UX Design Specification v1.0 (`docs/design/MVP-UI-UX-SPEC-v1.0.md`), `apps/desktop` serves as the desktop **body** of the editor.

### Responsibilities
- **Multi-Panel Workspace Layout**: Responsive layout featuring Top Bar, Media Bin, Preview Viewport, Timeline, Inspector, and Status Bar.
- **Design System & Theming**: WCAG AA compliant semantic color tokens (`ShadowColors`), dual theme support (Dark / Light mode), and bidirectional-safe typography (`Cairo` for operational Arabic/English text, `IBM Plex Mono` tabular figures for SMPTE timecodes).
- **Interactive Editing Workflow**: Direct manipulation of timeline tracks (`V1`, `A1`, `T1`), clips, trim handles, playhead scrub, split razor tool (`C`), select tool (`V`), and atomic undo/redo (`Ctrl+Z` / `Ctrl+Y`).
- **Media Ingestion & Invariant Validation**: Integrated with `packages/media_core` for probing, BLAKE3 deduplication, thumbnail generation, and proxy playback.
- **Pre-Flight Render Validation**: Live sequence profile inspection and pre-flight validation against `rendergraph.schema.json` via `EditingService.resolveGraph`.

### AI Agent Integration
The desktop app now hosts the AI agent as a UI surface while keeping the editing core authoritative:
- `AgentSessionController` (`lib/src/agent`) owns the real `AgentController`, `ToolExecutor`, `PermissionManager`, and approval gate. The AI tab renders only typed runtime events (plan, progress, tool activity, approvals, results) — never chain-of-thought or credentials.
- Provider, model, and base URL are selected in the app and persisted in `agent.json`; the API key is written only to the encrypted `SecureFileCredentialStore`. Environment variables are a first-run fallback only.
- Tools are `list_files`, `media_probe`, `media_analysis`, and `timeline_edit`. Every tool call still passes schema validation, workspace path confinement, permission policy, and audit. `timeline_edit` is `restricted` and therefore pauses on an explicit approval card.
- AI edits submit one atomic `EditTransaction` through the editing core. On success the runtime advances the task revision, and the desktop calls `EditorController.refreshAfterExternalEdit()` so the timeline re-renders without a full reload.
- AI data egress requires a per-session checkbox before a task can start. No provider request is made on app launch.
- `Ctrl+Shift+A` opens the AI tab. A task can be cancelled; pending approvals are revoked on stop or failure.

---

## 2. Directory Structure

```
apps/desktop/
├── lib/
│   ├── main.dart                      # Desktop application entrypoint
│   └── src/
│       ├── app.dart                   # Root ShadowStudioApp widget
│       ├── agent/
│       │   ├── agent_settings.dart    # Provider descriptors, agent.json, encrypted key store
│       │   ├── agent_session_controller.dart # Agent runtime/UI bridge, approvals, activity
│       │   └── desktop_tool_executor.dart    # ToolExecutor → ToolCallExecutor adapter
│       ├── controller/
│       │   └── editor_controller.dart # Unified ChangeNotifier coordinating editing state & tools
│       ├── theme/
│       │   ├── shadow_colors.dart     # Semantic design tokens (surface0..2, border, accent, playhead)
│       │   ├── shadow_typography.dart # Cairo & IBM Plex Mono typography definitions
│       │   └── shadow_theme.dart      # Material 3 ThemeData builders for dark/light themes
│       ├── utils/
│       │   └── timecode_formatter.dart# SMPTE HH:MM:SS:FF formatter with Unicode LTR isolate markers
│       └── ui/
│           ├── shell/
│           │   ├── app_shell.dart     # Global layout scaffolding & keyboard shortcuts
│           │   ├── top_bar.dart       # 48px header with project status, undo/redo, export trigger
│           │   └── status_bar.dart    # 28px footer with engine health, revision, zoom, timecode
│           ├── media/
│           │   ├── asset_card.dart    # Thumbnail card with duration & BLAKE3 dedupe badges
│           │   └── media_bin_panel.dart # Left panel media library and import trigger
│           ├── preview/
│           │   ├── preview_canvas.dart # 16:9 aspect ratio viewport with title/action safe areas
│           │   ├── transport_controls.dart # Play/pause, step frame, jump start/end buttons
│           │   └── preview_panel.dart  # Container combining canvas and transport bar
│           ├── timeline/
│           │   ├── timeline_toolbar.dart # Tool switch (Select/Razor), split, zoom controls
│           │   ├── timeline_ruler.dart   # Fractional second & frame time markers
│           │   ├── track_header.dart     # V1/A1/T1 headers with mute, solo, and visibility toggles
│           │   ├── clip_widget.dart      # Interactive clip rect with trim handles & selection border
│           │   ├── playhead_widget.dart  # Draggable playhead line and time indicator
│           │   ├── track_lane.dart       # Track lane containing arranged clips
│           │   └── timeline_panel.dart   # Complete horizontal scrolling timeline
│           ├── ai/
│           │   ├── ai_panel.dart            # Task input, consent, plan, approvals, activity
│           │   └── agent_settings_dialog.dart # Provider/model/API-key configuration
│           ├── inspector/
│           │   ├── transform_inspector.dart # Position, scale, rotation, and opacity inputs
│           │   ├── text_inspector.dart      # Arabic & English text overlay properties
│           │   └── inspector_panel.dart     # Right panel showing clip timing and sequence settings
│           └── export/
│               └── export_dialog.dart # Modal dialog for presets, pre-flight graph check, and render progress
├── test/
│   ├── widget_test.dart               # End-to-end desktop layout and modal smoke test
│   ├── editor_controller_test.dart    # Controller unit tests (seeking, splitting, trimming, undo/redo)
│   ├── timecode_formatter_test.dart   # Timecode formatting, frame math, and LTR isolation tests
│   ├── theme_test.dart                # Color tokens and typography verification
│   └── timeline_interaction_test.dart # Interactive widget tests (transport, zoom, tools, theme)
└── pubspec.yaml                       # App package manifest integrated into root workspace
```

---

## 3. Running Tests and Analysis

Run all tests inside `apps/desktop`:
```bash
flutter test
```

Run static analysis:
```bash
flutter analyze
```

Build the native Linux desktop executable:
```bash
flutter build linux --debug
```
