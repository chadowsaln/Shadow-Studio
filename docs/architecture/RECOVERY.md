# Recovery and Agent Checkpoints (D9)

**Status:** implemented and verified locally (2026-11-17).
**Baseline:** `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md` §4.4, §6, QG-9.
**Code:** `packages/contracts/lib/src/agent/checkpoint.dart`,
`packages/local_storage/lib/src/checkpoint_store.dart`,
`packages/agent_runtime/lib/src/recovery_manager.dart`,
`packages/agent_runtime/lib/src/agent_controller.dart`,
`packages/agent_runtime/lib/src/execution_loop.dart`.

## 1. Goal

Long-running AI and media tasks must survive application crashes, OS shutdown,
provider/network timeouts, and media-worker crashes. After restart the app must
know which tasks were interrupted, show the user their last known state, and
resume only when the previous state validates against the current workspace and
project revision.

The system never silently repeats a destructive operation.

## 2. Durable model

A checkpoint is an immutable snapshot of one task:

| Field | Purpose |
| --- | --- |
| `taskId`, `sequence` | Identity and strictly increasing order per task (unique together) |
| `createdAt`, `lastHeartbeatAt` | Wall-clock time and liveness signal |
| `contextHash`, `projectRevision`, `workspaceRoot` | Bind the snapshot to the context it was produced in |
| `plan`, `pendingStepId`, `toolCallCount` | Progress to continue from |
| `state` | `queued/planning/acting/awaitingApproval/succeeded/failed/cancelled` |
| `request` | Original user request, so restart does not depend on UI memory |
| `metadata` | Context metadata used to recompute `contextHash` on resume |
| `lastToolName`, `lastToolIdempotent`, `lastToolArgumentsHash` | Safety of replaying the last call |
| `lastToolStatus` | `none/started/succeeded/failed` |
| `lastToolErrorCode`, `lastToolErrorMessage` | Failed-task inspection |
| `runId`, `processId` | Owner identity; another process means orphaned |
| `resumeCount` | How many manual resumes this task has had |
| `partialArtifacts` | Output paths that may be incomplete |
| `errorCode`, `errorMessage`, `summary` | Terminal outcome |

Checkpoints are stored in SQLite (`execution_checkpoints`, schema v3) behind the
`CheckpointStore` port. `InMemoryCheckpointStore` implements the same contract
for tests and embedders. Every save is one committed INSERT, so a process kill
leaves either the previous checkpoint or the new one — never a partial row. WAL,
`busy_timeout`, and `foreign_keys` are enabled by `LocalDatabase`.

## 3. When checkpoints are written

1. **Task created** — `queued`, with the request and empty plan.
2. **Planning/acting** — whenever a plan (or revised plan) is produced.
3. **Before every tool call** — `state: acting`,
   `lastToolStatus: started`, tool name, idempotence, arguments hash.
4. **After every tool call** — `succeeded` or `failed`, plus error code/message
   and any partial outputs reported by the tool.
5. **Terminal** — `succeeded`, `failed`, or `cancelled`, with summary/error.

Saves are serialized per task inside `RecoveryManager`, so the controller and
execution loop cannot allocate the same `sequence`, and `sequence` remains
monotonic after restart by reading the latest stored checkpoint.

## 4. Interrupted-task detection

`RecoveryManager.detectInterrupted()` examines the latest checkpoint per task and
reports a non-terminal task when either condition holds:

- `processId` is set and differs from the current process (`process_restart`);
- `lastHeartbeatAt` is older than `staleAfter` (default 10 minutes,
  `heartbeat_stale`).

Checkpoints written by the current `runId` are ignored. Terminal checkpoints are
never reported. Results are ordered oldest heartbeat first so the UI can show the
most stale task at the top.

`AgentController.interruptedTasks()` and `inspectInterrupted()` expose this to the
desktop layer.

## 5. Resume policy (fail closed)

`RecoveryManager.planResume(checkpoint, workspaceRoot, currentProjectRevision)`
validates **before** the loop continues and throws `RecoveryException` on the
first blocker:

| Condition | Result |
| --- | --- |
| No checkpoint | `AGENT_CHECKPOINT_MISSING` |
| Terminal state | Refuse; nothing to resume |
| Workspace root changed | Refuse |
| Project revision changed | Refuse (`EDIT_REVISION_MISMATCH` blocker detail) |
| Context hash changed | Refuse |
| Plan empty or fully terminal | Refuse |
| In-flight tool not idempotent | `TOOL_NOT_IDEMPOTENT_RETRY` until explicit consent |
| Partial artifact path escapes workspace | `PERM_PATH_ESCAPE` |

`AgentController.resumeTask(taskId)` uses the request/workspace/revision stored in
the checkpoint, recomputes the context hash from stored metadata, persists the
resumed state, and then schedules the loop. The loop receives the validated plan
(`resumePlan`) and continues at the first non-terminal step instead of planning
from scratch.

`restoreTask(...)` remains as a compatibility wrapper for callers that already
know the request, workspace, and revision.

### Non-idempotent replay

`lastToolStatus == started` means the process may have died while the tool was
running. The tool may have produced effects that were never observed. Recovery
requires `allowNonIdempotentReplay: true` (an explicit user decision) before it
will re-enter the loop. Idempotent tools resume automatically.

The execution loop already retries only idempotent tools on transient failure;
non-idempotent tools return their first failure to the brain for replanning.

## 6. Partial outputs

Tools may report `partial_artifacts` (or a failing `output_path`) in their result
data. The loop persists those paths on the checkpoint. On inspection they are
resolved against the workspace, symlinks are resolved, and any path outside the
workspace is rejected.

Partial files are **never deleted automatically**. `planResume` reports them and
adds a warning; `discardPartialOutputs: true` explicitly deletes files (not
directories) that are still inside the workspace. This prevents a resumed media
render from silently reusing or deleting an unrelated user file.

Media workers that crash should return `MEDIA_ENGINE_CRASH` plus the partial
output path; that record is what the recovery UI shows after restart.

## 7. Cancellation

`CancellationToken` is cooperative. Cancelling an active task makes the loop
throw `CancelledException`; the controller writes a terminal `cancelled`
checkpoint before releasing the scheduler slot. Cancelling a queued task removes
it from the scheduler and persists `cancelled`. `AgentController.dispose()` waits
for in-flight tasks so their terminal checkpoints are not raced by teardown.

## 8. Failure matrix

| Failure | Behaviour |
| --- | --- |
| Application crash / kill -9 | Non-terminal checkpoint remains; next process sees orphaned `processId` and offers manual resume |
| OS shutdown | Same as crash; SQLite commit makes the last checkpoint durable |
| Provider timeout / network interruption | Tool/provider failure is written with code/message; brain may replan or fail; terminal state is persisted |
| Media worker crash | Failure code `MEDIA_ENGINE_CRASH` and partial path are persisted; resume requires explicit discard or overwrite decision |
| Invalid checkpoint row | `latest` raises `CheckpointCorruptException` / `STORE_CORRUPT`; recovery fails closed instead of silently using older state. `history`/`latestAll` skip the bad row |
| Stale heartbeat, process still alive | Detected after `staleAfter`; inspection shows age and reason |
| Changed project revision or workspace | Resume refused until the task is restarted in the current state |

## 9. Inspection API

```dart
final interrupted = await controller.interruptedTasks();
final inspection = await controller.inspectTask(taskId);
// inspection.history, .checkpoint, .blockers, .partialArtifacts,
// .isInterrupted, .isTerminal, .safeToResume, .errorCode/.errorMessage

await controller.resumeTask(
  taskId,
  allowNonIdempotentReplay: false,
  discardPartialOutputs: false,
);
```

`RecoveryInspection` and `InterruptedTask` are exported from
`package:shadow_agent_runtime/agent_runtime.dart`.

## 10. Verification

`packages/agent_runtime/test/crash_recovery_test.dart` (18 tests) covers:

- dead-process detection (`process_restart`) and stale-heartbeat detection;
- terminal tasks excluded;
- non-idempotent in-flight replay blocked until explicit consent;
- idempotent in-flight resume;
- corrupt store fails closed;
- failed-tool error/partial-output persistence and inspection;
- explicit partial-output discard, and path-escape rejection;
- revision/workspace changes blocking resume;
- an empty plan resumable only before any tool ran;
- concurrent saves producing unique ordered sequences and a stale write
  never resurrecting a terminal task;
- a task interrupted during initial planning replanning on resume;
- real SQLite close/reopen → detection → controller resume → terminal success;
- terminal checkpoint refusing resume after restart;
- active-task cancellation persisting `cancelled`.

`packages/local_storage/test/checkpoint_store_test.dart` covers field
round-trips, ordering, `latestAll`, JSON corruption, `clear`, owner-row creation
for the FK, and reopen persistence.

```bash
(cd packages/agent_runtime && dart test)
(cd packages/local_storage && dart test)
```

## 11. Known limitations

- Cancellation is cooperative; a tool that ignores the token delays termination.
- There is no automatic resume on startup: detection and inspection are exposed,
  and resume is a manual user decision (by design for destructive media jobs).
- Idempotency is declared per tool; argument-level deduplication of repeated
  idempotent calls is not implemented.
- TOCTOU between artifact validation and deletion remains; paths are resolved and
  contained but file handles are not held open.
- Heartbeats are written with state changes, not on a timer; a long single tool
  call in a live process relies on `runId` rather than heartbeat freshness.
- Checkpoint garbage collection/retention is not implemented; history is bounded
  per query, not by a retention policy.
