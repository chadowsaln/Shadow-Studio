# Shadow Studio — Permission Engine & Local Security Boundaries

**Status:** Implemented in `packages/permissions` (engine) and wired into `packages/tool_system` (executor). Approval *UI* and desktop shell wiring remain separate work items.
**Scope:** every capability an autonomous agent can request: filesystem access, timeline edits, exports, AI data egress, external commands, API-key storage, audit.
**Principle:** the model is untrusted. Nothing in a model response can widen a permission, mint an approval, or change a policy.

---

## 1. Trust boundaries

| Boundary | Inside | Outside / untrusted |
|---|---|---|
| Model boundary | `PermissionPolicy`, `PermissionManager`, approval registry | tool names, tool arguments, risk declarations, plan text |
| Filesystem boundary | workspace root (existing directory) | absolute paths, `..`, symlinked parents, control chars |
| Process boundary | allowlisted media binaries (`ffmpeg`, `ffprobe`, `mediainfo`) with argv lists | shell strings, metacharacters, arbitrary executables, foreign cwd |
| Secret boundary | encrypted secret store, OS keyring (future) | logs, audit records, project files, provider errors |
| Audit boundary | append-only hash-chained log | anything derived from raw argument values |
| UI boundary | approval dialog (not yet wired) | **never** the enforcement point; checks live in the engine |

Every tool call passes through `ToolExecutor` → `PermissionService.authorizeToolCall` → `PermissionPolicy` before `AgentTool.execute` runs. Approval UI is a display layer only; bypassing it cannot bypass the engine.

---

## 2. Risk classification (LOW / MEDIUM / HIGH)

Classification is **code-owned** (`PermissionPolicy.builtinToolPolicies`) and is a **floor**: a tool that declares a lower risk cannot downscope itself. Unknown tools are `restricted` and require approval by default (fail closed).

| Class | `ToolRiskLevel` | Examples | Default effect in workspace |
|---|---|---|---|
| LOW | `safe` | `list_files`, `get_metadata`, `scan_media`, `analyze_video`, `extract_keyframes`, `render_preview` | allow |
| MEDIUM | `restricted` | `add_clip`, `trim_clip`, `split_clip`, `move_clip`, `remove_clip`, `generate_subtitles`, `create_temp_file`, `create_project`, `render_video` | allow in workspace; approval outside workspace, for declared AI spending, or when a tool is marked `requiresApprovalAlways` |
| HIGH | `dangerous` | `delete_file`, `delete_directory`, `overwrite_file`, `overwrite_media`, `replace_media`, `move_file`, `export_project`, `write_outside_workspace`, every shell/process alias | **explicit, single-use approval required** |

Additional hard rules:

- Shell-shaped tools (`run_command`, `execute_command`, `spawn_process`, `shell_exec`, `kill_process`, camelCase aliases) are always HIGH risk, even if the tool declares `safe`.
- Policy-manipulating names (`grant_permission`, `set_permission_policy`, `disable_audit`, `disable_sandbox`, `approve_self`, `bypass_approval`) are **denied unconditionally**, with or without approval.
- `PermissionPolicy(toolPolicies: …)` is the only extension mechanism; custom tools must be explicitly added or they require approval.

---

## 3. Enforcement pipeline

```
tool call args (untrusted)
  → schema validation (closed schema, additionalProperties:false)
  → shell shape check (if shell-shaped) + ShellCommandGuard
  → path validation (WorkspaceGuard → canonical PathValidator)
  → approval token validation (issued registry, binding, expiry, single-use)
  → PermissionPolicy.evaluate (risk + workspace + spending + known-tool)
  → execute (executor re-checks cancellation; path guard runs again)
  → audit (redacted, hash-chained)
```

**Fail closed:** any unexpected error during authorization returns
`PermissionDecision.deny(PERM_POLICY_DENIED)` and is audited. If the workspace root
does not exist or cannot be canonicalized, path validation fails rather than
falling back to lexical comparison.

---

## 4. Filesystem and path rules

`PathValidator` (`packages/permissions/lib/src/path_validator.dart`):

1. Workspace root must exist and be a directory (canonicalized via `resolveSymbolicLinks`).
2. Empty paths and NUL bytes are rejected.
3. Any `..` segment is rejected **lexically**, before filesystem resolution, treating both `/` and `\` as separators.
4. Relative paths resolve against the workspace root, never the process CWD.
5. Existing targets are canonicalized; symlinks are validated against their target.
6. Non-existent targets resolve through the **nearest existing ancestor**, so a symlinked parent cannot escape.
7. Containment compares canonical paths with a separator-aware prefix check (`/workspace` does not match `/workspace-evil`).

`WorkspaceGuard` applies this to tool arguments **deny-by-default**:

- argument names containing path words (`path`, `dir`, `file`, `folder`, `uri`, `source`, `target`, `destination`, `output`, `workspace`, `root`), including camelCase (`assetPath`, `outputPath`);
- any string that *looks* like a path (absolute POSIX, Windows drive/UNC, or containing `..`) under an unexpected key;
- ambiguous keys (`source`, `target`, `destination`, `output`) are treated as paths only when the value is path-shaped (separator or file extension), so identifiers such as `target: "main"` are never rewritten;
- control characters (NUL, ESC, etc.) in names or values are rejected (`PERM_INVALID_ARGUMENT`).

`ToolExecutor` performs the same validation again before calling a tool, so a caller-supplied `PermissionService` cannot weaken the executor's own defense. It then passes the **canonicalized absolute paths** (not the model-supplied strings) to the tool, so a relative argument cannot be reinterpreted against the process CWD. The caller's argument map is not mutated, keeping approval bindings and audit hashes tied to the original call.

---

## 5. Approvals

| Property | Implementation |
|---|---|
| Explicit | `requestApproval` only creates a pending request; `approve` must be called by an explicit user action |
| Unforgeable id | 128-bit `Random.secure` identifiers (`apr_…`, `atk_…`) |
| Engine-issued | `validateToken` rejects tokens absent from the issuing manager's registry (`notIssuedByEngine`) |
| Bound | SHA-256 over canonical JSON of `{tool, args}` (sorted keys); any argument change invalidates |
| Single-use | Consumed on first successful authorization; replays rejected (`PERM_APPROVAL_INVALID`) |
| Expiring | Request and token share a TTL (default **10 minutes**); expired requests cannot mint tokens (`PERM_APPROVAL_TIMEOUT`) |
| Non-transferable | Token tool name, hash, and expiry must match the registry record |
| Revocable | `clearPendingApprovals()` revokes pending requests and unused tokens; `revokeAllApprovals()` also clears egress consent |
| One token per request | A second `approve()` returns null and is audited as denied |

There is **no permanent approval mode**. Safe operations run without approval; MEDIUM operations may run in-workspace; HIGH operations always require a fresh token.

---

## 6. External command protection

`ShellCommandGuard` (`packages/permissions/lib/src/shell_guard.dart`):

- commands are `executable + argv` only — a string like `command: "ffmpeg -i …"` is rejected;
- executable basename must be in the allowlist (`ffmpeg`, `ffprobe`, `mediainfo`) — `/bin/sh`, `bash`, `python`, and unknown binaries are blocked;
- `..` in executable paths, shell metacharacters (semicolon, ampersand, pipe, dollar, backtick, redirection, newline), control characters, overlong arguments, and excessive argument counts are rejected;
- no shell is ever spawned around the command; the engine passes argv lists to process APIs;
- the working directory must be inside the workspace (`mustExist: true`).

Shell tools also require a normal approval token bound to the full argv. Both checks are independent: a valid approval cannot authorize a blocked binary.

---

## 7. Secret storage

`FileSecretStore` (`packages/permissions/lib/src/secret_store.dart`) is the fallback when no OS keyring is available.

- 256-bit random device key in `device.key`; every stored secret encrypted with an HMAC-SHA256 PRF keystream and authenticated with encrypt-then-MAC over `nonce || ciphertext` (tag compared in constant time).
- Provider identifiers are base64url-encoded into filenames and validated (non-empty, ≤128 chars, no `..`), so identifiers cannot traverse directories.
- Atomic writes: temp file in the same directory then rename; `0600` files and `0700` directory on POSIX (best effort).
- Missing/corrupt key or failed tag → `SecretStoreException(STORE_CORRUPT)`; the store never returns partial plaintext.
- `SecureFileCredentialStore` in `provider_gateway` adapts it to `CredentialStore` and converts store failures into `PROVIDER_AUTH` (no unauthenticated fallback).

**Limitation:** an attacker who can read the user's home directory can read the device key. Production should back `CredentialStore` with an OS keyring (libsecret / DPAPI / Keychain).

---

## 8. Audit logging

`AppendOnlyAuditLogger`:

- JSONL, `FileMode.append`, flushed per record; writes serialized through a queue so concurrent tools cannot interleave the chain;
- SHA-256 hash chain: each record includes `prev_hash` and `hash` over `{ts, action, outcome, details, prev_hash}`; `verifyChain()` detects modification, reordering, or truncation;
- redaction before serialization: keys matching `api_key`, `secret`, `token`, `password`, `authorization`, `credential`, `private_key`, `bearer`, `session_id` become `[REDACTED]`; common token formats (`sk-…`, `Bearer …`, `AKIA…`, `AIza…`) are scrubbed from values;
- tool arguments are **never** logged — only `arguments_hash`, tool name, risk class, reason code, and boolean flags;
- best-effort `0600` file permissions.

If the audit sink cannot be written, authorization fails closed: the exception propagates out of `authorizeToolCall` and the tool does not run. A missing audit trail is treated as a security failure, not a warning.

The chain is tamper-**evident**, not tamper-**proof**: an attacker with write access can rewrite the entire file and recompute the chain. Retention/rotation is not yet implemented.

---

## 9. Cancellation

- Every tool receives a `CancellationToken`; the executor checks it before validation, before execution, and after awaiting the tool (`_withCancellation` races the tool future against cancellation).
- `PermissionManager.assertNotCancelled` is available to callers that execute outside the executor.
- Cancellation after approval still prevents execution; the token is not silently reused.

---

## 10. Tests (acceptance evidence)

| Area | Test file | Key cases |
|---|---|---|
| Path escapes | `packages/permissions/test/permission_engine_test.dart` | `..`, absolute outside, symlink escape, symlinked parent, traversal in nested args |
| Policy / risk | `permission_engine_test.dart`, `approval_security_test.dart` | safe/medium/high mapping, declared-risk downscope, unknown tool fail-closed, protected tools |
| Approvals | `approval_security_test.dart` | forged token, single approval, expiry (injected clock), revocation, replay, modified args, wrong tool |
| Shell | `approval_security_test.dart` | no approval, alias detection, `/bin/sh` blocked, command strings, metacharacters, foreign cwd, direct API |
| Audit | `audit_integrity_test.dart` | chain verification, modification, truncation, redaction, `0600`, no raw paths |
| Secrets | `secret_store_test.dart` | round-trip, ciphertext, permissions, traversal ids, swapped key, corruption, delete |
| Executor integration | `packages/tool_system/test/security_integration_test.dart` | destructive tool blocked, approved once, replay blocked, shell blocked, `assetPath` smuggling, cancellation |
| Gateway adapter | `packages/provider_gateway/test/secure_credential_store_test.dart` | encrypted storage, missing key auth error, corrupt store fail-closed |

Run:

```bash
(cd packages/permissions && dart test)
(cd packages/tool_system && dart test)
(cd packages/provider_gateway && dart test)
(cd packages/contracts && dart test)
```

---

## 11. Residual risks and non-goals

1. **TOCTOU:** path validation and use are separate syscalls; a local attacker who can mutate workspace symlinks between them is not fully mitigated (no `openat`/`O_NOFOLLOW` equivalent). Short-lived tools and in-workspace-only defaults reduce exposure.
2. **Approval UI not wired:** the engine is complete, but the desktop app does not yet surface approval dialogs or route UI-initiated destructive actions through `PermissionManager` (see audit finding S-02).
3. **Approval state is in-memory:** pending requests and issued tokens do not survive restart (safe default), but the UX must re-request after a crash.
4. **Audit persistence:** no rotation, retention policy, or off-device anchoring; local write access can rewrite the chain.
5. **File secret store is not a keyring:** it is encryption-at-rest with a colocated device key.
6. **Policy table is static:** new tools must be added to `PermissionPolicy` intentionally; otherwise they require approval on every call.
7. **No sandbox at OS level:** the engine restricts paths/commands; it does not use containers, seccomp, or filesystem namespaces.
8. **Cancellation is cooperative:** the executor stops waiting and blocks result use, but in-flight native work (for example an already-spawned encoder) must itself observe the token to stop early.
