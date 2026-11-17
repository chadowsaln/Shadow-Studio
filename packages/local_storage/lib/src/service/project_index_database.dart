import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../model/project_index_entry.dart';
import 'project_file_storage.dart';

/// App-level rebuildable project index database (Spec V2-D11).
///
/// The `.ssproj` project file is the authoritative source of truth;
/// this database is a pure rebuildable cache index. Deleting it and rescanning
/// project folders completely restores it.
class ProjectIndexDatabase {
  final Database db;

  ProjectIndexDatabase(this.db) {
    _initSchema();
  }

  /// Opens or creates an index database at [dbPath].
  factory ProjectIndexDatabase.open(String dbPath) {
    final file = File(dbPath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(dbPath);
    return ProjectIndexDatabase(db);
  }

  void _initSchema() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS project_index (
        project_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        revision INTEGER NOT NULL,
        duration_ticks INTEGER NOT NULL,
        thumbnail_uri TEXT,
        last_modified_ms INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_project_index_updated
      ON project_index(updated_at DESC);
    ''');
  }

  void upsert(ProjectIndexEntry entry) {
    final stmt = db.prepare('''
      INSERT INTO project_index (
        project_id, name, file_path, revision, duration_ticks,
        thumbnail_uri, last_modified_ms, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(project_id) DO UPDATE SET
        name = excluded.name,
        file_path = excluded.file_path,
        revision = excluded.revision,
        duration_ticks = excluded.duration_ticks,
        thumbnail_uri = excluded.thumbnail_uri,
        last_modified_ms = excluded.last_modified_ms,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      entry.projectId,
      entry.name,
      entry.filePath,
      entry.revision,
      entry.durationTicks,
      entry.thumbnailUri,
      entry.lastModifiedMs,
      entry.createdAt,
      entry.updatedAt,
    ]);
    stmt.close();
  }

  ProjectIndexEntry? get(String projectId) {
    final rows = db.select(
      'SELECT * FROM project_index WHERE project_id = ?;',
      [projectId],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  List<ProjectIndexEntry> getAll() {
    final rows = db.select('SELECT * FROM project_index ORDER BY updated_at DESC;');
    return rows.map(_fromRow).toList();
  }

  void remove(String projectId) {
    db.execute('DELETE FROM project_index WHERE project_id = ?;', [projectId]);
  }

  /// Scans [directory] for all `*.ssproj` files and rebuilds the entire index table.
  Future<int> rebuildFromDirectory(
    Directory directory, {
    ProjectFileStorage storage = const ProjectFileStorage(),
  }) async {
    db.execute('DELETE FROM project_index;');
    if (!directory.existsSync()) return 0;

    var count = 0;
    final entities = directory.listSync(recursive: true, followLinks: false);

    for (final entity in entities) {
      if (entity is File &&
          entity.path.endsWith('.ssproj') &&
          !entity.path.endsWith('.part')) {
        try {
          final (projectData, _) = await storage.openProjectFile(entity.path);
          final stat = entity.statSync();

          // Extract duration_ticks from documentJson if present
          var durationTicks = 0;
          try {
            final docMap = jsonDecode(projectData.documentJson) as Map<String, dynamic>;
            final tracks = docMap['tracks'] as List<dynamic>? ?? const [];
            for (final track in tracks) {
              final clips = (track['clips'] as List<dynamic>?) ??
                  (track['audio_clips'] as List<dynamic>?) ??
                  const [];
              for (final clip in clips) {
                final start = (clip['timeline_start_ticks'] as int?) ?? 0;
                final dur = (clip['duration_ticks'] as int?) ?? 0;
                if (start + dur > durationTicks) {
                  durationTicks = start + dur;
                }
              }
            }
          } catch (_) {}

          final entry = ProjectIndexEntry(
            projectId: projectData.projectId,
            name: projectData.name,
            filePath: entity.path,
            revision: projectData.revision,
            durationTicks: durationTicks,
            lastModifiedMs: stat.modified.millisecondsSinceEpoch,
            createdAt: projectData.createdAt,
            updatedAt: projectData.updatedAt,
          );

          upsert(entry);
          count++;
        } catch (_) {
          // Ignore corrupt or unreadable files during batch scan
        }
      }
    }

    return count;
  }

  ProjectIndexEntry _fromRow(Row row) {
    return ProjectIndexEntry(
      projectId: row['project_id'] as String,
      name: row['name'] as String,
      filePath: row['file_path'] as String,
      revision: row['revision'] as int,
      durationTicks: row['duration_ticks'] as int,
      thumbnailUri: row['thumbnail_uri'] as String?,
      lastModifiedMs: row['last_modified_ms'] as int,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
  }

  void close() {
    db.close();
  }
}
