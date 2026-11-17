import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Thin wrapper around a SQLite database for Shadow Studio local storage.
class LocalDatabase {
  LocalDatabase._(this._db, this.path);

  final Database _db;
  final String path;

  Database get raw => _db;

  /// Opens (or creates) the database at [path] and ensures schema exists.
  factory LocalDatabase.open(String path) {
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=NORMAL;');
    db.execute('PRAGMA busy_timeout=5000;');
    db.execute('PRAGMA foreign_keys=ON;');
    final instance = LocalDatabase._(db, path);
    instance._migrate();
    return instance;
  }

  /// In-memory database, useful for tests.
  factory LocalDatabase.memory() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys=ON;');
    final instance = LocalDatabase._(db, ':memory:');
    instance._migrate();
    return instance;
  }

  static const int _latestVersion = 3;

  /// Schema version currently applied to this database.
  int get schemaVersion => _db
      .select('SELECT COALESCE(MAX(version),0) AS v FROM schema_migrations')
      .first['v'] as int;

  /// Runs [action] inside an IMMEDIATE transaction, rolling back on error.
  ///
  /// Use this for multi-row invariants such as writing a timeline and bumping
  /// the owning project revision.
  T transaction<T>(T Function() action) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      final result = action();
      _db.execute('COMMIT;');
      return result;
    } catch (error) {
      try {
        _db.execute('ROLLBACK;');
      } catch (_) {
        // Ignore rollback failures; the original error is more useful.
      }
      rethrow;
    }
  }

  /// Returns true when SQLite's `PRAGMA integrity_check` reports no problems.
  bool integrityCheck() {
    final rows = _db.select('PRAGMA integrity_check;');
    if (rows.isEmpty) return false;
    final first = rows.first.values.first;
    return first is String && first.toLowerCase() == 'ok';
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL
      );
    ''');
    final row = _db
        .select('SELECT COALESCE(MAX(version),0) AS v FROM schema_migrations');
    var current = row.first['v'] as int;
    final migrations = <int, List<String>>{
      1: _migration1,
      2: _migration2,
      3: _migration3,
    };
    while (current < _latestVersion) {
      final next = current + 1;
      final stmts = migrations[next];
      if (stmts == null) break;
      _db.execute('BEGIN IMMEDIATE;');
      try {
        for (final s in stmts) {
          _db.execute(s);
        }
        if (next == 2) {
          _ensureColumn(
            'provider_configs',
            'enabled',
            'INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (next == 3) {
          for (final entry in _checkpointColumns3.entries) {
            _ensureColumn(
              'execution_checkpoints',
              entry.key,
              entry.value,
            );
          }
        }
        _db.execute(
            'INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);',
            [next, DateTime.now().millisecondsSinceEpoch]);
        _db.execute('COMMIT;');
        current = next;
      } catch (e) {
        _db.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  static const List<String> _migration1 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS session_memory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      project_id TEXT,
      kind TEXT NOT NULL,
      content TEXT NOT NULL,
      metadata TEXT,
      created_at INTEGER NOT NULL,
      expires_at INTEGER
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_session_memory_session ON session_memory(session_id, created_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_session_memory_project ON session_memory(project_id, created_at DESC);',
    '''
    CREATE TABLE IF NOT EXISTS task_memory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project_id TEXT,
      task_id TEXT,
      summary TEXT NOT NULL,
      outcome TEXT NOT NULL,
      context_json TEXT,
      metadata TEXT,
      untrusted INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      expires_at INTEGER
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_task_memory_project ON task_memory(project_id, created_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_task_memory_task ON task_memory(task_id);',
    'CREATE INDEX IF NOT EXISTS idx_task_memory_expires ON task_memory(expires_at);',
    '''
    CREATE TABLE IF NOT EXISTS agent_sessions (
      id TEXT PRIMARY KEY,
      project_id TEXT,
      workspace_root TEXT NOT NULL,
      state TEXT NOT NULL,
      project_revision INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS agent_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      metadata TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(session_id) REFERENCES agent_sessions(id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_agent_messages_session ON agent_messages(session_id, created_at);',
    '''
    CREATE TABLE IF NOT EXISTS agent_tasks (
      id TEXT PRIMARY KEY,
      session_id TEXT,
      state TEXT NOT NULL,
      request TEXT,
      project_revision INTEGER NOT NULL,
      workspace_root TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(session_id) REFERENCES agent_sessions(id)
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS tool_executions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id TEXT NOT NULL,
      tool_name TEXT NOT NULL,
      idempotent INTEGER NOT NULL,
      arguments_hash TEXT,
      result TEXT,
      status TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      finished_at INTEGER,
      FOREIGN KEY(task_id) REFERENCES agent_tasks(id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_tool_executions_task ON tool_executions(task_id, started_at);',
    '''
    CREATE TABLE IF NOT EXISTS approvals (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      action TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      resolved_at INTEGER,
      FOREIGN KEY(task_id) REFERENCES agent_tasks(id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_approvals_task ON approvals(task_id);',
    'CREATE INDEX IF NOT EXISTS idx_approvals_expires ON approvals(expires_at);',
    '''
    CREATE TABLE IF NOT EXISTS execution_checkpoints (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      context_hash TEXT NOT NULL,
      project_revision INTEGER NOT NULL,
      workspace_root TEXT NOT NULL,
      plan_json TEXT NOT NULL,
      tool_call_count INTEGER NOT NULL,
      pending_step_id TEXT,
      last_tool_name TEXT,
      last_tool_idempotent INTEGER,
      last_tool_arguments_hash TEXT,
      state TEXT NOT NULL,
      UNIQUE(task_id, sequence),
      FOREIGN KEY(task_id) REFERENCES agent_tasks(id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_checkpoints_task ON execution_checkpoints(task_id, sequence DESC);',
    '''
    CREATE TABLE IF NOT EXISTS provider_configs (
      id TEXT PRIMARY KEY,
      provider TEXT NOT NULL,
      model TEXT,
      base_url TEXT,
      api_key_ref TEXT,
      metadata TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
  ];

  static const List<String> _migration2 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      workspace_root TEXT NOT NULL,
      file_path TEXT NOT NULL,
      project_revision INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted_at INTEGER
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_projects_updated ON projects(updated_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_projects_workspace ON projects(workspace_root);',
    '''
    CREATE TABLE IF NOT EXISTS media_assets (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      path TEXT NOT NULL,
      mime_type TEXT,
      duration_ms INTEGER,
      width INTEGER,
      height INTEGER,
      frame_rate REAL,
      thumbnail_path TEXT,
      checksum TEXT,
      metadata TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL,
      FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_project ON media_assets(project_id, created_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_media_assets_path ON media_assets(path);',
    '''
    CREATE TABLE IF NOT EXISTS timelines (
      id TEXT PRIMARY KEY,
      project_id TEXT NOT NULL,
      name TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 0,
      tracks_json TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_timelines_project ON timelines(project_id, updated_at DESC);',
    '''
    CREATE TABLE IF NOT EXISTS execution_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      task_id TEXT,
      level TEXT NOT NULL,
      event TEXT NOT NULL,
      message TEXT NOT NULL,
      correlation_id TEXT,
      metadata TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_execution_logs_session ON execution_logs(session_id, created_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_execution_logs_task ON execution_logs(task_id, created_at DESC);',
    '''
    CREATE TABLE IF NOT EXISTS permission_decisions (
      id TEXT PRIMARY KEY,
      task_id TEXT,
      session_id TEXT,
      tool_name TEXT NOT NULL,
      action TEXT NOT NULL,
      status TEXT NOT NULL,
      scope TEXT,
      created_by TEXT,
      reason TEXT,
      created_at INTEGER NOT NULL,
      expires_at INTEGER,
      resolved_at INTEGER
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_permission_decisions_task ON permission_decisions(task_id);',
    'CREATE INDEX IF NOT EXISTS idx_permission_decisions_status ON permission_decisions(status, expires_at);',
    '''
    CREATE TABLE IF NOT EXISTS provider_configs (
      id TEXT PRIMARY KEY,
      provider TEXT NOT NULL,
      model TEXT,
      base_url TEXT,
      api_key_ref TEXT,
      metadata TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
  ];

  /// Version 3 also handles v1 databases that never had the table at all.
  static const List<String> _migration3 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS execution_checkpoints (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      context_hash TEXT NOT NULL,
      project_revision INTEGER NOT NULL,
      workspace_root TEXT NOT NULL,
      plan_json TEXT NOT NULL,
      tool_call_count INTEGER NOT NULL,
      pending_step_id TEXT,
      last_tool_name TEXT,
      last_tool_idempotent INTEGER,
      last_tool_arguments_hash TEXT,
      state TEXT NOT NULL,
      request TEXT,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      last_tool_status TEXT NOT NULL DEFAULT 'none',
      last_tool_error_code TEXT,
      last_tool_error_message TEXT,
      error_code TEXT,
      error_message TEXT,
      summary TEXT,
      resume_count INTEGER NOT NULL DEFAULT 0,
      partial_artifacts_json TEXT NOT NULL DEFAULT '[]',
      last_heartbeat_at INTEGER,
      run_id TEXT,
      process_id INTEGER,
      UNIQUE(task_id, sequence),
      FOREIGN KEY(task_id) REFERENCES agent_tasks(id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_checkpoints_task ON execution_checkpoints(task_id, sequence DESC);',
  ];

  /// Version 3: durable recovery metadata on checkpoints. Every column is
  /// additive with a safe default so v1/v2 databases migrate in place.
  static const Map<String, String> _checkpointColumns3 = <String, String>{
    'request': 'TEXT',
    'metadata_json': "TEXT NOT NULL DEFAULT '{}'",
    'last_tool_status': "TEXT NOT NULL DEFAULT 'none'",
    'last_tool_error_code': 'TEXT',
    'last_tool_error_message': 'TEXT',
    'error_code': 'TEXT',
    'error_message': 'TEXT',
    'summary': 'TEXT',
    'resume_count': 'INTEGER NOT NULL DEFAULT 0',
    'partial_artifacts_json': "TEXT NOT NULL DEFAULT '[]'",
    'last_heartbeat_at': 'INTEGER',
    'run_id': 'TEXT',
    'process_id': 'INTEGER',
  };

  /// Adds [column] to [table] when absent. Used for forward-compatible column
  /// additions that cannot be expressed as plain SQL.
  void _ensureColumn(String table, String column, String definition) {
    final exists = _db
        .select('PRAGMA table_info($table);')
        .any((row) => row['name'] == column);
    if (!exists) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition;');
    }
  }

  void close() => _db.close();
}
