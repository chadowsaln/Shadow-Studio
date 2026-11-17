# local_storage

Pure Dart persistence package for **Shadow Studio** desktop video editor.

It implements durable, crash-safe local storage for project files (`.ssproj`) and the rebuildable application project index database (`projects_index.db`).

## Principles & Hard Constraints

- **Dependency Rule (Spec §2.2)**: `local_storage` depends strictly on the standard library and SQLite (`sqlite3`). It has **zero dependency on `editing_core`**. `editing_core` depends on `local_storage`.
- **Atomic Save (Spec V2-D9)**: Always writes `<name>.part`, runs `PRAGMA integrity_check`, flushes to disk (`fsync`), flushes the directory where platform allows, and atomically renames to `<name>`. Never writes in place.
- **Source of Truth vs Index (Spec V2-D11)**: The `.ssproj` SQLite file is the authoritative source of truth containing the document snapshot and append-only operations log (`edit_ops`). The app-level index database is a rebuildable index that can be deleted and reconstructed at any time.
- **Forward-Only Schema Migrations**: Versioned schemas with migrations (`schema_migrations` table). Files with newer schema versions are rejected cleanly.
- **Spec Error Codes (§14.3)**: Uses exact codes `STORE_CORRUPT` and `STORE_DISK_FULL`.

---

## Public API Overview

### 1. Storage Models

- **`ProjectFileData`**: Canonical storage record for a project snapshot:
  - `projectId`, `name`, `schemaVersion`, `revision`, `documentJson`, `createdAt`, `updatedAt`.
- **`StoredEditOp`**: Row in the append-only `edit_ops` table:
  - `seq`, `projectId`, `revision`, `batchId`, `opType`, `payloadJson`, `inverseJson`, `origin`, `createdAt`.
- **`ProjectIndexEntry`**: Entry in the app-level index:
  - `projectId`, `name`, `filePath`, `revision`, `durationTicks`, `thumbnailUri`, `lastModifiedMs`, `createdAt`, `updatedAt`.

### 2. Services

- **`ProjectFileStorage`**:
  - `saveProjectFile(filePath, projectData, {ops, faultStage, simulateDiskFull})`: Performs atomic write via `AtomicSaver`.
  - `openProjectFile(filePath)`: Cleans leftover `.part` files, checks `PRAGMA integrity_check`, runs schema migrations forward, and loads project data + ops log.
- **`ProjectIndexDatabase`**:
  - `ProjectIndexDatabase.open(dbPath)`: Opens or creates index database.
  - `upsert(entry)` / `get(id)` / `getAll()` / `remove(id)`.
  - `rebuildFromDirectory(dir, storage)`: Rescans any directory tree for `*.ssproj` files and repopulates the index table.
- **`AtomicSaver`**:
  - Low-level atomic write utility implementing `.part` -> `fsync` -> `rename` with fault-injection hooks (`SaveFaultStage`).
- **`SchemaMigrations`**:
  - Schema version detection and forward migration executor.

---

## Running Tests & Static Analysis

```bash
# Run local_storage test suite
dart test packages/local_storage

# Run static analysis
dart analyze packages/local_storage
```
