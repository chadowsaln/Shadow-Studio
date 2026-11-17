import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'render_queue.dart';
import 'render_plan.dart';

/// Runs [RenderPlan]s through a local FFmpeg binary.
///
/// Progress is derived from FFmpeg's `-progress pipe:1` key/value stream, which
/// reports `out_time_us` for every encoded frame. Cancellation kills the child
/// process and deletes the partial output.
class ProcessRenderBackend implements RenderBackend {
  ProcessRenderBackend({
    this.ffmpegPath = 'ffmpeg',
    this.pollInterval = const Duration(milliseconds: 100),
  });

  final String ffmpegPath;
  final Duration pollInterval;

  @override
  Future<void> run(
    RenderPlan plan, {
    required String outputPath,
    required void Function(double progress) onProgress,
    required CancellationToken token,
  }) async {
    final totalUs = _durationUs(plan) ?? 0;
    final process = await Process.start(ffmpegPath, <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-progress',
      'pipe:1',
      ...plan.toArgs(),
      outputPath,
    ]);

    final stderr = <String>[];
    final stdout = StringBuffer();
    final subscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdout.writeln(line);
          final keyValue = line.indexOf('=');
          if (keyValue <= 0) return;
          final key = line.substring(0, keyValue);
          final value = line.substring(keyValue + 1);
          if (key == 'out_time_us' && totalUs > 0) {
            final us = int.tryParse(value);
            if (us != null) onProgress((us / totalUs).clamp(0.0, 1.0));
          } else if (key == 'progress' && value == 'end') {
            onProgress(1.0);
          }
        });
    process.stderr.transform(utf8.decoder).listen(stderr.add);

    Timer? watchdog;
    watchdog = Timer.periodic(pollInterval, (timer) {
      if (token.isCancelled) {
        process.kill(ProcessSignal.sigkill);
        timer.cancel();
      }
    });

    final exitCode = await process.exitCode;
    watchdog.cancel();
    await subscription.cancel();

    if (token.isCancelled) throw const RenderCancelled();
    if (exitCode != 0) {
      final detail = stderr.join().trim();
      throw RenderFailed(
        detail.isEmpty
            ? 'ffmpeg exited with code $exitCode'
            : 'ffmpeg exited with code $exitCode: ${detail.length > 500 ? detail.substring(detail.length - 500) : detail}',
        exitCode: exitCode,
      );
    }
    onProgress(1.0);
  }

  int? _durationUs(RenderPlan plan) {
    // The plan renders the graph range; `-t` is the final output argument.
    final t = plan.outputArgs.indexOf('-t');
    if (t < 0 || t + 1 >= plan.outputArgs.length) return null;
    final seconds = double.tryParse(plan.outputArgs[t + 1]);
    if (seconds == null) return null;
    return (seconds * 1000000).round();
  }
}
