import 'package:shadow_contracts/shadow_contracts.dart';

import 'agent_context.dart';

class InMemoryCheckpointStore implements CheckpointStore {
  final Map<String, AgentCheckpoint> _latest = <String, AgentCheckpoint>{};

  @override
  Future<void> save(AgentCheckpoint checkpoint) async {
    _latest[checkpoint.taskId] = checkpoint;
  }

  @override
  Future<AgentCheckpoint?> latest(String taskId) async => _latest[taskId];

  @override
  Future<void> clear(String taskId) async {
    _latest.remove(taskId);
  }
}

/// Saves checkpoints and restores interrupted tasks safely.
class RecoveryManager {
  RecoveryManager({CheckpointStore? store})
    : _store = store ?? InMemoryCheckpointStore();

  final CheckpointStore _store;
  final Map<String, int> _sequences = <String, int>{};

  /// Must be called after every tool call (enforced by ExecutionLoop).
  Future<AgentCheckpoint> saveAfterToolCall({
    required String taskId,
    required AgentContext context,
    required AgentPlan plan,
    required int toolCallCount,
    required String? pendingStepId,
    required String toolName,
    required bool toolIdempotent,
    required String argumentsHash,
    AgentTaskState state = AgentTaskState.acting,
  }) async {
    final seq = (_sequences[taskId] ?? 0) + 1;
    _sequences[taskId] = seq;
    final cp = AgentCheckpoint(
      taskId: taskId,
      sequence: seq,
      createdAt: DateTime.now().toUtc(),
      contextHash: context.contextHash,
      projectRevision: context.projectRevision,
      workspaceRoot: context.workspaceRoot,
      plan: plan,
      toolCallCount: toolCallCount,
      pendingStepId: pendingStepId,
      lastToolName: toolName,
      lastToolIdempotent: toolIdempotent,
      lastToolArgumentsHash: argumentsHash,
      state: state,
    );
    await _store.save(cp);
    return cp;
  }

  Future<AgentCheckpoint?> restore(String taskId) => _store.latest(taskId);

  /// Validates a checkpoint against current project state.
  /// Throws [StateError] with explicit reason on invalid revision or context mismatch.
  void validateForResume({
    required AgentCheckpoint checkpoint,
    required int currentProjectRevision,
    required String currentWorkspaceRoot,
  }) {
    if (checkpoint.workspaceRoot != currentWorkspaceRoot) {
      throw StateError(
        'CHECKPOINT_WORKSPACE_MISMATCH: checkpoint=${checkpoint.workspaceRoot} current=$currentWorkspaceRoot',
      );
    }
    if (checkpoint.projectRevision != currentProjectRevision) {
      throw StateError(
        '${ShadowErrorCode.editRevisionMismatch}: checkpoint revision ${checkpoint.projectRevision} != current $currentProjectRevision',
      );
    }
  }

  /// Ensures we never silently repeat a non-idempotent operation on resume.
  /// Call before replaying/retrying the last interrupted tool call.
  void assertSafeToRepeatLastTool(AgentCheckpoint checkpoint) {
    if (checkpoint.lastToolName == null) return;
    if (checkpoint.lastToolIdempotent == false) {
      throw StateError(
        '${ShadowErrorCode.toolNotIdempotentRetry}: cannot silently repeat non-idempotent tool ${checkpoint.lastToolName}',
      );
    }
  }

  Future<void> clear(String taskId) async {
    _sequences.remove(taskId);
    await _store.clear(taskId);
  }
}
