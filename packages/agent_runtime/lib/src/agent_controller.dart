import 'dart:async';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

import 'agent_context.dart';
import 'package:shadow_context_engine/context_engine.dart';

import 'agent_context_assembler.dart';
import 'agent_events.dart';
import 'agent_limits.dart';
import 'execution_loop.dart';
import 'recovery_manager.dart';
import 'task_scheduler.dart';

enum ManagedTaskState {
  queued,
  planning,
  acting,
  awaitingApproval,
  succeeded,
  failed,
  cancelled,
}

@immutable
class ManagedTask {
  const ManagedTask({
    required this.id,
    required this.request,
    required this.context,
    required this.state,
    required this.createdAt,
    this.plan,
    this.errorCode,
    this.errorMessage,
    this.summary,
  });

  final String id;
  final String request;
  final AgentContext context;
  final ManagedTaskState state;
  final DateTime createdAt;
  final AgentPlan? plan;
  final String? errorCode;
  final String? errorMessage;
  final String? summary;

  bool get isTerminal =>
      state == ManagedTaskState.succeeded ||
      state == ManagedTaskState.failed ||
      state == ManagedTaskState.cancelled;

  ManagedTask copyWith({
    ManagedTaskState? state,
    AgentPlan? plan,
    String? errorCode,
    String? errorMessage,
    String? summary,
  }) {
    return ManagedTask(
      id: id,
      request: request,
      context: context,
      state: state ?? this.state,
      createdAt: createdAt,
      plan: plan ?? this.plan,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      summary: summary ?? this.summary,
    );
  }
}

class AgentController {
  AgentController({
    required AgentBrain brain,
    required ToolCallExecutor toolExecutor,
    RecoveryManager? recoveryManager,
    TaskScheduler? scheduler,
    AgentRuntimeLimits limits = const AgentRuntimeLimits(),
    AuditSink? audit,
    ApprovalGate? approvalGate,
    AgentContextAssembler? contextAssembler,
    AgentContextHolder? contextHolder,
  }) : _brain = brain,
       _toolExecutor = toolExecutor,
       _recoveryManager = recoveryManager ?? RecoveryManager(),
       _scheduler = scheduler ?? TaskScheduler(),
       _limits = limits,
       _audit = audit ?? _NoopAuditSink(),
       _approvalGate = approvalGate,
       _contextAssembler = contextAssembler ?? AgentContextAssembler(),
       _contextHolder = contextHolder ?? AgentContextHolder() {
    _loop = ExecutionLoop(
      limits: _limits,
      brain: _brain,
      toolExecutor: _toolExecutor,
      recoveryManager: _recoveryManager,
      approvalGate: _approvalGate,
      contextAssembler: _contextAssembler,
      contextHolder: _contextHolder,
      emit: _handleLoopEvent,
    );
  }

  final AgentBrain _brain;
  final ToolCallExecutor _toolExecutor;
  final RecoveryManager _recoveryManager;
  final TaskScheduler _scheduler;
  final AgentRuntimeLimits _limits;
  final AuditSink _audit;
  final ApprovalGate? _approvalGate;
  final AgentContextHolder _contextHolder;
  final AgentContextAssembler _contextAssembler;
  late final ExecutionLoop _loop;

  final StreamController<AgentRuntimeEvent> _events =
      StreamController<AgentRuntimeEvent>.broadcast();
  final Map<String, ManagedTask> _tasks = <String, ManagedTask>{};
  final Map<String, CancellationToken> _tokens = <String, CancellationToken>{};
  final Map<String, Future<void>> _running = <String, Future<void>>{};
  final Map<String, int> _resumeCounts = <String, int>{};
  bool _disposed = false;
  String? _lastPersistenceError;
  int _idSeq = 0;

  /// Last checkpoint write failure, if any. Execution continues (the in-memory
  /// task is still usable) but the task is no longer crash-recoverable.
  String? get lastPersistenceError => _lastPersistenceError;

  Stream<AgentRuntimeEvent> get events => _events.stream;
  TaskScheduler get scheduler => _scheduler;
  RecoveryManager get recoveryManager => _recoveryManager;
  AgentRuntimeLimits get limits => _limits;

  /// Context snapshot of the most recent task turn, or null before any tool ran.
  ContextSnapshot? get contextSnapshot => _contextHolder.snapshot;

  /// The live holder, for layers that need to read the snapshot per turn.
  AgentContextHolder get contextHolder => _contextHolder;

  ManagedTask? task(String id) => _tasks[id];
  List<ManagedTask> get tasks => List<ManagedTask>.unmodifiable(_tasks.values);

  ManagedTask createTask({
    required String request,
    required String workspaceRoot,
    required int projectRevision,
    Map<String, Object?> metadata = const <String, Object?>{},
    String? taskId,
  }) {
    final id = taskId ?? _nextId();
    final ctx = AgentContext(
      taskId: id,
      workspaceRoot: workspaceRoot,
      projectRevision: projectRevision,
      metadata: metadata,
    );
    final managed = ManagedTask(
      id: id,
      request: request,
      context: ctx,
      state: ManagedTaskState.queued,
      createdAt: DateTime.now().toUtc(),
    );
    _tasks[id] = managed;
    _scheduler.enqueue(
      id: id,
      request: request,
      workspaceRoot: workspaceRoot,
      projectRevision: projectRevision,
    );
    // Fire-and-forget: task creation is synchronous, but the queued state must
    // be durable before the process can crash.
    unawaited(
      _persistQuietly(
        id,
        state: AgentTaskState.queued,
        plan: const AgentPlan(steps: <PlanStep>[], revision: 0),
      ),
    );
    // kick off if this became active
    _maybeStartActive();
    return managed;
  }

  void _maybeStartActive() {
    if (_disposed) return;
    final active = _scheduler.active;
    if (active == null) return;
    final managed = _tasks[active.id];
    if (managed == null || managed.state != ManagedTaskState.queued) return;
    // Completion is handled internally; keep the future so dispose() can wait
    // for terminal checkpoints instead of racing them.
    final future = _runTask(active.id);
    _running[active.id] = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_running[active.id], future)) _running.remove(active.id);
      }),
    );
  }

  Future<void> _runTask(String taskId) async {
    final managed = _tasks[taskId];
    if (managed == null) return;
    final token = CancellationToken();
    _tokens[taskId] = token;

    _contextHolder.snapshot = null;
    _setState(taskId, ManagedTaskState.planning);
    unawaited(_persistQuietly(taskId, state: AgentTaskState.planning));
    _emit(
      TaskStarted(
        taskId: taskId,
        timestamp: DateTime.now().toUtc(),
        request: managed.request,
        workspaceRoot: managed.context.workspaceRoot,
        projectRevision: managed.context.projectRevision,
      ),
    );

    _setState(taskId, ManagedTaskState.acting);
    final outcome = await _loop.run(
      taskId: taskId,
      request: managed.request,
      context: managed.context,
      cancel: token,
      audit: _audit,
      // A restored task continues its validated plan instead of asking the
      // model to plan from scratch. A task interrupted before any plan existed
      // passes null so the loop plans normally.
      resumePlan: (managed.plan?.steps.isEmpty ?? true) ? null : managed.plan,
    );

    switch (outcome.state) {
      case AgentTaskState.succeeded:
        _setState(taskId, ManagedTaskState.succeeded, summary: outcome.summary);
        break;
      case AgentTaskState.failed:
        _setState(
          taskId,
          ManagedTaskState.failed,
          errorCode: outcome.errorCode,
          errorMessage: outcome.errorMessage,
        );
        break;
      case AgentTaskState.cancelled:
        _setState(
          taskId,
          ManagedTaskState.cancelled,
          errorMessage: outcome.errorMessage,
        );
        // ensure cancelled event emitted if loop didn't
        break;
      default:
        _setState(
          taskId,
          ManagedTaskState.failed,
          errorCode: ShadowErrorCode.toolFailed,
          errorMessage: 'Unexpected terminal state',
        );
    }

    await _persistQuietly(
      taskId,
      state: outcome.state,
      errorCode: outcome.errorCode,
      errorMessage: outcome.errorMessage,
      summary: outcome.summary,
    );

    _tokens.remove(taskId);
    _scheduler.completeActive(taskId);
    _maybeStartActive();
  }

  Future<void> cancelTask(String taskId, {String? reason}) async {
    final found = _scheduler.cancel(taskId, reason: reason);
    final token = _tokens[taskId];
    token?.cancel(reason ?? 'cancelled');
    if (found && _tasks[taskId]?.state == ManagedTaskState.queued) {
      _setState(taskId, ManagedTaskState.cancelled, errorMessage: reason);
      _emit(
        TaskCancelled(
          taskId: taskId,
          timestamp: DateTime.now().toUtc(),
          reason: reason,
        ),
      );
      await _persistQuietly(
        taskId,
        state: AgentTaskState.cancelled,
        errorMessage: reason,
      );
    }
  }

  /// Non-terminal checkpoints that belong to a dead process or stopped
  /// heartbeating. The UI uses this to offer manual resume.
  Future<List<InterruptedTask>> interruptedTasks() =>
      _recoveryManager.detectInterrupted();

  /// Inspection views (history, blockers, partial outputs) for every
  /// interrupted task.
  Future<List<RecoveryInspection>> inspectInterrupted() async {
    final interrupted = await interruptedTasks();
    final out = <RecoveryInspection>[];
    for (final item in interrupted) {
      out.add(await _recoveryManager.inspect(taskId: item.checkpoint.taskId));
    }
    return out;
  }

  Future<RecoveryInspection> inspectTask(
    String taskId, {
    int? currentProjectRevision,
    String? workspaceRoot,
    bool allowNonIdempotentReplay = false,
  }) => _recoveryManager.inspect(
    taskId: taskId,
    currentProjectRevision: currentProjectRevision,
    workspaceRoot: workspaceRoot,
    allowNonIdempotentReplay: allowNonIdempotentReplay,
  );

  /// Resumes a task using the request/workspace/revision stored in its
  /// checkpoint. Validates everything before scheduling the loop again.
  Future<ManagedTask> resumeTask({
    required String taskId,
    String? workspaceRoot,
    int? currentProjectRevision,
    String? request,
    bool allowNonIdempotentReplay = false,
    bool discardPartialOutputs = false,
  }) async {
    final cp = await _recoveryManager.restore(taskId);
    if (cp == null) {
      throw RecoveryException(
        code: ShadowErrorCode.agentCheckpointMissing,
        message: 'No checkpoint exists for $taskId',
        taskId: taskId,
      );
    }
    final resolvedWorkspace = workspaceRoot ?? cp.workspaceRoot;
    final resolvedRevision = currentProjectRevision ?? cp.projectRevision;
    final ctx = AgentContext(
      taskId: taskId,
      workspaceRoot: resolvedWorkspace,
      projectRevision: resolvedRevision,
      metadata: cp.metadata,
    );
    final resume = await _recoveryManager.planResume(
      checkpoint: cp,
      workspaceRoot: resolvedWorkspace,
      currentProjectRevision: resolvedRevision,
      expectedContextHash: ctx.contextHash,
      allowNonIdempotentReplay: allowNonIdempotentReplay,
      discardPartialOutputs: discardPartialOutputs,
    );

    final managed = ManagedTask(
      id: taskId,
      request: request ?? cp.request ?? '',
      context: ctx,
      state: ManagedTaskState.queued,
      createdAt: cp.createdAt,
      plan: resume.plan,
    );
    _tasks[taskId] = managed;
    _resumeCounts[taskId] = resume.resumeCount;
    // Persist the resumed state before scheduling, so the loop cannot start
    // from (and later overwrite) the pre-restart checkpoint.
    await _persistQuietly(
      taskId,
      state: AgentTaskState.queued,
      plan: resume.plan,
      resumeCount: resume.resumeCount,
      // Explicitly discarded partial files must not stay advertised on the
      // resumed checkpoint.
      partialArtifacts: discardPartialOutputs ? const <String>[] : null,
    );
    _scheduler.enqueue(
      id: taskId,
      request: managed.request,
      workspaceRoot: resolvedWorkspace,
      projectRevision: resolvedRevision,
    );
    _maybeStartActive();
    return managed;
  }

  /// Restores an interrupted task from its last checkpoint if valid.
  Future<ManagedTask> restoreTask({
    required String taskId,
    required String request,
    required String workspaceRoot,
    required int currentProjectRevision,
  }) => resumeTask(
    taskId: taskId,
    request: request,
    workspaceRoot: workspaceRoot,
    currentProjectRevision: currentProjectRevision,
  );

  Future<void> _persistQuietly(
    String taskId, {
    AgentTaskState? state,
    AgentPlan? plan,
    String? errorCode,
    String? errorMessage,
    String? summary,
    int? resumeCount,
    List<String>? partialArtifacts,
  }) async {
    try {
      await _persist(
        taskId,
        state: state,
        plan: plan,
        errorCode: errorCode,
        errorMessage: errorMessage,
        summary: summary,
        resumeCount: resumeCount,
        partialArtifacts: partialArtifacts,
      );
    } catch (error) {
      _lastPersistenceError = error.toString();
    }
  }

  Future<void> _persist(
    String taskId, {
    AgentTaskState? state,
    AgentPlan? plan,
    String? errorCode,
    String? errorMessage,
    String? summary,
    int? resumeCount,
    List<String>? partialArtifacts,
  }) async {
    final task = _tasks[taskId];
    if (task == null) return;
    final latest = await _recoveryManager.restore(taskId);
    await _recoveryManager.saveTaskState(
      taskId: taskId,
      context: task.context,
      state: state ?? task.state.toAgentTaskState(),
      request: task.request,
      plan:
          plan ??
          task.plan ??
          const AgentPlan(steps: <PlanStep>[], revision: 0),
      toolCallCount: latest?.toolCallCount ?? 0,
      pendingStepId: latest?.pendingStepId,
      lastToolName: latest?.lastToolName,
      lastToolIdempotent: latest?.lastToolIdempotent,
      lastToolArgumentsHash: latest?.lastToolArgumentsHash,
      lastToolStatus: latest?.lastToolStatus ?? CheckpointToolStatus.none,
      lastToolErrorCode: latest?.lastToolErrorCode,
      lastToolErrorMessage: latest?.lastToolErrorMessage,
      resumeCount:
          resumeCount ?? _resumeCounts[taskId] ?? latest?.resumeCount ?? 0,
      partialArtifacts: partialArtifacts ?? latest?.partialArtifacts,
      errorCode: errorCode,
      errorMessage: errorMessage,
      summary: summary,
    );
    _lastPersistenceError = null;
  }

  void _handleLoopEvent(AgentRuntimeEvent event) {
    if (event is ApprovalRequested) {
      _setState(event.taskId, ManagedTaskState.awaitingApproval);
    } else if (event is ToolExecutionStarted || event is StepStarted) {
      final current = _tasks[event.taskId];
      if (current != null &&
          current.state == ManagedTaskState.awaitingApproval) {
        _setState(event.taskId, ManagedTaskState.acting);
      }
    }
    if (event is PlanUpdated) {
      final current = _tasks[event.taskId];
      if (current != null) {
        final plan = AgentPlan(steps: event.steps, revision: event.revision);
        _tasks[event.taskId] = current.copyWith(plan: plan);
        unawaited(
          _persistQuietly(
            event.taskId,
            state: AgentTaskState.acting,
            plan: plan,
          ),
        );
      }
    }
    _emit(event);
  }

  void _setState(
    String taskId,
    ManagedTaskState state, {
    String? errorCode,
    String? errorMessage,
    String? summary,
  }) {
    final current = _tasks[taskId];
    if (current == null) return;
    _tasks[taskId] = current.copyWith(
      state: state,
      errorCode: errorCode,
      errorMessage: errorMessage,
      summary: summary,
    );
  }

  void _emit(AgentRuntimeEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  String _nextId() =>
      'task_${DateTime.now().microsecondsSinceEpoch}_${++_idSeq}';

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final t in _tokens.values) {
      t.cancel('disposed');
    }
    for (final future in _running.values.toList()) {
      try {
        await future;
      } catch (_) {
        // A task failure must not prevent the rest of teardown.
      }
    }
    await _scheduler.dispose();
    await _events.close();
  }
}

extension on ManagedTaskState {
  AgentTaskState toAgentTaskState() => switch (this) {
    ManagedTaskState.queued => AgentTaskState.queued,
    ManagedTaskState.planning => AgentTaskState.planning,
    ManagedTaskState.acting => AgentTaskState.acting,
    ManagedTaskState.awaitingApproval => AgentTaskState.awaitingApproval,
    ManagedTaskState.succeeded => AgentTaskState.succeeded,
    ManagedTaskState.failed => AgentTaskState.failed,
    ManagedTaskState.cancelled => AgentTaskState.cancelled,
  };
}

class _NoopAuditSink implements AuditSink {
  @override
  Future<void> record(Map<String, Object?> event) async {}
}
