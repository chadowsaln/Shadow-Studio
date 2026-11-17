import 'package:sqlite3/sqlite3.dart';

import '../error/storage_error.dart';
import '../model/project_file_data.dart';
import '../model/stored_edit_op.dart';
import 'schema_migrations.dart';

/// Database operations on a single `.ssproj` SQLite file.
abstract final class SqliteProjectFile {
  /// Verifies SQLite file integrity via `PRAGMA integrity_check`.
  ///
  /// Throws [StorageError.corrupt] if corruption is detected.
  static void verifyIntegrity(Database db, {String? path}) {
    try {
      final rows = db.select('PRAGMA integrity_check;');
      if (rows.isEmpty) {
        throw StorageError.corrupt('Integrity check returned no rows', path: path);
      }
      final result = rows.first.columnAt(0) as String;
      if (result.toLowerCase() != 'ok') {
        throw StorageError.corrupt('Integrity check failed: $result', path: path);
      }
    } catch (e) {
      if (e is StorageError) rethrow;
      throw StorageError.corrupt('Integrity check query failed: $e', path: path);
    }
  }

  /// Writes [projectData] and [ops] in an atomic transaction.
  static void writeProject(
    Database db, {
    required ProjectFileData projectData,
    List<StoredEditOp> ops = const [],
    String? path,
  }) {
    SchemaMigrations.migrate(db, path: path);

    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      // Upsert project_state
      final stmt = db.prepare('''
        INSERT INTO project_state (id, name, revision, schema_version, document_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          revision = excluded.revision,
          schema_version = excluded.schema_version,
          document_json = excluded.document_json,
          updated_at = excluded.updated_at;
      ''');
      stmt.execute([
        projectData.projectId,
        projectData.name,
        projectData.revision,
        projectData.schemaVersion,
        projectData.documentJson,
        projectData.createdAt,
        projectData.updatedAt,
      ]);
      stmt.close();

      // Insert ops if any
      if (ops.isNotEmpty) {
        final opStmt = db.prepare('''
          INSERT INTO edit_ops (project_id, revision, batch_id, op_type, payload_json, inverse_json, origin, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        ''');

        for (final op in ops) {
          opStmt.execute([
            op.projectId,
            op.revision,
            op.batchId,
            op.opType,
            op.payloadJson,
            op.inverseJson,
            op.origin,
            op.createdAt,
          ]);
        }
        opStmt.close();
      }

      db.execute('COMMIT;');
    } catch (e) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Reads [ProjectFileData] and [StoredEditOp]s from an open [db].
  static (ProjectFileData, List<StoredEditOp>) readProject(
    Database db, {
    String? path,
  }) {
    verifyIntegrity(db, path: path);
    SchemaMigrations.migrate(db, path: path);

    final stateRows = db.select('SELECT * FROM project_state LIMIT 1;');
    if (stateRows.isEmpty) {
      throw StorageError.corrupt(
        'Project file has no project_state record',
        path: path,
      );
    }

    final row = stateRows.first;
    final projectData = ProjectFileData(
      projectId: row['id'] as String,
      name: row['name'] as String,
      revision: row['revision'] as int,
      schemaVersion: row['schema_version'] as int,
      documentJson: row['document_json'] as String,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );

    final opsRows = db.select(
      'SELECT * FROM edit_ops WHERE project_id = ? ORDER BY seq ASC;',
      [projectData.projectId],
    );

    final ops = opsRows
        .map(
          (r) => StoredEditOp(
            seq: r['seq'] as int,
            projectId: r['project_id'] as String,
            revision: r['revision'] as int,
            batchId: r['batch_id'] as String,
            opType: r['op_type'] as String,
            payloadJson: r['payload_json'] as String,
            inverseJson: r['inverse_json'] as String,
            origin: r['origin'] as String,
            createdAt: r['created_at'] as String,
          ),
        )
        .toList();

    return (projectData, ops);
  }
}
