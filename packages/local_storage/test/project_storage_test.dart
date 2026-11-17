import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectFileStorage & AtomicSaver', () {
    late Directory tempDir;
    late ProjectFileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_storage_test_');
      storage = const ProjectFileStorage();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('round-trip save and open preserves document data, revision, and ops log', () async {
      final filePath = '${tempDir.path}/test_project.ssproj';
      const docJson = '{"id":"proj-1","name":"Test Project","tracks":[],"assets":{}}';

      final projectData = ProjectFileData(
        projectId: 'proj-1',
        name: 'Test Project',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 42,
        documentJson: docJson,
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      final ops = [
        const StoredEditOp(
          projectId: 'proj-1',
          revision: 1,
          batchId: 'batch-1',
          opType: 'track.insert',
          payloadJson: '{"track_id":"v1"}',
          inverseJson: '{"track_id":"v1"}',
          origin: 'ui',
          createdAt: '2026-11-17T00:00:01Z',
        ),
        const StoredEditOp(
          projectId: 'proj-1',
          revision: 2,
          batchId: 'batch-2',
          opType: 'clip.insert',
          payloadJson: '{"clip_id":"c1"}',
          inverseJson: '{"clip_id":"c1"}',
          origin: 'ai',
          createdAt: '2026-11-17T00:00:02Z',
        ),
      ];

      // Save
      await storage.saveProjectFile(filePath, projectData, ops: ops);

      // Verify file exists and .part does NOT exist
      expect(File(filePath).existsSync(), isTrue);
      expect(File('$filePath.part').existsSync(), isFalse);

      // Open
      final (loadedData, loadedOps) = await storage.openProjectFile(filePath);

      expect(loadedData.projectId, equals('proj-1'));
      expect(loadedData.name, equals('Test Project'));
      expect(loadedData.revision, equals(42));
      expect(loadedData.schemaVersion, equals(SchemaMigrations.currentVersion));
      expect(loadedData.documentJson, equals(docJson));

      expect(loadedOps.length, equals(2));
      expect(loadedOps[0].batchId, equals('batch-1'));
      expect(loadedOps[0].origin, equals('ui'));
      expect(loadedOps[1].batchId, equals('batch-2'));
      expect(loadedOps[1].origin, equals('ai'));
    });

    test('fault injection before write leaves previous version intact and cleans .part', () async {
      final filePath = '${tempDir.path}/fault_before_write.ssproj';
      final v1Data = ProjectFileData(
        projectId: 'proj-v1',
        name: 'V1 Name',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 1,
        documentJson: '{"v":1}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      // 1. Initial valid save
      await storage.saveProjectFile(filePath, v1Data);

      // 2. Fault before write
      final v2Data = v1Data.copyWith(name: 'V2 Name', revision: 2);
      expect(
        () => storage.saveProjectFile(
          filePath,
          v2Data,
          faultStage: SaveFaultStage.beforeWrite,
        ),
        throwsA(isA<StorageError>().having((e) => e.code, 'code', 'STORE_CORRUPT')),
      );

      // 3. Verify previous version untouched and no .part leftover
      expect(File('$filePath.part').existsSync(), isFalse);
      final (loadedData, _) = await storage.openProjectFile(filePath);
      expect(loadedData.revision, equals(1));
      expect(loadedData.name, equals('V1 Name'));
    });

    test('fault injection after write before fsync leaves previous version intact', () async {
      final filePath = '${tempDir.path}/fault_after_write.ssproj';
      final v1Data = ProjectFileData(
        projectId: 'proj-v1',
        name: 'V1 Name',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 1,
        documentJson: '{"v":1}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath, v1Data);

      final v2Data = v1Data.copyWith(name: 'V2 Name', revision: 2);
      expect(
        () => storage.saveProjectFile(
          filePath,
          v2Data,
          faultStage: SaveFaultStage.afterWriteBeforeFsync,
        ),
        throwsA(isA<StorageError>().having((e) => e.code, 'code', 'STORE_CORRUPT')),
      );

      expect(File('$filePath.part').existsSync(), isFalse);
      final (loadedData, _) = await storage.openProjectFile(filePath);
      expect(loadedData.revision, equals(1));
    });

    test('fault injection before rename leaves previous version intact', () async {
      final filePath = '${tempDir.path}/fault_before_rename.ssproj';
      final v1Data = ProjectFileData(
        projectId: 'proj-v1',
        name: 'V1 Name',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 1,
        documentJson: '{"v":1}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath, v1Data);

      final v2Data = v1Data.copyWith(name: 'V2 Name', revision: 2);
      expect(
        () => storage.saveProjectFile(
          filePath,
          v2Data,
          faultStage: SaveFaultStage.beforeRename,
        ),
        throwsA(isA<StorageError>().having((e) => e.code, 'code', 'STORE_CORRUPT')),
      );

      expect(File('$filePath.part').existsSync(), isFalse);
      final (loadedData, _) = await storage.openProjectFile(filePath);
      expect(loadedData.revision, equals(1));
    });

    test('simulated disk-full throws STORE_DISK_FULL with old file untouched and .part cleaned', () async {
      final filePath = '${tempDir.path}/disk_full.ssproj';
      final v1Data = ProjectFileData(
        projectId: 'proj-v1',
        name: 'Original',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 5,
        documentJson: '{"rev":5}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath, v1Data);

      final v2Data = v1Data.copyWith(name: 'Attempted Rev 6', revision: 6);
      expect(
        () => storage.saveProjectFile(filePath, v2Data, simulateDiskFull: true),
        throwsA(
          isA<StorageError>()
              .having((e) => e.code, 'code', 'STORE_DISK_FULL')
              .having((e) => e.category, 'category', 'store')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );

      expect(File('$filePath.part').existsSync(), isFalse);
      final (loadedData, _) = await storage.openProjectFile(filePath);
      expect(loadedData.revision, equals(5));
      expect(loadedData.name, equals('Original'));
    });

    test('corrupted file with truncated or altered bytes throws STORE_CORRUPT', () async {
      final filePath = '${tempDir.path}/corrupt.ssproj';
      final validData = ProjectFileData(
        projectId: 'proj-corrupt',
        name: 'Corrupt Test',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 1,
        documentJson: '{"valid":true}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath, validData);

      // Truncate the file to 32 bytes (corrupting SQLite header/pages)
      final file = File(filePath);
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, 32));

      expect(
        () => storage.openProjectFile(filePath),
        throwsA(
          isA<StorageError>()
              .having((e) => e.code, 'code', 'STORE_CORRUPT')
              .having((e) => e.category, 'category', 'store')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );

      // Alter random bytes in SQLite pages
      final damagedBytes = List<int>.from(bytes);
      for (var i = 16; i < 64 && i < damagedBytes.length; i++) {
        damagedBytes[i] = 0xff;
      }
      file.writeAsBytesSync(damagedBytes);

      expect(
        () => storage.openProjectFile(filePath),
        throwsA(isA<StorageError>().having((e) => e.code, 'code', 'STORE_CORRUPT')),
      );
    });

    test('leftover .part file from previous crash is detected and cleaned on open', () async {
      final filePath = '${tempDir.path}/leftover_part.ssproj';
      final validData = ProjectFileData(
        projectId: 'proj-1',
        name: 'Good Project',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 10,
        documentJson: '{"good":true}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath, validData);

      // Simulate an uncleaned .part file left behind by an external sudden crash
      final leftoverPart = File('$filePath.part');
      leftoverPart.writeAsStringSync('corrupt partial write debris');
      expect(leftoverPart.existsSync(), isTrue);

      // openProjectFile cleans leftover .part and opens good version
      final (loadedData, _) = await storage.openProjectFile(filePath);
      expect(loadedData.revision, equals(10));
      expect(leftoverPart.existsSync(), isFalse);
    });
  });
}
