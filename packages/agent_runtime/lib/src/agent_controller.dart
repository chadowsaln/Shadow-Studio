import 'dart:async';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

import 'agent_context.dart';
import 'agent_events.dart';
import 'agent_limits.dart';
import 'execution_loop.dart';
import 'planner.dart';
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
  })  : _brain = brain,
        _toolExecutor = toolExecutor,
        _recoveryManager = recoveryManager ?? RecoveryManager(),
        _scheduler = scheduler ?? TaskScheduler(),
        _limits = limits,
        _audit = audit ?? _NoopAuditSink(),
        _approvalGate = approvalGate {
    _loop = ExecutionLoop(
      limits: _limits,
      brain: _brain,
      toolExecutor: _toolExecutor,
      recoveryManager: _recoveryManager,
      approvalGate: _approvalGate,
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
  late final ExecutionLoop _loop;

  final StreamController<AgentRuntimeEvent> _events =
      StreamController<AgentRuntimeEvent>.broadcast();
  final Map<String, ManagedTask> _tasks = <String, ManagedTask>{};
  final Map<String, CancellationToken> _tokens = <String, CancellationToken>{};
  int _idSeq = 0;

  Stream<AgentRuntimeEvent> get events => _events.stream;
  TaskScheduler get scheduler => _scheduler;
  RecoveryManager get recoveryManager => _recoveryManager;
  AgentRuntimeLimits get limits => _limits;

  ManagedTask? task(String id) => _tasks[id];
  List<ManagedTask> get tasks => List<ManagedTask>.unmodifiable(_tasks.values);

  ManagedTask createTask({
    required String request,
    required String workspaceRoot,
    required int projectRevision,
    String? taskId,
  }) {
    final id = taskId ?? _nextId();
    final ctx = AgentContext(
      taskId: id,
      workspaceRoot: workspaceRoot,
      projectRevision: projectRevision,
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
    // kick off if this became active
    _maybeStartActive();
    return managed;
  }

  void _maybeStartActive() {
    final active = _scheduler.active;
    if (active == null) return;
    final managed = _tasks[active.id];
    if (managed == null || managed.state != ManagedTaskState.queued) return;
    // fire and forget; completion handled internally
    unawaited(_runTask(active.id));
  }

  Future<void> _runTask(String taskId) async {
    final managed = _tasks[taskId];
    if (managed == null) return;
    final token = CancellationToken();
    _tokens[taskId] = token;

    _setState(taskId, ManagedTaskState.planning);
    _emit(TaskStarted(
      taskId: taskId,
      timestamp: DateTime.now().toUtc(),
      request: managed.request,
      workspaceRoot: managed.context.workspaceRoot,
      projectRevision: managed.context.projectRevision,
    ));

    _setState(taskId, ManagedTaskState.acting);
    final outcome = await _loop.run(
      taskId: taskId,
      request: managed.request,
      context: managed.context,
      cancel: token,
      audit: _audit,
    );

    switch (outcome.state) {
      case AgentTaskState.succeeded:
        _setState(taskId, ManagedTaskState.succeeded, summary: outcome.summary);
        break;
      case AgentTaskState.failed:
        _setState(taskId, ManagedTaskState.failed,
            errorCode: outcome.errorCode, errorMessage: outcome.errorMessage);
        break;
      case AgentTaskState.cancelled:
        _setState(taskId, ManagedTaskState.cancelled,
            errorMessage: outcome.errorMessage);
        // ensure cancelled event emitted if loop didn't
        break;
      default:
        _setState(taskId, ManagedTaskState.failed,
            errorCode: ShadowErrorCode.toolFailed, errorMessage: 'Unexpected terminal state');
    }

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
      _emit(TaskCancelled(taskId: taskId, timestamp: DateTime.now().toUtc(), reason: reason));
    }
  }

  /// Restores an interrupted task from its last checkpoint if valid.
  Future<ManagedTask> restoreTask({
    required String taskId,
    required String request,
    required String workspaceRoot,
    required int currentProjectRevision,
  }) async {
    final cp = await _recoveryManager.restore(taskId);
    if (cp == null) {
      throw StateError(ShadowErrorCode.agentCheckpointMissing);
    }
    _recoveryManager.validateForResume(
      checkpoint: cp,
      currentProjectRevision: currentProjectRevision,
      currentWorkspaceRoot: workspaceRoot,
    );
    _recoveryManager.assertSafeToRepeatLastTool(cp);
    final ctx = AgentContext(
      taskId: taskId,
      workspaceRoot: workspaceRoot,
      projectRevision: currentProjectRevision,
    );
    final managed = ManagedTask(
      id: taskId,
      request: request,
      context: ctx,
      state: ManagedTaskState.queued,
      createdAt: DateTime.now().toUtc(),
      plan: cp.plan,
    );
    _tasks[taskId] = managed;
    _scheduler.enqueue(
      id: taskId,
      request: request,
      workspaceRoot: workspaceRoot,
      projectRevision: currentProjectRevision,
    );
    _maybeStartActive();
    return managed;
  }

  void _handleLoopEvent(AgentRuntimeEvent event) {
    if (event is ApprovalRequested) {
      _setState(event.taskId, ManagedTaskState.awaitingApproval);
    } else if (event is ToolExecutionStarted || event is StepStarted) {
      final current = _tasks[event.taskId];
      if (current != null && current.state == ManagedTaskState.awaitingApproval) {
        _setState(event.taskId, ManagedTaskState.acting);
      }
    }
    if (event is PlanUpdated) {
      final current = _tasks[event.taskId];
      if (current != null) {
        _tasks[event.taskId] = current.copyWith(plan: AgentPlan(steps: event.steps, revision: event.revision));
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
    if (!_events.isClosed) _events.add(event);
  }

  String _nextId() => 'task_${DateTime.now().microsecondsSinceEpoch}_${++_idSeq}';

  Future<void> dispose() async {
    for (final t in _tokens.values) {
      t.cancel('disposed');
    }
    await _events.close();
    await _scheduler.dispose();
  }
}

class _NoopAuditSink implements AuditSink {
  @override
  Future<void> record(Map<String, Object?> event) async {}
}
