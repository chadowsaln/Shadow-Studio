import 'dart:convert';
import 'dart:io';

import 'package:desktop/src/agent/agent_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ss_agent_settings_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('first run uses environment defaults and environment key', () async {
    final store = AgentSettingsStore(
      configDirectory: tempDir.path,
      environment: <String, String>{
        'SHADOW_AI_PROVIDER': 'anthropic',
        'SHADOW_AI_MODEL': 'claude-test',
        'SHADOW_AI_API_KEY': 'env-secret-key',
      },
    );

    final settings = await store.load();
    expect(settings.providerId, 'anthropic');
    expect(settings.model, 'claude-test');
    expect(settings.provider.defaultBaseUri, 'https://api.anthropic.com/v1');
    expect(await store.readApiKey('anthropic'), 'env-secret-key');
    expect(await store.readApiKey('openai'), isNull);
  });

  test('saved key is encrypted and never appears in agent.json', () async {
    final store = AgentSettingsStore(
      configDirectory: tempDir.path,
      environment: const <String, String>{},
    );
    const secret = 'sk-test-super-secret-value';
    const settings = AgentSettings(
      providerId: 'openai',
      model: 'gpt-4o-mini',
    );

    await store.save(settings, apiKey: secret);

    final configFile = File(store.configFilePath);
    expect(configFile.existsSync(), isTrue);
    final raw = await configFile.readAsString();
    expect(raw, isNot(contains(secret)));
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['provider'], 'openai');
    expect(decoded['model'], 'gpt-4o-mini');

    expect(await store.hasApiKey('openai'), isTrue);
    expect(await store.readApiKey('openai'), secret);

    // A new instance with a stale environment key must prefer the saved key.
    final reopened = AgentSettingsStore(
      configDirectory: tempDir.path,
      environment: const <String, String>{
        'SHADOW_AI_PROVIDER': 'openai',
        'SHADOW_AI_API_KEY': 'env-should-not-win',
      },
    );
    final loaded = await reopened.load();
    expect(loaded.providerId, 'openai');
    expect(await reopened.readApiKey('openai'), secret);
  });

  test('delete removes the stored key', () async {
    final store = AgentSettingsStore(
      configDirectory: tempDir.path,
      environment: const <String, String>{},
    );
    await store.save(
      const AgentSettings(providerId: 'gemini', model: 'gemini-1.5-flash'),
      apiKey: 'gemini-secret',
    );

    await store.deleteApiKey('gemini');

    expect(await store.hasApiKey('gemini'), isFalse);
  });

  test('unknown provider falls back to OpenAI defaults', () async {
    final store = AgentSettingsStore(
      configDirectory: tempDir.path,
      environment: const <String, String>{'SHADOW_AI_PROVIDER': 'unknown'},
    );

    final settings = await store.load();
    expect(settings.providerId, 'openai');
    expect(settings.model, 'gpt-4o-mini');
  });
}
