import 'dart:io';

import 'package:shadow_permissions/permissions.dart' as perm;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('perm_secrets_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('round-trips API keys without storing plaintext', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    await store.saveApiKey(providerId: 'openai', apiKey: 'sk-secret-value-123');

    expect(await store.readApiKey('openai'), 'sk-secret-value-123');
    expect(await store.readApiKey('missing-provider'), isNull);

    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.secret'))
        .toList();
    expect(files, hasLength(1));
    final contents = await File(files.single.path).readAsString();
    expect(contents, isNot(contains('sk-secret-value-123')));
    expect(contents, contains('"v":"v1"'));
  });

  test('overwrites atomically and removes old value', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    await store.saveApiKey(providerId: 'openai', apiKey: 'first');
    await store.saveApiKey(providerId: 'openai', apiKey: 'second');
    expect(await store.readApiKey('openai'), 'second');
    final leftovers = await dir
        .list()
        .where((e) => e.path.contains('.tmp.'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test('files are not readable by group/other on POSIX', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    await store.saveApiKey(providerId: 'gemini', apiKey: 'AIza-secret');
    if (!Platform.isWindows) {
      final keyFile = File('${dir.path}/device.key');
      final secretFile = await dir.list().firstWhere(
        (e) => e.path.endsWith('.secret'),
      );
      expect(keyFile.statSync().mode & 0x1FF, 0x180);
      expect(secretFile.statSync().mode & 0x1FF, 0x180);
      expect(Directory(dir.path).statSync().mode & 0x1FF, 0x1C0); // 0700
    }
  });

  test('provider ids cannot traverse directories', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    expect(
      () => store.saveApiKey(providerId: '../outside', apiKey: 'x'),
      throwsA(isA<perm.SecretStoreException>()),
    );
    expect(
      () => store.saveApiKey(providerId: '', apiKey: 'x'),
      throwsA(isA<perm.SecretStoreException>()),
    );
    expect(
      () => store.saveApiKey(providerId: 'a' * 200, apiKey: 'x'),
      throwsA(isA<perm.SecretStoreException>()),
    );
  });

  test(
    'a swapped device key fails closed instead of returning garbage',
    () async {
      final store = perm.FileSecretStore(directory: dir.path);
      await store.saveApiKey(providerId: 'openai', apiKey: 'sk-very-secret');
      final keyFile = File('${dir.path}/device.key');
      await keyFile.delete();

      final reopened = perm.FileSecretStore(directory: dir.path);
      await expectLater(
        reopened.readApiKey('openai'),
        throwsA(
          isA<perm.SecretStoreException>().having(
            (e) => e.code,
            'code',
            contains('STORE_CORRUPT'),
          ),
        ),
      );
    },
  );

  test('corrupt payload is rejected', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    await store.saveApiKey(providerId: 'openai', apiKey: 'sk-very-secret');
    final secretFile = await dir.list().firstWhere(
      (e) => e.path.endsWith('.secret'),
    );
    await File(secretFile.path).writeAsString('{"v":"v1","n":"bad"}');
    await expectLater(
      store.readApiKey('openai'),
      throwsA(isA<perm.SecretStoreException>()),
    );
  });

  test('deleting a key removes the file and the value', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    await store.saveApiKey(providerId: 'openai', apiKey: 'sk-very-secret');
    await store.deleteApiKey('openai');
    expect(await store.readApiKey('openai'), isNull);
  });

  test('toString never exposes stored secrets', () async {
    final store = perm.FileSecretStore(directory: dir.path);
    await store.saveApiKey(providerId: 'openai', apiKey: 'sk-very-secret');
    expect(store.toString(), isNot(contains('sk-very-secret')));
  });
}
