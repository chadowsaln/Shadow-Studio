import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

@immutable
class ScheduledTask {
  const ScheduledTask({
    required this.id,
    required this.request,
    required this.workspaceRoot,
    required this.projectRevision,
    required this.createdAt,
  });
  final String id;
  final String request;
  final String workspaceRoot;
  final int projectRevision;
  final DateTime createdAt;
}

/// v1: single active task, FIFO queue, cancellable.
class TaskScheduler {
  final Queue<ScheduledTask> _queue = Queue<ScheduledTask>();
  ScheduledTask? _active;
  final Set<String> _cancelled = <String>{};
  final StreamController<ScheduledTask?> _activeController =
      StreamController<ScheduledTask?>.broadcast();

  ScheduledTask? get active => _active;
  List<ScheduledTask> get pending => List<ScheduledTask>.unmodifiable(_queue);
  Stream<ScheduledTask?> get onActiveChanged => _activeController.stream;
  bool get isIdle => _active == null && _queue.isEmpty;

  bool isCancelled(String taskId) => _cancelled.contains(taskId);

  ScheduledTask enqueue({
    required String id,
    required String request,
    required String workspaceRoot,
    required int projectRevision,
  }) {
    final task = ScheduledTask(
      id: id,
      request: request,
      workspaceRoot: workspaceRoot,
      projectRevision: projectRevision,
      createdAt: DateTime.now().toUtc(),
    );
    _queue.addLast(task);
    _pump();
    return task;
  }

  /// Cancels active or queued task. Returns true if found.
  bool cancel(String taskId, {String? reason}) {
    if (_active?.id == taskId) {
      _cancelled.add(taskId);
      return true; // controller/loop must observe cancellation token/state
    }
    final before = _queue.length;
    _queue.removeWhere((t) => t.id == taskId);
    if (_queue.length != before) {
      _cancelled.add(taskId);
      return true;
    }
    return false;
  }

  /// Mark active task finished (succeeded/failed/cancelled) and promote next.
  void completeActive(String taskId) {
    if (_active?.id != taskId) return;
    _active = null;
    _cancelled.remove(taskId);
    _activeController.add(null);
    _pump();
  }

  void _pump() {
    if (_active != null) return;
    while (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      if (_cancelled.remove(next.id)) {
        continue; // dropped cancelled queued task
      }
      _active = next;
      _activeController.add(next);
      return;
    }
  }

  Future<void> dispose() async {
    await _activeController.close();
  }
}
