import 'dart:io';

import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('EditingService Persistence Integration (V2-D9 & V2-D11)', () {
    late Directory tempDir;
    late Asset sampleAsset;
    late ProjectDocument doc;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ss_edit_persist_');

      sampleAsset = Asset(
        id: UuidV7.generate(),
        kind: AssetKind.video,
        uri: 'file:///media/intro.mp4',
        durationTicks: 20000000,
        hash: '0' * 64,
      );

      final track0 = Track(
        id: UuidV7.generate(),
        kind: TrackKind.video,
        position: 0,
        name: 'V1',
      );

      doc = ProjectDocument(
        name: 'Persistence Integration Project',
        profile: ProjectProfile.hd1080p(),
        timebase: Timebase.ntsc2997(),
        tracks: [track0],
        assets: {sampleAsset.id: sampleAsset},
      );
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('save and openProject round-trip preserves exact document and revision', () async {
      final projectPath = '${tempDir.path}/integration.ssproj';
      final service = DefaultEditingService(initialDocument: doc);

      // Perform an edit transaction: Add clip
      final clip = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleAsset.id,
        timelineStartTicks: 0,
        durationTicks: 5000000,
        sourceInTicks: 1000000,
      );

      final outcome = await service.apply(
        EditTransaction.single(AddClipCommand(trackId: doc.tracks[0].id, clip: clip)),
        expectedRevision: 0,
      );
      expect(outcome.isSuccess, isTrue);
      expect(service.revision, equals(1));

      // Save to projectPath
      await service.saveTo(projectPath);
      expect(File(projectPath).existsSync(), isTrue);
      expect(File('$projectPath.part').existsSync(), isFalse);

      // Open in a completely fresh EditingService instance
      final freshBlankDoc = ProjectDocument.createBlank(name: 'Blank');
      final newService = DefaultEditingService(initialDocument: freshBlankDoc);

      final loadedDoc = await newService.openProject(projectPath);
      expect(loadedDoc, equals(service.currentDocument));
      expect(newService.revision, equals(1));
      expect(newService.projectFilePath, equals(projectPath));
      expect(newService.currentDocument.tracks[0].clips.length, equals(1));
      expect(newService.currentDocument.tracks[0].clips[0].id, equals(clip.id));
      expect(newService.committedOps.length, equals(1));
      expect(newService.committedOps.first.opType, equals('clip.insert'));

      // Perform a subsequent edit on the loaded project
      final clip2 = Clip.video(
        id: UuidV7.generate(),
        assetId: sampleAsset.id,
        timelineStartTicks: 5000000,
        durationTicks: 3000000,
      );

      final outcome2 = await newService.apply(
        EditTransaction.single(AddClipCommand(trackId: doc.tracks[0].id, clip: clip2)),
        expectedRevision: 1,
      );
      expect(outcome2.isSuccess, isTrue);
      expect(newService.revision, equals(2));

      // Save without passing path (uses established projectFilePath)
      await newService.save();

      // Reopen again and verify revision 2 and both clips are intact
      final loadedDoc2 = await service.openProject(projectPath);
      expect(loadedDoc2.tracks[0].clips.length, equals(2));
      expect(service.revision, equals(2));
    });

    test('openProject on corrupt file throws ShadowError STORE_CORRUPT', () async {
      final projectPath = '${tempDir.path}/corrupt_test.ssproj';
      File(projectPath).writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]); // invalid file

      final service = DefaultEditingService(initialDocument: doc);
      expect(
        () => service.openProject(projectPath),
        throwsA(
          isA<ShadowError>()
              .having((e) => e.code, 'code', 'STORE_CORRUPT')
              .having((e) => e.category, 'category', 'store')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });
  });
}
