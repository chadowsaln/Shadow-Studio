# Data Model and Migrations (D2)

**Status:** implemented and verified locally (2026-11-17).
**Baseline:** `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md` §11, V2-D11.
**Code:** `packages/local_storage/lib/src/local_database.dart`,
`packages/local_storage/lib/src/model/storage_models.dart`,
`packages/local_storage/lib/src/repository/storage_repositories.dart`.

## 1. Storage layout

Shadow Studio keeps two independent stores:

| Store | Format | Authority | Rebuildable |
| --- | --- | --- | --- |
| Project file (`*.ssproj`) | SQLite, atomic `.part` → fsync → rename | Source of truth for one project | No |
| App index database | SQLite (`LocalDatabase`, WAL) | Cross-project index, agent state, approvals, logs, provider config | Yes (project files are the truth) |

The index database never becomes a second source of truth for edit data: project
documents and edit operations live in `*.ssproj`. V2-D11 therefore stays intact.

## 2. Schema version 2

`LocalDatabase` is forward-only. `schema_migrations(version, applied_at)` records
every applied migration; each migration runs inside `BEGIN IMMEDIATE` and is
rolled back as a unit.

Version 1 (pre-existing) created: `session_memory`, `task_memory`,
`agent_sessions`, `agent_messages`, `agent_tasks`, `tool_executions`,
`approvals`, `execution_checkpoints`, `provider_configs`.

Version 2 adds the persistence categories required by D2:

| Table | Purpose | Key constraints |
| --- | --- | --- |
| `projects` | Registered projects (id, name, workspace root, file path, revision) | `id` PK; `updated_at` index; `workspace_root` index |
| `media_assets` | Ingested media per project (kind, path, mime, duration, dimensions, checksum, metadata) | `project_id` FK → `projects(id)` `ON DELETE CASCADE`; path + project indexes |
| `timelines` | Timeline snapshots (`tracks_json`, monotonic `revision`) | `project_id` FK cascade; `(project_id, updated_at)` index |
| `execution_logs` | Append-only structured logs (session/task/correlation) | session + task indexes; no updates by design |
| `permission_decisions` | Approval/permission decisions with expiry | task index; `(status, expires_at)` index |
| `provider_configs` | Provider/model/base URL/API-key **reference** (never the key itself) | `id` PK; `enabled` flag added forward-compatibly |

Existing tables reused as-is: `agent_sessions`, `agent_tasks`,
`tool_executions` (tool executions), `execution_checkpoints` (checkpoints),
`approvals` (pending approval state), `provider_configs` (provider
configuration). No duplicate tables were introduced for these categories.

`provider_configs.enabled` is added by a guarded `_ensureColumn` step rather
than a bare `ALTER TABLE`, so databases that predate `provider_configs` (for
example a legacy v1 index that only ever created `session_memory`) migrate
cleanly instead of failing with "no such table".

## 3. Repositories

`StorageRepositories` bundles the SQLite-backed repositories:

| Repository | Model | Operations |
| --- | --- | --- |
| `ProjectRepository` | `ProjectRecord` | `upsert`, `get`, `list`, `updateRevision`, `softDelete` (cascades), `purge` |
| `MediaAssetRepository` | `MediaAsset` | `save`, `get`, `listByProject`, `delete` |
| `TimelineRepository` | `TimelineRecord` | `save`, `get`, `listByProject`, `delete` |
| `ExecutionLogRepository` | `ExecutionLog` | `append`, `listBySession`, `listByTask`, `purgeBefore` |
| `PermissionRepository` | `PermissionDecision` | `save`, `get`, `listByTask`, `listExpired`, `resolve` |
| `AgentSessionRepository` | `AgentSessionRecord` | `save`, `get`, `list`, `updateState` |
| `AgentTaskRepository` | `AgentTaskRecord` | `save`, `get`, `listBySession`, `updateState` |
| `ToolExecutionRepository` | `ToolExecutionRecord` | `save`, `listByTask` |
| `ProviderConfigRepository` | `ProviderConfig` | `save`, `get`, `list(enabledOnly)`, `delete` |

All timestamps are stored as UTC epoch milliseconds and restored as UTC.
JSON-valued columns (`metadata`, `tracks_json`) are decoded defensively, so a
malformed row degrades to an empty map instead of crashing the read path.

## 4. Integrity, transactions, and crash safety

- `LocalDatabase.transaction<T>(action)` wraps `BEGIN IMMEDIATE` /
  `COMMIT` and rolls back on any error.
- `LocalDatabase.integrityCheck()` runs `PRAGMA integrity_check` and returns
  `true` only for the single `ok` result.
- `LocalDatabase.schemaVersion` exposes the applied migration version.
- File databases enable WAL (`journal_mode=WAL`), `synchronous=NORMAL`,
  `busy_timeout=5000`, and `foreign_keys=ON`; in-memory databases enable
  `foreign_keys=ON` for tests.
- Deletion is soft for projects (`deleted_at`) and cascades to media assets and
  timelines in the same transaction; `purge` removes rows physically.

## 5. Migration and compatibility rules

1. Migrations are append-only. Never edit an applied migration; add version N+1.
2. A migration must be a closed transaction: either every statement applies or
   none do.
3. Additive, non-breaking columns use `_ensureColumn` inside the migration so
   both fresh and legacy databases reach the same shape.
4. Repositories must not assume a column exists until the schema version that
   introduced it has been applied.
5. `local_storage` no longer depends on `shadow_agent_runtime`; checkpoint
   persistence depends only on `shadow_contracts`.

## 6. Verification

`packages/local_storage/test/storage_data_model_test.dart` covers:

- schema v2 contains every required table;
- project CRUD, revision updates, soft delete + cascade, purge;
- media asset metadata round-trip and FK rejection of unknown projects;
- timeline track JSON round-trip and per-project listing;
- execution log append/filter/age purge;
- permission decision save/resolve/expiry query;
- agent session/task/tool execution persistence;
- provider config `enabled` flags, metadata, and filtering;
- transaction rollback on failure;
- integrity check plus reopen-after-close persistence;
- forward migration from a hand-built v1 database without row loss.

Run:

```bash
cd packages/local_storage
dart test
```