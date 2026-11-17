# Shadow Studio — Security Audit

**Scope:** Static security review of the Dart/Flutter codebase and its auxiliary tooling, against the local-first, AI-assisted desktop video editor threat model in `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md`.
**Method:** Source inspection of all security-relevant paths (providers, tools, permissions, paths, persistence, credentials, audit), plus targeted probes.
**No exploitation performed.** Findings are based on code reading and controlled local probes.

---

## 1. Threat model

Shadow Studio is a **local-first desktop app** with these assets and boundaries:

| Asset | Boundary |
|---|---|
| User's media files | Local filesystem, outside the app |
| Project files (`.ssproj`) | Local filesystem; may contain absolute paths |
| AI provider API keys | OS keyring (required by spec) |
| Media/file content | Must not leave the device without explicit consent |
| Tool execution | Filesystem + process (FFmpeg) |
| Model output | Untrusted: tool calls, file paths, proposed edits |

Primary threats:

1. **Path traversal / symlink escape** — model or tool arguments escape the workspace.
2. **Unconsented data egress** — media/files sent to a cloud provider without explicit consent.
3. **Credential leakage** — keys written to disk, logs, project files, or error messages.
4. **Unauthorized destructive actions** — edits/exports/deletes without approval.
5. **Audit evasion** — actions not logged or logs tamperable.
6. **Supply-chain / process abuse** — FFmpeg or shell invocation with attacker-controlled arguments.
7. **Untrusted model output driving the UI** — XSS-like injection into Flutter widgets (lower risk; Flutter is not HTML).

---

## 2. Findings summary

| ID | Severity | Title |
|---|---|---|
| S-01 | **High** | Egress consent can be bypassed by omitting payload metadata |
| S-02 | **High** | Desktop app bypasses permission/approval/path-safety entirely |
| S-03 | **High** | Duplicate path validators; tool system uses the weaker one; incomplete path-key coverage |
| S-04 | **Medium-High** | No real HTTP transport; adapters silently fall back to mock (fail-safe, but masks misconfiguration) |
| S-05 | **Medium** | `ApprovalToken` duplication and manual conversion (drift risk) |
| S-06 | **Medium** | Consent manager ignores TTL and is non-persistent |
| S-07 | **Medium** | Audit log is append-only but not tamper-evident; no rotation/retention |
| S-08 | **Medium** | Tool output schema is never validated; result truncation can drop data |
| S-09 | **Medium** | `UuidV7.ensureValid` derives IDs from `String.hashCode` and a hard-coded 2025 timestamp |
| S-10 | **Low-Medium** | TOCTOU between path validation and use; no openat-style safety |
| S-11 | **Low-Medium** | Credential store defaults to in-memory; no OS keyring implementation |
| S-12 | **Low** | Tool exceptions are collapsed to a generic message (good for confidentiality, bad for diagnosis) |
| S-13 | **Low** | `list_files` relative-path handling rejects legitimate inputs and has inconsistent semantics |
| S-14 | **Low** | Project files contain absolute paths; no encryption at rest (expected, but must be documented) |

---

## 3. Detailed findings

### S-01 — Egress consent bypass via missing payload metadata — **High**

**Evidence:** `packages/provider_gateway/lib/src/provider_router.dart`, `_enforceEgressConsent`:

```dart
collectMeta(request.metadata);
for (final m in request.messages) {
  collectMeta(m.metadata);
}
if (payloads.isEmpty) return;   // <-- consent skipped
```

**Issue:** Consent is derived only from `request.metadata['egress_payloads']` and per-message metadata. If a caller (or a future agent/tool) places file contents, base64 media, or paths into `messages` without declaring `egress_payloads`, the router treats the request as payload-free and proceeds.

**Impact:** Silent exfiltration of user media to a cloud provider, violating the explicit-consent requirement (spec §8 / V2-D*).

**Fix:**
- Make payload declaration **mandatory** for any request that includes non-text content or file references; reject otherwise.
- Derive payloads from message content types, not only metadata.
- Default `DenyAll` and require an explicit `requestConsent` result; never auto-grant.
- Add a test: message with `image_url`/`file` content and no metadata must be denied.

---

### S-02 — Desktop app bypasses the entire safety stack — **High**

**Evidence:** `apps/desktop/pubspec.yaml` dependencies are only `editing_core`, `local_storage`, `media_core`. `app_shell.dart` contains no permission/approval surfaces. `EditorController` calls `EditingService` directly.

**Issue:** All permission checks, approvals, path validation, and audit logging live in packages the app does not depend on. User-initiated destructive operations (delete clip, overwrite project, export over an existing file) have **no approval or audit trail**.

**Impact:** The safety model is decorative until the AI stack is wired. Any future tool integration must not repeat this mistake.

**Fix:**
- Add the AI/safety stack as app dependencies and route **all** capability use (AI tools and destructive UI actions) through `ToolExecutor`/`PermissionManager`.
- Add an approval dialog and an audit sink at app startup.
- Add an app-level test that a destructive action without approval is blocked.

---

### S-03 — Duplicate path validators + incomplete path-key coverage — **High**

**Evidence:**
- `packages/permissions/lib/src/path_validator.dart` — canonical, symlink-aware, nearest-existing-ancestor resolution, `PathSecurityException`.
- `packages/tool_system/lib/src/workspace_path_validator.dart` — separate implementation, `ToolPathException`, normalizes `\` to `/`.
- `tool_executor.dart:141` path-key set: `path, file_path, filePath, project_path, projectPath, media_path, mediaPath, directory, dir`.

**Issues:**
1. Two algorithms → drift; the tool system uses the **weaker** one.
2. `tool_executor` does not validate keys such as `assetPath`, `asset_path`, `source_path`, `output_path`, `target_path`. A tool accepting `assetPath` can bypass workspace validation.
3. `mustExist: false` is always passed; non-existent targets resolve against the nearest existing ancestor, but the check is easy to misconfigure.
4. `WorkspacePathValidator._normalize` converts backslashes to `/`, which can mis-handle POSIX filenames containing `\`.

**Impact:** Path traversal/symlink escape via an unvalidated key.

**Fix:**
- Delete `workspace_path_validator.dart`; make `tool_system` depend on `permissions.PathValidator`.
- Replace the allow-list with a **deny-by-default** rule: any argument name matching `*path*`, `*dir*`, `*file*`, or `*uri*` (file scheme) is validated.
- Validate relative paths against the workspace root consistently (reject or resolve explicitly).
- Add adversarial tests: `../`, absolute paths, symlink loops, missing ancestors, Windows separators.

---

### S-04 — No real transport; adapters silently fall back to mock — **Medium-High**

**Evidence:** `provider_transport.dart` defines only `MockProviderTransport`; `openai_adapter.dart:17`, `anthropic_adapter.dart:17`, `gemini_adapter.dart:17`, `openrouter_adapter.dart:18` all default to it.

**Issue:** This is fail-safe (no accidental network) but **silently non-functional**. A production build could ship with no AI capability and no error. It also means all provider tests validate mock behaviour, not real HTTP/TLS/SSE handling.

**Impact:** False sense of security/coverage; no validation of TLS, header handling, SSE parsing, or error mapping against real APIs.

**Fix:**
- Add a real `ProviderTransport` (HTTP/SSE) with strict TLS, timeouts, and size caps.
- Make the transport **required** in production constructors; keep mock only in tests.
- Add contract tests against recorded fixtures and (optionally) a sandbox endpoint.

---

### S-05 — Duplicate `ApprovalToken` and manual conversion — **Medium**

**Evidence:** `contracts/lib/src/permissions/permissions.dart:3` and `permissions/lib/src/approval_token.dart:6`; conversion in `approval_token.dart:25-34` and `permission_manager.dart:202`.

**Issue:** Two types with the same meaning; manual `fromContract`/`toContractToken` is easy to get wrong (fields added on one side, forgotten on the other).

**Impact:** Approval binding could silently weaken (e.g., a new security field not carried across).

**Fix:** Single `ApprovalToken` in `contracts`; `permissions` re-exports it. Delete the duplicate.

---

### S-06 — Consent manager ignores TTL and is non-persistent — **Medium**

**Evidence:** `permissions/lib/src/permission_manager.dart`, `InMemoryAiEgressConsentManager.grantConsent(... Duration? ttl)` — `ttl` is never stored or checked; grants live in a `Set<String>` and vanish on restart.

**Issues:**
1. TTL is accepted but ignored → consent never expires.
2. In-memory only → consent is lost on restart (usability) but, more importantly, any persistence added later must enforce expiry.

**Impact:** Over-broad, non-expiring consent; inconsistent UX.

**Fix:** Store grants with `grantedAt`/`expiresAt`; check expiry on `hasConsent`; persist via `local_storage`; add tests for expiry and revocation.

---

### S-07 — Audit log not tamper-evident; no retention — **Medium**

**Evidence:** `permissions/lib/src/audit_logger.dart` — `AppendOnlyAuditLogger` appends JSONL with `flush: true`; no hash chain, no signature, no rotation.

**Issue:** "Append-only" is a convention, not a guarantee. A local attacker (or a bug) can truncate/rewrite the file. No rotation means unbounded growth.

**Fix:** Hash-chain each record (`prev_hash` + record hash), optionally sign with a device key; rotate by size/date; document retention.

---

### S-08 — Tool output schema never validated; truncation drops data — **Medium**

**Evidence:** `tool_executor.dart` validates **input** only (`_schemaValidator.validate(schema: tool.inputSchema, ...)`); results go through `_limitResult`. `ToolRegistry._validateToolDefinition` has an empty `additionalProperties` branch (`tool_registry.dart:36-39`).

**Issues:**
1. A tool can return arbitrary/unbounded structures; only byte truncation applies.
2. Closed-schema is not enforced at registration, so a tool with `additionalProperties` omitted is accepted and then accepts extra args at call time.
3. Truncation can silently drop fields the agent/UI needs.

**Fix:** Add `outputSchema` to the tool contract and validate; enforce `additionalProperties: false` at registration; return a structured "truncated" result rather than silently dropping fields.

---

### S-09 — `UuidV7.ensureValid` derives IDs from `hashCode` and a fixed timestamp — **Medium**

**Evidence:** `packages/editing_core/lib/src/uuid/uuid_v7.dart:20-31`:

```dart
final ms = (seed ?? 1763300000000) & 0xFFFFFFFFFFFF;
...
final hash = value.hashCode.abs();
```

**Issues:**
1. `1763300000000` is **2025-11-16**, so every fallback ID carries a stale timestamp, breaking UUIDv7 time-ordering.
2. `String.hashCode` is not contractually stable across Dart versions/platforms; IDs derived from it can change if the runtime changes (probe on this toolchain was stable across processes, but this is not guaranteed).
3. `ensureValid` is used for **persisted** document/track/clip IDs (`default_editing_service.dart:420-638`), so any instability silently rewrites identity.

**Fix:** Derive the fallback UUID from a **stable** hash (e.g., BLAKE3/SHA-256 of the value, already available via `media_core`'s Blake3 or `crypto`), and use the current time or a passed seed. Add a golden test that pins the mapping.

---

### S-10 — TOCTOU between validation and use — **Low-Medium**

**Evidence:** Path validation resolves and checks, then the tool opens/uses the path later. Symlinks can change in between; there is no `openat`/`O_NOFOLLOW` equivalent.

**Impact:** A local attacker with write access to the workspace could swap a path after validation. Low likelihood on a single-user desktop, but relevant for shared workspaces.

**Fix:** Document the limitation; where possible, open by file descriptor and validate the opened handle; re-validate immediately before use.

---

### S-11 — Credential store defaults to in-memory; no keyring — **Low-Medium**

**Evidence:** `provider_gateway/lib/src/credential_store.dart` — `InMemoryCredentialStore` is the default; `ProviderCredentialResolver` uses it when none is supplied.

**Issue:** No OS keyring implementation (libsecret/DPAPI/Keychain). Keys are lost on restart; if a caller supplies a file-based store, nothing prevents plaintext persistence.

**Fix:** Implement a keyring-backed `CredentialStore`; make it required in production; add a lint/test that no key material is written to project files or logs.

---

### S-12 — Tool exceptions collapsed to generic message — **Low**

**Evidence:** `tool_executor.dart` catch-all returns `'Tool execution failed'`.

**Issue:** Good for confidentiality (no internal leakage), but it discards diagnostics and makes security incident investigation hard.

**Fix:** Keep the user-facing message generic but log the full error to the audit sink with a correlation ID.

---

### S-13 — `list_files` relative-path handling — **Low**

**Evidence:** `builtin_tools.dart:99` `ListFilesTool` uses `Directory(rel)`, where `rel` defaults to `context.workspaceRoot`. A relative `path` therefore resolves against the **process CWD**, not the workspace root, and is rejected by `WorkspacePathValidator` when CWD differs.

**Issue:** Inconsistent semantics; legitimate relative inputs fail, and the failure mode may push callers to use absolute paths (which then need validation).

**Fix:** Define one rule (resolve relative to workspace root) and apply it consistently across tools.

---

### S-14 — Project files contain absolute paths; no encryption at rest — **Low**

**Evidence:** `Asset.uri` stores `imported.sourceUri`; `ProjectDocument` persists it as JSON.

**Issue:** `.ssproj` leaks local filesystem layout; not encrypted. This is expected for a local editor but should be documented, and "share project" must strip/rewrite paths.

**Fix:** Document; add a project-sanitization step for sharing/export.

---

## 4. Positive controls (verified)

| Control | Evidence |
|---|---|
| Auth failures never fall back | `provider_router.dart` `_canFallback` / `e.isAuth` rethrow |
| Budget failures never fall back | `_canFallback` excludes `providerBudgetExceeded` |
| Tool args validated against closed schema | `schema_validator.dart` (input) |
| Workspace path escape rejected | `permissions/path_validator.dart` (lexical + symlink + ancestor) |
| Approvals are single-use and bound to tool+args | `permission_manager.dart` + `approval_request.dart` |
| Approval TTL enforced | `ApprovalRequest.isExpired`, `PermissionManager` expiry checks |
| Audit records include args **hash**, not args | `approval_request.dart` `toAudit()` |
| Atomic save prevents partial files | `atomic_saver.dart` + process-kill tests |
| FFmpeg invoked via CLI arg lists (no shell string) | `ffmpeg_media_worker.dart` uses `Process.run`/`Process.start` with argument lists |
| No secrets in code | Grep found no hard-coded keys |

---

## 5. Recommendations (priority order)

1. **S-01** — make egress consent mandatory and metadata-independent.
2. **S-03** — unify path validation; validate all path-like keys.
3. **S-02** — route app capabilities through the permission/audit stack.
4. **S-09** — stable UUID derivation for persisted IDs.
5. **S-08** — output schema validation + closed-schema registration.
6. **S-04** — real transport with required-in-production wiring.
7. **S-06/S-07/S-11** — consent TTL/persistence, tamper-evident audit, keyring.
8. **S-05/S-10/S-12/S-13/S-14** — cleanup and documentation.

---

## 6. Residual risk statement

Until **S-01, S-02, S-03, and S-04** are addressed, Shadow Studio must be considered **not safe to expose to untrusted model output or third-party media**. The editing core and persistence layer are the only parts with defensible safety properties today.