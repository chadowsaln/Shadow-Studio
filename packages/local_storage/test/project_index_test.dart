import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectIndexDatabase (V2-D11)', () {
    late Directory tempDir;
    late ProjectFileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_index_test_');
      storage = const ProjectFileStorage();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('rebuilds index from a folder of projects after deleting index DB', () async {
      final projectsDir = Directory('${tempDir.path}/projects')..createSync();
      final indexDbPath = '${tempDir.path}/app_index.db';

      // 1. Create 3 distinct .ssproj files (including nested folders)
      for (var i = 1; i <= 3; i++) {
        final subDir = Directory('${projectsDir.path}/folder_$i')..createSync();
        final projPath = '${subDir.path}/project_$i.ssproj';

        final data = ProjectFileData(
          projectId: 'proj-$i',
          name: 'Project $i',
          schemaVersion: SchemaMigrations.currentVersion,
          revision: i * 10,
          documentJson: '''{
            "id": "proj-$i",
            "name": "Project $i",
            "tracks": [
              {
                "kind": "video",
                "clips": [
                  {"timeline_start_ticks": 0, "duration_ticks": ${i * 1000000}}
                ]
              }
            ]
          }''',
          createdAt: '2026-11-17T00:00:0${i}Z',
          updatedAt: '2026-11-17T00:00:0${i}Z',
        );

        await storage.saveProjectFile(projPath, data);
      }

      // 2. Open and build index
      var indexDb = ProjectIndexDatabase.open(indexDbPath);
      final count1 = await indexDb.rebuildFromDirectory(projectsDir, storage: storage);
      expect(count1, equals(3));

      final entries1 = indexDb.getAll();
      expect(entries1.length, equals(3));
      final p1 = indexDb.get('proj-1')!;
      expect(p1.name, equals('Project 1'));
      expect(p1.revision, equals(10));
      expect(p1.durationTicks, equals(1000000));

      // Close index DB and delete the SQLite index file (simulating loss or corruption)
      indexDb.close();
      final indexFile = File(indexDbPath);
      expect(indexFile.existsSync(), isTrue);
      indexFile.deleteSync();
      expect(indexFile.existsSync(), isFalse);

      // 3. Re-open index DB and rescan from the projects directory
      indexDb = ProjectIndexDatabase.open(indexDbPath);
      expect(indexDb.getAll(), isEmpty); // starts empty

      final count2 = await indexDb.rebuildFromDirectory(projectsDir, storage: storage);
      expect(count2, equals(3));

      final entries2 = indexDb.getAll();
      expect(entries2.length, equals(3));

      final restoredP1 = indexDb.get('proj-1')!;
      expect(restoredP1.name, equals('Project 1'));
      expect(restoredP1.revision, equals(10));
      expect(restoredP1.durationTicks, equals(1000000));

      final restoredP3 = indexDb.get('proj-3')!;
      expect(restoredP3.name, equals('Project 3'));
      expect(restoredP3.revision, equals(30));
      expect(restoredP3.durationTicks, equals(3000000));

      indexDb.close();
    });
  });
}
