import 'dart:async';

/// Cooperative cancellation token shared across agent loop, tools and workers.
class CancellationToken {
  CancellationToken() : _controller = StreamController<void>.broadcast();

  final StreamController<void> _controller;
  bool _isCancelled = false;
  String? _reason;

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;
  Stream<void> get onCancel => _controller.stream;

  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    if (!_controller.isClosed) {
      _controller.add(null);
      _controller.close();
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancelledException(reason: _reason);
    }
  }
}

class CancelledException implements Exception {
  const CancelledException({this.reason});
  final String? reason;

  @override
  String toString() => 'CancelledException(${reason ?? 'cancelled'})';
}
