# Internal Contracts (D3)

**Status:** implemented and verified locally (2026-11-17).
**Baseline:** `docs/architecture/SOFTWARE-ARCHITECTURE-SPEC-v2.0.md` §13, V2-D3.
**Code:** `packages/contracts/lib/src/agent/`, `packages/contracts/lib/src/tools/`,
`packages/contracts/lib/src/common/cancellation.dart`,
`packages/contracts/lib/src/errors/error_codes.dart`.

## 1. Layout

| File | Contents |
| --- | --- |
| `src/agent/agent_plan.dart` | `PlanStepStatus`, `PlanStep`, `AgentPlan`, `Planner` |
| `src/agent/agent_brain.dart` | `AgentDecision` hierarchy, `AgentBrain`, `ToolCallExecutor`, `ApprovalGate` |
| `src/agent/checkpoint.dart` | `AgentCheckpoint`, `CheckpointStore` |
| `src/agent/agents.dart` | Barrel export for the four agent files |
| `src/tools/schema_validator.dart` | Canonical closed-schema `ToolSchemaValidator` |
| `src/tools/tool_contracts.dart` | `AgentTool`, `ToolContext`, `ToolResult`, `ToolExecutionStatus`, `ToolExecutionMetadata`, `ToolContractValidator` |
| `src/common/cancellation.dart` | `CancellationToken`, `CancelledException`, `ShadowTimeoutException`, `runWithTimeout` |
| `src/errors/error_codes.dart` | `ShadowError`, `ShadowErrorCode`, `ShadowErrorCategory` |

## 2. Agent contracts

### Plan

- `PlanStep` carries `id`, `description`, `expectedOutcome`, `status`
  (`pending/running/succeeded/failed/skipped`), and optional `outcome`; JSON
  round-trips with `toJson`/`fromJson`.
- `AgentPlan` carries `revision`, `steps`, and derived `pendingSteps`,
  `completedSteps`, `isComplete`; `updateStep` and `withRevision` return new
  immutable plans.

### Decisions

`AgentDecision` is sealed and carries the plan revision:

| Decision | Meaning |
| --- | --- |
| `CompleteDecision` | Task finished, with the final response |
| `ToolCallsDecision` | Execute the given tool calls |
| `ReplanDecision` | Replace the plan (explicit revision) |
| `FailDecision` | Terminate with a structured error |

Consumers exhaustively switch on the sealed type, so adding a decision is a
compile error until every consumer handles it.

### Collaborators

- `AgentBrain.decide(...)` returns the next decision.
- `ToolCallExecutor.execute(...)` executes one approved tool call.
- `ApprovalGate.requestApproval(...)` returns an `ApprovalToken` or `null`
  (denied).
- `Planner.makePlan(...)` produces an `AgentPlan`.
- `AgentCheckpoint` / `CheckpointStore` persist plan, tool state, task state,
  revision, and correlation data; `clear(taskId)` removes a checkpoint.

`agent_runtime` now re-exports these types from its public library, so existing
imports of `package:shadow_agent_runtime/agent_runtime.dart` keep compiling.

## 3. Tool contracts

### Definition

Every `AgentTool` declares `name`, `description`, `riskLevel`, `idempotent`,
`timeout`, `inputSchema`, `outputSchema`, and `execute`.

`ToolContractValidator.validateDefinition` rejects:

- names that do not match `^[a-z][a-z0-9_]{0,63}$`;
- blank descriptions;
- timeouts outside `(0, 10 minutes]`;
- input or output schemas that are not closed JSON-Schema objects
  (`additionalProperties: false`).

`ToolRegistry` runs this validation at registration time and throws a
structured `StateError` carrying `ShadowErrorCode.toolSchemaInvalid` and all
violations.

### Schema validation

`ToolSchemaValidator` is the single implementation (previously duplicated in
`tool_system`). It supports object/type/required/additionalProperties, string
length/pattern, numeric bounds, arrays with item schemas, and enum. Unknown
keywords are ignored so schemas can carry annotations.

### Results

- `ToolResult.ok(data:)` and `ToolResult.failure(code:, message:)`.
- `ToolResult.fromError(ShadowError)` copies code, message, and correlation id
  into `artifacts`.
- `status` maps structured codes to `ToolExecutionStatus`:
  `succeeded`, `failed`, `cancelled` (`agentCancelled`), `denied`
  (`permApprovalRequired`), `timedOut` (`toolTimeout`).
- `duration` is the recorded execution time.

`ToolExecutor` enforces, in order: definition validation, timeout via
`runWithTimeout`, structured failure mapping for `ShadowTimeoutException`, size
limiting, and output validation against `outputSchema` (skipped for truncated
results, which are already marked).

### Execution metadata

`ToolExecutionMetadata` records tool name, task id, correlation id, attempt,
status, start/finish timestamps, duration, and result size, with JSON
round-tripping and an `isTerminal` helper.

## 4. Cancellation and timeouts

- `CancellationToken.cancel([reason])` is idempotent and broadcasts on
  `onCancel`; `cancelAfter(duration, reason)` schedules cancellation.
- `throwIfCancelled()` raises `CancelledException`.
- `runWithTimeout({timeout, cancel, body, operation, timeoutReason})` is an
  async function that throws `CancelledException` (pre-cancelled) or
  `ShadowTimeoutException` (deadline), and returns the body result otherwise.
- Cooperative cancellation is expected in long-running tool bodies; the
  executor observes `ShadowTimeoutException` and converts it to
  `ToolResult.failure(code: ShadowErrorCode.toolTimeout)`.

## 5. Structured errors

`ShadowError` is immutable and serializes to a stable JSON shape:

```json
{
  "code": "EDIT_REVISION_MISMATCH",
  "category": "edit",
  "retryable": false,
  "correlation_id": "c-1",
  "details": {"expected": 1, "actual": 2},
  "message": "stale revision"
}
```

New codes added for D3: `TOOL_TIMEOUT`, `TOOL_OUTPUT_INVALID`.

## 6. Backward compatibility

- `agent_runtime` re-exports plan, decision, checkpoint, and collaborator types.
- `tool_system` re-exports the canonical validator and adds
  `ToolContractValidator` usage without changing `ToolRegistry` /
  `ToolExecutor` public signatures.
- `local_storage`'s `SqliteCheckpointStore` depends only on
  `shadow_contracts`; the `shadow_agent_runtime` dependency was removed.

## 7. Verification

| Suite | Coverage |
| --- | --- |
| `packages/contracts/test/agent_plan_test.dart` | plan/step JSON, status parsing, revision, decisions, checkpoint round-trip |
| `packages/contracts/test/tool_contracts_test.dart` | schema validation, definition validation, result validation, status mapping, metadata, cancellation/timeout, structured errors |
| `packages/agent_runtime/test` | planner, execution loop, budgets, retries, recovery |
| `packages/tool_system/test` | registry validation, execution timeout/output validation, audit events, built-in tools |

Run:

```bash
cd packages/contracts && dart test
cd ../agent_runtime && dart test
cd ../tool_system && dart test
```