import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../agent_controller.dart';
import '../agent_events.dart';
import '../agent_limits.dart';
import 'agent_message.dart';
import 'agent_role.dart';
import 'shared_task_state.dart';
import 'specialized_agent.dart';

/// One unit of work handed to a specialized agent.
class AgentAssignment {
  const AgentAssignment({
    required this.role,
    required this.request,
    this.inbound,
    this.expectedArtifacts = const <String, Object?>{},
  });

  final AgentRole role;
  final String request;
  final AgentMessage? inbound;
  final Map<String, Object?> expectedArtifacts;
}

/// Result of one assignment, including the managed sub-task state.
class AssignmentOutcome {
  const AssignmentOutcome({
    required this.role,
    required this.taskId,
    required this.state,
    required this.summary,
    this.errorCode,
    this.errorMessage,
  });

  final AgentRole role;
  final String taskId;
  final SharedTaskStatus state;
  final String? summary;
  final String? errorCode;
  final String? errorMessage;

  bool get succeeded => state == SharedTaskStatus.completed;
}

/// Coordinates several specialized agents over one shared task.
///
/// The coordinator is the only writer of [SharedTaskState]: agents talk to each
/// other through structured [AgentMessage]s that the coordinator records and
/// routes, and every sub-task result is folded back into shared artifacts and
/// the project revision. Nothing here executes media or edits on its own.
class MultiAgentCoordinator {
  MultiAgentCoordinator({
    required this.taskId,
    required this.goal,
    required this.workspaceRoot,
    required int projectRevision,
    required AgentBrain Function(AgentRole role) brainFactory,
    required ToolCallExecutor toolExecutor,
    this.limits = const AgentRuntimeLimits(),
    AuditSink? audit,
    this.approvalGate,
    SharedTaskStatus initialStatus = SharedTaskStatus.created,
  }) : _state = SharedTaskState(
         taskId: taskId,
         goal: goal,
         workspaceRoot: workspaceRoot,
         projectRevision: projectRevision,
         status: initialStatus,
       ),
       _brainFactory = brainFactory,
       _toolExecutor = toolExecutor,
       _audit = audit ?? _NoopAuditSink();

  final String taskId;
  final String goal;
  final String workspaceRoot;
  final AgentBrain Function(AgentRole role) _brainFactory;
  final ToolCallExecutor _toolExecutor;
  final AgentRuntimeLimits limits;
  final AuditSink _audit;
  final ApprovalGate? approvalGate;

  final SharedTaskState _state;
  final Map<AgentRole, SpecializedAgent> _agents =
      <AgentRole, SpecializedAgent>{};
  final Map<String, AgentRole> _taskOwners = <String, AgentRole>{};
  final List<StreamSubscription<Object>> _subscriptions =
      <StreamSubscription<Object>>[];
  int _assignmentSeq = 0;

  SharedTaskState get state => _state;
  List<AgentMessage> get messages => _state.messages;
  Map<String, Object?> get artifacts => _state.artifacts;
  int get projectRevision => _state.projectRevision;
  SharedTaskStatus get status => _state.status;

  SpecializedAgent agent(AgentRole role) {
    final existing = _agents[role];
    if (existing != null) return existing;
    final allowed = role.defaultTools;
    final ToolCallExecutor executor = allowed.isEmpty
        ? _toolExecutor
        : RoleToolFilter(delegate: _toolExecutor, allowedTools: allowed);
    final created = SpecializedAgent(
      role: role,
      controllerFactory: () => AgentController(
        brain: _brainFactory(role),
        toolExecutor: executor,
        limits: limits,
        audit: _audit,
        approvalGate: approvalGate,
      ),
    );
    _agents[role] = created;
    _subscriptions.add(_observe(created));
    return created;
  }

  StreamSubscription<Object> _observe(SpecializedAgent agent) {
    return agent.controller.events.listen((event) {
      _taskOwners[event.taskId] = agent.role;
      if (event is ToolExecutionCompleted) {
        _state.updateRole(agent.role, status: 'running');
        final revision = event.result.data['revision'];
        if (event.result.success && revision is int) {
          updateProjectRevision(revision);
        }
      } else if (event is TaskCompleted) {
        _state.updateRole(agent.role, status: 'completed');
        dispatch(
          AgentMessage(
            id: 'artifact_${event.taskId}',
            taskId: taskId,
            from: agent.role,
            type: AgentMessageType.result,
            content: <String, Object?>{
              'task_id': event.taskId,
              'summary': event.summary,
              'artifacts': event.result,
            },
            createdAt: event.timestamp,
          ),
        );
        _state.setArtifact('${agent.role.id}.result', event.result);
      } else if (event is TaskFailed) {
        _state.updateRole(agent.role, status: 'failed');
        _state.setArtifact('${agent.role.id}.error', <String, Object?>{
          'code': event.code,
          'message': event.message,
        });
      } else if (event is TaskCancelled) {
        _state.updateRole(agent.role, status: 'cancelled');
      } else if (event is ApprovalRequested) {
        _state.setStatus(SharedTaskStatus.awaitingApproval);
      }
    });
  }

  /// Records and routes a structured message between agents.
  AgentMessage dispatch(AgentMessage message) {
    if (message.taskId != taskId) {
      throw ArgumentError.value(
        message.taskId,
        'message.taskId',
        'does not match coordinator task $taskId',
      );
    }
    _state.recordMessage(message);
    _state.absorbArtifacts(message);
    return message;
  }

  /// Creates a message from [from] and records it.
  AgentMessage send({
    required AgentRole from,
    AgentRole? to,
    required AgentMessageType type,
    required Map<String, Object?> content,
  }) {
    final message = AgentMessage(
      id: 'msg_${_state.messages.length + 1}_$_assignmentSeq',
      taskId: taskId,
      from: from,
      to: to,
      type: type,
      content: content,
      createdAt: DateTime.now().toUtc(),
    );
    return dispatch(message);
  }

  /// Runs one assignment and folds its outcome into the shared state.
  Future<AssignmentOutcome> assign(AgentAssignment assignment) async {
    _state.setStatus(SharedTaskStatus.inProgress);
    final worker = agent(assignment.role);
    final subTaskId = '${taskId}_${assignment.role.id}_${++_assignmentSeq}';
    _taskOwners[subTaskId] = assignment.role;

    if (assignment.inbound != null) {
      dispatch(assignment.inbound!);
    }

    final managed = await worker.run(
      request: assignment.request,
      workspaceRoot: workspaceRoot,
      projectRevision: _state.projectRevision,
      inbound: assignment.inbound,
    );

    if (managed.state == ManagedTaskState.succeeded) {
      _state.setArtifact('${assignment.role.id}.summary', managed.summary);
      _state.setStatus(SharedTaskStatus.inProgress);
      return AssignmentOutcome(
        role: assignment.role,
        taskId: managed.id,
        state: SharedTaskStatus.completed,
        summary: managed.summary,
      );
    }

    final failed = managed.state == ManagedTaskState.failed;
    _state.setStatus(
      failed ? SharedTaskStatus.failed : SharedTaskStatus.cancelled,
    );
    return AssignmentOutcome(
      role: assignment.role,
      taskId: managed.id,
      state: failed ? SharedTaskStatus.failed : SharedTaskStatus.cancelled,
      summary: managed.summary,
      errorCode: managed.errorCode,
      errorMessage: managed.errorMessage,
    );
  }

  /// Runs assignments in order, stopping at the first failure.
  Future<List<AssignmentOutcome>> runAll(
    List<AgentAssignment> assignments, {
    bool continueOnFailure = false,
  }) async {
    final outcomes = <AssignmentOutcome>[];
    for (final assignment in assignments) {
      final outcome = await assign(assignment);
      outcomes.add(outcome);
      if (!outcome.succeeded && !continueOnFailure) break;
    }
    return outcomes;
  }

  /// Records a project revision observed by a role, never moving backwards.
  void updateProjectRevision(int revision) {
    if (revision <= _state.projectRevision) return;
    _state.updateProjectRevision(revision);
  }

  /// Marks the shared task completed and returns its serializable snapshot.
  Map<String, Object?> complete(String summary) {
    _state.setStatus(SharedTaskStatus.completed);
    _state.setArtifact('summary', summary);
    return _state.toJson();
  }

  void fail(String code, String message) {
    _state.setStatus(SharedTaskStatus.failed);
    _state.setArtifact('error', <String, Object?>{
      'code': code,
      'message': message,
    });
  }

  void cancel() => _state.setStatus(SharedTaskStatus.cancelled);

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final agent in _agents.values) {
      await agent.dispose();
    }
    _agents.clear();
  }
}

class _NoopAuditSink implements AuditSink {
  @override
  Future<void> record(Map<String, Object?> event) async {}
}
