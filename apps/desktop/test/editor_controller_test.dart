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
    tempDir = Directory.systemTemp.createTempSync('ss_controller_test_');
    fakeWorker = FakeMediaWorker();
    mediaLibrary = MediaLibraryService(worker: fakeWorker, cacheDir: tempDir);

    final initialDoc = ProjectDocument(
      name: 'controller_test_project',
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
    tempDir.deleteSync(recursive: true);
  });

  group('EditorController Core Functionality', () {
    test('initializes with default playhead and zoom', () {
      expect(controller.playheadTicks, equals(0));
      expect(controller.pixelsPerSecond, equals(50.0));
      expect(controller.isPlaying, isFalse);
      expect(controller.revision, equals(0));
      expect(controller.document.tracks.length, equals(2));
    });

    test('seeks and clamps playhead to valid range', () {
      controller.seek(2000000);
      expect(controller.playheadTicks, equals(2000000));

      controller.seek(-100);
      expect(controller.playheadTicks, equals(0));
    });

    test('stepFrame moves by exact frame ticks', () {
      // 30fps -> 1 frame = 1,000,000 / 30 = 33333.33 -> 33334 ticks
      controller.stepFrame(1);
      expect(controller.playheadTicks, equals(33334));

      controller.stepFrame(-1);
      expect(controller.playheadTicks, equals(0));
    });

    test('zooms in and out within clamped boundaries', () {
      controller.zoomIn();
      expect(controller.pixelsPerSecond, equals(62.5));

      controller.zoomOut();
      expect(controller.pixelsPerSecond, equals(50.0));

      // Test lower boundary clamp (5.0)
      for (int i = 0; i < 20; i++) {
        controller.zoomOut();
      }
      expect(controller.pixelsPerSecond, greaterThanOrEqualTo(5.0));

      // Test upper boundary clamp (500.0)
      for (int i = 0; i < 40; i++) {
        controller.zoomIn();
      }
      expect(controller.pixelsPerSecond, lessThanOrEqualTo(500.0));
    });

    test('switches tool mode between select and razor', () {
      expect(controller.toolMode, equals(ToolMode.select));
      controller.setToolMode(ToolMode.razor);
      expect(controller.toolMode, equals(ToolMode.razor));
      controller.setToolMode(ToolMode.select);
      expect(controller.toolMode, equals(ToolMode.select));
    });

    test('adds imported media asset and clip to timeline', () async {
      const imported = ImportedMediaAsset(
        id: 'asset_test_1',
        kind: MediaKind.video,
        sourceUri: 'file:///media/test.mp4',
        sourcePath: '/media/test.mp4',
        durationTicks: 3000000, // 3 seconds
        blake3Hash: 'fakeblake3hash',
        probe: MediaProbeResult(
          filePath: '/media/test.mp4',
          container: 'mp4',
          durationTicks: 3000000,
          fileSizeBytes: 1048576,
        ),
      );

      final added = await controller.addAssetToTimeline(imported);
      expect(added, isTrue);
      expect(controller.revision, equals(1));
      expect(controller.document.assets.containsKey('asset_test_1'), isTrue);

      final videoTrack = controller.document.tracks.firstWhere((t) => t.id == 'track_v1');
      expect(videoTrack.clips.length, equals(1));
      expect(videoTrack.clips.first.durationTicks, equals(3000000));
    });

    test('splits clip at playhead position', () async {
      const imported = ImportedMediaAsset(
        id: 'asset_test_2',
        kind: MediaKind.video,
        sourceUri: 'file:///media/clip.mp4',
        sourcePath: '/media/clip.mp4',
        durationTicks: 4000000, // 4 seconds
        blake3Hash: 'fakeblake3hash2',
        probe: MediaProbeResult(
          filePath: '/media/clip.mp4',
          container: 'mp4',
          durationTicks: 4000000,
          fileSizeBytes: 2048576,
        ),
      );
      await controller.addAssetToTimeline(imported);

      final track = controller.document.tracks.firstWhere((t) => t.id == 'track_v1');
      final clip = track.clips.first;

      // Seek playhead to 2 seconds (2,000,000 ticks)
      controller.seek(2000000);

      // Split clip
      final splitSuccess = await controller.splitClipAtPlayhead(track.id, clip.id);
      expect(splitSuccess, isTrue);
      expect(controller.revision, equals(2));

      final updatedTrack = controller.document.tracks.firstWhere((t) => t.id == 'track_v1');
      expect(updatedTrack.clips.length, equals(2));
      expect(updatedTrack.clips[0].durationTicks, equals(2000000));
      expect(updatedTrack.clips[1].durationTicks, equals(2000000));
      expect(updatedTrack.clips[1].timelineStartTicks, equals(2000000));
    });

    test('deletes selected clip and undos deletion', () async {
      const imported = ImportedMediaAsset(
        id: 'asset_test_3',
        kind: MediaKind.video,
        sourceUri: 'file:///media/clip3.mp4',
        sourcePath: '/media/clip3.mp4',
        durationTicks: 2000000,
        blake3Hash: 'fakeblake3hash3',
        probe: MediaProbeResult(
          filePath: '/media/clip3.mp4',
          container: 'mp4',
          durationTicks: 2000000,
          fileSizeBytes: 1048576,
        ),
      );
      await controller.addAssetToTimeline(imported);
      expect(controller.revision, equals(1));

      final track = controller.document.tracks.firstWhere((t) => t.id == 'track_v1');
      final clip = track.clips.first;

      controller.selectClip(clip.id, trackId: track.id);
      expect(controller.selectedClipId, equals(clip.id));

      final deleted = await controller.deleteSelectedClip();
      expect(deleted, isTrue);
      expect(controller.revision, equals(2));
      expect(controller.selectedClipId, isNull);

      final updatedTrack = controller.document.tracks.firstWhere((t) => t.id == 'track_v1');
      expect(updatedTrack.clips, isEmpty);

      // Undo deletion
      await controller.undo();
      expect(controller.revision, equals(3));

      final restoredTrack = controller.document.tracks.firstWhere((t) => t.id == 'track_v1');
      expect(restoredTrack.clips.length, equals(1));
    });

    test('resolves render graph for export preview validation', () {
      final graph = controller.editingService.resolveGraph(
        revision: controller.revision,
        range: const RangeTicks(startTicks: 0, durationTicks: 1000000),
      );
      expect(graph, isNotNull);
      expect(graph.graphSchema, equals('shadow.rendergraph/1'));
      expect(graph.timebase.fpsNum, equals(30));
    });
  });
}
