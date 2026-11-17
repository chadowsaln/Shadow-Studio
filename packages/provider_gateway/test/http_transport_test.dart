import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:test/test.dart';

class _TestServer {
  _TestServer(this.handler);

  final void Function(HttpResponse response, HttpRequest request) handler;
  HttpServer? _server;

  Future<Uri> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      handler(request.response, request);
      await request.response.close();
    });
    return Uri.parse('http://127.0.0.1:${server.port}/v1/chat');
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }
}

void main() {
  group('HttpClientProviderTransport', () {
    test('decodes a server-sent event stream', () async {
      final server = _TestServer((response, _) {
        response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        response.write('data: {"choices":[{"delta":{"content":"he"}}]}\n\n');
        response.write(': keep-alive\n\n');
        response.write('data: {"choices":[{"delta":{"content":"llo"}}]}\n\n');
        response.write('data: [DONE]\n\n');
      });
      final uri = await server.start();
      addTearDown(server.close);

      final events = await HttpClientProviderTransport()
          .send(
            uri: uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: const <String, Object?>{'model': 'x'},
            stream: true,
            timeout: const Duration(seconds: 5),
            cancel: CancellationToken(),
          )
          .toList();

      expect(events, hasLength(2));
      expect(
        (events.first as Map)['choices'],
        isA<List<Object?>>(),
      );
    });

    test('returns a decoded body for non-streaming calls', () async {
      final server = _TestServer((response, _) {
        response.headers.contentType = ContentType.json;
        response.write('{"id":"resp_1","text":"ok"}');
      });
      final uri = await server.start();
      addTearDown(server.close);

      final events = await HttpClientProviderTransport()
          .send(
            uri: uri,
            headers: const <String, String>{},
            body: const <String, Object?>{'stream': false},
            stream: false,
            timeout: const Duration(seconds: 5),
            cancel: CancellationToken(),
          )
          .toList();

      expect(events.single, isA<Map<String, Object?>>());
      expect((events.single as Map)['id'], 'resp_1');
    });

    test('maps 401 to a non-retryable auth failure', () async {
      final server = _TestServer((response, _) {
        response.statusCode = HttpStatus.unauthorized;
        response.write('{"error":{"message":"bad key"}}');
      });
      final uri = await server.start();
      addTearDown(server.close);

      await expectLater(
        HttpClientProviderTransport()
            .send(
              uri: uri,
              headers: const <String, String>{},
              body: const <String, Object?>{},
              stream: true,
              timeout: const Duration(seconds: 5),
              cancel: CancellationToken(),
            )
            .toList(),
        throwsA(
          isA<ProviderGatewayException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', ShadowErrorCode.providerAuth)
              .having((e) => e.retryable, 'retryable', false),
        ),
      );
    });

    test('maps 503 to a retryable failure', () async {
      final server = _TestServer((response, _) {
        response.statusCode = HttpStatus.serviceUnavailable;
        response.write('upstream down');
      });
      final uri = await server.start();
      addTearDown(server.close);

      await expectLater(
        HttpClientProviderTransport()
            .send(
              uri: uri,
              headers: const <String, String>{},
              body: const <String, Object?>{},
              stream: false,
              timeout: const Duration(seconds: 5),
              cancel: CancellationToken(),
            )
            .toList(),
        throwsA(
          isA<ProviderGatewayException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having((e) => e.retryable, 'retryable', true),
        ),
      );
    });
  });

  group('RetryingProviderTransport', () {
    test('retries retryable failures until a success', () async {
      var attempts = 0;
      final delegate = MockProviderTransport(
        handler: ({required uri, required headers, required body, required stream, required timeout, required cancel}) {
          attempts++;
          if (attempts < 3) {
            throw const ProviderGatewayException(
              code: ShadowErrorCode.providerStreamBroken,
              message: 'temporary',
              retryable: true,
              statusCode: 503,
            );
          }
          return Stream<Object?>.fromIterable(<Object?>[
            <String, Object?>{'ok': true},
          ]);
        },
      );
      final transport = RetryingProviderTransport(
        delegate: delegate,
        maxAttempts: 3,
        sleep: (_) async {},
      );

      final events = await transport
          .send(
            uri: Uri.parse('http://localhost/v1'),
            headers: const <String, String>{},
            body: const <String, Object?>{},
            stream: true,
            timeout: const Duration(seconds: 5),
            cancel: CancellationToken(),
          )
          .toList();

      expect(attempts, 3);
      expect((events.single as Map)['ok'], isTrue);
    });

    test('does not replay a stream that already emitted events', () async {
      var attempts = 0;
      final delegate = MockProviderTransport(
        handler: ({required uri, required headers, required body, required stream, required timeout, required cancel}) {
          attempts++;
          return Stream<Object?>.multi((controller) {
            controller.add(<String, Object?>{'partial': true});
            controller.addError(
              const ProviderGatewayException(
                code: ShadowErrorCode.providerStreamBroken,
                message: 'broke mid-stream',
                retryable: true,
              ),
            );
            controller.close();
          });
        },
      );
      final transport = RetryingProviderTransport(
        delegate: delegate,
        maxAttempts: 3,
        sleep: (_) async {},
      );

      await expectLater(
        transport
            .send(
              uri: Uri.parse('http://localhost/v1'),
              headers: const <String, String>{},
              body: null,
              stream: true,
              timeout: const Duration(seconds: 5),
              cancel: CancellationToken(),
            )
            .toList(),
        throwsA(isA<ProviderGatewayException>()),
      );
      expect(attempts, 1);
    });

    test('never retries non-retryable failures', () async {
      var attempts = 0;
      final delegate = MockProviderTransport(
        handler: ({required uri, required headers, required body, required stream, required timeout, required cancel}) {
          attempts++;
          throw const ProviderGatewayException(
            code: ShadowErrorCode.providerAuth,
            message: 'bad key',
            retryable: false,
            statusCode: 401,
          );
        },
      );
      final transport = RetryingProviderTransport(
        delegate: delegate,
        maxAttempts: 3,
        sleep: (_) async {},
      );

      await expectLater(
        transport
            .send(
              uri: Uri.parse('http://localhost/v1'),
              headers: const <String, String>{},
              body: null,
              stream: false,
              timeout: const Duration(seconds: 5),
              cancel: CancellationToken(),
            )
            .toList(),
        throwsA(isA<ProviderGatewayException>()),
      );
      expect(attempts, 1);
    });

    test('passes through a successful single attempt', () async {
      final delegate = MockProviderTransport(
        handler: ({required uri, required headers, required body, required stream, required timeout, required cancel}) =>
            Stream<Object?>.fromIterable(<Object?>[const <String, Object?>{'a': 1}]),
      );
      final transport = RetryingProviderTransport(
        delegate: delegate,
        sleep: (_) async {},
      );

      final events = await transport
          .send(
            uri: Uri.parse('http://localhost/v1'),
            headers: const <String, String>{},
            body: jsonEncode(<String, Object?>{'x': 1}),
            stream: false,
            timeout: const Duration(seconds: 5),
            cancel: CancellationToken(),
          )
          .toList();

      expect(events, hasLength(1));
    });
  });
}