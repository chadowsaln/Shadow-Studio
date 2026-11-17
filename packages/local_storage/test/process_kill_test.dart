import 'dart:convert';
import 'dart:io';

import 'package:local_storage/local_storage.dart';
import 'package:test/test.dart';

void main() {
  group('Crash Safety & Process Kill Test (QG-9)', () {
    late Directory tempDir;
    late ProjectFileStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_kill_test_');
      storage = const ProjectFileStorage();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('child process killed mid-save with SIGKILL leaves old version intact and cleans .part', () async {
      final filePath = '${tempDir.path}/killed_mid_save.ssproj';

      // 1. Parent writes original valid version at revision 5
      final originalData = ProjectFileData(
        projectId: 'proj-stable',
        name: 'Stable Version',
        schemaVersion: SchemaMigrations.currentVersion,
        revision: 5,
        documentJson: '{"stable":true,"revision":5}',
        createdAt: '2026-11-17T00:00:00Z',
        updatedAt: '2026-11-17T00:00:00Z',
      );

      await storage.saveProjectFile(filePath, originalData);
      expect(File(filePath).existsSync(), isTrue);

      // 2. Spawn child process that writes to .part and waits to be killed
      final possiblePaths = [
        '${Directory.current.path}/test/mid_save_worker.dart',
        '${Directory.current.path}/packages/local_storage/test/mid_save_worker.dart',
      ];
      final workerScriptPath = possiblePaths.firstWhere(
        (p) => File(p).existsSync(),
        orElse: () => '${Directory.current.path}/test/mid_save_worker.dart',
      );

      final process = await Process.start(
        Platform.executable,
        [workerScriptPath, filePath],
        mode: ProcessStartMode.normal,
      );

      // Collect stderr for diagnostics if child fails
      final stderrBuffer = StringBuffer();
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

      // Wait until child signals PART_WRITTEN
      var signaled = false;
      final lines = process.stdout.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (line.contains('PART_WRITTEN')) {
          signaled = true;
          break;
        }
      }

      if (!signaled) {
        fail('Child process failed to emit PART_WRITTEN. stderr: $stderrBuffer');
      }

      // Verify the .part file currently exists on disk
      final partFile = File('$filePath.part');
      expect(partFile.existsSync(), isTrue);

      // 3. Brutally kill the child process mid-save with SIGKILL
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;

      // 4. Parent reopens the file:
      // - detects and cleans leftover .part
      // - opens original version at revision 5 completely undamaged
      final (loadedData, _) = await storage.openProjectFile(filePath);

      expect(loadedData.projectId, equals('proj-stable'));
      expect(loadedData.revision, equals(5));
      expect(loadedData.name, equals('Stable Version'));

      // The leftover .part file was cleaned up on open
      expect(partFile.existsSync(), isFalse);
    });
  });
}
