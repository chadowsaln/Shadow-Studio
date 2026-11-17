import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop/src/agent/agent_session_controller.dart';
import 'package:desktop/src/agent/agent_settings.dart';
import 'package:desktop/src/controller/editor_controller.dart';
import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// Local HTTP provider stand-in. Mirrors the fake-server pattern used by
/// `packages/provider_gateway/test/http_transport_test.dart`.
class _FakeProviderServer {
  _FakeProviderServer(this._handler, {this.closeResponse = true});

  final FutureOr<void> Function(HttpResponse response, HttpRequest request)
      _handler;
  final bool closeResponse;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];
  HttpServer? _server;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server!.port}/v1');

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      requests.add(
        _CapturedRequest(uri: request.uri, headers: headers, body: body),
      );
      await _handler(request.response, request);
      if (closeResponse) await request.response.close();
    });
  }

  Future<void> close() async {
    await _server?.close(force: true);
  }
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;

  Map<String, Object?> get json =>
      (jsonDecode(body) as Map).cast<String, Object?>();
}

void _writeSseText(HttpResponse response, String text) {
  response.headers.contentType = ContentType(
    'text',
    'event-stream',
    charset: 'utf-8',
  );
  // Split the assistant text across events so the test proves the controller
  // consumes a real stream rather than one buffered body.
  final midpoint = text.length ~/ 2;
  for (final chunk in <String>[
    text.substring(0, midpoint),
    text.substring(midpoint)
  ]) {
    response.write(
      'data: ${jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'delta': <String, Object?>{'content': chunk},
              },
            ],
          })}\n\n',
    );
  }
  response.write(
    'data: ${jsonEncode(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'delta': <String, Object?>{},
              'finish_reason': 'stop',
            },
          ],
        })}\n\n',
  );
  response.write('data: [DONE]\n\n');
}

void _writeSseJson(HttpResponse response, Map<String, Object?> payload) =>
    _writeSseText(response, jsonEncode(payload));

void main() {
  late Directory tempDir;
  late FakeMediaWorker worker;
  late core.DefaultEditingService editing;
  late EditorController editor;
  late AgentSettingsStore settingsStore;
  late AgentSessionController session;

  const apiKey = 'sk-test-provider-secret-0123456789';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ss_agent_provider_');
    worker = FakeMediaWorker();
    editing = core.DefaultEditingService(
      initialDocument: core.ProjectDocument.createBlank(name: 'provider_test'),
    );
    editor = EditorController(
      editingService: editing,
      mediaLibrary: MediaLibraryService(worker: worker, cacheDir: tempDir),
      initialProjectPath: '${tempDir.path}/project.ssproj',
    );
    settingsStore = AgentSettingsStore(
      configDirectory: tempDir.path,
      environment: const <String, String>{},
    );
  });

  tearDown(() {
    session.dispose();
    editor.dispose();
    worker.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> configure(Uri baseUri, {Duration? providerTimeout}) async {
    await settingsStore.save(
      AgentSettings(
        providerId: 'openai',
        model: 'gpt-4o-mini',
        baseUri: baseUri,
      ),
      apiKey: apiKey,
    );
    session = AgentSessionController(
      editor: editor,
      settingsStore: settingsStore,
      workspaceRootOverride: tempDir.path,
      providerTimeout: providerTimeout ?? const Duration(seconds: 30),
    );
    await session.initialize();
  }

  test(
    'egress-consent denial fails before any provider socket is opened',
    () async {
      final server = _FakeProviderServer((response, _) {
        _writeSseJson(response, <String, Object?>{
          'action': 'complete',
          'summary': 'must not run',
        });
      });
      await server.start();
      addTearDown(server.close);
      await configure(server.baseUri);

      await session.run('Summarize the timeline.');

      expect(session.status, AgentSessionStatus.failed);
      expect(session.errorCode, ShadowErrorCode.permApprovalRequired);
      expect(server.requests, isEmpty);
    },
  );

  test(
    'authorized run sends the saved key and consumes a streamed provider reply',
    () async {
      var call = 0;
      final server = _FakeProviderServer((response, _) {
        call++;
        if (call == 1) {
          // Planning request: one verifiable step.
          _writeSseJson(response, <String, Object?>{
            'steps': <Object?>[
              <String, Object?>{
                'description': 'Acknowledge the task.',
                'expected_outcome': 'A completion summary is produced.',
              },
            ],
          });
          return;
        }
        _writeSseJson(response, <String, Object?>{
          'action': 'complete',
          'summary': 'Fake provider replied.',
        });
      });
      await server.start();
      addTearDown(server.close);
      await configure(server.baseUri);
      session.setEgressConsent(true);

      await session.run('Summarize the timeline.');
      await session.waitForTask().timeout(const Duration(seconds: 15));

      expect(
        session.status,
        AgentSessionStatus.succeeded,
        reason: '${session.errorCode} ${session.errorMessage}',
      );
      expect(session.summary, 'Fake provider replied.');
      expect(server.requests, hasLength(2));

      for (final request in server.requests) {
        expect(request.uri.path, '/v1/chat/completions');
        expect(request.headers['authorization'], 'Bearer $apiKey');
        final body = request.json;
        expect(body['model'], 'gpt-4o-mini');
        expect(body['stream'], isTrue);
        final messages = body['messages'] as List<Object?>;
        expect(messages.first, isA<Map<String, Object?>>());
        expect(
          (messages.first as Map<String, Object?>)['role'],
          'system',
        );
        expect(
          messages.last,
          isA<Map<String, Object?>>().having(
            (message) => message['content'],
            'content',
            contains('Summarize the timeline.'),
          ),
        );
        expect(
          body['tools'],
          isA<List<Object?>>().having(
            (tools) => tools
                .whereType<Map<String, Object?>>()
                .map((tool) => tool['function']),
            'tool names',
            contains(
              isA<Map<String, Object?>>().having(
                (function) => function['name'],
                'name',
                'timeline_edit',
              ),
            ),
          ),
        );
      }

      final transcript = <String>[
        session.summary ?? '',
        session.errorMessage ?? '',
        ...session.activity.map((entry) => entry.message),
      ].join('\n');
      expect(transcript, isNot(contains(apiKey)));
      expect(
        File('${tempDir.path}/agent.json').readAsStringSync(),
        isNot(contains(apiKey)),
      );
    },
  );

  test(
    'provider timeout surfaces as a failed task instead of a hang',
    () async {
      // Accept the request but never send headers, so the transport's own
      // deadline is what ends the request.
      final server =
          _FakeProviderServer((response, _) {}, closeResponse: false);
      await server.start();
      addTearDown(server.close);
      await configure(
        server.baseUri,
        providerTimeout: const Duration(milliseconds: 250),
      );
      session.setEgressConsent(true);

      final started = DateTime.now();
      await session.run('Summarize the timeline.');
      await session.waitForTask().timeout(const Duration(seconds: 15));
      final elapsed = DateTime.now().difference(started);

      expect(session.status, AgentSessionStatus.failed);
      expect(session.errorMessage, contains('timed out'));
      expect(server.requests, isNotEmpty);
      expect(elapsed, lessThan(const Duration(seconds: 10)));
    },
  );

  test(
    'provider 5xx surfaces as a failed task instead of a hang',
    () async {
      final server = _FakeProviderServer((response, _) {
        response.statusCode = HttpStatus.serviceUnavailable;
        response.write('upstream down');
      });
      await server.start();
      addTearDown(server.close);
      await configure(server.baseUri);
      session.setEgressConsent(true);

      await session.run('Summarize the timeline.');
      await session.waitForTask().timeout(const Duration(seconds: 15));

      expect(session.status, AgentSessionStatus.failed);
      expect(server.requests, isNotEmpty);
      expect(
        '${session.errorCode} ${session.errorMessage}',
        isNot(contains(apiKey)),
      );
    },
  );
}
