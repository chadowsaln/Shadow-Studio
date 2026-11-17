# Shadow Studio — Implementation Matrix

**Companion to:** `PROJECT_AUDIT.md`
**Purpose:** Per-feature status, existing implementation, missing components, dependencies, recommended order, and acceptance criteria.
**Status legend:** Complete / Partial / Missing.
**Evidence convention:** `path:line` refers to the working tree at audit time.

---

## 1. How to read this matrix

Each feature row answers six questions:

1. **Status** — how much of the feature is real and reachable.
2. **Existing implementation** — files that already do part of the work.
3. **Missing components** — what must be built or wired.
4. **Dependencies** — what must exist first.
5. **Order** — recommended implementation phase (see §3).
6. **Acceptance criteria** — objective, testable definition of done.

A feature is **not** "Complete" merely because a library exists; it must be reachable from `apps/desktop` and covered by a test that exercises the real path.

---

## 2. Feature matrix

### F-01 — Project lifecycle (create / open / save / close)

| Field | Value |
|---|---|
| **Status** | **Partial** |
| **Existing** | `DefaultEditingService` (`packages/editing_core/lib/src/service/default_editing_service.dart`); `ProjectFileStorage`/`SqliteProjectFile` (`packages/local_storage/...`); app seeds a demo document (`apps/desktop/lib/src/app.dart:48-66`); `saveProject` in `EditorController` (`editor_controller.dart:383-407`) |
| **Missing** | New/open/close flows in UI (no menu wiring to `open()`); recovery of unsaved changes; project picker; "open" path in `EditorController`; handling of `projectFilePath` relative vs absolute |
| **Dependencies** | Editing Core (done), Local Persistence (partial), Desktop shell (done) |
| **Order** | Phase 1 |
| **Acceptance** | Create → edit → save → close → reopen produces identical document, revision, and edit history; no duplicate `edit_ops`; save works with absolute paths; UI exposes open/save/save-as. |

**Known defects:** `saveTo` re-inserts all `_committedOps` (`default_editing_service.dart:385`) → duplicate history. App default path is relative (`'ep12_demo.ssproj'`, `app.dart:53`).

---

### F-02 — Timeline editing (add / split / trim / delete / move / undo / redo)

| Field | Value |
|---|---|
| **Status** | **Partial** (add/split/trim/delete/undo/redo real; move/ripple/join partial) |
| **Existing** | `editing_core` commands + invariants + undo/redo; `EditorController.addAssetToTimeline/splitClipAtPlayhead/trimClip/deleteSelectedClip/undo/redo` (`editor_controller.dart:182-380`); timeline widgets (`src/ui/timeline/*`) |
| **Missing** | Move/drag-reorder with ripple; join (same asset); multi-select + marquee; keyboard map completeness (§5.8); snap/drag-drop from media bin (partial); effect/transition/text layer editing |
| **Dependencies** | F-01, F-03 (for visual feedback) |
| **Order** | Phase 1 |
| **Acceptance** | Each operation is a single atomic transaction; undo restores exact prior state; invariants reject invalid ops with `EDIT_INVALID_OPERATION`; revision bumps once per transaction; no orphan clips/gaps. |

---

### F-03 — Preview (frame-accurate playback + scrub)

| Field | Value |
|---|---|
| **Status** | **Missing** (UI shell exists; rendering is a mock) |
| **Existing** | `PreviewCanvas` draws icon + label + timecode (`src/ui/preview/preview_canvas.dart:45-75`); `TransportControls`; `EditorController` play/pause/seek timer (`editor_controller.dart:114-141`) |
| **Missing** | Real decode of the active clip at playhead; frame cache; GPU/texture upload; scrub-accurate seek; frame-delay indicator; proxy vs full-res selection; audio playback sync |
| **Dependencies** | F-05 (media decode), RenderGraph (done), Native Media Engine (missing) |
| **Order** | Phase 3 |
| **Acceptance** | Seeking to any tick renders the correct composited frame (text/overlay/effects) within the UX budget (§6.6); playback advances at the project frame rate; scrubbing is smooth and interruptible. |

---

### F-04 — Export / render

| Field | Value |
|---|---|
| **Status** | **Missing (Dart) / Partial (Python spike)** |
| **Existing** | `ExportDialog` pre-flight via `resolveGraph` + **simulated** timer progress (`src/ui/export/export_dialog.dart:35-69`); Python spike renders a real MP4 with determinism + refusal tests (`tools/media-spike/`) |
| **Missing** | Dart RenderGraph executor (port the spike), encoder pipeline, atomic output file, progress/ETA/cancel, queue, pre-flight blockers, output-exists handling, "first 3 frames valid" gate (V2-D10), background export, resume after crash |
| **Dependencies** | F-03 (preview path), Native Media Engine, F-01 |
| **Order** | Phase 4 |
| **Acceptance** | Export produces a byte-deterministic MP4 matching the RenderGraph; first 3 frames validated before full render; progress/ETA/cancel real; output written atomically; failure codes mapped to UI messages. |

**Note:** the Python spike is the reference implementation and must be treated as the behavioural spec for the Dart port.

---

### F-05 — Media ingestion (import / probe / proxy / thumbnail / waveform / hash)

| Field | Value |
|---|---|
| **Status** | **Partial** |
| **Existing** | `FfmpegMediaWorker` (probe/proxy/thumbnail/waveform), `MediaLibraryService`, `Blake3`, `MediaHashRegistry` (`packages/media_core/...`) |
| **Missing** | Import UI wiring from `ImportDialog` to controller (verify); missing-media/relink flow; transcode status/progress; cache eviction; `assetPath` path-safety key (see S-03); Windows FFmpeg discovery |
| **Dependencies** | Local filesystem, FFmpeg binary |
| **Order** | Phase 1 |
| **Acceptance** | Importing a file produces a stable asset ID (content hash), duration, resolution, thumbnail, and waveform; duplicate imports dedupe; missing files are flagged and relinkable. |

---

### F-06 — Editing Core (document / commands / invariants / revision / undo)

| Field | Value |
|---|---|
| **Status** | **Complete** |
| **Existing** | `editing_core`: models, commands, invariants, `DefaultEditingService`, `resolveGraph`, `UuidV7`, `TimeTicks` |
| **Missing** | Integration-level tests only (unit/golden exist); move/ripple/join commands if required by UI spec |
| **Dependencies** | contracts (currently duplicated) |
| **Order** | Done (foundation) |
| **Acceptance** | All invariants hold after every transaction; revision monotonic; undo/redo symmetric; `resolveGraph` matches the validated contract (`validate_contract.py` passes). |

---

### F-07 — Local persistence (atomic save / index / migrations / recovery)

| Field | Value |
|---|---|
| **Status** | **Partial** |
| **Existing** | `.ssproj` SQLite, atomic `.part`→rename, integrity check, `SchemaMigrations`, project index, checkpoint store, session/task memory, process-kill tests |
| **Missing** | Real directory fsync (currently no-op); dedupe of `edit_ops`; unified migration system; index auto-rebuild; crash recovery UI |
| **Dependencies** | F-06 |
| **Order** | Phase 2 |
| **Acceptance** | Kill -9 during save leaves either the old or new file, never corrupt; reopening yields no duplicate ops; index can be deleted and rebuilt from `.ssproj`; migrations are forward-only and idempotent. |

---

### F-08 — Permissions, approvals, path safety

| Field | Value |
|---|---|
| **Status** | **Implemented (engine); approval UI pending** |
| **Existing** | `PermissionManager` (issued-token registry, fail-closed, shell auth), `PermissionPolicy` (LOW/MEDIUM/HIGH table, protected tools, unknown-tool approval), canonical `PathValidator`, deny-by-default `WorkspaceGuard`, `ShellCommandGuard`, hash-chained redacting `AppendOnlyAuditLogger`, encrypted `FileSecretStore`, wired into `ToolExecutor`; adversarial tests in `packages/permissions/test` + `tool_system/test/security_integration_test.dart`; boundaries documented in `docs/security/PERMISSIONS.md` |
| **Missing** | Approval dialog + desktop wiring; persisted consent/approval state; OS keyring backend; audit rotation/anchoring; TOCTOU-hardened file handles |
| **Dependencies** | F-09 (agent), F-12 (tools) |
| **Order** | Phase 2 |
| **Acceptance** | Every tool call passes through permission checks; destructive/out-of-workspace ops require explicit approval; approval is single-use, bound to tool+args hash, TTL-enforced; all decisions audited; no path escape via symlink/traversal. |

---

### F-09 — Provider Gateway (routing / adapters / budgets / fallback)

| Field | Value |
|---|---|
| **Status** | **Partial / non-functional** |
| **Existing** | `ProviderRouter`, 4 adapters, `BudgetEnforcer`, `CapabilityResolver`, `ModelSelector`, `ToolCallNormalizer`, `InMemoryCredentialStore` |
| **Missing** | **Real HTTP/SSE `ProviderTransport`**; OS keyring `CredentialStore`; persistent egress consent; stream-error/timeout integration tests; payload-declaration enforcement |
| **Dependencies** | contracts |
| **Order** | Phase 2 |
| **Acceptance** | A real OpenAI/Anthropic/Gemini/OpenRouter request streams tokens and tool calls; 401/403 never fall back; budgets enforced pre/post; egress consent required whenever media/file content is present (no bypass); keys never logged or persisted outside keyring. |

---

### F-10 — Agent runtime (plan → decide → tool call → observe → repeat)

| Field | Value |
|---|---|
| **Status** | **Partial (loop only; no real brain/tools)** |
| **Existing** | `AgentController`, `execution_loop`, `DefaultPlanner`, `TaskScheduler`, `RecoveryManager`, `AgentLimits`, events |
| **Missing** | LLM-backed `AgentBrain`; wiring to `ProviderGateway` + `ToolExecutor` + `PermissionManager` + `ContextEngine`; production `ApprovalGate`; cancellation propagation to tools; checkpoint restore |
| **Dependencies** | F-08, F-09, F-12, F-13 |
| **Order** | Phase 3 |
| **Acceptance** | A user request produces a plan, executes real tools through the permission gate, observes results, and completes or recovers; limits stop runaway loops; cancellation is prompt; state is checkpointed and resumable. |

---

### F-11 — Context Engine (reproducible snapshots / trimming / memory)

| Field | Value |
|---|---|
| **Status** | **Partial (unconsumed, untested)** |
| **Existing** | `ContextSnapshot` (SHA-256), `ContextBuilder`, `ContextTrimmer`, `MemoryManager`, `ContextManager` |
| **Missing** | Tests; single canonical context hash (align with agent runtime); integration into the agent loop; token-budget enforcement at call time; memory pruning policy |
| **Dependencies** | F-10, F-07 (memory storage) |
| **Order** | Phase 3 |
| **Acceptance** | Each tool call carries a deterministic `context_hash`; two builds from the same inputs produce identical hashes; trimming respects token budget and records truncated sections; memory is scoped per task/project. |

---

### F-12 — Tool System (registry / executor / 27 tools)

| Field | Value |
|---|---|
| **Status** | **Partial (10/27 tools; executor present)** |
| **Existing** | `ToolRegistry`, `ToolExecutor`, `ToolSchemaValidator`, `WorkspacePathValidator`, 10 built-ins |
| **Missing** | 17 tools (see PROJECT_AUDIT §4.5); closed-schema enforcement at registration; output-schema validation; full path-key coverage; result-size/truncation policy; tool tests for real file effects |
| **Dependencies** | F-06, F-05, F-08 |
| **Order** | Phase 2 (tools that mutate the document), Phase 3 (media/AI tools) |
| **Acceptance** | All 27 v1 tools registered with closed schemas; every call validated for args **and** output; all path-like args validated; every mutating tool produces an `EditTransaction` and is undoable; audit record per call. |

---

### F-13 — AI surfaces (chat / plan / approval / review / settings)

| Field | Value |
|---|---|
| **Status** | **Missing** |
| **Existing** | None in Flutter. UX spec §8.4/§8.5 describes the intended surfaces; HTML prototype has a single mock surface only |
| **Missing** | Chat panel, plan/step timeline, tool-call inspector, approval dialog, AI proposal review (diff accept/reject), settings (providers, keys, egress consent, budgets), status/progress |
| **Dependencies** | F-09, F-10, F-08 |
| **Order** | Phase 5 |
| **Acceptance** | User can start a task, watch the plan and each tool call, approve/deny sensitive calls, review AI edit proposals, and configure providers/consent; all state survives navigation. |

---

### F-14 — Observability & audit

| Field | Value |
|---|---|
| **Status** | **Partial (library only)** |
| **Existing** | `AppendOnlyAuditLogger`, `ToolExecutionRecord`/`toAuditEvent`, `provider_accounting`, `BudgetEnforcer` |
| **Missing** | Wiring into app; log file location/rotation; tamper-evidence; user-visible diagnostics; correlation IDs end-to-end |
| **Dependencies** | F-08, F-10, F-12 |
| **Order** | Phase 3 |
| **Acceptance** | Every permission decision, tool call, provider request, and budget event is logged with correlation IDs; logs are append-only and reviewable; secrets never appear. |

---

### F-15 — Localization / RTL / accessibility

| Field | Value |
|---|---|
| **Status** | **Partial** |
| **Existing** | RTL shell + LTR timeline (`timeline_panel.dart:64-66`), timecode LTR isolation, theme contrast tokens, focus/theme tests |
| **Missing** | Full Arabic microcopy coverage; screen-reader semantics; keyboard-only operation for all surfaces; `prefers-reduced-motion` in Flutter; high-contrast verification |
| **Dependencies** | F-13 (AI surfaces must also comply) |
| **Order** | Phase 5 |
| **Acceptance** | All spec §13.1 UX budgets met; full keyboard map; RTL/LTR isolation verified; accessibility scan clean. |

---

### F-16 — Native media engine / worker

| Field | Value |
|---|---|
| **Status** | **Missing** |
| **Existing** | FFmpeg CLI worker (probe/proxy/thumbnail/waveform); Python render spike |
| **Missing** | In-process render/export engine or separate worker + C ABI (V2-D2); caching layer; GPU path; frame-accurate preview decode |
| **Dependencies** | F-03, F-04 |
| **Order** | Phase 4 |
| **Acceptance** | Rendering runs off the UI isolate; progress/cancel work; output is deterministic; the engine is replaceable behind the contract. |

---

## 3. Recommended implementation order

### Phase 0 — Stabilize the base (1 sprint)
- Commit or stash the dirty tree (§8 of PROJECT_AUDIT).
- De-duplicate contracts: one `ShadowError`, one `ApprovalToken`, one editing type family.
- Remove dead theme tree (`apps/desktop/lib/ui/core/theme/*`).
- Add `contracts` and `context_engine` tests.
- Fix `edit_ops` duplicate insertion and document the fsync limitation (or implement it).

**Exit criteria:** clean tree, single contracts, tests for all packages, persistence save/reopen stable.

### Phase 1 — Product editing loop (1–2 sprints)
- Project open/save/save-as UI.
- Complete timeline interactions (move/ripple/join/marquee/keyboard).
- Import → timeline → edit → save end-to-end app test.
- Wire permissions into editing operations where destructive.

**Exit criteria:** a user can edit and persist a real project without touching the filesystem manually.

### Phase 2 — Safety + tools (1–2 sprints)
- Production `ApprovalGate` + approval UI stub.
- Complete path-safety unification; full path-key coverage.
- Implement the 17 missing tools (document-mutating first).
- Closed-schema registration + output validation.

**Exit criteria:** all 27 tools registered and tested; every mutation undoable; path escapes rejected.

### Phase 3 — AI spine (2–3 sprints)
- Real `ProviderTransport` (HTTP/SSE) + OS keyring.
- LLM-backed `AgentBrain` wired to `ProviderRouter` + `ToolExecutor`.
- Context snapshot integration + single context hash.
- Agent loop checkpoint/recovery + observability.

**Exit criteria:** a real model plans and executes real tools with budgets, approvals, and audit.

### Phase 4 — Render + preview (2–3 sprints)
- Port the Python spike to a Dart RenderGraph executor.
- Real preview frame pipeline.
- Real export with pre-flight, progress, ETA, cancel, queue, resume.

**Exit criteria:** export produces a verified MP4; preview is frame-accurate; V2-D10 satisfied.

### Phase 5 — AI surfaces + polish (1–2 sprints)
- Chat/plan/approval/review/settings UI.
- Localization, accessibility, keyboard completeness.
- Performance budgets.

**Exit criteria:** spec §13.1 budgets met; full UX spec coverage; accessibility clean.

---

## 4. Dependency graph

```
F-06 Editing Core (done)
 ├─► F-01 Project lifecycle ─► F-02 Timeline
 ├─► F-07 Persistence
 └─► F-12 Tool System ─► F-08 Permissions
F-05 Media ─► F-03 Preview ─► F-16 Native engine ─► F-04 Export
F-09 Provider ─► F-10 Agent ─► F-11 Context
F-10 + F-12 + F-08 ─► F-14 Observability
F-10 + F-08 ─► F-13 AI surfaces ─► F-15 Localization/a11y
```

**Critical path:** F-06 → F-09 → F-10 → F-12 → F-13. Without F-09 (transport) nothing AI-related can be demonstrated.

---

## 5. Quick status dashboard

| ID | Feature | Status | Phase |
|---|---|---|---|
| F-01 | Project lifecycle | Partial | 1 |
| F-02 | Timeline editing | Partial | 1 |
| F-03 | Preview | Missing | 3 |
| F-04 | Export/render | Missing (Dart) | 4 |
| F-05 | Media ingestion | Partial | 1 |
| F-06 | Editing Core | Complete | — |
| F-07 | Persistence | Partial | 2 |
| F-08 | Permissions/approvals | Implemented (engine) | 2 (UI) |
| F-09 | Provider gateway | Partial | 2 |
| F-10 | Agent runtime | Partial | 3 |
| F-11 | Context engine | Partial | 3 |
| F-12 | Tool system | Partial | 2/3 |
| F-13 | AI surfaces | Missing | 5 |
| F-14 | Observability | Partial | 3 |
| F-15 | Localization/a11y | Partial | 5 |
| F-16 | Native engine | Missing | 4 |