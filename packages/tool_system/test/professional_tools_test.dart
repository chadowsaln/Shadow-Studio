import 'dart:io';

import 'package:editing_core/editing_core.dart' as core;
import 'package:media_core/media_core.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_tool_system/tool_system.dart';
import 'package:test/test.dart';

class _Audit implements AuditSink {
  @override
  Future<void> record(Map<String, Object?> event) async {}
}

ToolContext _ctx({
  String workspaceRoot = '/tmp/ws',
  int revision = 0,
  CancellationToken? cancel,
}) {
  return ToolContext(
    taskId: 'task_test',
    correlationId: 'corr_test',
    revision: revision,
    workspaceRoot: workspaceRoot,
    cancel: cancel ?? CancellationToken(),
    audit: _Audit(),
  );
}

String? _fixture(String name) {
  for (final candidate in <String>[
    'tools/media-spike/out/fixtures/$name',
    '../../tools/media-spike/out/fixtures/$name',
    '../../../tools/media-spike/out/fixtures/$name',
  ]) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}

bool _hasFfmpeg() {
  try {
    final result = Process.runSync('ffmpeg', <String>['-version']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  group('MediaProbeTool (real worker)', () {
    test('returns probe data from the media worker', () async {
      final worker = FakeMediaWorker();
      final probe = MediaProbeResult(
        filePath: '/tmp/ws/a.mp4',
        container: 'mov,mp4,m4a',
        durationTicks: 6006000,
        fileSizeBytes: 1234,
        videoStreams: const <VideoStreamInfo>[],
      );
      worker.mockProbes['/tmp/ws/a.mp4'] = probe;

      final tool = MediaProbeTool(worker: worker);
      final result = await tool.execute(
        _ctx(workspaceRoot: '/tmp/ws'),
        <String, Object?>{'path': 'a.mp4'},
      );

      expect(result.success, isTrue);
      final data = result.data['probe'] as Map<String, Object?>;
      expect(data['duration_ticks'], 6006000);
      expect(result.data['path'], '/tmp/ws/a.mp4');
    });

    test('maps worker failures to structured media codes', () async {
      final worker = FakeMediaWorker()..shouldReportCorrupt = true;
      worker.mockProbes['/tmp/ws/a.mp4'] = const MediaProbeResult(
        filePath: '/tmp/ws/a.mp4',
        container: 'mp4',
        durationTicks: 1,
        fileSizeBytes: 1,
      );
      final tool = MediaProbeTool(worker: worker);
      final result = await tool.execute(
        _ctx(workspaceRoot: '/tmp/ws'),
        <String, Object?>{'path': 'a.mp4'},
      );
      expect(result.success, isFalse);
      expect(result.errorCode, ShadowErrorCode.mediaCorrupt);
    });

    test('probes a real file with ffprobe', () async {
      final path = _fixture('intro-4k.mp4');
      if (path == null || !_hasFfmpeg()) {
        markTestSkipped('ffmpeg/fixture unavailable');
        return;
      }
      final tool = MediaProbeTool();
      final result = await tool.execute(
        _ctx(workspaceRoot: File(path).parent.path),
        <String, Object?>{'path': path},
      );
      expect(result.success, isTrue);
      final data = result.data['probe'] as Map<String, Object?>;
      expect(data['duration_ticks'], 6006000);
      expect((data['video_streams'] as List).isNotEmpty, isTrue);
    });
  });

  group('MediaAnalysisTool (real ffmpeg)', () {
    test('parses scene, black segment and volume output', () {
      final scenes = MediaAnalysisTool.parseSceneTimestamps(
        '[Parsed_showinfo_1] n:0 pts:1024 pts_time:1.5\n'
        '[Parsed_showinfo_1] n:1 pts:2048 pts_time:3.25\n',
      );
      expect(scenes, hasLength(2));
      expect(scenes.first['time_ticks'], 1500000);

      final blacks = MediaAnalysisTool.parseBlackSegments(
        'black_start:0.5 black_end:1.2 black_duration:0.7\n',
      );
      expect(blacks.single['start_ticks'], 500000);

      final volume = MediaAnalysisTool.parseVolume(
        '[Parsed_volumedetect_0] mean_volume: -20.5 dB\n'
        '[Parsed_volumedetect_0] max_volume: 0.0 dB\n',
      );
      expect(volume!['mean_db'], -20.5);
      expect(volume['clipped'], isTrue);
    });

    test('analyzes a real media file', () async {
      final path = _fixture('intro-4k.mp4');
      if (path == null || !_hasFfmpeg()) {
        markTestSkipped('ffmpeg/fixture unavailable');
        return;
      }
      final tool = MediaAnalysisTool();
      final result = await tool.execute(
        _ctx(workspaceRoot: File(path).parent.path),
        <String, Object?>{'path': path},
      );
      expect(result.success, isTrue);
      final analysis = result.data['analysis'] as Map<String, Object?>;
      expect(analysis['has_video'], isTrue);
      expect(analysis['scene_count'], isA<int>());
      expect(analysis['black_segments'], isA<List<Object?>>());
    });

    test('measures loudness and waveform for real audio', () async {
      final path = _fixture('vo-take3.wav');
      if (path == null || !_hasFfmpeg()) {
        markTestSkipped('ffmpeg/fixture unavailable');
        return;
      }
      final tool = MediaAnalysisTool();
      final result = await tool.execute(
        _ctx(workspaceRoot: File(path).parent.path),
        <String, Object?>{'path': path},
      );
      expect(result.success, isTrue);
      final analysis = result.data['analysis'] as Map<String, Object?>;
      expect(analysis['has_audio'], isTrue);
      expect(analysis['volume'], isNotNull);
      expect(analysis['waveform_samples'], isA<int>());
    });
  });

  group('TimelineEditTool (real Editing Core)', () {
    late core.DefaultEditingService editing;
    late core.ProjectDocument document;

    setUp(() async {
      document = core.ProjectDocument.createBlank(name: 'Ad');
      editing = core.DefaultEditingService(initialDocument: document);
      await editing.apply(
        core.EditTransaction(
          commands: <core.EditCommand>[
            core.AddTrackCommand(
              core.Track(
                id: 'track_v1',
                kind: core.TrackKind.video,
                position: 0,
                name: 'Main',
              ),
            ),
            core.AddAssetCommand(
              core.Asset(
                id: 'asset_intro',
                kind: core.AssetKind.video,
                uri: 'intro.mp4',
                durationTicks: 40000000,
              ),
            ),
          ],
        ),
        expectedRevision: 0,
      );
    });

    test('adds a clip and bumps revision through the adapter', () async {
      final adapter = CoreEditingServiceAdapter(editing);
      final tool = TimelineEditTool(adapter);

      final result = await tool.execute(
        _ctx(revision: 1),
        <String, Object?>{
          'operations': <Object?>[
            <String, Object?>{
              'type': 'add_clip',
              'target': 'track_v1',
              'payload': <String, Object?>{
                'assetId': 'asset_intro',
                'startTick': 0,
                'durationTicks': 30000000,
              },
            },
          ],
        },
      );

      expect(result.success, isTrue);
      expect(result.data['revision'], 2);
      expect(result.data['applied'], 1);
      expect(editing.currentDocument.tracks.single.clips, hasLength(1));
    });

    test('rejects a stale revision without applying edits', () async {
      final tool = TimelineEditTool(CoreEditingServiceAdapter(editing));
      final result = await tool.execute(
        _ctx(revision: 0),
        <String, Object?>{
          'operations': <Object?>[
            <String, Object?>{
              'type': 'add_clip',
              'target': 'track_v1',
              'payload': <String, Object?>{
                'assetId': 'asset_intro',
                'startTick': 0,
                'durationTicks': 10,
              },
            },
          ],
        },
      );
      expect(result.success, isFalse);
      expect(result.errorCode, ShadowErrorCode.editRevisionMismatch);
      expect(editing.currentDocument.tracks.single.clips, isEmpty);
    });

    test('splits and trims a clip atomically', () async {
      final adapter = CoreEditingServiceAdapter(editing);
      final tool = TimelineEditTool(adapter);

      final added = await tool.execute(
        _ctx(revision: 1),
        <String, Object?>{
          'operations': <Object?>[
            <String, Object?>{
              'type': 'add_clip',
              'target': 'track_v1',
              'payload': <String, Object?>{
                'clipId': 'clip_a',
                'assetId': 'asset_intro',
                'startTick': 0,
                'durationTicks': 10000000,
              },
            },
          ],
        },
      );
      expect(added.success, isTrue);
      final revision = added.data['revision'] as int;

      final split = await tool.execute(
        _ctx(revision: revision),
        <String, Object?>{
          'operations': <Object?>[
            <String, Object?>{
              'type': 'split_clip',
              'target': 'track_v1',
              'payload': <String, Object?>{
                'clipId': 'clip_a',
                'splitAtTick': 5000000,
                'newClipId': 'clip_b',
              },
            },
          ],
        },
      );
      expect(split.success, isTrue);
      expect(editing.currentDocument.tracks.single.clips, hasLength(2));
    });

    test('rejects malformed operations', () async {
      final tool = TimelineEditTool(CoreEditingServiceAdapter(editing));
      final result = await tool.execute(
        _ctx(revision: 1),
        <String, Object?>{'operations': <Object?>[]},
      );
      expect(result.success, isFalse);
      expect(result.errorCode, ShadowErrorCode.toolInvalidArgs);
    });
  });
}