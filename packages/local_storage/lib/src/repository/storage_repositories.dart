import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../local_database.dart';
import '../model/storage_models.dart';

Map<String, Object?> _rowToMap(Row row) => row.cast<String, Object?>();

DateTime _epoch(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

/// Projects registered in the app database.
class ProjectRepository {
  ProjectRepository(this._db);
  final LocalDatabase _db;

  void upsert(ProjectRecord project) {
    final stmt = _db.raw.prepare('''
      INSERT INTO projects
        (id, name, workspace_root, file_path, project_revision, created_at, updated_at, deleted_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        workspace_root = excluded.workspace_root,
        file_path = excluded.file_path,
        project_revision = excluded.project_revision,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
    ''');
    try {
      stmt.execute([
        project.id,
        project.name,
        project.workspaceRoot,
        project.filePath,
        project.revision,
        project.createdAt.millisecondsSinceEpoch,
        project.updatedAt.millisecondsSinceEpoch,
        project.deletedAt?.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  ProjectRecord? get(String id) {
    final rows = _db.raw.select('SELECT * FROM projects WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final map = _rowToMap(rows.first);
    return ProjectRecord(
      id: map['id'] as String,
      name: map['name'] as String,
      workspaceRoot: map['workspace_root'] as String,
      filePath: map['file_path'] as String,
      revision: map['project_revision'] as int,
      createdAt: _epoch(map['created_at'] as int),
      updatedAt: _epoch(map['updated_at'] as int),
      deletedAt:
          map['deleted_at'] == null ? null : _epoch(map['deleted_at'] as int),
    );
  }

  List<ProjectRecord> list({bool includeDeleted = false, int limit = 100}) {
    final rows = _db.raw.select(
      'SELECT * FROM projects '
      '${includeDeleted ? '' : 'WHERE deleted_at IS NULL '} '
      'ORDER BY updated_at DESC LIMIT ?',
      [limit],
    );
    return rows.map((row) {
      final map = _rowToMap(row);
      return ProjectRecord(
        id: map['id'] as String,
        name: map['name'] as String,
        workspaceRoot: map['workspace_root'] as String,
        filePath: map['file_path'] as String,
        revision: map['project_revision'] as int,
        createdAt: _epoch(map['created_at'] as int),
        updatedAt: _epoch(map['updated_at'] as int),
        deletedAt:
            map['deleted_at'] == null ? null : _epoch(map['deleted_at'] as int),
      );
    }).toList(growable: false);
  }

  void updateRevision(String id, int revision, {DateTime? updatedAt}) {
    final stmt = _db.raw.prepare(
      'UPDATE projects SET project_revision = ?, updated_at = ? WHERE id = ?',
    );
    try {
      stmt.execute([
        revision,
        (updatedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
        id,
      ]);
    } finally {
      stmt.close();
    }
  }

  /// Soft-deletes a project and cascades media assets and timelines.
  void softDelete(String id) {
    _db.transaction(() {
      final stmt = _db.raw.prepare(
        'UPDATE projects SET deleted_at = ? WHERE id = ?',
      );
      try {
        stmt.execute([DateTime.now().toUtc().millisecondsSinceEpoch, id]);
      } finally {
        stmt.close();
      }
      _db.raw.execute('DELETE FROM media_assets WHERE project_id = ?', [id]);
      _db.raw.execute('DELETE FROM timelines WHERE project_id = ?', [id]);
    });
  }

  void purge(String id) {
    _db.transaction(() {
      _db.raw.execute('DELETE FROM media_assets WHERE project_id = ?', [id]);
      _db.raw.execute('DELETE FROM timelines WHERE project_id = ?', [id]);
      _db.raw.execute('DELETE FROM projects WHERE id = ?', [id]);
    });
  }
}

/// Media assets tracked per project.
class MediaAssetRepository {
  MediaAssetRepository(this._db);
  final LocalDatabase _db;

  void save(MediaAsset asset) {
    final stmt = _db.raw.prepare('''
      INSERT INTO media_assets
        (id, project_id, kind, path, mime_type, duration_ms, width, height, frame_rate,
         thumbnail_path, checksum, metadata, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        project_id = excluded.project_id,
        kind = excluded.kind,
        path = excluded.path,
        mime_type = excluded.mime_type,
        duration_ms = excluded.duration_ms,
        width = excluded.width,
        height = excluded.height,
        frame_rate = excluded.frame_rate,
        thumbnail_path = excluded.thumbnail_path,
        checksum = excluded.checksum,
        metadata = excluded.metadata
    ''');
    try {
      stmt.execute([
        asset.id,
        asset.projectId,
        asset.kind,
        asset.path,
        asset.mimeType,
        asset.durationMs,
        asset.width,
        asset.height,
        asset.frameRate,
        asset.thumbnailPath,
        asset.checksum,
        jsonEncode(asset.metadata),
        asset.createdAt.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  MediaAsset? get(String id) {
    final rows =
        _db.raw.select('SELECT * FROM media_assets WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return MediaAsset.fromJson(_rowToMap(rows.first));
  }

  List<MediaAsset> listByProject(String projectId) {
    final rows = _db.raw.select(
      'SELECT * FROM media_assets WHERE project_id = ? ORDER BY created_at DESC',
      [projectId],
    );
    return rows
        .map((r) => MediaAsset.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  void delete(String id) {
    _db.raw.execute('DELETE FROM media_assets WHERE id = ?', [id]);
  }
}

/// Timeline snapshots per project.
class TimelineRepository {
  TimelineRepository(this._db);
  final LocalDatabase _db;

  void save(TimelineRecord timeline) {
    final stmt = _db.raw.prepare('''
      INSERT INTO timelines
        (id, project_id, name, revision, tracks_json, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        project_id = excluded.project_id,
        name = excluded.name,
        revision = excluded.revision,
        tracks_json = excluded.tracks_json,
        updated_at = excluded.updated_at
    ''');
    try {
      stmt.execute([
        timeline.id,
        timeline.projectId,
        timeline.name,
        timeline.revision,
        timeline.tracksJson,
        timeline.createdAt.millisecondsSinceEpoch,
        timeline.updatedAt.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  TimelineRecord? get(String id) {
    final rows = _db.raw.select('SELECT * FROM timelines WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return TimelineRecord.fromJson(_rowToMap(rows.first));
  }

  List<TimelineRecord> listByProject(String projectId) {
    final rows = _db.raw.select(
      'SELECT * FROM timelines WHERE project_id = ? ORDER BY updated_at DESC',
      [projectId],
    );
    return rows
        .map((r) => TimelineRecord.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  void delete(String id) {
    _db.raw.execute('DELETE FROM timelines WHERE id = ?', [id]);
  }
}

/// Append-only execution logs.
class ExecutionLogRepository {
  ExecutionLogRepository(this._db);
  final LocalDatabase _db;

  int append(ExecutionLog log) {
    final stmt = _db.raw.prepare('''
      INSERT INTO execution_logs
        (session_id, task_id, level, event, message, correlation_id, metadata, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        log.sessionId,
        log.taskId,
        log.level,
        log.event,
        log.message,
        log.correlationId,
        jsonEncode(log.metadata),
        log.createdAt.millisecondsSinceEpoch,
      ]);
      return _db.raw.lastInsertRowId;
    } finally {
      stmt.close();
    }
  }

  List<ExecutionLog> listBySession(String sessionId, {int limit = 200}) {
    final rows = _db.raw.select(
      'SELECT * FROM execution_logs WHERE session_id = ? ORDER BY created_at DESC LIMIT ?',
      [sessionId, limit],
    );
    return rows
        .map((r) => ExecutionLog.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  List<ExecutionLog> listByTask(String taskId, {int limit = 200}) {
    final rows = _db.raw.select(
      'SELECT * FROM execution_logs WHERE task_id = ? ORDER BY created_at DESC LIMIT ?',
      [taskId, limit],
    );
    return rows
        .map((r) => ExecutionLog.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  int purgeBefore(DateTime cutoff) {
    _db.raw.execute(
      'DELETE FROM execution_logs WHERE created_at <= ?',
      [cutoff.millisecondsSinceEpoch],
    );
    return _db.raw.select('SELECT changes() AS c').first['c'] as int;
  }
}

/// Permission and approval decisions.
class PermissionRepository {
  PermissionRepository(this._db);
  final LocalDatabase _db;

  void save(PermissionDecision decision) {
    final stmt = _db.raw.prepare('''
      INSERT INTO permission_decisions
        (id, task_id, session_id, tool_name, action, status, scope, created_by, reason,
         created_at, expires_at, resolved_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        status = excluded.status,
        scope = excluded.scope,
        created_by = excluded.created_by,
        reason = excluded.reason,
        expires_at = excluded.expires_at,
        resolved_at = excluded.resolved_at
    ''');
    try {
      stmt.execute([
        decision.id,
        decision.taskId,
        decision.sessionId,
        decision.toolName,
        decision.action,
        decision.status,
        decision.scope,
        decision.createdBy,
        decision.reason,
        decision.createdAt.millisecondsSinceEpoch,
        decision.expiresAt?.millisecondsSinceEpoch,
        decision.resolvedAt?.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  PermissionDecision? get(String id) {
    final rows = _db.raw.select(
      'SELECT * FROM permission_decisions WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return PermissionDecision.fromJson(_rowToMap(rows.first));
  }

  List<PermissionDecision> listByTask(String taskId) {
    final rows = _db.raw.select(
      'SELECT * FROM permission_decisions WHERE task_id = ? ORDER BY created_at DESC',
      [taskId],
    );
    return rows
        .map((r) => PermissionDecision.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  List<PermissionDecision> listExpired({DateTime? now}) {
    final ts = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final rows = _db.raw.select(
      'SELECT * FROM permission_decisions '
      'WHERE status = ? AND expires_at IS NOT NULL AND expires_at <= ?',
      ['pending', ts],
    );
    return rows
        .map((r) => PermissionDecision.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  void resolve(String id, {required String status, String? reason}) {
    final stmt = _db.raw.prepare(
      'UPDATE permission_decisions SET status = ?, reason = ?, resolved_at = ? WHERE id = ?',
    );
    try {
      stmt.execute([
        status,
        reason,
        DateTime.now().toUtc().millisecondsSinceEpoch,
        id,
      ]);
    } finally {
      stmt.close();
    }
  }
}

/// Agent sessions.
class AgentSessionRepository {
  AgentSessionRepository(this._db);
  final LocalDatabase _db;

  void save(AgentSessionRecord session) {
    final stmt = _db.raw.prepare('''
      INSERT INTO agent_sessions
        (id, project_id, workspace_root, state, project_revision, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        project_id = excluded.project_id,
        workspace_root = excluded.workspace_root,
        state = excluded.state,
        project_revision = excluded.project_revision,
        updated_at = excluded.updated_at
    ''');
    try {
      stmt.execute([
        session.id,
        session.projectId,
        session.workspaceRoot,
        session.state,
        session.projectRevision,
        session.createdAt.millisecondsSinceEpoch,
        session.updatedAt.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  AgentSessionRecord? get(String id) {
    final rows =
        _db.raw.select('SELECT * FROM agent_sessions WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return AgentSessionRecord.fromJson(_rowToMap(rows.first));
  }

  List<AgentSessionRecord> list({int limit = 50}) {
    final rows = _db.raw.select(
      'SELECT * FROM agent_sessions ORDER BY updated_at DESC LIMIT ?',
      [limit],
    );
    return rows
        .map((r) => AgentSessionRecord.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  void updateState(String id, String state, {int? projectRevision}) {
    final stmt = _db.raw.prepare(
      projectRevision == null
          ? 'UPDATE agent_sessions SET state = ?, updated_at = ? WHERE id = ?'
          : 'UPDATE agent_sessions SET state = ?, project_revision = ?, updated_at = ? WHERE id = ?',
    );
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (projectRevision == null) {
        stmt.execute([state, now, id]);
      } else {
        stmt.execute([state, projectRevision, now, id]);
      }
    } finally {
      stmt.close();
    }
  }
}

/// Agent tasks.
class AgentTaskRepository {
  AgentTaskRepository(this._db);
  final LocalDatabase _db;

  void save(AgentTaskRecord task) {
    final stmt = _db.raw.prepare('''
      INSERT INTO agent_tasks
        (id, session_id, state, request, project_revision, workspace_root, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        session_id = excluded.session_id,
        state = excluded.state,
        request = excluded.request,
        project_revision = excluded.project_revision,
        updated_at = excluded.updated_at
    ''');
    try {
      stmt.execute([
        task.id,
        task.sessionId,
        task.state,
        task.request,
        task.projectRevision,
        task.workspaceRoot,
        task.createdAt.millisecondsSinceEpoch,
        task.updatedAt.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  AgentTaskRecord? get(String id) {
    final rows = _db.raw.select('SELECT * FROM agent_tasks WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return AgentTaskRecord.fromJson(_rowToMap(rows.first));
  }

  List<AgentTaskRecord> listBySession(String sessionId) {
    final rows = _db.raw.select(
      'SELECT * FROM agent_tasks WHERE session_id = ? ORDER BY created_at DESC',
      [sessionId],
    );
    return rows
        .map((r) => AgentTaskRecord.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  void updateState(String id, String state) {
    final stmt = _db.raw.prepare(
      'UPDATE agent_tasks SET state = ?, updated_at = ? WHERE id = ?',
    );
    try {
      stmt.execute([state, DateTime.now().toUtc().millisecondsSinceEpoch, id]);
    } finally {
      stmt.close();
    }
  }
}

/// Tool executions.
class ToolExecutionRepository {
  ToolExecutionRepository(this._db);
  final LocalDatabase _db;

  int save(ToolExecutionRecord record) {
    final stmt = _db.raw.prepare('''
      INSERT INTO tool_executions
        (task_id, tool_name, idempotent, arguments_hash, result, status, started_at, finished_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        record.taskId,
        record.toolName,
        record.idempotent ? 1 : 0,
        record.argumentsHash,
        record.result,
        record.status,
        record.startedAt.millisecondsSinceEpoch,
        record.finishedAt?.millisecondsSinceEpoch,
      ]);
      return _db.raw.lastInsertRowId;
    } finally {
      stmt.close();
    }
  }

  List<ToolExecutionRecord> listByTask(String taskId) {
    final rows = _db.raw.select(
      'SELECT * FROM tool_executions WHERE task_id = ? ORDER BY started_at ASC',
      [taskId],
    );
    return rows
        .map((r) => ToolExecutionRecord.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }
}

/// Provider configurations.
class ProviderConfigRepository {
  ProviderConfigRepository(this._db);
  final LocalDatabase _db;

  void save(ProviderConfig config) {
    final stmt = _db.raw.prepare('''
      INSERT INTO provider_configs
        (id, provider, model, base_url, api_key_ref, enabled, metadata, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        provider = excluded.provider,
        model = excluded.model,
        base_url = excluded.base_url,
        api_key_ref = excluded.api_key_ref,
        enabled = excluded.enabled,
        metadata = excluded.metadata,
        updated_at = excluded.updated_at
    ''');
    try {
      stmt.execute([
        config.id,
        config.provider,
        config.model,
        config.baseUrl,
        config.apiKeyRef,
        config.enabled ? 1 : 0,
        jsonEncode(config.metadata),
        config.createdAt.millisecondsSinceEpoch,
        config.updatedAt.millisecondsSinceEpoch,
      ]);
    } finally {
      stmt.close();
    }
  }

  ProviderConfig? get(String id) {
    final rows = _db.raw.select(
      'SELECT * FROM provider_configs WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) return null;
    return ProviderConfig.fromJson(_rowToMap(rows.first));
  }

  List<ProviderConfig> list({bool enabledOnly = false}) {
    final rows = _db.raw.select(
      'SELECT * FROM provider_configs '
      '${enabledOnly ? 'WHERE enabled = 1 ' : ''}ORDER BY provider ASC',
    );
    return rows
        .map((r) => ProviderConfig.fromJson(_rowToMap(r)))
        .toList(growable: false);
  }

  void delete(String id) {
    _db.raw.execute('DELETE FROM provider_configs WHERE id = ?', [id]);
  }
}

/// Bundles the repositories for a database instance.
class StorageRepositories {
  StorageRepositories(this.db)
      : projects = ProjectRepository(db),
        mediaAssets = MediaAssetRepository(db),
        timelines = TimelineRepository(db),
        executionLogs = ExecutionLogRepository(db),
        permissions = PermissionRepository(db),
        agentSessions = AgentSessionRepository(db),
        agentTasks = AgentTaskRepository(db),
        toolExecutions = ToolExecutionRepository(db),
        providerConfigs = ProviderConfigRepository(db);

  final LocalDatabase db;
  final ProjectRepository projects;
  final MediaAssetRepository mediaAssets;
  final TimelineRepository timelines;
  final ExecutionLogRepository executionLogs;
  final PermissionRepository permissions;
  final AgentSessionRepository agentSessions;
  final AgentTaskRepository agentTasks;
  final ToolExecutionRepository toolExecutions;
  final ProviderConfigRepository providerConfigs;
}
