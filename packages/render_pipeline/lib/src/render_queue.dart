import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import 'render_graph_doc.dart';
import 'render_plan.dart';
import 'render_preset.dart';

/// Raised when a render is aborted through its [CancellationToken].
class RenderCancelled implements Exception {
  const RenderCancelled();

  @override
  String toString() => 'RenderCancelled';
}

/// Raised when the encoder exits with a non-zero status.
class RenderFailed implements Exception {
  const RenderFailed(this.message, {this.exitCode});

  final String message;
  final int? exitCode;

  @override
  String toString() =>
      'RenderFailed(${exitCode == null ? '' : 'exit $exitCode: '}$message)';
}

/// Cooperative cancellation signal shared by the queue and the encoder.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const RenderCancelled();
  }
}

enum RenderJobState { queued, running, succeeded, failed, cancelled }

@immutable
class RenderJob {
  const RenderJob({
    required this.id,
    required this.graph,
    required this.preset,
    required this.outputUri,
    required this.createdAt,
    this.state = RenderJobState.queued,
    this.progress = 0,
    this.error,
  });

  final String id;
  final RenderGraphDoc graph;
  final RenderPreset preset;
  final String outputUri;
  final DateTime createdAt;
  final RenderJobState state;
  final double progress;
  final String? error;

  bool get isPending => state == RenderJobState.queued;

  bool get isActive =>
      state == RenderJobState.queued || state == RenderJobState.running;

  RenderJob copyWith({
    RenderJobState? state,
    double? progress,
    String? error,
  }) => RenderJob(
    id: id,
    graph: graph,
    preset: preset,
    outputUri: outputUri,
    createdAt: createdAt,
    state: state ?? this.state,
    progress: progress ?? this.progress,
    error: error ?? this.error,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'output_uri': outputUri,
    'preset_id': preset.id,
    'state': state.name,
    'progress_ppm': (progress * 1000000).round(),
    if (error != null) 'error': error,
  };
}

/// Executes a [RenderPlan]. Implemented by the FFmpeg backend in production and
/// by fakes in tests.
abstract class RenderBackend {
  Future<void> run(
    RenderPlan plan, {
    required String outputPath,
    required void Function(double progress) onProgress,
    required CancellationToken token,
  });
}

/// Serial render queue with cooperative cancellation and atomic outputs.
///
/// Each job renders into `<output>.part` and is renamed onto the final path
/// only after the encoder reports success, so a crash can never leave a
/// half-written file at the requested destination.
class RenderQueue {
  RenderQueue({
    required RenderBackend backend,
    this.concurrency = 1,
    String Function()? idSource,
  }) : _backend = backend,
       _nextId = idSource ?? _autoId {
    if (concurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be >= 1');
    }
  }

  static int _counter = 0;

  static String _autoId() => (_counter++).toString();

  final RenderBackend _backend;
  final int concurrency;
  final String Function() _nextId;

  final List<RenderJob> _jobs = <RenderJob>[];
  final Map<String, CancellationToken> _tokens = <String, CancellationToken>{};
  final StreamController<List<RenderJob>> _changes =
      StreamController<List<RenderJob>>.broadcast();

  List<RenderJob> get jobs => List<RenderJob>.unmodifiable(_jobs);

  Stream<List<RenderJob>> get changes => _changes.stream;

  RenderJob? jobById(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  RenderJob enqueue(
    RenderGraphDoc graph, {
    required RenderPreset preset,
    required String outputUri,
  }) {
    final job = RenderJob(
      id: _nextId(),
      graph: graph,
      preset: preset,
      outputUri: outputUri,
      createdAt: DateTime.now(),
    );
    _jobs.add(job);
    _changes.add(List<RenderJob>.of(_jobs));
    return job;
  }

  Future<void> cancel(String jobId) async {
    final token = _tokens[jobId];
    token?.cancel();
    final index = _jobs.indexWhere((j) => j.id == jobId);
    if (index >= 0 && _jobs[index].state == RenderJobState.queued) {
      _replace(
        index,
        _jobs[index].copyWith(
          state: RenderJobState.cancelled,
          error: 'cancelled before start',
        ),
      );
    }
  }

  Future<void> cancelAll() async {
    for (final token in _tokens.values) {
      token.cancel();
    }
    for (var i = 0; i < _jobs.length; i++) {
      if (_jobs[i].state == RenderJobState.queued) {
        _replace(
          i,
          _jobs[i].copyWith(
            state: RenderJobState.cancelled,
            error: 'cancelled before start',
          ),
        );
      }
    }
  }

  /// Runs every queued job, honouring [concurrency]. Resolves once the queue is
  /// empty or cancelled.
  Future<void> drain() async {
    while (true) {
      final batch = _jobs
          .where((j) => j.state == RenderJobState.queued)
          .take(concurrency)
          .toList(growable: false);
      if (batch.isEmpty) return;
      await Future.wait(batch.map(_runJob));
    }
  }

  Future<void> _runJob(RenderJob job) async {
    final index = _jobs.indexWhere((j) => j.id == job.id);
    if (index < 0 || _jobs[index].state != RenderJobState.queued) return;

    final token = CancellationToken();
    _tokens[job.id] = token;
    _replace(index, job.copyWith(state: RenderJobState.running));

    final partPath = '${job.outputUri}.part';
    try {
      token.throwIfCancelled();
      await _backend.run(
        RenderPlanner().plan(graph: job.graph, preset: job.preset),
        outputPath: partPath,
        token: token,
        onProgress: (value) {
          final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
          final currentIndex = _jobs.indexWhere((j) => j.id == job.id);
          if (currentIndex < 0) return;
          if (_jobs[currentIndex].state != RenderJobState.running) return;
          _replace(
            currentIndex,
            _jobs[currentIndex].copyWith(progress: clamped),
          );
        },
      );
      token.throwIfCancelled();
      _commitAtomically(partPath, job.outputUri);
      _finish(job.id, RenderJobState.succeeded, 1.0, null);
    } on RenderCancelled {
      _discard(partPath);
      _finish(job.id, RenderJobState.cancelled, 0.0, 'cancelled');
    } on RenderFailed catch (error) {
      _discard(partPath);
      _finish(job.id, RenderJobState.failed, 0.0, error.message);
    } catch (error) {
      _discard(partPath);
      _finish(job.id, RenderJobState.failed, 0.0, error.toString());
    } finally {
      _tokens.remove(job.id);
    }
  }

  void _commitAtomically(String partPath, String outputUri) {
    final part = File(partPath);
    final target = File(outputUri);
    if (!part.existsSync()) {
      throw RenderFailed('encoder produced no output at $partPath');
    }
    final parent = target.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    if (target.existsSync()) target.deleteSync();
    part.renameSync(outputUri);
  }

  void _discard(String partPath) {
    final part = File(partPath);
    if (part.existsSync()) {
      try {
        part.deleteSync();
      } on FileSystemException {
        // Best effort: a leftover .part must never mask the original error.
      }
    }
  }

  void _finish(
    String id,
    RenderJobState state,
    double progress,
    String? error,
  ) {
    final index = _jobs.indexWhere((j) => j.id == id);
    if (index < 0) return;
    _replace(
      index,
      _jobs[index].copyWith(state: state, progress: progress, error: error),
    );
  }

  void _replace(int index, RenderJob job) {
    _jobs[index] = job;
    _changes.add(List<RenderJob>.of(_jobs));
  }

  Future<void> dispose() => _changes.close();
}
