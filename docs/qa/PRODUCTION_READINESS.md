# Shadow Studio — Production Readiness Verification

**Audit date:** 2026-11-17  
**Repository:** `chadowsaln/Shadow-Studio`  
**Audited ref:** `main`  
**Audited commit:** `e0e169a8f82a2f5725714b03852a081a696929b3`  
**Report status:** Source-level audit completed; runtime verification is incomplete.  
**Release verdict:** **NOT READY FOR PRODUCTION**

> This report deliberately separates source inspection from executed verification. The repository was inspected through GitHub. No Dart/Flutter/Python/FFmpeg command, GitHub Actions job, desktop binary, crash-injection test, or full end-to-end scenario was executed during this audit. Therefore no runtime test is marked PASS.

## 1. Executive summary

The repository contains substantial foundations: a Dart workspace, agent/runtime and provider packages, a tool registry, a permission engine, SQLite persistence, an editing core, a RenderGraph/FFmpeg render pipeline, security-focused unit/integration test source files, and a Linux CI workflow.

However, the current desktop application is not yet wired to the autonomous agent stack. Its `apps/desktop/pubspec.yaml` declares dependencies on `editing_core`, `local_storage`, and `media_core`, but not on `agent_runtime`, `context_engine`, `provider_gateway`, `tool_system`, or `permissions`. The inspected root app widget initializes an editor and `FfmpegMediaWorker`; it does not construct an agent controller, provider router, tool executor, or approval UI.

The documented D4 media spike is explicitly a Python + FFmpeg proof of concept, not the production C++/MLT worker. Its README says it renders the example graph and verifies pixels/audio/determinism, but also documents important limitations: MP4/H.264 only, restricted operations, trusted fixture inputs, and approximately 0.15× realtime CPU performance. This is useful contract evidence, not proof of a production media engine.

Arabic localization is still listed as UX-P3, not started. The inspected `MaterialApp` does not declare `localizationsDelegates` or `supportedLocales`. The CI workflow builds Linux only and its package test matrix omits `packages/context_engine` and `packages/render_pipeline`, although the local `tool/ci/verify.sh` script includes both.

**The mandatory user scenario (“Create a professional 30-second advertisement”) is NOT VERIFIED and is currently blocked by missing desktop-to-agent integration and the absence of a verified production native worker path.**

## 2. Verification method and evidence limits

### Inspected repository evidence

- `docs/README.md`
- `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md`
- `docs/security/PERMISSIONS.md`
- `docs/data-model.md`
- `docs/contracts.md`
- `.github/workflows/ci.yml`
- `tool/ci/verify.sh`
- `tool/ci/validate_docs.py`
- `apps/desktop/pubspec.yaml`
- `apps/desktop/lib/main.dart`
- `apps/desktop/lib/src/app.dart`
- `packages/permissions/test/permission_engine_test.dart`
- `packages/permissions/test/approval_security_test.dart`
- `packages/tool_system/test/security_integration_test.dart`
- `packages/local_storage/test/storage_data_model_test.dart`
- `packages/contracts/test/agent_plan_test.dart`
- `packages/editing_core/test/commands_test.dart`
- `packages/render_pipeline/test/render_queue_test.dart`
- `tools/media-spike/README.md`

### Execution status

| Verification activity | Result |
|---|---|
| Repository source inspection | Completed |
| Test source inspection | Partial; representative suites inspected |
| Dart format / analyze | NOT RUN |
| Dart package tests | NOT RUN |
| Flutter widget tests | NOT RUN |
| Documentation validators | NOT RUN |
| GitHub Actions run logs | No status-check records were returned for the audited commit |
| Real media-spike execution | NOT RUN in this audit; prior README evidence only |
| Desktop release build | NOT RUN |
| Real-video agent E2E | NOT RUN |
| Crash/recovery injection | NOT RUN |
| Performance benchmark execution | NOT RUN |

An empty GitHub commit-status response is not evidence of a successful workflow. Obtain the actual Actions run and job logs before release approval.

## 3. Production readiness matrix

Status meanings:
- **PASS (source evidence):** the inspected implementation/test source supports the capability; runtime execution is still required.
- **FAIL:** an identified product/CI gap prevents the required capability from being considered ready.
- **NOT VERIFIED:** there is insufficient execution evidence to make a pass/fail claim.

| Area | Source-level finding | Runtime result | Verdict |
|---|---|---|---|
| 1. Agent planning and execution | Agent contracts/runtime packages and plan/checkpoint types exist. Desktop app does not depend on or initialize the agent runtime. | No agent task executed. | **FAIL — desktop integration gap** |
| 2. Tool registration and invocation | Tool registry/executor package exists; security integration test source covers invocation and denial. | Tests not run; no UI-to-agent tool call verified. | **NOT VERIFIED** |
| 3. Provider switching | Provider gateway package and provider-independent interfaces exist; docs describe adapters/routing. | No live or deterministic adapter-switch test run. | **NOT VERIFIED** |
| 4. API failures and retries | Architecture documents retry/fallback and provider error rules. | No 401/403/429/5xx/timeout/retry test run in this audit. | **NOT VERIFIED** |
| 5. Permission enforcement | Permission engine and approval-token policy are implemented in source; approval UI is explicitly described as not wired. | Security tests not run; user approval flow not verified in desktop. | **FAIL — approval UX/integration gap** |
| 6. Filesystem security | Path validator/workspace guard and adversarial tests cover traversal and symlink escapes. | Adversarial tests not run on target OS/filesystem. | **NOT VERIFIED** |
| 7. Checkpoint creation | Checkpoint contract and persistence model exist. | No checkpoint write/read test executed here. | **NOT VERIFIED** |
| 8. Recovery after crashes | Recovery manager/checkpoint work is documented. | No process-kill, restart, replay, or interrupted-render test run. | **NOT VERIFIED** |
| 9. Timeline editing | Editing core commands and inverse-command tests exist. Desktop app constructs an editing service. | Tests not run; complete UI/AI edit path not verified. | **NOT VERIFIED** |
| 10. Media rendering | RenderGraph pipeline and queue exist. Queue test inspected here uses a fake backend. D4 spike documents a real FFmpeg render against a fixed example graph. | No render run in this audit; arbitrary user media and production worker not verified. | **NOT VERIFIED** |
| 11. Video/audio export | D4 spike documentation describes H.264 MP4 + AAC/audio verification. It is not the production native worker and has constrained graph support. | No export run in this audit. | **NOT VERIFIED** |
| 12. Arabic localization | UX-P3 is marked not started in docs. Root app has no inspected localization delegates/supported locales. | No Arabic UI test possible from current inspected setup. | **FAIL — localization incomplete** |
| 13. Desktop packaging | CI defines a Linux release build and artifact upload. Desktop package describes Linux & Windows. | Workflow/build not run; Windows packaging is absent from inspected CI. | **NOT VERIFIED — Linux only in CI** |

## 4. Blocking findings

### P0 — Desktop does not integrate the AI agent system

Evidence:
- `apps/desktop/pubspec.yaml` only declares `editing_core`, `local_storage`, and `media_core` among project packages.
- `apps/desktop/lib/src/app.dart` initializes `EditorController`, `DefaultEditingService`, `MediaLibraryService`, and `FfmpegMediaWorker`.
- No agent runtime, context engine, provider gateway, tool registry, or permission service is initialized in the inspected app entry path.

Required work:
1. Add explicit composition-root/DI wiring for the runtime packages.
2. Connect UI task submission to AgentController.
3. Route every tool invocation through ToolExecutor and PermissionService.
4. Surface plan, progress, approval, cancellation, and result events in the UI.
5. Add a desktop integration test proving the entire dependency path.

### P0 — Permission approval UX is not wired

`docs/security/PERMISSIONS.md` explicitly says the permission engine is implemented but approval UI and desktop shell wiring remain separate work items.

Required work:
1. Implement an approval dialog/panel with tool, target, risk, and effect summary.
2. Ensure approval is bound to the exact tool + canonical arguments and is single-use.
3. Test approve, deny, expiry, replay, cancellation, and changed-argument rejection through the actual desktop UI.
4. Keep enforcement in the engine; never rely on UI-only checks.

### P0 — Production native media worker is not demonstrated

`tools/media-spike/README.md` explicitly calls the spike a Python + FFmpeg proof of concept and says it is not a product worker (no C++, no MLT, single process). It also documents restricted feature support and low CPU throughput.

Required work:
1. Decide and document the actual MVP renderer contract: current Dart/FFmpeg process backend versus planned C++/MLT worker.
2. Implement the chosen production backend behind the existing render abstraction.
3. Test arbitrary imported media, codec failures, corrupt files, cancellation, atomic output, audio/video sync, and resource limits.
4. Do not claim crash isolation until the worker is a separate process and crash injection proves the desktop survives.

### P1 — CI test matrix is incomplete

The inspected `.github/workflows/ci.yml` test matrix includes contracts, agent_runtime, tool_system, provider_gateway, permissions, local_storage, editing_core, and media_core. It does not include:
- `packages/context_engine`
- `packages/render_pipeline`

The local `tool/ci/verify.sh` does include both, so local and hosted CI gates are inconsistent.

Required work:
1. Add both missing packages to the GitHub Actions test matrix.
2. Add Windows build/test coverage if Windows is a supported target.
3. Add E2E, security, and performance jobs (or explicitly define them as manual release gates).
4. Capture and retain test reports and build artifacts.

### P1 — Arabic localization is incomplete

The documentation marks UX-P3 as not started. The inspected root MaterialApp does not configure Flutter localization delegates/locales.

Required work:
1. Add AR and EN locale resources using Flutter gen-l10n.
2. Configure delegates and supported locales at the app root.
3. Verify RTL layout for timeline, inspector, dialogs, text inputs, and export screens.
4. Add widget tests for Arabic strings, directionality, overflow, and mixed LTR media paths/timecodes.

### P1 — Secret storage has a documented production limitation

The security document describes a file-based fallback where the device key is stored in the user's home directory and notes that an attacker who can read that directory can read the key. It recommends an OS keyring (libsecret / DPAPI / Keychain) for production.

Required work:
- Implement OS-backed credential storage for supported desktop OSes, or explicitly block production release when only the file fallback is available.
- Add OS-level permission and credential lifecycle tests.

### P2 — Audit log is tamper-evident, not tamper-proof

The security document states that an attacker with write access can rewrite the entire audit file and recompute its hash chain; retention/rotation is not implemented.

Required work:
- Document the threat model and retention policy.
- Consider anchoring checkpoints/hashes in OS-protected storage.
- Add rotation, corruption, truncation, and recovery tests.

## 5. Existing test assets found in source

These are test files inspected, **not tests executed**:

| Suite | Evidence found | What it covers in source |
|---|---|---|
| Contracts | `packages/contracts/test/agent_plan_test.dart` | plan JSON, status, revisions, decisions, checkpoint round-trip |
| Permissions | `packages/permissions/test/permission_engine_test.dart` | traversal, absolute paths, symlink escapes, workspace guard |
| Approval security | `packages/permissions/test/approval_security_test.dart` | forged tokens, single-use, expiry, revocation, fail-closed |
| Tool/permission integration | `packages/tool_system/test/security_integration_test.dart` | destructive tool denial, approved execution once, shell guard |
| Persistence | `packages/local_storage/test/storage_data_model_test.dart` | schema v2, CRUD, foreign keys, rollback, integrity, migration |
| Editing core | `packages/editing_core/test/commands_test.dart` | command execution and inverse restoration |
| Render queue | `packages/render_pipeline/test/render_queue_test.dart` | queue state, progress, failure cleanup, cancellation, concurrency using fake backend |

The repository documentation also describes agent runtime/provider tests, but this audit did not retrieve every test file or run those suites. Do not infer full coverage from the existence of the package or its documentation.

## 6. Required test plan

The following tests must be added or confirmed and then executed. Tests using fakes are useful for deterministic unit tests but do not replace real process/provider/media integration tests.

### 6.1 Unit tests

- Planner: valid plan, empty plan, duplicate step IDs, malformed provider response, replan revision, terminal-state invariants.
- Execution loop: tool-call limit, task deadline, duplicate-call loop detection, retry budget, cancellation.
- Tool registry: duplicate registration, invalid name/schema, closed schema, unknown tool, invalid output.
- Provider gateway: adapter capability negotiation, model selection, error mapping, rate-limit backoff, non-retryable auth errors, stream cancellation.
- Permission engine: risk escalation, unknown-tool default, forged/replayed/expired approval, argument mutation, symlink race, NUL/control characters, shell metacharacters.
- Persistence: transaction rollback, forward migration, corruption handling, checkpoint serialization, reopen-after-crash.
- Editing: clip/track/transition/text/audio commands, inverse operations, revision conflicts, RenderGraph generation.
- Localization: AR string resolution, fallback locale, RTL semantics and plural/format cases.

### 6.2 Integration tests

- AgentController → Planner → ProviderGateway → ToolExecutor → PermissionService → real tool.
- Provider fallback across two deterministic local HTTP mock servers, including 401/429/500/timeout.
- SQLite checkpoint creation and recovery with a fresh process/database handle.
- Editing Core → RenderGraph → ProcessRenderBackend → FFmpeg → ffprobe verification.
- Filesystem sandbox and approval flow on Linux; repeat on Windows if supported.
- Credential store integration with OS keyring.

### 6.3 Security tests

- Path traversal using POSIX, Windows drive, UNC, nested maps, symlinked parents, dangling symlinks, and non-existent targets.
- TOCTOU test between path validation and file open/write.
- Approval replay, expired approval, altered arguments, wrong tool, forged token, and approval after cancellation.
- Secret leakage scans across logs, errors, crash dumps, artifacts, and project files.
- Malicious provider tool-call payloads and oversized/deep JSON.
- Shell command attempts with separators, substitutions, redirection, environment assignments, and executable path aliases.
- Audit log corruption, truncation, concurrent writes, and rotation.

### 6.4 End-to-end test — mandatory advertisement scenario

Use a checked-in, licensed, small test fixture with known video and audio streams. Do not upload private user media to a cloud provider without explicit consent.

1. Launch the packaged desktop application.
2. Import the fixture and wait for metadata/probe completion.
3. Submit: “Create a professional 30-second advertisement.”
4. Assert that a structured plan is displayed with expected duration and deliverable.
5. Assert that real tools are registered and invoked; record tool IDs and outputs.
6. Assert that external AI egress is disclosed and approved before media leaves the device.
7. Assert that restricted/dangerous operations request approval in the UI.
8. Deny one operation and verify it does not execute; then approve a fresh request and verify exactly one execution.
9. Assert that timeline edits are persisted and the original source file hashes remain unchanged.
10. Render a real MP4 with video and audio streams; inspect with ffprobe and decode the full output.
11. Assert output duration is 30 seconds within the documented frame/timebase tolerance.
12. Preview the rendered result in the app, make a manual edit, undo it, and redo it.
13. Kill the app during a safe checkpoint boundary or render; relaunch and verify task state is recovered without duplicating non-idempotent operations.
14. Capture logs, test artifacts, output hashes, and a screen recording.

This scenario is currently **BLOCKED** until desktop agent wiring, approval UI, and the production media backend are available.

### 6.5 Performance benchmarks

Create a repeatable benchmark harness with fixed fixtures and machine metadata. Record baseline and p50/p95/max, not just one average.

- Cold startup and time-to-interactive.
- 300-clip timeline frame time and scrub latency.
- Media probe and thumbnail throughput.
- Render throughput for 1080p and 4K with documented codec/preset.
- Peak RSS for UI and media worker separately.
- Agent task latency, provider token usage, tool-call count, and retry count.
- Checkpoint write/read latency and database growth.
- Cancellation latency and worker restart latency.

The architecture specifies targets such as 60 fps timeline interaction, scrub p95 ≤120 ms, worker restart ≤3 s, UI memory <800 MB, and worker memory <1.5 GB. These are **targets, not measured results**. The media spike README reports approximately 0.15× realtime on its documented CPU fixture; this is not a benchmark of the integrated product.

## 7. Commands to execute in a clean checkout

Run from the repository root after installing the documented toolchain and native Linux build dependencies:

```bash
git status --short
git rev-parse HEAD
dart --version
flutter --version

dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze

python3 tool/ci/validate_docs.py
python3 docs/architecture/contracts/validate_contract.py
python3 docs/architecture/contracts/validate_schema.py
python3 docs/architecture/contracts/validate_v2.py
python3 docs/design/verify_design_spec.py

./tool/ci/verify.sh

# Explicitly exercise the media spike in a fresh fixture/output directory.
python3 -m venv tools/media-spike/.venv
tools/media-spike/.venv/bin/pip install blake3 numpy
tools/media-spike/.venv/bin/python tools/media-spike/spike.py all --force
tools/media-spike/.venv/bin/python tools/media-spike/test_refusals.py

# Desktop release build (Linux)
(cd apps/desktop && flutter build linux --release)
```

Afterward, run the integration, security, E2E, and benchmark suites described above. Store machine-readable test output and artifact hashes under `docs/qa/artifacts/` or the CI artifact store. Do not add generated videos, secrets, user files, or large benchmark binaries to Git.

## 8. Release gates

A release candidate must not be approved until all of the following are true:

- [ ] Desktop application wires the agent runtime, context, provider gateway, tool system, and permission engine.
- [ ] Approval UX is implemented and tested end-to-end.
- [ ] Production media backend is selected, implemented, and crash-isolated as specified.
- [ ] Real-media integration tests pass for video and audio export.
- [ ] Provider switching, retry, timeout, and non-retryable errors pass deterministic tests.
- [ ] Filesystem adversarial tests pass on every supported OS.
- [ ] Checkpoint recovery survives process termination without duplicate side effects.
- [ ] Arabic localization and RTL widget tests pass.
- [ ] CI includes context_engine and render_pipeline tests and supported desktop OS builds.
- [ ] Performance targets are measured on documented reference hardware.
- [ ] All unit, integration, security, E2E, and packaging jobs have successful run links and retained artifacts.
- [ ] No unresolved Critical/High security findings remain.

## 9. Final verdict

**NOT READY FOR PRODUCTION.**

The repository has meaningful foundations and useful source-level test coverage. The principal release blockers are not the absence of all architecture or packages; they are the missing integration of the autonomous agent into the desktop app, the unwired approval UX, the gap between the media spike and a production native worker, incomplete Arabic localization, and the absence of executed end-to-end/performance/crash-recovery evidence.

Re-run this audit after the blockers are implemented. Change a status to PASS only when the corresponding command or scenario has actually run and its output/artifact is retained.
