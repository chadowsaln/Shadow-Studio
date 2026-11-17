# Shadow Studio — Technical Debt Register

**Purpose:** Inventory of structural debt, duplication, dead code, and correctness risks that will slow or destabilize future work.
**Method:** Cross-file inspection, dependency analysis, test inventory, and targeted probes.
**Severity:** Blocker / High / Medium / Low. **Effort:** S (<1d), M (1–3d), L (>3d).

---

## 1. Summary

| Category | Items | Highest severity |
|---|---|---|
| Duplication | 5 | High |
| Dead / unused code | 3 | Medium |
| Correctness defects | 5 | High |
| Dependency/layering | 4 | High |
| Test gaps | 4 | Medium |
| Tooling/build | 3 | Medium |
| Documentation drift | 3 | Medium |

The debt is concentrated in the **seams between packages**, not inside any single package. `editing_core` and `local_storage` are individually strong; the cost comes from duplicated contracts, inverted dependencies, and an AI stack that is not connected.

---

## 2. Duplication

### D-01 — Two `ShadowError` types — **High** (S)

- `packages/contracts/lib/src/errors/shadow_error.dart`
- `packages/editing_core/lib/src/error/shadow_error.dart`

Two error models with the same name and overlapping codes. Consumers must know which package threw. Error handling at boundaries is guesswork.

**Fix:** Keep one `ShadowError` (contracts), make `editing_core` re-export/convert, delete the duplicate.

---

### D-02 — Two `ApprovalToken` types — **High** (S)

- `contracts/lib/src/permissions/permissions.dart:3`
- `permissions/lib/src/approval_token.dart:6`

Manual conversion (`toContractToken`/`fromContract`) is a drift hazard for a security-critical type.

**Fix:** Single type in contracts; `permissions` re-exports.

---

### D-03 — Two editing contracts (`EditingService`, `ProjectDocument`, `EditTransaction`, `EditOutcome`) — **High** (M)

- `contracts/lib/src/editing/editing_contracts.dart` — interface + `EditOperation` (`operations` field)
- `editing_core` — concrete + `EditCommand` (`commands` field)

The field name differs (`operations` vs `commands`), and the interfaces are structurally incompatible. Any code targeting the contract cannot consume `editing_core` without an adapter.

**Fix:** Decide the canonical model (editing_core is richer). Either move it into `contracts` or delete the contracts variant and have the interface depend on editing_core's types.

---

### D-04 — Two path validators — **High** (M)

- `permissions/lib/src/path_validator.dart` (canonical)
- `tool_system/lib/src/workspace_path_validator.dart` (weaker duplicate)

Different algorithms, error types, and normalization. The tool system uses the weaker one. See S-03.

**Fix:** Delete the tool_system copy; depend on `permissions`.

---

### D-05 — Two theme systems in the desktop app — **Medium** (S)

- `apps/desktop/lib/src/theme/{shadow_colors,shadow_theme,shadow_typography}.dart` — **used**
- `apps/desktop/lib/ui/core/theme/{app_theme,tokens}.dart` — **unused** (`buildShadowTheme`, `ShadowTokens` referenced nowhere outside that folder)

Dead code that will confuse contributors and drift from the live theme.

**Fix:** Delete `ui/core/theme/` or migrate to it and delete `src/theme/`. One system.

---

## 3. Dead / unused code

### D-06 — `ToolRegistry._validateToolDefinition` closed-schema branch is empty — **Medium** (S)

`packages/tool_system/lib/src/tool_registry.dart:36-39`:

```dart
if (schema['additionalProperties'] != false) {
  // allow explicit false only for MVP safety; treat missing as invalid
  // but be tolerant if properties absent? spec says reject additional JSON properties
}
```

An `if` with only comments. Registration does not enforce closed schemas.

**Fix:** Either enforce (`throw`) or remove the branch and document the decision.

---

### D-07 — `_fsyncDirectory` is a no-op — **Medium** (M)

`packages/local_storage/lib/src/service/atomic_saver.dart` (~line 120):

```dart
// Standard Dart FileSystemEntity does not expose directory fsync,
// but calling sync on disk caches is done at the OS level.
```

The comment claims durability that the code does not provide. On power loss, the rename may not be durable.

**Fix:** Use `package:posix`/`dart:ffi` `fsync` on a directory fd, or downgrade the documentation to "file-fsync + atomic rename, directory entry not guaranteed" and adjust the spec claim.

---

### D-08 — Two theme barrels / unused exports — **Low** (S)

`contracts` exposes both `contracts.dart` and `shadow_contracts.dart`; consumers use `shadow_contracts.dart`. The unused barrel invites accidental divergence.

**Fix:** Keep one barrel; delete or alias the other.

---

## 4. Correctness defects

### D-09 — `edit_ops` duplicates on every save — **High** (M)

`DefaultEditingService.saveTo` passes `ops: _committedOps` (all ops ever committed) to `saveProjectFile` (`default_editing_service.dart:385`), and `SqliteProjectFile.writeProject` inserts every row unconditionally (`sqlite_project_file.dart:57-77`).

**Impact:** After N saves, the ops table contains O(N²) rows; history replay/undo and file size grow without bound; reopening may replay duplicates.

**Fix:** Insert only ops since the last persisted revision, or `INSERT ... ON CONFLICT DO NOTHING` keyed by `(project_id, seq)`, or rewrite the file from the current document and a compacted op log. Add a test: save 3 times → ops count equals unique ops.

---

### D-10 — Two migration systems — **Medium** (M)

- `local_storage/lib/src/local_database.dart` — `_migration1`, `applied_at INTEGER`
- `local_storage/lib/src/database/schema_migrations.dart` — `applied_at TEXT`, `currentVersion`

Independent version tables with different schemas. They can disagree about the current version.

**Fix:** One migration framework and one `schema_migrations` table. Remove `_migration1`.

---

### D-11 — Context hash inconsistency — **Medium** (S)

- `agent_runtime/lib/src/agent_context.dart` — FNV-1a 64
- `context_engine/lib/src/context_snapshot.dart` — SHA-256

Spec V2-D4 requires a reproducible `context_hash`; two definitions make cross-checking impossible.

**Fix:** One canonical hash function (SHA-256), one serialization, one test vector shared by both packages.

---

### D-12 — `UuidV7.ensureValid` uses `hashCode` + stale timestamp — **Medium** (S)

`editing_core/lib/src/uuid/uuid_v7.dart:20-31`. See S-09.

**Fix:** Stable hash (BLAKE3/SHA-256) and a current/seeded timestamp; pin with a golden test.

---

### D-13 — `local_storage` depends on `agent_runtime` — **High** (M)

`local_storage/lib/src/checkpoint_store.dart:3` imports `shadow_agent_runtime`, and `local_storage/pubspec.yaml` declares it.

**Impact:** Persistence cannot be used without pulling in the agent; creates a layering inversion and a package-graph cycle risk (`editing_core` → `local_storage` → `agent_runtime`; `context_engine` → `local_storage`).

**Fix:** Move the checkpoint types into `contracts`; `agent_runtime` depends on `local_storage`/`contracts`, not the reverse.

---

### D-14 — `editing_core` depends on `local_storage` — **High** (M)

`default_editing_service.dart:5` imports `package:local_storage/local_storage.dart` for `ProjectFileStorage`/`StoredEditOp`.

**Impact:** The pure editing port is coupled to persistence; unit testing requires SQLite; the dependency graph inverts the spec's intent.

**Fix:** Define a `ProjectStore` port in `editing_core` (or contracts); provide the SQLite adapter in `local_storage`; inject it.

---

## 5. Dependency / layering debt

### D-15 — Non-workspace packages — **Medium** (S)

`agent_runtime`, `context_engine`, `contracts`, `permissions`, `provider_gateway`, `tool_system` are **not** in the root `workspace:` list, yet are consumed via `path:`.

**Impact:** Inconsistent resolution, duplicated lockfiles, `dart pub get` behaviour differs per package, CI coverage gaps.

**Fix:** Add all packages to the workspace and use `workspace:` resolution.

---

### D-16 — SDK constraint mismatch — **Medium** (S)

- Workspace packages: `sdk: ^3.6.0`
- Non-workspace packages: `sdk: ^3.9.0`
- `provider_router.dart` uses `?primaryId` (null-aware element), which requires a newer SDK.

**Impact:** A contributor on 3.6–3.8 cannot build the AI packages; CI may silently use different SDKs.

**Fix:** Standardize on one SDK constraint (3.9+) across all packages and document the toolchain.

---

### D-17 — Desktop does not depend on the AI stack — **High** (M)

`apps/desktop/pubspec.yaml` lists only `editing_core`, `local_storage`, `media_core`.

**Impact:** The product's headline features (AI, tools, permissions, agent) are unreachable from the app; integration work is invisible to app-level tests.

**Fix:** Add the packages (once stable) and add an app-boundary integration test.

---

## 6. Test gaps

### D-18 — No tests for `contracts` — **Medium** (S)

No `test/` directory; `dart test` prints usage.

**Fix:** Add serialization/hash/error-code tests.

### D-19 — No tests for `context_engine` — **Medium** (M)

No `test/` directory. Hash, trimming, and budget behaviour are unverified.

**Fix:** Add snapshot/hash/truncation tests with golden vectors.

### D-20 — No app-boundary integration tests — **High** (L)

Desktop tests are unit/widget only (`editor_controller_test`, `theme_test`, `timecode_formatter_test`, `timeline_interaction_test`, `widget_test`). There is no test that imports media → edits → saves → reopens through the app.

**Fix:** Add an integration test using a temp workspace and a fake/real FFmpeg worker.

### D-21 — Provider tests use mocks only — **Medium** (M)

No HTTP/SSE transport exists, so network error mapping, TLS, and timeouts are untested.

**Fix:** Add transport tests with recorded fixtures; add a real-transport test behind an env flag.

---

## 7. Tooling / build

### D-22 — Dirty working tree — **Medium** (S)

Uncommitted changes across 7 packages plus deleted `apps/desktop/pubspec.lock` and `.dart_tool` noise. `windows/**` is excluded from analysis but a Windows runner exists.

**Fix:** Commit or stash; add `.gitignore` entries for `.dart_tool`; decide on Windows support and analyze it.

### D-23 — Generated artifacts tracked — **Low** (S)

`.dart_tool/` and kernel snapshots appear in `git status`. They should not be tracked.

**Fix:** Ignore and untrack.

### D-24 — Python spike and JS prototype are outside the build — **Low** (S)

`tools/media-spike/` and `prototype/ux-p1/` are not part of CI or the Dart build. The spike contains a local `.venv` (untracked) and encodes real decisions (RenderGraph mapping, UX states) that can silently rot.

**Fix:** Add a CI job for the spike (at least `test_refusals.py`), document the `.venv` as non-portable, and treat the prototype as a design artifact with an owner.

---

## 8. Documentation drift

### D-25 — "Atomic save" overstates durability — **Medium** (S)

Docs/spec claim `.part → fsync → rename`; directory fsync is a no-op (D-07). Either implement it or correct the claim in `local_storage.dart` and the spec.

### D-26 — "Context snapshot" claim vs unused implementation — **Medium** (S)

V2-D4 is described as binding, but `ContextSnapshot` is not consumed and its hash differs from the runtime's (D-11).

### D-27 — "27 tools" claim vs 10 implemented — **High** (M)

Spec §7.3 lists 27 v1 tools; 10 exist. The gap is not reflected in the README or any status doc.

**Fix:** Add a tool-coverage table to the repo (this audit's matrix is a starting point) and update it per PR.

---

## 9. Prioritized remediation plan

### Now (blockers)
1. D-09 duplicate ops — data growth/corruption risk.
2. D-13/D-14 layering inversions — block all AI wiring.
3. D-03/D-01/D-02 duplicate contracts — cause integration defects.
4. D-20 app-boundary tests — no safety net for the above.

### Next (high)
5. D-04 unify path validators.
6. D-17 desktop dependency on AI stack.
7. D-21 real transport + tests.
8. D-11/D-12 stable hashes and UUIDs.

### Then (medium)
9. D-10 unify migrations; D-07 fsync or doc fix.
10. D-15/D-16 workspace + SDK standardization.
11. D-18/D-19 missing package tests.
12. D-22/D-23 clean tree and ignores.

### Finally (low)
13. D-05/D-08 dead theme and barrels.
14. D-24 CI for spike/prototype.
15. D-25/D-26/D-27 doc corrections.

---

## 10. Debt-to-risk mapping

| Debt | Blocks | Risk if ignored |
|---|---|---|
| D-01/02/03 | AI + tool integration | Silent conversion bugs, security drift |
| D-04 | Safe tool execution | Path escape |
| D-09 | Persistence/replay | Unbounded files, wrong history |
| D-13/14/17 | Everything AI | AI remains unreachable |
| D-15/16 | CI/DevEx | Non-reproducible builds |
| D-18/19/20 | Refactoring safety | Regressions |
| D-25/26/27 | Trust | False claims in docs |
---

## 11. Resolution log (D2/D3 implementation, 2026-11-17)

| Debt | Status | Evidence |
|---|---|---|
| D-06 `ToolRegistry` closed-schema validation was empty | **Resolved** | `ToolRegistry` now calls `ToolContractValidator.validateDefinition` and throws a structured `toolSchemaInvalid` error; covered by `tool_system` tests |
| D-13 `local_storage` depends on `agent_runtime` | **Resolved** | Dependency removed from `packages/local_storage/pubspec.yaml`; `SqliteCheckpointStore` imports only `shadow_contracts` |
| D-10 two migration systems | **Scoped** | Index DB migrations (`LocalDatabase`, `_migration1`/`_migration2`) and per-file project migrations (`SchemaMigrations`) remain intentionally separate: they version different databases (`shadow.sqlite` vs `*.ssproj`). The v2 index migration is transactional and covered by `storage_data_model_test.dart`. |
| D-01/D-02/D-03 duplicated contract types | **Open** | D3 created the canonical contracts in `packages/contracts`; `agent_runtime` now re-exports them, but `editing_core`/`provider_gateway` duplicates remain |
| D-04 duplicate path validators | **Open** | `tool_system/lib/src/workspace_path_validator.dart` still exists |

New coverage added by D2/D3: `packages/contracts/test/agent_plan_test.dart`,
`packages/contracts/test/tool_contracts_test.dart`,
`packages/local_storage/test/storage_data_model_test.dart`.
