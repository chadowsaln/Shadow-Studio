import 'dart:async';

/// Cooperative cancellation token shared across agent loop, tools and workers.
class CancellationToken {
  CancellationToken() : _controller = StreamController<void>.broadcast();

  final StreamController<void> _controller;
  bool _isCancelled = false;
  String? _reason;
  Timer? _timer;

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;
  Stream<void> get onCancel => _controller.stream;

  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    _timer?.cancel();
    _timer = null;
    if (!_controller.isClosed) {
      _controller.add(null);
      _controller.close();
    }
  }

  /// Cancels this token after [duration], unless cancelled earlier.
  ///
  /// The returned [Timer] can be used to cancel the scheduled cancellation.
  Timer cancelAfter(Duration duration, [String? reason]) {
    _timer?.cancel();
    final timer = Timer(duration, () => cancel(reason));
    _timer = timer;
    return timer;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancelledException(reason: _reason);
    }
  }

  /// Releases resources. Safe to call multiple times.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

class CancelledException implements Exception {
  const CancelledException({this.reason});
  final String? reason;

  @override
  String toString() => 'CancelledException(${reason ?? 'cancelled'})';
}

/// Raised when an operation exceeds its declared timeout.
class ShadowTimeoutException implements Exception {
  const ShadowTimeoutException({
    required this.operation,
    required this.timeout,
    this.reason,
  });

  final String operation;
  final Duration timeout;
  final String? reason;

  @override
  String toString() =>
      'ShadowTimeoutException($operation exceeded ${timeout.inMilliseconds}ms'
      '${reason == null ? '' : ', $reason'})';
}

/// Runs [body] and enforces [timeout].
///
/// [cancel] is checked before starting; long-running bodies are expected to
/// call [CancellationToken.throwIfCancelled] (or use [CancellationToken.cancelAfter])
/// so cancellation is observed cooperatively.
///
/// Throws [CancelledException] if [cancel] is already cancelled, and
/// [ShadowTimeoutException] if [timeout] elapses first.
Future<T> runWithTimeout<T>({
  required Duration timeout,
  required CancellationToken cancel,
  required Future<T> Function() body,
  String? operation,
  String? timeoutReason,
}) async {
  final op = operation ?? 'operation';
  cancel.throwIfCancelled();

  final timeoutFuture = Future<T>.delayed(timeout, () {
    throw ShadowTimeoutException(
      operation: op,
      timeout: timeout,
      reason: timeoutReason,
    );
  });

  return Future.any<T>([body(), timeoutFuture]);
}
