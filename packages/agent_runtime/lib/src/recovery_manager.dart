import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shadow_contracts/shadow_contracts.dart';

import 'agent_context.dart';

/// In-memory store used by tests and embedders without persistence.
///
/// It keeps **all** checkpoints per task so recovery history and interrupted
/// detection behave exactly like the SQLite implementation.
class InMemoryCheckpointStore implements CheckpointStore {
  final Map<String, List<AgentCheckpoint>> _byTask =
      <String, List<AgentCheckpoint>>{};

  @override
  Future<void> save(AgentCheckpoint checkpoint) async {
    final list = _byTask.putIfAbsent(
      checkpoint.taskId,
      () => <AgentCheckpoint>[],
    );
    final existing = list.indexWhere((c) => c.sequence == checkpoint.sequence);
    if (existing >= 0) {
      list[existing] = checkpoint;
    } else {
      list.add(checkpoint);
    }
    list.sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  @override
  Future<AgentCheckpoint?> latest(String taskId) async {
    final list = _byTask[taskId];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  @override
  Future<List<AgentCheckpoint>> history(String taskId, {int limit = 50}) async {
    final list = _byTask[taskId];
    if (list == null || list.isEmpty) return const <AgentCheckpoint>[];
    final start = limit >= list.length ? 0 : list.length - limit;
    return list.sublist(start).reversed.toList(growable: false);
  }

  @override
  Future<List<AgentCheckpoint>> latestAll() async {
    final out = <AgentCheckpoint>[];
    for (final list in _byTask.values) {
      if (list.isNotEmpty) out.add(list.last);
    }
    out.sort((a, b) {
      final ah = a.lastHeartbeatAt ?? a.createdAt;
      final bh = b.lastHeartbeatAt ?? b.createdAt;
      return bh.compareTo(ah);
    });
    return out;
  }

  @override
  Future<void> clear(String taskId) async {
    _byTask.remove(taskId);
  }
}

/// Raised when a task cannot be resumed safely or its stored state is invalid.
class RecoveryException implements Exception {
  const RecoveryException({
    required this.code,
    required this.message,
    this.taskId,
  });

  final String code;
  final String message;
  final String? taskId;

  @override
  String toString() => 'RecoveryException($code): $message';
}

@immutable
class RecoveryBlocker {
  const RecoveryBlocker(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

@immutable
class InterruptedTask {
  const InterruptedTask({
    required this.checkpoint,
    required this.age,
    required this.reason,
  });

  final AgentCheckpoint checkpoint;
  final Duration age;

  /// `process_restart` (orphaned pid) or `heartbeat_stale`.
  final String reason;
}

@immutable
class RecoveryInspection {
  const RecoveryInspection({
    required this.taskId,
    required this.exists,
    required this.history,
    required this.isTerminal,
    required this.isInterrupted,
    required this.blockers,
    required this.partialArtifacts,
    this.checkpoint,
    this.errorCode,
    this.errorMessage,
  });

  final String taskId;
  final bool exists;
  final AgentCheckpoint? checkpoint;
  final List<AgentCheckpoint> history;
  final bool isTerminal;
  final bool isInterrupted;
  final List<RecoveryBlocker> blockers;

  /// Partial artifact paths that currently exist on disk.
  final List<String> partialArtifacts;

  final String? errorCode;
  final String? errorMessage;

  bool get safeToResume =>
      exists && !isTerminal && errorCode == null && blockers.isEmpty;
}

@immutable
class ResumePlan {
  const ResumePlan({
    required this.checkpoint,
    required this.plan,
    required this.resumeCount,
    required this.partialArtifacts,
    required this.discardedPartialArtifacts,
    required this.warnings,
  });

  final AgentCheckpoint checkpoint;
  final AgentPlan plan;
  final int resumeCount;

  /// Partial files present at resume time (not deleted unless requested).
  final List<String> partialArtifacts;

  /// Paths explicitly discarded by the caller.
  final List<String> discardedPartialArtifacts;

  final List<String> warnings;
}

/// Saves checkpoints and restores interrupted tasks safely.
///
/// Invariants:
/// * every save is sequenced per task and serialized, so concurrent tool calls
///   cannot overwrite each other;
/// * a tool is marked `started` before execution and `succeeded`/`failed` after;
/// * a resume validates terminal state, workspace, revision and context hash
///   before the loop continues;
/// * a non-idempotent tool that was in flight requires explicit confirmation;
/// * partial outputs are only deleted when the caller explicitly asks.
class RecoveryManager {
  RecoveryManager({
    CheckpointStore? store,
    DateTime Function()? now,
    String? runId,
    int? processId,
    this.staleAfter = const Duration(minutes: 10),
    this.maxHistory = 50,
  }) : _store = store ?? InMemoryCheckpointStore(),
       _now = now ?? (() => DateTime.now().toUtc()),
       _processId = processId ?? _currentProcessId(),
       _runId = runId ?? _newRunId();

  final CheckpointStore _store;
  final DateTime Function() _now;
  final int _processId;
  final String _runId;
  final Duration staleAfter;
  final int maxHistory;

  final Map<String, int> _sequences = <String, int>{};
  final Map<String, Future<void>> _queues = <String, Future<void>>{};

  String get runId => _runId;

  static String _newRunId() {
    final random = Random.secure().nextInt(1 << 32);
    return 'run_${DateTime.now().microsecondsSinceEpoch}_$random';
  }

  static int _currentProcessId() {
    try {
      return pid;
    } catch (_) {
      return 0;
    }
  }

  /// Serializes checkpoint writes per task so `sequence` stays monotonic even
  /// when the controller and execution loop save concurrently.
  Future<T> _serialized<T>(String taskId, Future<T> Function() action) {
    final previous = _queues[taskId] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _queues[taskId] = tail;
    return result.whenComplete(() {
      if (identical(_queues[taskId], tail)) _queues.remove(taskId);
    });
  }

  Future<int> _nextSequence(String taskId, AgentCheckpoint? latest) async {
    var sequence = _sequences[taskId];
    sequence ??= latest?.sequence ?? await _latestSequenceFromStore(taskId);
    sequence += 1;
    _sequences[taskId] = sequence;
    return sequence;
  }

  Future<int> _latestSequenceFromStore(String taskId) async {
    try {
      final latest = await _store.latest(taskId);
      return latest?.sequence ?? 0;
    } on CheckpointCorruptException catch (error) {
      throw RecoveryException(
        code: ShadowErrorCode.storeCorrupt,
        message: error.message,
        taskId: taskId,
      );
    }
  }

  /// Persists a full task state snapshot. This is the single write path used by
  /// the controller and the execution loop.
  Future<AgentCheckpoint> saveTaskState({
    required String taskId,
    required AgentContext context,
    required AgentTaskState state,
    String? request,
    AgentPlan plan = const AgentPlan(steps: <PlanStep>[], revision: 0),
    int toolCallCount = 0,
    String? pendingStepId,
    String? lastToolName,
    bool? lastToolIdempotent,
    String? lastToolArgumentsHash,
    CheckpointToolStatus lastToolStatus = CheckpointToolStatus.none,
    String? lastToolErrorCode,
    String? lastToolErrorMessage,
    int? resumeCount,
    List<String>? partialArtifacts,
    String? errorCode,
    String? errorMessage,
    String? summary,
  }) {
    return _serialized(taskId, () async {
      AgentCheckpoint? previous;
      try {
        previous = await _store.latest(taskId);
      } on CheckpointCorruptException catch (error) {
        // A corrupt latest checkpoint must not be silently replaced: that
        // would erase the only evidence of the interrupted run.
        throw RecoveryException(
          code: ShadowErrorCode.storeCorrupt,
          message: error.message,
          taskId: taskId,
        );
      }
      // A delayed plan/progress write must never resurrect a task that has
      // already reached a terminal state (for example a late PlanUpdated
      // scheduled just before cancellation).
      if (previous != null && previous.isTerminal && !_isTerminalState(state)) {
        return previous;
      }
      final sequence = await _nextSequence(taskId, previous);
      final now = _now();
      // A successful or re-started tool must not inherit the previous
      // attempt's error; a failed tool records its own (or keeps the stored
      // one when the controller is merely persisting task state).
      final clearToolError = lastToolStatus != CheckpointToolStatus.failed;
      final checkpoint = AgentCheckpoint(
        taskId: taskId,
        sequence: sequence,
        createdAt: now,
        contextHash: context.contextHash,
        projectRevision: context.projectRevision,
        workspaceRoot: context.workspaceRoot,
        plan: plan,
        toolCallCount: toolCallCount,
        pendingStepId: pendingStepId,
        request: request ?? previous?.request,
        metadata: context.metadata,
        lastToolName: lastToolName ?? previous?.lastToolName,
        lastToolIdempotent: lastToolIdempotent ?? previous?.lastToolIdempotent,
        lastToolArgumentsHash:
            lastToolArgumentsHash ?? previous?.lastToolArgumentsHash,
        lastToolStatus: lastToolStatus,
        lastToolErrorCode:
            lastToolErrorCode ??
            (clearToolError ? null : previous?.lastToolErrorCode),
        lastToolErrorMessage:
            lastToolErrorMessage ??
            (clearToolError ? null : previous?.lastToolErrorMessage),
        lastHeartbeatAt: now,
        runId: _runId,
        processId: _processId,
        resumeCount: resumeCount ?? previous?.resumeCount ?? 0,
        partialArtifacts:
            partialArtifacts ?? previous?.partialArtifacts ?? const <String>[],
        errorCode: errorCode,
        errorMessage: errorMessage,
        summary: summary,
        state: state,
      );
      await _store.save(checkpoint);
      return checkpoint;
    });
  }

  /// Written immediately before a tool is executed.
  Future<AgentCheckpoint> saveBeforeToolCall({
    required String taskId,
    required AgentContext context,
    required AgentPlan plan,
    required int toolCallCount,
    required String? pendingStepId,
    required String toolName,
    required bool toolIdempotent,
    required String argumentsHash,
    String? request,
  }) {
    return saveTaskState(
      taskId: taskId,
      context: context,
      state: AgentTaskState.acting,
      request: request,
      plan: plan,
      toolCallCount: toolCallCount,
      pendingStepId: pendingStepId,
      lastToolName: toolName,
      lastToolIdempotent: toolIdempotent,
      lastToolArgumentsHash: argumentsHash,
      lastToolStatus: CheckpointToolStatus.started,
    );
  }

  /// Written after every tool call (success or failure).
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
    String? request,
    bool toolSucceeded = true,
    String? toolErrorCode,
    String? toolErrorMessage,
    List<String>? partialArtifacts,
  }) {
    return saveTaskState(
      taskId: taskId,
      context: context,
      state: state,
      request: request,
      plan: plan,
      toolCallCount: toolCallCount,
      pendingStepId: pendingStepId,
      lastToolName: toolName,
      lastToolIdempotent: toolIdempotent,
      lastToolArgumentsHash: argumentsHash,
      lastToolStatus: toolSucceeded
          ? CheckpointToolStatus.succeeded
          : CheckpointToolStatus.failed,
      lastToolErrorCode: toolErrorCode,
      lastToolErrorMessage: toolErrorMessage,
      partialArtifacts: partialArtifacts,
    );
  }

  Future<AgentCheckpoint?> restore(String taskId) async {
    try {
      return await _store.latest(taskId);
    } on CheckpointCorruptException catch (error) {
      throw RecoveryException(
        code: ShadowErrorCode.storeCorrupt,
        message: error.message,
        taskId: taskId,
      );
    } catch (error) {
      throw RecoveryException(
        code: ShadowErrorCode.storeCorrupt,
        message: 'Unable to read checkpoint: $error',
        taskId: taskId,
      );
    }
  }

  Future<List<AgentCheckpoint>> history(String taskId, {int? limit}) async {
    try {
      return await _store.history(taskId, limit: limit ?? maxHistory);
    } on CheckpointCorruptException catch (error) {
      throw RecoveryException(
        code: ShadowErrorCode.storeCorrupt,
        message: error.message,
        taskId: taskId,
      );
    }
  }

  /// Non-terminal checkpoints that are no longer owned by a live process or
  /// have not sent a heartbeat within [staleAfter].
  Future<List<InterruptedTask>> detectInterrupted({
    Duration? staleAfter,
  }) async {
    final threshold = staleAfter ?? this.staleAfter;
    final now = _now();
    final latest = await _store.latestAll();
    final out = <InterruptedTask>[];
    for (final checkpoint in latest) {
      if (checkpoint.isTerminal) continue;
      if (checkpoint.runId == _runId) continue;
      final heartbeat = checkpoint.lastHeartbeatAt ?? checkpoint.createdAt;
      var age = now.difference(heartbeat);
      if (age.isNegative) age = Duration.zero;
      final orphanedProcess =
          checkpoint.processId != null && checkpoint.processId != _processId;
      final stale = age >= threshold;
      if (!orphanedProcess && !stale) continue;
      out.add(
        InterruptedTask(
          checkpoint: checkpoint,
          age: age,
          reason: orphanedProcess ? 'process_restart' : 'heartbeat_stale',
        ),
      );
    }
    out.sort((a, b) => b.age.compareTo(a.age));
    return out;
  }

  /// A structured view used by the failure inspector / resume UI.
  Future<RecoveryInspection> inspect({
    required String taskId,
    int? currentProjectRevision,
    String? workspaceRoot,
    String? expectedContextHash,
    bool allowNonIdempotentReplay = false,
    int? historyLimit,
  }) async {
    AgentCheckpoint? checkpoint;
    var history = <AgentCheckpoint>[];
    String? errorCode;
    String? errorMessage;
    try {
      checkpoint = await _store.latest(taskId);
      if (checkpoint != null) {
        history = await _store.history(
          taskId,
          limit: historyLimit ?? maxHistory,
        );
      }
    } on CheckpointCorruptException catch (error) {
      errorCode = ShadowErrorCode.storeCorrupt;
      errorMessage = error.message;
    } catch (error) {
      errorCode = ShadowErrorCode.storeCorrupt;
      errorMessage = 'Unable to read checkpoint: $error';
    }

    final blockers = checkpoint == null
        ? <RecoveryBlocker>[
            const RecoveryBlocker(
              ShadowErrorCode.agentCheckpointMissing,
              'No checkpoint exists for this task',
            ),
          ]
        : _resumeBlockers(
            checkpoint: checkpoint,
            currentProjectRevision: currentProjectRevision,
            workspaceRoot: workspaceRoot,
            expectedContextHash: expectedContextHash,
            allowNonIdempotentReplay: allowNonIdempotentReplay,
          );
    var partials = const <String>[];
    if (checkpoint != null) {
      try {
        partials = await existingPartialArtifacts(checkpoint);
      } on RecoveryException catch (error) {
        blockers.add(RecoveryBlocker(error.code, error.message));
      }
    }

    return RecoveryInspection(
      taskId: taskId,
      exists: checkpoint != null,
      checkpoint: checkpoint,
      history: history,
      isTerminal: checkpoint?.isTerminal ?? false,
      isInterrupted:
          checkpoint != null && _isInterrupted(checkpoint, staleAfter),
      blockers: blockers,
      partialArtifacts: partials,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  /// Validates the checkpoint and returns the plan the loop should continue.
  ///
  /// Throws [RecoveryException] for every blocker. Partial artifacts are only
  /// deleted when [discardPartialOutputs] is explicitly true.
  Future<ResumePlan> planResume({
    required AgentCheckpoint checkpoint,
    required String workspaceRoot,
    required int currentProjectRevision,
    String? expectedContextHash,
    bool allowNonIdempotentReplay = false,
    bool discardPartialOutputs = false,
  }) async {
    final blockers = _resumeBlockers(
      checkpoint: checkpoint,
      currentProjectRevision: currentProjectRevision,
      workspaceRoot: workspaceRoot,
      expectedContextHash: expectedContextHash,
      allowNonIdempotentReplay: allowNonIdempotentReplay,
    );
    if (blockers.isNotEmpty) {
      throw RecoveryException(
        code: blockers.first.code,
        message: blockers.map((b) => b.message).join('; '),
        taskId: checkpoint.taskId,
      );
    }

    final partials = await existingPartialArtifacts(checkpoint);
    final discarded = <String>[];
    final warnings = <String>[];
    if (discardPartialOutputs) {
      for (final artifact in partials) {
        final resolved = await _resolveArtifact(
          artifact: artifact,
          workspaceRoot: checkpoint.workspaceRoot,
        );
        final type = await FileSystemEntity.type(resolved.path);
        if (type != FileSystemEntityType.file) {
          warnings.add('Skipped non-file partial output: $artifact');
          continue;
        }
        await resolved.delete();
        discarded.add(artifact);
      }
    } else if (partials.isNotEmpty) {
      warnings.add(
        '${partials.length} partial output(s) exist; pass discardPartialOutputs:true to remove them.',
      );
    }

    return ResumePlan(
      checkpoint: checkpoint,
      plan: checkpoint.plan,
      resumeCount: checkpoint.resumeCount + 1,
      partialArtifacts: partials,
      discardedPartialArtifacts: discarded,
      warnings: warnings,
    );
  }

  List<RecoveryBlocker> _resumeBlockers({
    required AgentCheckpoint checkpoint,
    int? currentProjectRevision,
    String? workspaceRoot,
    String? expectedContextHash,
    required bool allowNonIdempotentReplay,
  }) {
    final blockers = <RecoveryBlocker>[];
    if (checkpoint.isTerminal) {
      blockers.add(
        RecoveryBlocker(
          ShadowErrorCode.agentCheckpointMissing,
          'Task already reached terminal state ${checkpoint.state.name}',
        ),
      );
    }
    if (workspaceRoot != null && checkpoint.workspaceRoot != workspaceRoot) {
      blockers.add(
        RecoveryBlocker(
          ShadowErrorCode.agentCheckpointMissing,
          'Workspace changed: checkpoint=${checkpoint.workspaceRoot} current=$workspaceRoot',
        ),
      );
    }
    if (currentProjectRevision != null &&
        checkpoint.projectRevision != currentProjectRevision) {
      blockers.add(
        RecoveryBlocker(
          ShadowErrorCode.editRevisionMismatch,
          'Project revision changed: checkpoint=${checkpoint.projectRevision} current=$currentProjectRevision',
        ),
      );
    }
    if (expectedContextHash != null &&
        checkpoint.contextHash != expectedContextHash) {
      blockers.add(
        const RecoveryBlocker(
          ShadowErrorCode.agentCheckpointMissing,
          'Context metadata changed since the checkpoint',
        ),
      );
    }
    if (checkpoint.plan.steps.isEmpty) {
      // A crash during initial planning is safe to resume by replanning: no
      // tool has run. An empty plan after tool calls means the plan was lost.
      if (checkpoint.toolCallCount > 0) {
        blockers.add(
          const RecoveryBlocker(
            ShadowErrorCode.agentCheckpointMissing,
            'Checkpoint lost its plan after executing tools',
          ),
        );
      }
    } else if (checkpoint.plan.steps.every((s) => s.isTerminal)) {
      blockers.add(
        const RecoveryBlocker(
          ShadowErrorCode.agentCheckpointMissing,
          'Plan is already complete; nothing to resume',
        ),
      );
    }
    if (checkpoint.requiresReplayConfirmation && !allowNonIdempotentReplay) {
      blockers.add(
        RecoveryBlocker(
          ShadowErrorCode.toolNotIdempotentRetry,
          'Tool ${checkpoint.lastToolName} was in flight and is not idempotent; explicit confirmation is required before retrying',
        ),
      );
    }
    return blockers;
  }

  static bool _isTerminalState(AgentTaskState state) =>
      state == AgentTaskState.succeeded ||
      state == AgentTaskState.failed ||
      state == AgentTaskState.cancelled;

  bool _isInterrupted(AgentCheckpoint checkpoint, Duration threshold) {
    if (checkpoint.isTerminal) return false;
    if (checkpoint.runId == _runId) return false;
    final heartbeat = checkpoint.lastHeartbeatAt ?? checkpoint.createdAt;
    final age = _now().difference(heartbeat);
    final orphaned =
        checkpoint.processId != null && checkpoint.processId != _processId;
    return orphaned || age >= threshold;
  }

  /// Existing partial artifacts, resolved and contained in the workspace.
  Future<List<String>> existingPartialArtifacts(
    AgentCheckpoint checkpoint,
  ) async {
    final out = <String>[];
    for (final artifact in checkpoint.partialArtifacts) {
      final resolved = await _resolveArtifact(
        artifact: artifact,
        workspaceRoot: checkpoint.workspaceRoot,
      );
      if (await resolved.exists()) out.add(artifact);
    }
    return out;
  }

  Future<File> _resolveArtifact({
    required String artifact,
    required String workspaceRoot,
  }) async {
    if (artifact.trim().isEmpty || artifact.contains('\u0000')) {
      throw RecoveryException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Invalid partial artifact path',
      );
    }
    final root = p.normalize(p.absolute(workspaceRoot));
    final candidate = p.isAbsolute(artifact)
        ? p.normalize(artifact)
        : p.normalize(p.join(root, artifact));
    if (!_isWithin(root, candidate)) {
      throw RecoveryException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Partial artifact escapes workspace: $artifact',
      );
    }
    final type = await FileSystemEntity.type(candidate, followLinks: true);
    if (type == FileSystemEntityType.notFound) return File(candidate);
    final resolved = p.normalize(await File(candidate).resolveSymbolicLinks());
    if (!_isWithin(root, resolved)) {
      throw RecoveryException(
        code: ShadowErrorCode.permPathEscape,
        message: 'Partial artifact symlink escapes workspace: $artifact',
      );
    }
    return File(resolved);
  }

  bool _isWithin(String root, String target) {
    final normalizedRoot = p.normalize(root);
    final normalizedTarget = p.normalize(target);
    if (normalizedTarget == normalizedRoot) return true;
    final prefix = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';
    return normalizedTarget.startsWith(prefix);
  }

  /// Validates a checkpoint against current project state.
  ///
  /// Kept for callers that only have revision/workspace; [expectedContextHash]
  /// additionally binds metadata.
  void validateForResume({
    required AgentCheckpoint checkpoint,
    required int currentProjectRevision,
    required String currentWorkspaceRoot,
    String? expectedContextHash,
  }) {
    final blockers = _resumeBlockers(
      checkpoint: checkpoint,
      currentProjectRevision: currentProjectRevision,
      workspaceRoot: currentWorkspaceRoot,
      expectedContextHash: expectedContextHash,
      allowNonIdempotentReplay: false,
    );
    if (blockers.isNotEmpty) {
      final first = blockers.first;
      final error = StateError('${first.code}: ${first.message}');
      throw error;
    }
  }

  /// Ensures we never silently repeat a non-idempotent operation on resume.
  ///
  /// Conservative by design: even a completed non-idempotent tool blocks blind
  /// replay because the resumed model turn may request the same call again.
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
