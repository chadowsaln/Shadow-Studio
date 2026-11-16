import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import 'provider_exception.dart';

/// Low-level transport abstraction (HTTP/SSE in real adapters, fake in tests).
/// Adapters must not be wired to AgentController; they implement [AIProvider].
abstract interface class ProviderTransport {
  /// Returns a stream of decoded provider-native events/chunks (maps/strings) or raw lines.
  Stream<Object?> send({
    required Uri uri,
    required Map<String, String> headers,
    required Object? body,
    required bool stream,
    required Duration timeout,
    required CancellationToken cancel,
  });
}

/// In-memory transport for mock-provider tests (no network, no real keys).
class MockProviderTransport implements ProviderTransport {
  MockProviderTransport({this.handler});

  /// If set, called per request to produce events or throw [ProviderGatewayException].
  final FutureOr<Stream<Object?>> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Object? body,
    required bool stream,
    required Duration timeout,
    required CancellationToken cancel,
  })? handler;

  final List<({Uri uri, Map<String, String> headers, Object? body, bool stream})> requests = [];

  @override
  Stream<Object?> send({
    required Uri uri,
    required Map<String, String> headers,
    required Object? body,
    required bool stream,
    required Duration timeout,
    required CancellationToken cancel,
  }) async* {
    requests.add((uri: uri, headers: Map.of(headers), body: body, stream: stream));
    cancel.throwIfCancelled();
    final h = handler;
    if (h == null) return;
    final out = await h(
      uri: uri,
      headers: headers,
      body: body,
      stream: stream,
      timeout: timeout,
      cancel: cancel,
    );
    await for (final e in out) {
      if (cancel.isCancelled) {
        throw ProviderCancelledException(reason: cancel.reason);
      }
      yield e;
    }
  }
}

ProviderGatewayException normalizeTransportError(Object error, {String? providerId, int? statusCode}) {
  if (error is ProviderGatewayException) return error;
  if (error is TimeoutException) {
    return ProviderGatewayException(
      code: ShadowErrorCode.providerRateLimit,
      message: 'Provider request timed out',
      retryable: true,
      providerId: providerId,
    );
  }
  if (error is CancelledException) {
    return ProviderCancelledException(providerId: providerId, reason: error.reason);
  }
  return ProviderGatewayException(
    code: ShadowErrorCode.providerStreamBroken,
    message: 'Provider transport error',
    retryable: true,
    providerId: providerId,
    statusCode: statusCode,
  );
}
