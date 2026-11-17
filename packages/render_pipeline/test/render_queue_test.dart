import 'dart:async';
import 'dart:io';

import 'package:render_pipeline/render_pipeline.dart';
import 'package:test/test.dart';

import 'graph_fixtures.dart';

class _FakeBackend implements RenderBackend {
  _FakeBackend({
    this.behaviour = _Behaviour.succeed,
    this.progressSteps = const <double>[0.25, 0.5, 0.75],
    this.startDelay = Duration.zero,
  });

  final _Behaviour behaviour;
  final List<double> progressSteps;
  final Duration startDelay;

  int runs = 0;
  final List<String> attemptedPaths = <String>[];

  @override
  Future<void> run(
    RenderPlan plan, {
    required String outputPath,
    required void Function(double progress) onProgress,
    required CancellationToken token,
  }) async {
    runs++;
    attemptedPaths.add(outputPath);
    if (startDelay > Duration.zero) {
      await Future<void>.delayed(startDelay);
    }
    token.throwIfCancelled();
    switch (behaviour) {
      case _Behaviour.succeed:
        for (final step in progressSteps) {
          token.throwIfCancelled();
          onProgress(step);
        }
        await File(outputPath).writeAsString('rendered');
      case _Behaviour.fail:
        throw const RenderFailed('encoder exploded', exitCode: 1);
      case _Behaviour.hangUntilCancelled:
        while (!token.isCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        throw const RenderCancelled();
    }
  }
}

enum _Behaviour { succeed, fail, hangUntilCancelled }

void main() {
  late Directory tempDir;
  late String outputPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('render_queue_test');
    outputPath = '${tempDir.path}/out.mp4';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  RenderQueue queueWith(_FakeBackend backend, {int concurrency = 1}) =>
      RenderQueue(backend: backend, concurrency: concurrency);

  test('renders to a .part file and renames on success', () async {
    final backend = _FakeBackend();
    final queue = queueWith(backend);
    final job = queue.enqueue(
      validDoc(),
      preset: RenderPreset.mp4H2641080p,
      outputUri: outputPath,
    );

    await queue.drain();

    expect(backend.attemptedPaths.single, '$outputPath.part');
    expect(File(outputPath).existsSync(), isTrue);
    expect(File('$outputPath.part').existsSync(), isFalse);
    expect(queue.jobById(job.id)!.state, RenderJobState.succeeded);
    expect(queue.jobById(job.id)!.progress, 1.0);
    await queue.dispose();
  });

  test('emits progress while the job runs', () async {
    final backend = _FakeBackend(progressSteps: const <double>[0.5, 1.0]);
    final queue = queueWith(backend);
    queue.enqueue(
      validDoc(),
      preset: RenderPreset.mp4H2641080p,
      outputUri: outputPath,
    );

    final updates = <double>[];
    final subscription = queue.changes.listen(
      (jobs) => updates.add(jobs.single.progress),
    );

    await queue.drain();
    await Future<void>.delayed(Duration.zero);

    expect(updates.first, 0.0);
    expect(updates.last, 1.0);
    expect(updates.where((p) => p == 0.5), isNotEmpty);
    await subscription.cancel();
    await queue.dispose();
  });

  test('deletes the .part file when the encoder fails', () async {
    final backend = _FakeBackend(behaviour: _Behaviour.fail);
    final queue = queueWith(backend);
    final job = queue.enqueue(
      validDoc(),
      preset: RenderPreset.mp4H2641080p,
      outputUri: outputPath,
    );

    await queue.drain();

    expect(queue.jobById(job.id)!.state, RenderJobState.failed);
    expect(queue.jobById(job.id)!.error, contains('encoder exploded'));
    expect(File('$outputPath.part').existsSync(), isFalse);
    expect(File(outputPath).existsSync(), isFalse);
    await queue.dispose();
  });

  test('cancelling a queued job never invokes the backend', () async {
    final backend = _FakeBackend();
    final queue = queueWith(backend);
    final job = queue.enqueue(
      validDoc(),
      preset: RenderPreset.mp4H2641080p,
      outputUri: outputPath,
    );

    await queue.cancel(job.id);
    await queue.drain();

    expect(backend.runs, 0);
    expect(queue.jobById(job.id)!.state, RenderJobState.cancelled);
    await queue.dispose();
  });

  test('cancelling a running job kills the render and cleans up', () async {
    final backend = _FakeBackend(behaviour: _Behaviour.hangUntilCancelled);
    final queue = queueWith(backend);
    final job = queue.enqueue(
      validDoc(),
      preset: RenderPreset.mp4H2641080p,
      outputUri: outputPath,
    );

    final drain = queue.drain();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await queue.cancel(job.id);
    await drain;

    expect(queue.jobById(job.id)!.state, RenderJobState.cancelled);
    expect(File('$outputPath.part').existsSync(), isFalse);
    expect(File(outputPath).existsSync(), isFalse);
    await queue.dispose();
  });

  test('runs jobs up to the concurrency limit', () async {
    final backend = _FakeBackend(startDelay: const Duration(milliseconds: 10));
    final decrementing = _ConcurrencyProbe(backend);
    final queue = RenderQueue(backend: decrementing, concurrency: 2);

    for (var i = 0; i < 4; i++) {
      queue.enqueue(
        validDoc(),
        preset: RenderPreset.mp4H2641080p,
        outputUri: '${tempDir.path}/out$i.mp4',
      );
    }

    await queue.drain();

    expect(decrementing.peak, lessThanOrEqualTo(2));
    expect(
      queue.jobs.where((j) => j.state == RenderJobState.succeeded),
      hasLength(4),
    );
    await queue.dispose();
  });

  test('serialises concurrent drains without running a job twice', () async {
    final backend = _FakeBackend();
    final queue = queueWith(backend);
    queue.enqueue(
      validDoc(),
      preset: RenderPreset.mp4H2641080p,
      outputUri: outputPath,
    );

    await Future.wait<void>([queue.drain(), queue.drain()]);

    expect(backend.runs, 1);
    expect(queue.jobs.single.state, RenderJobState.succeeded);
    await queue.dispose();
  });
}

class _ConcurrencyProbe implements RenderBackend {
  _ConcurrencyProbe(this.inner);

  final _FakeBackend inner;
  int active = 0;
  int peak = 0;

  @override
  Future<void> run(
    RenderPlan plan, {
    required String outputPath,
    required void Function(double progress) onProgress,
    required CancellationToken token,
  }) async {
    active++;
    if (active > peak) peak = active;
    try {
      await inner.run(
        plan,
        outputPath: outputPath,
        onProgress: onProgress,
        token: token,
      );
    } finally {
      active--;
    }
  }
}
