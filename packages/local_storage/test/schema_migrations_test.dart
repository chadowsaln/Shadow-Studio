import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaMigrations', () {
    late Directory tempDir;
    late ProjectFileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_migration_test_');
      storage = const ProjectFileStorage();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('migrates v1 fixture forward to current v2 schema cleanly', () async {
      final v1FilePath = '${tempDir.path}/v1_fixture.ssproj';

      // 1. Manually craft a strict v1 SQLite database
      final db = sqlite3.open(v1FilePath);
      db.execute('''
        CREATE TABLE project_state (
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
        CREATE TABLE edit_ops (
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

      db.execute('''
        INSERT INTO project_state VALUES (
          'proj-legacy', 'Legacy v1 Project', 7, 1, '{"v":1,"legacy":true}',
          '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
        );
      ''');
      db.execute('''
        INSERT INTO edit_ops VALUES (
          1, 'proj-legacy', 7, 'batch-legacy', 'clip.insert', '{}', '{}', 'ui', '2026-01-01T00:00:00Z'
        );
      ''');
      db.close();

      // 2. Open via ProjectFileStorage -> triggers auto-migration
      final (loadedData, loadedOps) = await storage.openProjectFile(v1FilePath);

      expect(loadedData.projectId, equals('proj-legacy'));
      expect(loadedData.name, equals('Legacy v1 Project'));
      expect(loadedData.revision, equals(7));
      expect(loadedData.schemaVersion, equals(SchemaMigrations.currentVersion));
      expect(loadedOps.length, equals(1));
      expect(loadedOps.first.opType, equals('clip.insert'));

      // 3. Inspect underlying DB to confirm schema_migrations table and v2 indexes exist
      final verifiedDb = sqlite3.open(v1FilePath);
      try {
        final version = SchemaMigrations.readVersion(verifiedDb);
        expect(version, equals(2));

        final indexes = verifiedDb.select(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_edit_ops%';",
        );
        expect(indexes.length, equals(2));
      } finally {
        verifiedDb.close();
      }
    });

    test('refuses file from newer schema with clear error', () async {
      final futureFilePath = '${tempDir.path}/future_v99.ssproj';

      final db = sqlite3.open(futureFilePath);
      db.execute('''
        CREATE TABLE schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
        );
      ''');
      db.execute('''
        CREATE TABLE project_state (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          revision INTEGER NOT NULL,
          schema_version INTEGER NOT NULL,
          document_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
      ''');
      db.execute("INSERT INTO schema_migrations VALUES (99, '2099-01-01T00:00:00Z');");
      db.execute('''
        INSERT INTO project_state VALUES (
          'proj-future', 'Future Project', 1, 99, '{}',
          '2099-01-01T00:00:00Z', '2099-01-01T00:00:00Z'
        );
      ''');
      db.close();

      expect(
        () => storage.openProjectFile(futureFilePath),
        throwsA(
          isA<StorageError>()
              .having((e) => e.code, 'code', 'STORE_CORRUPT')
              .having((e) => e.details['file_version'], 'file_version', 99)
              .having((e) => e.message, 'message', contains('newer than max supported')),
        ),
      );
    });
  });
}
