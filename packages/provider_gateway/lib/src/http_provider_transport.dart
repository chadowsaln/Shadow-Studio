import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';

import 'provider_exception.dart';
import 'provider_transport.dart';

/// Real HTTP(S) transport for provider adapters.
///
/// Speaks plain HTTP for unary calls and Server-Sent Events for streaming,
/// yielding decoded JSON objects exactly like [MockProviderTransport] so the
/// adapters stay transport-agnostic. HTTP failures become
/// [ProviderGatewayException]s carrying the status code, so the router can
/// decide whether fallback is allowed (never on 401/403).
class HttpClientProviderTransport implements ProviderTransport {
  HttpClientProviderTransport({
    HttpClient Function()? newClient,
    this.connectionTimeout = const Duration(seconds: 10),
  }) : _newClient = newClient ?? HttpClient.new;

  final HttpClient Function() _newClient;
  final Duration connectionTimeout;

  @override
  Stream<Object?> send({
    required Uri uri,
    required Map<String, String> headers,
    required Object? body,
    required bool stream,
    required Duration timeout,
    required CancellationToken cancel,
  }) async* {
    cancel.throwIfCancelled();
    final client = _newClient()..connectionTimeout = connectionTimeout;
    try {
      final request = await client.openUrl('POST', uri).timeout(timeout);
      headers.forEach(request.headers.set);
      if (body != null) {
        request.add(utf8.encode(body is String ? body : jsonEncode(body)));
      }

      final response = await request.close().timeout(timeout);
      if (response.statusCode >= 400) {
        final text = await _readAll(response).timeout(timeout);
        throw ProviderGatewayException(
          code: _codeForStatus(response.statusCode),
          message: _shortMessage(text) ?? 'Provider returned ${response.statusCode}',
          retryable: _isRetryableStatus(response.statusCode),
          statusCode: response.statusCode,
        );
      }

      if (!stream) {
        final text = await _readAll(response).timeout(timeout);
        if (text.trim().isEmpty) {
          throw const ProviderGatewayException(
            code: ShadowErrorCode.providerStreamBroken,
            message: 'Provider returned an empty body',
            retryable: true,
          );
        }
        yield _decode(text);
        return;
      }

      yield* _readSse(response, cancel: cancel, timeout: timeout);
    } on ProviderGatewayException {
      rethrow;
    } on CancelledException {
      rethrow;
    } on TimeoutException {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerRateLimit,
        message: 'Provider request timed out',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerStreamBroken,
        message: 'Network error: ${e.message}',
        retryable: true,
      );
    } on HttpException catch (e) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerStreamBroken,
        message: 'HTTP error: ${e.message}',
        retryable: true,
      );
    } on FormatException catch (e) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerStreamBroken,
        message: 'Malformed provider payload: ${e.message}',
        retryable: false,
      );
    } finally {
      client.close(force: true);
    }
  }

  Stream<Object?> _readSse(
    HttpClientResponse response, {
    required CancellationToken cancel,
    required Duration timeout,
  }) async* {
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(timeout);
    final data = StringBuffer();
    var sawAny = false;

    await for (final line in lines) {
      cancel.throwIfCancelled();
      if (line.isEmpty) {
        final payload = data.toString().trim();
        data.clear();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') return;
        sawAny = true;
        yield _decode(payload);
        continue;
      }
      if (line.startsWith(':')) continue; // SSE comment / keep-alive
      if (line.startsWith('data:')) {
        final value = line.substring(5);
        final trimmed = value.startsWith(' ') ? value.substring(1) : value;
        if (data.isNotEmpty) data.writeln();
        data.write(trimmed);
      }
      // Ignore `event:`/`id:`/`retry:` fields; adapters only need the payload.
    }

    final trailing = data.toString().trim();
    if (trailing.isNotEmpty) {
      if (trailing == '[DONE]') return;
      sawAny = true;
      yield _decode(trailing);
    }
    if (!sawAny) {
      throw const ProviderGatewayException(
        code: ShadowErrorCode.providerStreamBroken,
        message: 'Provider stream ended without any event',
        retryable: true,
      );
    }
  }

  static Object? _decode(String payload) {
    try {
      return jsonDecode(payload);
    } on FormatException {
      return payload;
    }
  }

  static Future<String> _readAll(HttpClientResponse response) =>
      response.fold<StringBuffer>(
        StringBuffer(),
        (buffer, List<int> chunk) => buffer..write(utf8.decode(chunk, allowMalformed: true)),
      ).then((buffer) => buffer.toString());

  static String? _shortMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= 500 ? trimmed : '${trimmed.substring(0, 497)}...';
  }

  static bool _isRetryableStatus(int status) => status == 429 || status >= 500;

  static String _codeForStatus(int status) {
    if (status == 401 || status == 403) return ShadowErrorCode.providerAuth;
    if (status == 429) return ShadowErrorCode.providerRateLimit;
    if (status == 400 || status == 404 || status == 422) {
      return ShadowErrorCode.providerUnsupported;
    }
    return ShadowErrorCode.providerStreamBroken;
  }
}

/// Adds bounded retry with exponential backoff around another [ProviderTransport].
///
/// Only retryable failures are retried, and only while nothing has been emitted:
/// replaying a partially consumed stream would duplicate output.
class RetryingProviderTransport implements ProviderTransport {
  RetryingProviderTransport({
    required this.delegate,
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(milliseconds: 250),
    this.maxBackoff = const Duration(seconds: 4),
    this.jitter,
    Future<void> Function(Duration delay)? sleep,
  }) : _sleep = sleep ?? _defaultSleep;

  final ProviderTransport delegate;
  final int maxAttempts;
  final Duration initialBackoff;
  final Duration maxBackoff;

  /// Deterministic jitter source for tests; defaults to a small fixed factor.
  final double Function(int attempt)? jitter;
  final Future<void> Function(Duration delay) _sleep;

  @override
  Stream<Object?> send({
    required Uri uri,
    required Map<String, String> headers,
    required Object? body,
    required bool stream,
    required Duration timeout,
    required CancellationToken cancel,
  }) async* {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      cancel.throwIfCancelled();
      var emitted = false;
      try {
        await for (final event in delegate.send(
          uri: uri,
          headers: headers,
          body: body,
          stream: stream,
          timeout: timeout,
          cancel: cancel,
        )) {
          emitted = true;
          yield event;
        }
        return;
      } on ProviderGatewayException catch (e) {
        if (emitted || !e.retryable || attempt == maxAttempts) rethrow;
        await _sleep(_delayFor(attempt));
      } on CancelledException {
        rethrow;
      }
    }
  }

  Duration _delayFor(int attempt) {
    final baseMs = initialBackoff.inMilliseconds * (1 << (attempt - 1));
    final capped = baseMs > maxBackoff.inMilliseconds
        ? maxBackoff.inMilliseconds
        : baseMs;
    final factor = jitter?.call(attempt) ?? 1.0;
    return Duration(milliseconds: (capped * factor).round());
  }

  static Future<void> _defaultSleep(Duration delay) =>
      Future<void>.delayed(delay);
}