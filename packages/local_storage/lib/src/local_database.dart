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

  static const int _latestVersion = 1;

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL
      );
    ''');
    final row = _db.select('SELECT COALESCE(MAX(version),0) AS v FROM schema_migrations');
    var current = row.first['v'] as int;
    final migrations = <int, List<String>>{
      1: _migration1,
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
        _db.execute('INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?);', [next, DateTime.now().millisecondsSinceEpoch]);
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

  void close() => _db.close();
}
