import 'dart:convert';

/// Decodes a metadata value stored either as a JSON string or as a map.
Map<String, Object?> _decodeMetadata(Object? raw) {
  if (raw == null) return <String, Object?>{};
  final value = raw is String ? jsonDecode(raw) : raw;
  if (value is Map) return value.cast<String, Object?>();
  return <String, Object?>{};
}

/// Immutable record types persisted by [LocalDatabase].
///
/// Timestamps are stored as epoch milliseconds (UTC). JSON-valued fields are
/// stored as text and exposed as decoded maps.

/// A project registered in the app database.
class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.workspaceRoot,
    required this.filePath,
    this.revision = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String workspaceRoot;
  final String filePath;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  ProjectRecord copyWith({
    String? name,
    String? workspaceRoot,
    String? filePath,
    int? revision,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return ProjectRecord(
      id: id,
      name: name ?? this.name,
      workspaceRoot: workspaceRoot ?? this.workspaceRoot,
      filePath: filePath ?? this.filePath,
      revision: revision ?? this.revision,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'workspace_root': workspaceRoot,
        'file_path': filePath,
        'revision': revision,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  static ProjectRecord fromJson(Map<String, Object?> json) => ProjectRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        workspaceRoot: json['workspace_root'] as String,
        filePath: json['file_path'] as String,
        revision: json['revision'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            json['updated_at'] as int,
            isUtc: true),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['deleted_at'] as int,
                isUtc: true),
      );
}

/// A media file tracked for a project.
class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.projectId,
    required this.kind,
    required this.path,
    this.mimeType,
    this.durationMs,
    this.width,
    this.height,
    this.frameRate,
    this.thumbnailPath,
    this.checksum,
    this.metadata = const <String, Object?>{},
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String kind;
  final String path;
  final String? mimeType;
  final int? durationMs;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? thumbnailPath;
  final String? checksum;
  final Map<String, Object?> metadata;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'project_id': projectId,
        'kind': kind,
        'path': path,
        'mime_type': mimeType,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'frame_rate': frameRate,
        'thumbnail_path': thumbnailPath,
        'checksum': checksum,
        'metadata': metadata,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static MediaAsset fromJson(Map<String, Object?> json) => MediaAsset(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        kind: json['kind'] as String,
        path: json['path'] as String,
        mimeType: json['mime_type'] as String?,
        durationMs: json['duration_ms'] as int?,
        width: json['width'] as int?,
        height: json['height'] as int?,
        frameRate: (json['frame_rate'] as num?)?.toDouble(),
        thumbnailPath: json['thumbnail_path'] as String?,
        checksum: json['checksum'] as String?,
        metadata: _decodeMetadata(json['metadata']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
      );
}

/// An editing timeline snapshot for a project.
class TimelineRecord {
  const TimelineRecord({
    required this.id,
    required this.projectId,
    required this.name,
    required this.revision,
    required this.tracksJson,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String name;
  final int revision;
  final String tracksJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> tracks() {
    final decoded = jsonDecode(tracksJson);
    if (decoded is Map<String, Object?>) return decoded;
    return <String, Object?>{};
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'project_id': projectId,
        'name': name,
        'revision': revision,
        'tracks_json': tracksJson,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static TimelineRecord fromJson(Map<String, Object?> json) => TimelineRecord(
        id: json['id'] as String,
        projectId: json['project_id'] as String,
        name: json['name'] as String,
        revision: json['revision'] as int? ?? 0,
        tracksJson: json['tracks_json'] as String? ?? '{}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            json['updated_at'] as int,
            isUtc: true),
      );
}

/// A structured log line for diagnostics and auditing.
class ExecutionLog {
  const ExecutionLog({
    this.id,
    this.sessionId,
    this.taskId,
    required this.level,
    required this.event,
    required this.message,
    this.correlationId,
    this.metadata = const <String, Object?>{},
    required this.createdAt,
  });

  final int? id;
  final String? sessionId;
  final String? taskId;
  final String level;
  final String event;
  final String message;
  final String? correlationId;
  final Map<String, Object?> metadata;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'session_id': sessionId,
        'task_id': taskId,
        'level': level,
        'event': event,
        'message': message,
        'correlation_id': correlationId,
        'metadata': metadata,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static ExecutionLog fromJson(Map<String, Object?> json) => ExecutionLog(
        id: json['id'] as int?,
        sessionId: json['session_id'] as String?,
        taskId: json['task_id'] as String?,
        level: json['level'] as String,
        event: json['event'] as String,
        message: json['message'] as String,
        correlationId: json['correlation_id'] as String?,
        metadata: _decodeMetadata(json['metadata']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
      );
}

/// A recorded permission/approval decision.
class PermissionDecision {
  const PermissionDecision({
    required this.id,
    this.taskId,
    this.sessionId,
    required this.toolName,
    required this.action,
    required this.status,
    this.scope,
    this.createdBy,
    this.reason,
    required this.createdAt,
    this.expiresAt,
    this.resolvedAt,
  });

  final String id;
  final String? taskId;
  final String? sessionId;
  final String toolName;
  final String action;
  final String status;
  final String? scope;
  final String? createdBy;
  final String? reason;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? resolvedAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'task_id': taskId,
        'session_id': sessionId,
        'tool_name': toolName,
        'action': action,
        'status': status,
        'scope': scope,
        'created_by': createdBy,
        'reason': reason,
        'created_at': createdAt.millisecondsSinceEpoch,
        'expires_at': expiresAt?.millisecondsSinceEpoch,
        'resolved_at': resolvedAt?.millisecondsSinceEpoch,
      };

  static PermissionDecision fromJson(Map<String, Object?> json) =>
      PermissionDecision(
        id: json['id'] as String,
        taskId: json['task_id'] as String?,
        sessionId: json['session_id'] as String?,
        toolName: json['tool_name'] as String,
        action: json['action'] as String,
        status: json['status'] as String,
        scope: json['scope'] as String?,
        createdBy: json['created_by'] as String?,
        reason: json['reason'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['expires_at'] as int,
                isUtc: true),
        resolvedAt: json['resolved_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['resolved_at'] as int,
                isUtc: true),
      );
}

/// An agent session record.
class AgentSessionRecord {
  const AgentSessionRecord({
    required this.id,
    this.projectId,
    required this.workspaceRoot,
    required this.state,
    required this.projectRevision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? projectId;
  final String workspaceRoot;
  final String state;
  final int projectRevision;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'project_id': projectId,
        'workspace_root': workspaceRoot,
        'state': state,
        'project_revision': projectRevision,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static AgentSessionRecord fromJson(Map<String, Object?> json) =>
      AgentSessionRecord(
        id: json['id'] as String,
        projectId: json['project_id'] as String?,
        workspaceRoot: json['workspace_root'] as String,
        state: json['state'] as String,
        projectRevision: json['project_revision'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            json['updated_at'] as int,
            isUtc: true),
      );
}

/// An agent task record.
class AgentTaskRecord {
  const AgentTaskRecord({
    required this.id,
    this.sessionId,
    required this.state,
    this.request,
    required this.projectRevision,
    required this.workspaceRoot,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? sessionId;
  final String state;
  final String? request;
  final int projectRevision;
  final String workspaceRoot;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'session_id': sessionId,
        'state': state,
        'request': request,
        'project_revision': projectRevision,
        'workspace_root': workspaceRoot,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static AgentTaskRecord fromJson(Map<String, Object?> json) => AgentTaskRecord(
        id: json['id'] as String,
        sessionId: json['session_id'] as String?,
        state: json['state'] as String,
        request: json['request'] as String?,
        projectRevision: json['project_revision'] as int? ?? 0,
        workspaceRoot: json['workspace_root'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            json['updated_at'] as int,
            isUtc: true),
      );
}

/// A tool execution record.
class ToolExecutionRecord {
  const ToolExecutionRecord({
    this.id,
    required this.taskId,
    required this.toolName,
    required this.idempotent,
    this.argumentsHash,
    this.result,
    required this.status,
    required this.startedAt,
    this.finishedAt,
  });

  final int? id;
  final String taskId;
  final String toolName;
  final bool idempotent;
  final String? argumentsHash;
  final String? result;
  final String status;
  final DateTime startedAt;
  final DateTime? finishedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'task_id': taskId,
        'tool_name': toolName,
        'idempotent': idempotent,
        'arguments_hash': argumentsHash,
        'result': result,
        'status': status,
        'started_at': startedAt.millisecondsSinceEpoch,
        'finished_at': finishedAt?.millisecondsSinceEpoch,
      };

  static ToolExecutionRecord fromJson(Map<String, Object?> json) =>
      ToolExecutionRecord(
        id: json['id'] as int?,
        taskId: json['task_id'] as String,
        toolName: json['tool_name'] as String,
        idempotent: (json['idempotent'] as int? ?? 0) == 1,
        argumentsHash: json['arguments_hash'] as String?,
        result: json['result'] as String?,
        status: json['status'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
            json['started_at'] as int,
            isUtc: true),
        finishedAt: json['finished_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['finished_at'] as int,
                isUtc: true),
      );
}

/// A provider configuration record.
class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.provider,
    this.model,
    this.baseUrl,
    this.apiKeyRef,
    this.enabled = true,
    this.metadata = const <String, Object?>{},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String provider;
  final String? model;
  final String? baseUrl;
  final String? apiKeyRef;
  final bool enabled;
  final Map<String, Object?> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'provider': provider,
        'model': model,
        'base_url': baseUrl,
        'api_key_ref': apiKeyRef,
        'enabled': enabled,
        'metadata': metadata,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static ProviderConfig fromJson(Map<String, Object?> json) => ProviderConfig(
        id: json['id'] as String,
        provider: json['provider'] as String,
        model: json['model'] as String?,
        baseUrl: json['base_url'] as String?,
        apiKeyRef: json['api_key_ref'] as String?,
        enabled: (json['enabled'] as int? ?? 1) == 1,
        metadata: _decodeMetadata(json['metadata']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            json['created_at'] as int,
            isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            json['updated_at'] as int,
            isUtc: true),
      );
}
