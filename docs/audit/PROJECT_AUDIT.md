# Shadow Studio — Project Audit (Documentation vs Implementation)

**Audit date:** 2026-11-17
**Type:** Read-only senior software architect audit. No production code was modified.
**Approved baseline:** `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md` (722 lines)
**UI baseline:** `docs/design/MVP-UI-UX-SPEC-v1.0.md` (831 lines)
**Superseded reference (contract only):** `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v1.0.md` — Appendix A/E remain canonical for the RenderGraph contract.

---

## 1. Executive verdict

Shadow Studio is a **well-structured, well-documented, and largely non-functional product skeleton**.

- The **domain/editing core is genuinely implemented**: immutable document, commands, invariants, optimistic concurrency, undo/redo, RenderGraph resolution, atomic SQLite persistence, media probing via FFmpeg.
- The **desktop editor shell is genuinely interactive**: RTL shell, timeline, inspector, media bin, status bar, theme system, keyboard map, controller state.
- The **AI/agent half of the product is not wired and cannot run**: there is **no real HTTP transport** (every provider adapter defaults to `MockProviderTransport`), **no LLM-backed brain**, **no production `ApprovalGate`**, and **the desktop app does not depend on the agent, provider, tool, permission, or context packages at all**.
- The **preview is a mock** (icon + label, no decoded frames) and **export is a simulated timer** (no encode, no file written).
- Several **duplicated contracts and models** (two `ShadowError`, two `ApprovalToken`, two `EditingService`/`ProjectDocument`/`EditTransaction`, two theme systems) are actively misleading and will cause integration defects.

**Bottom line:** the project passes static analysis and tests, and its editing/persistence foundation is credible. It is **not** an end-to-end AI video editor yet. Treat the current tree as *"Editing Core + UI prototype + AI contracts"*, not as a shippable MVP.

### 1.1 Status counts

| Status | Meaning | Count (major features) |
|---|---|---|
| Complete | Implemented, tested, wired into the app | 3 |
| Partial | Core implemented, integration/tests/gaps remain | 9 |
| Missing | Specified but no implementation | 4 |

---

## 2. Method and verification evidence

All commands were executed on the working tree at `14c64b3` (plus uncommitted changes, §8).

| Check | Command | Result |
|---|---|---|
| Contract validation | `python3 docs/architecture/contracts/validate_contract.py` | PASS — 2538 checks |
| Schema validation | `python3 docs/architecture/contracts/validate_schema.py` | PASS — 387 checks |
| v2 validator | `python3 docs/architecture/contracts/validate_v2.py` | PASS — 200 checks |
| Design-spec verifier | `python3 docs/design/verify_design_spec.py` | PASS — 128 checks |
| Dart analyze (root + packages) | `dart analyze` per package | PASS — 0 issues |
| Flutter analyze (desktop) | `flutter analyze` | PASS — 0 issues |
| Dart tests | `dart test` per package | PASS |
| Flutter tests | `flutter test` (desktop) | PASS |
| Manual source review | 40+ files across all packages + desktop UI | see §4 |

**Not verified:** runtime behaviour on real media, real provider network calls (impossible — no transport), real render/export, multi-window, packaging/installer, performance budgets.

### 2.1 Test inventory

| Package | Test files | Notes |
|---|---|---|
| `agent_runtime` | 5 | loop, budgets, retries, recovery, approvals (fake gate) |
| `editing_core` | 9 | commands, invariants, persistence, resolveGraph, golden media, perf, UUID, time |
| `local_storage` | 6 | atomic save, process-kill, migrations, index, budget |
| `media_core` | 4 | blake3, fake worker, ffmpeg worker, library |
| `permissions` | 1 | permission engine |
| `provider_gateway` | 1 | router/adapters/normalizer |
| `tool_system` | 1 | registry/executor/tools |
| `contracts` | **0** | no `test/` directory |
| `context_engine` | **0** | no `test/` directory |
| `desktop` | 5 | controller, theme, timecode, timeline interaction, boot |

---

## 3. Repository map

### 3.1 Workspace packages (root `pubspec.yaml`)

| Package | Path | Role | LOC (lib) | SDK |
|---|---|---|---|---|
| `contracts` | `packages/contracts` | Shared contracts/errors/codes | 637 | `^3.6.0` |
| `agent_runtime` | `packages/agent_runtime` | Agent loop, planner, scheduler, recovery | 1,635 | `^3.9.0` |
| `provider_gateway` | `packages/provider_gateway` | Provider routing, adapters, budgets | 1,719 | `^3.9.0` |
| `context_engine` | `packages/context_engine` | Reproducible context snapshots/trimming | 580 | `^3.9.0` |
| `tool_system` | `packages/tool_system` | Tool registry/executor/builtins | 1,150 | `^3.9.0` |
| `permissions` | `packages/permissions` | Permission policy, approvals, path safety | 928 | `^3.6.0` |
| `editing_core` | `packages/editing_core` | Document/commands/invariants/RenderGraph | 4,280 | `^3.6.0` |
| `media_core` | `packages/media_core` | Probe/proxy/thumbnail/waveform | 1,790 | `^3.6.0` |
| `local_storage` | `packages/local_storage` | `.ssproj` SQLite + index | 1,597 | `^3.6.0` |
| `desktop` | `apps/desktop` | Flutter desktop app | 3,695 | `^3.6.0` |

### 3.2 Non-workspace packages (path deps only)

`packages/agent_runtime`, `context_engine`, `contracts`, `permissions`, `provider_gateway`, `tool_system` are **not** members of the root workspace (`workspace:` list contains only `editing_core`, `local_storage`, `media_core`, `desktop`). They resolve via `path:` dependencies but are outside workspace resolution.

### 3.3 Auxiliary assets

| Path | Role | Status |
|---|---|---|
| `docs/architecture/contracts/*` | RenderGraph schema + 3 validators | Validated, pass |
| `tools/media-spike/` | Python FFmpeg proof-of-concept that really renders `rendergraph.example.json` to MP4 with determinism checks and refusal tests | **Working**, not ported to Dart |
| `prototype/ux-p1/` | Clickable HTML/JS UX prototype for Timeline + Export (Arabic, RTL), explicitly mock | **Working**, not integrated |

---

## 4. Module-by-module status

Legend: **Complete** / **Partial** / **Missing**.

### 4.1 Contracts — **Partial**

- Two barrels: `packages/contracts/lib/contracts.dart` and `shadow_contracts.dart`. Consumers import `shadow_contracts.dart` (see `tool_system`, `permissions`, `provider_gateway`, `agent_runtime`).
- Duplicate / conflicting types with `editing_core`:
  - `ShadowError` — `contracts/lib/src/errors/shadow_error.dart` vs `editing_core/lib/src/error/shadow_error.dart`.
  - `ApprovalToken` — `contracts/lib/src/permissions/permissions.dart` vs `permissions/lib/src/approval_token.dart` (the latter converts to/from the contract type).
  - `EditingService`, `ProjectDocument`, `EditTransaction`, `EditOutcome` — `contracts/lib/src/editing/editing_contracts.dart` (interface + `EditOperation` model) vs `editing_core` (concrete + `EditCommand` model). Field names differ: contracts uses `operations`, editing_core uses `commands`.
- **No tests** for `contracts`.

### 4.2 Agent Runtime — **Partial**

Implemented:
- `AgentController` (`agent_controller.dart`), `execution_loop.dart` (456 lines) with cancellation, budget/loop/retry detection, approval hooks.
- `DefaultPlanner`/`Planner` (`planner.dart`), `TaskScheduler` (single active + queue), `RecoveryManager`, `AgentLimits`, `AgentContext`, event model.

Gaps:
- **No LLM-backed brain.** `default_brain.dart` is `CallbackAgentBrain`, a test double; production wiring to `provider_gateway` does not exist.
- **`agent_runtime` does not import `provider_gateway`, `tool_system`, `context_engine`, or `permissions`.** Its only non-Dart dependency is `shadow_contracts`. It cannot drive a real model or a real tool executor.
- `ApprovalGate` is an `abstract interface class` (`execution_loop.dart:68`); **no production implementation**. Tests use fakes; `permissions.PermissionManager` is not wired to it.
- `AgentContext.contextHash` uses **FNV-1a 64** (`agent_context.dart`), while `context_engine.ContextSnapshot.contextHash` uses **SHA-256**. Two incompatible "context hash" definitions.

### 4.3 Provider Gateway — **Partial / Non-functional**

Implemented:
- `ProviderRouter` with capability resolution, budget enforcement, egress consent, credential resolution, timeout, and **controlled fallback** (never on 401/403; skips budget/unsupported).
- Adapters: OpenAI, Anthropic, Gemini, OpenRouter — request shaping, streaming normalization, error mapping.
- `BudgetEnforcer`, `CapabilityResolver`, `ModelSelector`, `ToolCallNormalizer`, `ProviderBudgetAccounting`, `InMemoryCredentialStore`.

Critical gaps:
- **No real `ProviderTransport`.** Only `MockProviderTransport` exists (`provider_transport.dart`). All four adapters default to it:
  - `openai_adapter.dart:17`, `anthropic_adapter.dart:17`, `gemini_adapter.dart:17`, `openrouter_adapter.dart:18`.
  - Consequence: constructing an adapter without a transport **silently performs no network I/O**. AI requests cannot succeed against any real provider.
- **Egress consent bypass:** `ProviderRouter._enforceEgressConsent` (`provider_router.dart`) collects payloads only from `request.metadata['egress_payloads']` and message metadata. If the caller embeds media/file content in `messages` without declaring `egress_payloads`, `payloads.isEmpty` → consent is **skipped** and the request proceeds.
- **Default credential store is in-memory** (`InMemoryCredentialStore`); keys are lost on restart. No OS keyring implementation.
- **Egress consent implementations are test-only:** `DenyAllEgressConsentService` / `AllowAllEgressConsentService`. The `permissions.InMemoryAiEgressConsentManager` is a separate, incompatible interface and **ignores the `ttl` parameter** (never expires, never persists).
- No tests for transport timeouts/stream aborts at the network layer (mock only).

### 4.4 Context Engine — **Partial / Unconsumed**

Implemented: `ContextSnapshot` (SHA-256 hash, token budget fields), `ContextBuilder`, `ContextTrimmer`, `MemoryManager`, `ContextManager`.

Gaps:
- **No tests.** `dart test` in `context_engine` prints usage (no `test/` dir).
- **Not consumed by `agent_runtime` or desktop.** The agent loop does not build snapshots.
- Two context-hash definitions (FNV-1a vs SHA-256) — see §4.2.
- `memory_manager.dart` imports `local_storage`, and `local_storage` depends on `agent_runtime` → circular-ish layering at the package graph level (§7).

### 4.5 Tool System — **Partial**

Implemented:
- `ToolRegistry`, `ToolExecutor` (permission → path validation → execution → result limiting → audit), `ToolSchemaValidator` (closed-schema subset), `WorkspacePathValidator`, `AuditEvent`.
- 10 built-in tools: `get_system_info`, `inspect_capabilities`, `list_files`, `scan_media`, `get_metadata`, `create_project`, `open_project`, `save_project`, `add_clip`, `trim_clip`.

Gaps (against spec §7.3, 27 v1 tools):
- Missing 17 tools: `analyze_video`, `extract_keyframes`, `detect_scenes`, `split_clip`, `move_clip`, `remove_clip`, `add_effect`, `remove_effect`, `add_transition`, `extract_audio`, `mix_audio`, `normalize_audio`, `add_text`, `generate_subtitles`, `render_preview`, `get_preview`, `render_video`, `export_project`.
- `ToolRegistry._validateToolDefinition` has **dead code**: the closed-schema `additionalProperties` check is an empty `if` body (`tool_registry.dart:36-39`), so registration does not enforce it.
- `ToolExecutor` **never validates the tool output schema** — only input. Result is passed through `_limitResult` (truncation/drop).
- Path-argument key set (`tool_executor.dart:141`) omits asset/media keys such as `assetPath`, `asset_path`, `source_path`, `output_path`; tools that use those keys bypass workspace validation.
- `list_files` uses `Directory(rel)` (`builtin_tools.dart:99`), so a relative `path` resolves against the **process CWD**, not the workspace root, and is then rejected by the workspace validator when CWD differs from the workspace. Semantics are inconsistent with the schema.

### 4.6 Permission & Safety — **Partial**

Implemented:
- `PermissionPolicy`, `PermissionManager` (approval request → single-use token bound to tool+args hash, TTL, used-token set), `PathValidator` (lexical + symlink + nearest-ancestor resolution), `WorkspaceGuard`, `AppendOnlyAuditLogger` (JSONL, flush), `InMemoryAiEgressConsentManager`.

Gaps:
- **Not wired into the app.** Desktop depends on none of these packages.
- **Duplicate `ApprovalToken`** (contracts vs permissions) with manual conversion.
- **Duplicate path validators:** `permissions/lib/src/path_validator.dart` vs `tool_system/lib/src/workspace_path_validator.dart` — different algorithms, different error types (`PathSecurityException` vs `ToolPathException`), different normalization. The tool system uses the weaker one.
- `InMemoryAiEgressConsentManager.grantConsent` ignores `ttl`; no persistence; no UI.
- Audit log is append-only but **not tamper-evident** (no hash chain/signature) and there is no rotation/retention policy.

### 4.7 Editing Core — **Complete (strongest module)**

Implemented:
- Immutable `ProjectDocument`, tracks/clips/assets/effects/transitions/text layers, `TimeTicks`, `RangeTicks`.
- `DefaultEditingService`: atomic `EditTransaction`, invariant validation (`EDIT_INVALID_OPERATION`), optimistic concurrency (`EDIT_REVISION_MISMATCH`), full undo/redo symmetry, monotonic revision, `resolveGraph` producing `RenderGraph`.
- `UuidV7` generation/validation, `RenderGraph` models, `SchemaMigrations`-aware persistence.

Evidence: `editing_service.dart`, `default_editing_service.dart` (650+ lines), `commands/`, `invariants/`, `resolve_graph_test.dart`, `golden_media_spike_test.dart`.

Caveats:
- `editing_core` depends on `local_storage` (`default_editing_service.dart:5`), and `local_storage` depends on `agent_runtime`. This inverts the intended layering (Editing Core should not know about persistence/agent packages).
- `saveTo` passes **all accumulated `_committedOps`** to `writeProject` on every save (`default_editing_service.dart:385`), and `SqliteProjectFile.writeProject` blindly `INSERT`s them (`sqlite_project_file.dart:57-77`) → **edit_ops table grows with duplicates on every save**.
- `_fsyncDirectory` in `atomic_saver.dart` is a **no-op** (comment admits Dart exposes no directory fsync). Durability against power loss is weaker than the doc claims.

### 4.8 Native Media Engine — **Missing (as an engine) / Partial (as tooling)**

Implemented in Dart:
- `FfmpegMediaWorker`: probe (ffprobe), proxy encode, thumbnail, waveform — via **FFmpeg CLI subprocess**.
- `MediaLibraryService`, `Blake3` hashing, media registry, `FakeMediaWorker` for tests.

Missing:
- **No render/export implementation in Dart.** `media_core` exports no RenderGraph executor; `render_video`/`export_project` tools do not exist.
- **No C ABI / separate worker process** (V2-D2). Everything is in-process CLI calls.
- The only real renderer is **`tools/media-spike/` (Python)**. It proves the contract is renderable and deterministic, but it is not ported to the product.
- No preview frame pipeline (decode → texture), no GPU path, no caching layer.

### 4.9 Local Persistence — **Partial**

Implemented:
- `.ssproj` as SQLite source of truth, atomic `.part` → fsync(file) → rename, integrity check, forward-only migrations, project index DB, checkpoint store, session/task memory repos, process-kill tests.

Gaps:
- Directory fsync is a no-op (§4.7).
- Duplicate `edit_ops` insertion on save (§4.7).
- **Two migration systems:** `local_database.dart` (`_migration1`, `applied_at INTEGER`) and `schema_migrations.dart` (`applied_at TEXT`). They are independent and can drift.
- `local_storage` depends on `agent_runtime` only for `checkpoint_store.dart` → layering violation.
- Index DB is described as rebuildable, but there is no automatic rebuild/repair path exercised in tests.

### 4.10 Environment Adapter — **Missing**

Spec §12 defines an environment adapter (capabilities, tools, paths, FFmpeg discovery, OS integration). There is `inspect_capabilities` / `get_system_info` tooling, but **no dedicated environment package/adapter** and no capability negotiation surface for the agent.

### 4.11 Desktop Shell / UI — **Partial**

Implemented (real Flutter):
- `ShadowStudioApp`, `AppShell` (RTL, responsive, resizable panels), `TopBar`, `StatusBar`, `MediaBinPanel`, `PreviewPanel`, `TimelinePanel` (+ ruler, toolbar, track header/lane, clip, playhead), `InspectorPanel` (+ transform/text), `ExportDialog`, `ImportDialog`, `timecode_formatter`, theme system (`src/theme/*`).
- `EditorController`: playhead/zoom/tool mode/selection/layout presets, add asset, split, delete, trim, undo/redo, save.
- 5 test files; `flutter analyze` clean.

Gaps (UI vs spec):
- **Preview is a mock:** `preview_canvas.dart` draws an icon + clip label + timecode; no decoded frames, no scrub-accurate rendering, no frame-delay indicator.
- **Export is simulated:** `export_dialog.dart` runs a `Timer.periodic` progress bar and calls `resolveGraph` only for pre-flight. **No encoder, no output file, no queue, no ETA, no cancellation of real work.**
- **No AI surfaces:** no chat panel, no plan/step view, no approval dialog, no AI proposal review (§8.4), no settings/egress consent UI (§8.5). `app_shell.dart` contains only media/preview/timeline/inspector.
- **Theme duplication:** `apps/desktop/lib/src/theme/*` (used) vs `apps/desktop/lib/ui/core/theme/*` (unused; `buildShadowTheme`/`ShadowTokens` referenced nowhere outside that folder).
- **Keyboard map / timeline interactions** are implemented but not fully verified against spec §5.8 (e.g., snap, ripple, marquee, join) — the HTML prototype covers more than the Flutter app.
- Desktop `pubspec.yaml` depends only on `editing_core`, `local_storage`, `media_core` — **no agent/provider/tool/permission/context dependencies**.

---

## 5. End-to-end capability assessment

| Capability | Works today? | Evidence / gap |
|---|---|---|
| Create/open a project | **Yes (in-memory + save)** | `DefaultEditingService`, `saveTo`; app seeds a demo doc |
| Import media | **Yes** | `MediaLibraryService` + FFmpeg probe |
| Edit timeline (split/trim/delete/undo) | **Yes** | `EditorController` + `editing_core` |
| Persist `.ssproj` | **Yes, with caveats** | SQLite + atomic save; duplicate ops, no dir fsync |
| Resolve RenderGraph | **Yes** | `resolveGraph` + tests + Python spike |
| Preview frames | **No** | mock canvas |
| Render/export video | **No (Dart) / Yes (Python spike)** | timer simulation; spike is separate |
| Call an AI provider | **No** | no HTTP transport; adapters default to mock |
| Run an agent tool loop | **No (tests only)** | no LLM brain, no wiring |
| Enforce permissions/approvals | **Library only** | `PermissionManager` not used by app |
| AI chat / review UI | **No** | absent |
| Audit/observability | **Library only** | `AppendOnlyAuditLogger`, not wired |
| Settings / egress consent UI | **No** | absent |

---

## 6. Spec compliance (v2.0 decisions)

| ID | Requirement | Status | Note |
|---|---|---|---|
| V2-D1 | No backend/HTTP server | **Met** | local-only; no server |
| V2-D2 | Heavy work in separate worker | **Not met** | FFmpeg CLI in-process; no worker/C ABI |
| V2-D3 | Tools are the only capability surface | **Partial** | tool system exists but not wired; 10/27 tools |
| V2-D4 | Reproducible context snapshot | **Partial** | `ContextSnapshot` exists; unused; hash mismatch with runtime |
| V2-D5 | Limits enforced in engine, not model | **Met** | `AgentLimits`, `BudgetEnforcer`, loop detector |
| V2-D6 | No silent retry on rejected key | **Met** | `ProviderRouter` rethrows auth; `_canFallback` excludes auth |
| V2-D7 | Tools mutate document only via Commands | **Partial** | `editing_core` enforces; tool adapters not connected |
| V2-D8 | Three risk classes, not five | **Unverified** | `ToolRiskLevel` present; policy mapping not audited |
| V2-D9 | Atomic save always | **Partial** | file atomicity yes; directory fsync no-op |
| V2-D10 | Export must validate first 3 frames | **Not met** | no export pipeline; spike has verification, not ported |
| V2-D11 | Project file is source, DB is index | **Partial** | `.ssproj` source; index rebuild path untested |

---

## 7. Dependency and layering map

Intended (spec §2.2): `contracts` ← everything; `editing_core`, `media_core`, `local_storage` independent; `agent_runtime` uses contracts; `provider_gateway`, `tool_system`, `permissions`, `context_engine` are ports/adapters.

Actual imports:

```
desktop ──► editing_core, local_storage, media_core        (no AI stack)
editing_core ──► local_storage ──► agent_runtime ──► contracts
local_storage ──► agent_runtime            (checkpoint_store.dart:3)
context_engine ──► local_storage           (memory_manager.dart:1)
agent_runtime ──► contracts only
provider_gateway ──► contracts only
tool_system ──► contracts only
permissions ──► contracts only
```

Violations:
1. **`local_storage` → `agent_runtime`** (checkpoint store) — persistence should not depend on the agent.
2. **`editing_core` → `local_storage`** — the pure editing port should not depend on storage.
3. **`context_engine` → `local_storage`** while `local_storage` → `agent_runtime` — creates a package-level cycle risk.
4. **Contracts duplication** forces adapters to convert between types (`permissions/approval_token.dart`), adding drift surface.

---

## 8. Working tree state

`git status` shows uncommitted changes (pre-existing, not from this audit):

- Modified: `context_engine` trimmer/memory_manager, `provider_gateway` adapters/router/exceptions, `permissions` barrel, `tool_system` audit/builtin/schema/tests, `agent_runtime` tests, `editing_core` golden test, `apps/desktop/analysis_options.yaml`.
- Deleted: `apps/desktop/pubspec.lock`.
- Untracked/modified: `.dart_tool` artifacts, `packages/contracts/.dart_tool/*`.
- `apps/desktop/analysis_options.yaml` now excludes `windows/**` (Windows runner present but unanalyzed).

**Risk:** the tree is not clean; any audit conclusion is against a dirty state. Recommend committing or stashing before implementation work.

---

## 9. Risk register (top 10)

| # | Risk | Severity | Evidence |
|---|---|---|---|
| R1 | AI features cannot function at all (no HTTP transport) | **Critical** | `provider_transport.dart`; adapters default to mock |
| R2 | Agent runtime cannot use provider/tools/permissions | **Critical** | `agent_runtime` imports only contracts |
| R3 | Desktop app does not depend on AI stack | **Critical** | `apps/desktop/pubspec.yaml` |
| R4 | Preview/export are simulated; no render engine in Dart | **High** | `preview_canvas.dart`, `export_dialog.dart`, `media_core` |
| R5 | Egress consent bypass when payload metadata omitted | **High** | `provider_router.dart` `_enforceEgressConsent` |
| R6 | Duplicate types (ShadowError/ApprovalToken/EditingService) | **High** | contracts vs editing_core/permissions |
| R7 | `edit_ops` duplicate growth on every save | **Medium-High** | `default_editing_service.dart:385`, `sqlite_project_file.dart` |
| R8 | Directory fsync no-op; weaker durability than documented | **Medium** | `atomic_saver.dart:120+` |
| R9 | No tests for `contracts` and `context_engine` | **Medium** | missing `test/` dirs |
| R10 | 17/27 tools missing; registry dead code; output schema unvalidated | **Medium** | `builtin_tools.dart`, `tool_registry.dart:36-39` |

---

## 10. Definition of "done" per capability

A capability is **done** only when:

1. It is reachable from `apps/desktop` (declared dependency + UI/wiring).
2. It has a real implementation (not mock/simulated) and a test that exercises the real path.
3. It has an integration test at the app boundary.
4. It satisfies the relevant spec decision (V2-D*) and error codes.
5. `dart analyze`, `flutter analyze`, and all tests pass.

By this definition, only **editing + persistence + media ingestion** approach "done"; **preview, export, AI, permissions, agent, context, and 17 tools are not done**.

---

## 11. Recommended next steps (summary)

Full detail in `docs/audit/IMPLEMENTATION_MATRIX.md`, `SECURITY_AUDIT.md`, `TECHNICAL_DEBT.md`.

1. **Unblock the AI spine:** real `ProviderTransport` (HTTP/SSE), LLM-backed `AgentBrain`, production `ApprovalGate`, and wire `agent_runtime` ↔ `provider_gateway` ↔ `tool_system` ↔ `permissions`.
2. **Make desktop depend on the AI stack** and add chat/plan/approval UI.
3. **Replace simulated preview/export** with a real RenderGraph executor (port the Python spike) and frame-accurate preview.
4. **De-duplicate contracts** (single `ShadowError`, `ApprovalToken`, editing types) and remove the dead theme tree.
5. **Fix persistence defects** (no duplicate ops, real dir fsync or documented limitation, single migration system).
6. **Close tool gaps** (17 tools, closed-schema registration, output validation, full path-key coverage).
7. **Add missing tests** (`contracts`, `context_engine`) and app-boundary integration tests.