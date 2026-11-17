import 'dart:convert';
import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:test/test.dart';

void main() {
  group('Performance & Budgets (QG-7, QG-10, Spec §15)', () {
    late Directory tempDir;
    late ProjectFileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_budget_test_');
      storage = const ProjectFileStorage();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('document with 200 clips opens within spec target (< 120 ms) and 300 clips saves quickly', () async {
      // 1. Generate 200-clip project
      final clips200 = <Map<String, dynamic>>[];
      for (var i = 0; i < 200; i++) {
        clips200.add({
          'id': 'clip-$i',
          'timeline_start_ticks': i * 1000000,
          'duration_ticks': 1000000,
          'source_in_ticks': 0,
          'speed_num': 1,
          'speed_den': 1,
          'enabled': true,
        });
      }

      final doc200Json = jsonEncode({
        'id': 'proj-200',
        'name': '200 Clips Benchmark',
        'tracks': [
          {'id': 'v1', 'kind': 'video', 'position': 0, 'name': 'V1', 'clips': clips200},
        ],
        'assets': <String, dynamic>{},
      });

      final filePath200 = '${tempDir.path}/bench_200.ssproj';
      final data200 = ProjectFileData(
        projectId: 'proj-200',
        name: '200 Clips Benchmark',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 10,
        documentJson: doc200Json,
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath200, data200);

      // Benchmark Open for 200 clips (Spec v1 §3.5.3 target < 120 ms; QG-7 < 2500 ms)
      final openStopwatch = Stopwatch()..start();
      final (loadedData, _) = await storage.openProjectFile(filePath200);
      final openMs = openStopwatch.elapsedMilliseconds;

      expect(loadedData.projectId, equals('proj-200'));
      expect(loadedData.revision, equals(10));
      // Measured budget check: < 120 ms
      expect(
        openMs,
        lessThan(120),
        reason: '200-clip project open took $openMs ms (budget is < 120 ms per Spec §3.5.3)',
      );

      // 2. Generate 300-clip project and benchmark save time
      final clips300 = <Map<String, dynamic>>[];
      for (var i = 0; i < 300; i++) {
        clips300.add({
          'id': 'clip-$i',
          'timeline_start_ticks': i * 1000000,
          'duration_ticks': 1000000,
          'source_in_ticks': 0,
          'speed_num': 1,
          'speed_den': 1,
          'enabled': true,
        });
      }

      final doc300Json = jsonEncode({
        'id': 'proj-300',
        'name': '300 Clips Benchmark',
        'tracks': [
          {'id': 'v1', 'kind': 'video', 'position': 0, 'name': 'V1', 'clips': clips300},
        ],
        'assets': <String, dynamic>{},
      });

      final filePath300 = '${tempDir.path}/bench_300.ssproj';
      final data300 = ProjectFileData(
        projectId: 'proj-300',
        name: '300 Clips Benchmark',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 15,
        documentJson: doc300Json,
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      final saveStopwatch = Stopwatch()..start();
      await storage.saveProjectFile(filePath300, data300);
      final saveMs = saveStopwatch.elapsedMilliseconds;

      expect(File(filePath300).existsSync(), isTrue);
      // 300-clip save budget check: < 250 ms
      expect(
        saveMs,
        lessThan(250),
        reason: '300-clip project atomic save took $saveMs ms (budget is < 250 ms)',
      );
    });
  });
}
