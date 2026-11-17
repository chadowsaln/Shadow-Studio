import 'package:sqlite3/sqlite3.dart';

import '../error/storage_error.dart';

/// Manages forward-only schema migrations for `.ssproj` project files.
abstract final class SchemaMigrations {
  /// Current normative schema version for project files.
  static const int currentVersion = 2;

  /// Determines the schema version of the opened [db].
  static int readVersion(Database db, {String? path}) {
    // Check if schema_migrations table exists
    final tableCheck = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_migrations';",
    );

    if (tableCheck.isNotEmpty) {
      final rows = db.select(
        'SELECT MAX(version) AS max_v FROM schema_migrations;',
      );
      if (rows.isNotEmpty && rows.first['max_v'] != null) {
        return rows.first['max_v'] as int;
      }
    }

    // Check project_state table
    final stateCheck = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='project_state';",
    );
    if (stateCheck.isNotEmpty) {
      final rows = db.select(
        'SELECT schema_version FROM project_state LIMIT 1;',
      );
      if (rows.isNotEmpty && rows.first['schema_version'] != null) {
        return rows.first['schema_version'] as int;
      }
      return 1;
    }

    return 0; // Empty / uninitialized
  }

  /// Applies forward-only migrations up to [targetVersion].
  static void migrate(
    Database db, {
    int targetVersion = currentVersion,
    String? path,
  }) {
    final current = readVersion(db, path: path);

    if (current > targetVersion) {
      throw StorageError.schemaTooNew(
        fileVersion: current,
        maxSupportedVersion: targetVersion,
        path: path,
      );
    }

    if (current == 0) {
      _applyV1(db);
      _applyV2(db);
      return;
    }

    if (current < 1 && targetVersion >= 1) {
      _applyV1(db);
    }
    if (current < 2 && targetVersion >= 2) {
      _applyV2(db);
    }
  }

  static void _applyV1(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS project_state (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        revision INTEGER NOT NULL,
        schema_version INTEGER NOT NULL,
        document_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS edit_ops (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        batch_id TEXT NOT NULL,
        op_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        inverse_json TEXT NOT NULL,
        origin TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
  }

  static void _applyV2(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_edit_ops_project_revision
      ON edit_ops(project_id, revision);
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_edit_ops_batch
      ON edit_ops(batch_id);
    ''');

    // Record migration applied
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES (1, ?);',
      [now],
    );
    db.execute(
      'INSERT OR REPLACE INTO schema_migrations (version, applied_at) VALUES (2, ?);',
      [now],
    );

    // Update project_state schema_version if present
    db.execute('UPDATE project_state SET schema_version = 2 WHERE schema_version < 2;');
  }
}
