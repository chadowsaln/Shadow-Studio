@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:render_pipeline/render_pipeline.dart';
import 'package:test/test.dart';

import 'graph_fixtures.dart';

bool _hasFfmpeg() {
  try {
    return Process.runSync('ffmpeg', <String>['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  late Directory tempDir;
  late String sourcePath;

  setUpAll(() {
    if (!_hasFfmpeg()) return;
    tempDir = Directory.systemTemp.createTempSync('render_backend_');
    sourcePath = '${tempDir.path}/source.mp4';
    final generated = Process.runSync('ffmpeg', <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=640x360:rate=30:duration=1',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000:duration=1',
      '-pix_fmt',
      'yuv420p',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-c:a',
      'aac',
      '-shortest',
      sourcePath,
    ]);
    if (generated.exitCode != 0) {
      throw StateError(
        'ffmpeg failed to generate the source: ${generated.stderr}',
      );
    }
  });

  tearDownAll(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'ProcessRenderBackend encodes a real MP4 through an atomic temp file',
    () async {
      if (!_hasFfmpeg()) {
        markTestSkipped('ffmpeg unavailable');
        return;
      }

      final graphJson = validGraph();
      graphJson['range'] = <String, Object?>{
        'start_ticks': 0,
        'duration_ticks': 1000000,
      };
      graphJson['tracks'] = <Object?>[
        videoTrack(
          clips: <Object?>[
            videoClip(
              uri: Uri.file(sourcePath).toString(),
              durationTicks: 1000000,
            ),
          ],
        ),
      ];
      final graph = RenderGraphDoc.parse(graphJson);
      final outputPath = '${tempDir.path}/out.mp4';
      final queue = RenderQueue(backend: ProcessRenderBackend());
      addTearDown(queue.dispose);
      final job = queue.enqueue(
        graph,
        preset: RenderPreset.mp4H264720p,
        outputUri: outputPath,
      );

      await queue.drain();

      final finished = queue.jobById(job.id)!;
      expect(finished.state, RenderJobState.succeeded, reason: finished.error);
      expect(finished.progress, 1.0);
      expect(File(outputPath).existsSync(), isTrue);
      expect(File(outputPath).lengthSync(), greaterThan(1000));
      // The temp name keeps the container extension so FFmpeg can mux it, and
      // it must be gone after the atomic rename.
      expect(File('${tempDir.path}/out.part.mp4').existsSync(), isFalse);

      final probe = Process.runSync('ffprobe', <String>[
        '-v',
        'error',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        outputPath,
      ]);
      expect(probe.exitCode, 0, reason: probe.stderr.toString());
      final probed =
          jsonDecode(probe.stdout.toString()) as Map<String, Object?>;
      final streams = (probed['streams'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final video = streams.firstWhere((s) => s['codec_type'] == 'video');
      expect(video['codec_name'], 'h264');
      expect(video['width'], 1280);
      expect(video['height'], 720);
      final duration = double.parse(
        (probed['format'] as Map<String, Object?>)['duration'] as String,
      );
      expect(duration, closeTo(1.0, 0.2));
    },
  );

  test('ProcessRenderBackend exports a real WAV audio file', () async {
    if (!_hasFfmpeg()) {
      markTestSkipped('ffmpeg unavailable');
      return;
    }

    final graphJson = validGraph();
    graphJson['range'] = <String, Object?>{
      'start_ticks': 0,
      'duration_ticks': 1000000,
    };
    final audio = audioClip(durationTicks: 1000000)
      ..['source_uri'] = Uri.file(sourcePath).toString();
    graphJson['tracks'] = <Object?>[
      audioTrack(clips: <Object?>[audio], position: 0),
    ];
    final graph = RenderGraphDoc.parse(graphJson);
    final outputPath = '${tempDir.path}/out.wav';
    final queue = RenderQueue(backend: ProcessRenderBackend());
    addTearDown(queue.dispose);
    final job = queue.enqueue(
      graph,
      preset: RenderPreset.wavPcm,
      outputUri: outputPath,
    );

    await queue.drain();

    final finished = queue.jobById(job.id)!;
    expect(finished.state, RenderJobState.succeeded, reason: finished.error);
    expect(File(outputPath).existsSync(), isTrue);
    expect(File('${tempDir.path}/out.part.wav').existsSync(), isFalse);

    final probe = Process.runSync('ffprobe', <String>[
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      outputPath,
    ]);
    expect(probe.exitCode, 0, reason: probe.stderr.toString());
    final probed = jsonDecode(probe.stdout.toString()) as Map<String, Object?>;
    final streams = (probed['streams'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final audioStream = streams.single;
    expect(audioStream['codec_type'], 'audio');
    expect(audioStream['codec_name'], 'pcm_s16le');
    final duration = double.parse(
      (probed['format'] as Map<String, Object?>)['duration'] as String,
    );
    expect(duration, closeTo(1.0, 0.2));
  });
}
