import 'package:meta/meta.dart';

import '../errors/error_codes.dart';
import 'agent_models.dart';
import 'agent_plan.dart';

/// Status of the last tool call recorded in a checkpoint.
///
/// `started` is written **before** execution and `succeeded`/`failed` after it.
/// A checkpoint left in `started` means the process may have died while the tool
/// was running, so recovery must not blindly repeat a non-idempotent operation.
enum CheckpointToolStatus { none, started, succeeded, failed }

/// A durable snapshot of agent execution, used to resume an interrupted task.
///
/// Checkpoints are written when a task is created, before and after every tool
/// call, and when the task reaches a terminal state. They bind the plan to the
/// project revision, workspace, and context hash so a resume validates the old
/// state before continuing.
@immutable
class AgentCheckpoint {
  const AgentCheckpoint({
    required this.taskId,
    required this.sequence,
    required this.createdAt,
    required this.contextHash,
    required this.projectRevision,
    required this.workspaceRoot,
    required this.plan,
    required this.toolCallCount,
    required this.pendingStepId,
    this.request,
    this.metadata = const <String, Object?>{},
    this.lastToolName,
    this.lastToolIdempotent,
    this.lastToolArgumentsHash,
    this.lastToolStatus = CheckpointToolStatus.none,
    this.lastToolErrorCode,
    this.lastToolErrorMessage,
    this.lastHeartbeatAt,
    this.runId,
    this.processId,
    this.resumeCount = 0,
    this.partialArtifacts = const <String>[],
    this.errorCode,
    this.errorMessage,
    this.summary,
    this.state = AgentTaskState.acting,
  });

  final String taskId;
  final int sequence;
  final DateTime createdAt;
  final String contextHash;
  final int projectRevision;
  final String workspaceRoot;
  final AgentPlan plan;
  final int toolCallCount;
  final String? pendingStepId;

  /// Original user request, persisted so a restart can resume without the UI.
  final String? request;

  /// Context metadata used to recompute [contextHash] on resume.
  final Map<String, Object?> metadata;

  final String? lastToolName;
  final bool? lastToolIdempotent;
  final String? lastToolArgumentsHash;
  final CheckpointToolStatus lastToolStatus;
  final String? lastToolErrorCode;
  final String? lastToolErrorMessage;

  /// Last write time; used for interrupted-task detection.
  final DateTime? lastHeartbeatAt;

  /// Identifier of the controller instance that wrote the checkpoint.
  final String? runId;

  /// Operating-system process id that wrote the checkpoint. A checkpoint from
  /// another process is treated as orphaned immediately after restart.
  final int? processId;

  final int resumeCount;

  /// Workspace-relative or absolute paths of outputs that may be partial.
  final List<String> partialArtifacts;

  final String? errorCode;
  final String? errorMessage;
  final String? summary;

  final AgentTaskState state;

  bool get isTerminal =>
      state == AgentTaskState.succeeded ||
      state == AgentTaskState.failed ||
      state == AgentTaskState.cancelled;

  /// True when the process may have died while the last tool was executing.
  bool get mayHaveInFlightTool =>
      lastToolStatus == CheckpointToolStatus.started;

  /// True when the last recorded tool call finished (successfully or not).
  bool get lastToolCompleted =>
      lastToolStatus == CheckpointToolStatus.succeeded ||
      lastToolStatus == CheckpointToolStatus.failed;

  /// Safe retry requires idempotence or an explicit user decision.
  bool get requiresReplayConfirmation =>
      mayHaveInFlightTool && lastToolIdempotent != true;

  AgentCheckpoint copyWith({
    int? sequence,
    DateTime? createdAt,
    String? contextHash,
    int? projectRevision,
    String? workspaceRoot,
    AgentPlan? plan,
    int? toolCallCount,
    String? pendingStepId,
    String? request,
    Map<String, Object?>? metadata,
    String? lastToolName,
    bool? lastToolIdempotent,
    String? lastToolArgumentsHash,
    CheckpointToolStatus? lastToolStatus,
    String? lastToolErrorCode,
    String? lastToolErrorMessage,
    DateTime? lastHeartbeatAt,
    String? runId,
    int? processId,
    int? resumeCount,
    List<String>? partialArtifacts,
    String? errorCode,
    String? errorMessage,
    String? summary,
    AgentTaskState? state,
  }) {
    return AgentCheckpoint(
      taskId: taskId,
      sequence: sequence ?? this.sequence,
      createdAt: createdAt ?? this.createdAt,
      contextHash: contextHash ?? this.contextHash,
      projectRevision: projectRevision ?? this.projectRevision,
      workspaceRoot: workspaceRoot ?? this.workspaceRoot,
      plan: plan ?? this.plan,
      toolCallCount: toolCallCount ?? this.toolCallCount,
      pendingStepId: pendingStepId ?? this.pendingStepId,
      request: request ?? this.request,
      metadata: metadata ?? this.metadata,
      lastToolName: lastToolName ?? this.lastToolName,
      lastToolIdempotent: lastToolIdempotent ?? this.lastToolIdempotent,
      lastToolArgumentsHash:
          lastToolArgumentsHash ?? this.lastToolArgumentsHash,
      lastToolStatus: lastToolStatus ?? this.lastToolStatus,
      lastToolErrorCode: lastToolErrorCode ?? this.lastToolErrorCode,
      lastToolErrorMessage: lastToolErrorMessage ?? this.lastToolErrorMessage,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      runId: runId ?? this.runId,
      processId: processId ?? this.processId,
      resumeCount: resumeCount ?? this.resumeCount,
      partialArtifacts: partialArtifacts ?? this.partialArtifacts,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      summary: summary ?? this.summary,
      state: state ?? this.state,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': taskId,
    'sequence': sequence,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'contextHash': contextHash,
    'projectRevision': projectRevision,
    'workspaceRoot': workspaceRoot,
    'plan': plan.toJson(),
    'toolCallCount': toolCallCount,
    if (pendingStepId != null) 'pendingStepId': pendingStepId,
    if (request != null) 'request': request,
    if (metadata.isNotEmpty) 'metadata': metadata,
    if (lastToolName != null) 'lastToolName': lastToolName,
    if (lastToolIdempotent != null) 'lastToolIdempotent': lastToolIdempotent,
    if (lastToolArgumentsHash != null)
      'lastToolArgumentsHash': lastToolArgumentsHash,
    'lastToolStatus': lastToolStatus.name,
    if (lastToolErrorCode != null) 'lastToolErrorCode': lastToolErrorCode,
    if (lastToolErrorMessage != null)
      'lastToolErrorMessage': lastToolErrorMessage,
    if (lastHeartbeatAt != null)
      'lastHeartbeatAt': lastHeartbeatAt!.toUtc().toIso8601String(),
    if (runId != null) 'runId': runId,
    if (processId != null) 'processId': processId,
    'resumeCount': resumeCount,
    if (partialArtifacts.isNotEmpty) 'partialArtifacts': partialArtifacts,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (summary != null) 'summary': summary,
    'state': state.name,
  };

  static AgentTaskState _stateFromJson(Object? value) {
    if (value is String) {
      for (final s in AgentTaskState.values) {
        if (s.name == value) return s;
      }
    }
    throw FormatException('Invalid checkpoint state: $value');
  }

  static CheckpointToolStatus _toolStatusFromJson(Object? value) {
    if (value is String) {
      for (final s in CheckpointToolStatus.values) {
        if (s.name == value) return s;
      }
    }
    return CheckpointToolStatus.none;
  }

  static String _requireString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Checkpoint is missing "$key"');
  }

  static int _requireInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('Checkpoint is missing integer "$key"');
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, Object?>{};
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  /// Strict parser. Throws [CheckpointCorruptException] on malformed input.
  static AgentCheckpoint fromJson(Map<String, Object?> json) {
    try {
      final createdAtRaw = json['createdAt'];
      if (createdAtRaw is! String) {
        throw const FormatException('Checkpoint is missing "createdAt"');
      }
      final planRaw = json['plan'];
      final plan = planRaw is Map
          ? AgentPlan.fromJson(_map(planRaw))
          : const AgentPlan(steps: <PlanStep>[], revision: 0);
      final heartbeatRaw = json['lastHeartbeatAt'];
      final heartbeat = heartbeatRaw is String
          ? DateTime.parse(heartbeatRaw).toUtc()
          : null;
      return AgentCheckpoint(
        taskId: _requireString(json, 'taskId'),
        sequence: _requireInt(json, 'sequence'),
        createdAt: DateTime.parse(createdAtRaw).toUtc(),
        contextHash: _requireString(json, 'contextHash'),
        projectRevision: _requireInt(json, 'projectRevision'),
        workspaceRoot: _requireString(json, 'workspaceRoot'),
        plan: plan,
        toolCallCount: json['toolCallCount'] as int? ?? 0,
        pendingStepId: json['pendingStepId'] as String?,
        request: json['request'] as String?,
        metadata: _map(json['metadata']),
        lastToolName: json['lastToolName'] as String?,
        lastToolIdempotent: json['lastToolIdempotent'] as bool?,
        lastToolArgumentsHash: json['lastToolArgumentsHash'] as String?,
        lastToolStatus: _toolStatusFromJson(json['lastToolStatus']),
        lastToolErrorCode: json['lastToolErrorCode'] as String?,
        lastToolErrorMessage: json['lastToolErrorMessage'] as String?,
        lastHeartbeatAt: heartbeat,
        runId: json['runId'] as String?,
        processId: json['processId'] as int?,
        resumeCount: json['resumeCount'] as int? ?? 0,
        partialArtifacts: _stringList(json['partialArtifacts']),
        errorCode: json['errorCode'] as String?,
        errorMessage: json['errorMessage'] as String?,
        summary: json['summary'] as String?,
        state: _stateFromJson(json['state']),
      );
    } on CheckpointCorruptException {
      rethrow;
    } catch (error) {
      throw CheckpointCorruptException(
        taskId: json['taskId'] is String ? json['taskId'] as String : null,
        message: 'Invalid checkpoint: $error',
      );
    }
  }

  /// Non-throwing variant for list/history reads that may skip bad rows.
  static AgentCheckpoint? tryFromJson(Map<String, Object?> json) {
    try {
      return fromJson(json);
    } on CheckpointCorruptException {
      return null;
    }
  }
}

/// A checkpoint row that cannot be trusted. Recovery must fail closed for the
/// affected task rather than resuming from an older, stale snapshot.
class CheckpointCorruptException implements Exception {
  const CheckpointCorruptException({required this.message, this.taskId});

  static const String code = ShadowErrorCode.storeCorrupt;

  final String? taskId;
  final String message;

  @override
  String toString() => 'CheckpointCorruptException($code): $message';
}

/// Persistence port for [AgentCheckpoint]s.
abstract interface class CheckpointStore {
  Future<void> save(AgentCheckpoint checkpoint);

  Future<AgentCheckpoint?> latest(String taskId);

  /// Newest first, bounded by [limit].
  Future<List<AgentCheckpoint>> history(String taskId, {int limit = 50});

  /// Latest checkpoint per task, newest heartbeat first.
  Future<List<AgentCheckpoint>> latestAll();

  Future<void> clear(String taskId);
}
