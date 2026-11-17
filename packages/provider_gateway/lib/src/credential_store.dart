import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:shadow_permissions/permissions.dart' as perm;

import 'provider_exception.dart';

/// Credential storage abstraction. Implementations must never write keys to
/// SQLite, project files, logs, or crash reports.
abstract interface class CredentialStore {
  Future<void> saveApiKey({required String providerId, required String apiKey});
  Future<String?> readApiKey(String providerId);
  Future<void> deleteApiKey(String providerId);
}

/// In-memory store for tests only. Not for production persistence.
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, String> _keys = <String, String>{};

  @override
  Future<void> saveApiKey({
    required String providerId,
    required String apiKey,
  }) async {
    _keys[providerId] = apiKey;
  }

  @override
  Future<String?> readApiKey(String providerId) async => _keys[providerId];

  @override
  Future<void> deleteApiKey(String providerId) async {
    _keys.remove(providerId);
  }
}

/// Production-oriented adapter over [perm.FileSecretStore].
///
/// Keys are encrypted at rest, filenames are traversal-safe, writes are atomic,
/// and POSIX permissions are restricted to the user. For the strongest
/// boundary, pair this with an OS keyring implementation of [CredentialStore];
/// see `docs/security/PERMISSIONS.md`.
class SecureFileCredentialStore implements CredentialStore {
  SecureFileCredentialStore({
    required String directory,
    bool restrictPermissions = true,
  }) : _store = perm.FileSecretStore(
         directory: directory,
         restrictPermissions: restrictPermissions,
       );

  final perm.FileSecretStore _store;

  @override
  Future<void> saveApiKey({
    required String providerId,
    required String apiKey,
  }) async {
    try {
      await _store.saveApiKey(providerId: providerId, apiKey: apiKey);
    } on perm.SecretStoreException {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerAuth,
        message: 'Credential store unavailable',
        retryable: false,
        providerId: providerId,
      );
    }
  }

  @override
  Future<String?> readApiKey(String providerId) async {
    try {
      return await _store.readApiKey(providerId);
    } on perm.SecretStoreException {
      // Fail closed: a corrupt or unreadable store must not be treated as
      // "no key" and trigger an unauthenticated request.
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerAuth,
        message: 'Credential store unavailable',
        retryable: false,
        providerId: providerId,
      );
    }
  }

  @override
  Future<void> deleteApiKey(String providerId) async {
    try {
      await _store.deleteApiKey(providerId);
    } on perm.SecretStoreException {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerAuth,
        message: 'Credential store unavailable',
        retryable: false,
        providerId: providerId,
      );
    }
  }
}

class ProviderCredentialResolver {
  ProviderCredentialResolver(this._store);

  final CredentialStore _store;

  Future<String> requireApiKey(String providerId) async {
    final key = await _store.readApiKey(providerId);
    if (key == null || key.trim().isEmpty) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerAuth,
        message: 'Missing API key for provider',
        retryable: false,
        providerId: providerId,
      );
    }
    return key;
  }
}
