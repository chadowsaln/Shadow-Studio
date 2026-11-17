import 'dart:io';

import 'package:desktop/src/controller/editor_controller.dart';
import 'package:editing_core/editing_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

void main() {
  late Directory tempDir;
  late FakeMediaWorker fakeWorker;
  late MediaLibraryService mediaLibrary;
  late EditingService editingService;
  late EditorController controller;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('shadow_dnd_test_');
    fakeWorker = FakeMediaWorker();
    mediaLibrary = MediaLibraryService(worker: fakeWorker, cacheDir: tempDir);

    final initialDoc = ProjectDocument(
      name: 'Test Project',
      profile: ProjectProfile.hd1080p(),
      timebase: Timebase.fps30(),
      tracks: [
        Track(id: 'track_v1', kind: TrackKind.video, position: 0, name: 'V1'),
        Track(id: 'track_a1', kind: TrackKind.audio, position: 1, name: 'A1'),
      ],
      assets: const {},
    );

    editingService = DefaultEditingService(initialDocument: initialDoc);
    controller = EditorController(
      editingService: editingService,
      mediaLibrary: mediaLibrary,
    );
  });

  tearDown(() {
    controller.dispose();
    fakeWorker.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Drag and Drop & Magnetic Snapping Interactions', () {
    test('insertClipAt adds clip and asset to specified track at drop tick', () async {
      const sampleAsset = ImportedMediaAsset(
        id: 'asset_dnd_01',
        sourceUri: 'file:///tmp/sample.mp4',
        sourcePath: '/tmp/sample.mp4',
        kind: MediaKind.video,
        durationTicks: 5000000, // 5s
        blake3Hash: 'b3hash1234567890abcdef',
        probe: MediaProbeResult(
          filePath: '/tmp/sample.mp4',
          container: 'mp4',
          durationTicks: 5000000,
          fileSizeBytes: 2048576,
        ),
      );

      final success = await controller.insertClipAt(
        imported: sampleAsset,
        trackId: 'track_v1',
        timelineStartTicks: 2000000, // 2s
      );

      expect(success, isTrue);
      expect(controller.document.tracks[0].clips.length, equals(1));
      final clip = controller.document.tracks[0].clips.first;
      expect(clip.timelineStartTicks, equals(2000000));
      expect(clip.durationTicks, equals(5000000));
      expect(clip.assetId, equals('asset_dnd_01'));
      expect(controller.document.assets.containsKey('asset_dnd_01'), isTrue);
    });

    test('moveClip updates clip start position with atomic transaction', () async {
      const sampleAsset = ImportedMediaAsset(
        id: 'asset_move_01',
        sourceUri: 'file:///tmp/sample.mp4',
        sourcePath: '/tmp/sample.mp4',
        kind: MediaKind.video,
        durationTicks: 3000000,
        blake3Hash: 'b3hash1111111111111111',
        probe: MediaProbeResult(
          filePath: '/tmp/sample.mp4',
          container: 'mp4',
          durationTicks: 3000000,
          fileSizeBytes: 1048576,
        ),
      );

      await controller.insertClipAt(
        imported: sampleAsset,
        trackId: 'track_v1',
        timelineStartTicks: 1000000,
      );

      final clipId = controller.document.tracks[0].clips.first.id;
      final moved = await controller.moveClip(
        trackId: 'track_v1',
        clipId: clipId,
        newTimelineStartTicks: 4000000,
      );

      expect(moved, isTrue);
      final updatedClip = controller.document.tracks[0].clips.first;
      expect(updatedClip.timelineStartTicks, equals(4000000));
      expect(updatedClip.timelineEndTicks, equals(7000000));
    });

    test('snapTick magnetically snaps to 0, playhead, and adjacent clip boundaries', () async {
      controller.setPixelsPerSecond(50.0); // 1s = 50px -> 12px threshold = 240,000 ticks

      // 1. Snap to 0
      final snappedToZero = controller.snapTick(150000, thresholdPx: 12);
      expect(snappedToZero, equals(0));

      // 2. Snap to Playhead
      controller.seek(3000000); // 3s
      final snappedToPlayhead = controller.snapTick(3100000, thresholdPx: 12);
      expect(snappedToPlayhead, equals(3000000));

      // 3. Snap to clip boundary
      const sampleAsset = ImportedMediaAsset(
        id: 'asset_snap_01',
        sourceUri: 'file:///tmp/sample.mp4',
        sourcePath: '/tmp/sample.mp4',
        kind: MediaKind.video,
        durationTicks: 4000000,
        blake3Hash: 'b3hash2222222222222222',
        probe: MediaProbeResult(
          filePath: '/tmp/sample.mp4',
          container: 'mp4',
          durationTicks: 4000000,
          fileSizeBytes: 1048576,
        ),
      );
      await controller.insertClipAt(
        imported: sampleAsset,
        trackId: 'track_v1',
        timelineStartTicks: 5000000, // ends at 9,000,000
      );

      // Candidate near 9,000,000 should snap to 9,000,000
      final snappedToClipEnd = controller.snapTick(9120000, thresholdPx: 12);
      expect(snappedToClipEnd, equals(9000000));

      // When snapping is disabled, candidates are preserved
      controller.toggleSnapping();
      expect(controller.snappingEnabled, isFalse);
      final noSnap = controller.snapTick(9120000);
      expect(noSnap, equals(9120000));
    });

    test('addTrack and removeTrack modify project tracks dynamically', () async {
      expect(controller.document.tracks.length, equals(2));

      // Add a second video track V2
      final added = await controller.addTrack(TrackKind.video);
      expect(added, isTrue);
      expect(controller.document.tracks.length, equals(3));
      final newTrack = controller.document.tracks.last;
      expect(newTrack.kind, equals(TrackKind.video));
      expect(newTrack.name, equals('V2'));

      // Remove the newly added track
      final removed = await controller.removeTrack(newTrack.id);
      expect(removed, isTrue);
      expect(controller.document.tracks.length, equals(2));
    });
  });
}
