import 'dart:io';

import 'package:shadow_provider_gateway/provider_gateway.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('provider_creds_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('stores keys encrypted and resolves them', () async {
    final store = SecureFileCredentialStore(directory: dir.path);
    await store.saveApiKey(providerId: 'openai', apiKey: 'sk-live-secret');
    expect(await store.readApiKey('openai'), 'sk-live-secret');

    final resolver = ProviderCredentialResolver(store);
    expect(await resolver.requireApiKey('openai'), 'sk-live-secret');

    for (final entity in await dir.list(recursive: true).toList()) {
      if (entity is File && entity.path.endsWith('.secret')) {
        expect(await entity.readAsString(), isNot(contains('sk-live-secret')));
      }
    }
  });

  test('missing key is an auth error without fallback', () async {
    final store = SecureFileCredentialStore(directory: dir.path);
    await expectLater(
      ProviderCredentialResolver(store).requireApiKey('gemini'),
      throwsA(
        isA<ProviderGatewayException>().having(
          (e) => e.code,
          'code',
          'PROVIDER_AUTH',
        ),
      ),
    );
  });

  test(
    'corrupt store fails closed instead of requesting unauthenticated',
    () async {
      final store = SecureFileCredentialStore(directory: dir.path);
      await store.saveApiKey(providerId: 'openai', apiKey: 'sk-live-secret');
      await File('${dir.path}/device.key').delete();
      await expectLater(
        ProviderCredentialResolver(
          SecureFileCredentialStore(directory: dir.path),
        ).requireApiKey('openai'),
        throwsA(isA<ProviderGatewayException>()),
      );
    },
  );
}
