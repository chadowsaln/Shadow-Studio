import 'provider_exception.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// OS credential keyring abstraction. Implementations must use system keyring only.
/// Keys must never be stored in SQLite/project files and never logged/exported.
abstract interface class CredentialStore {
  Future<void> saveApiKey({required String providerId, required String apiKey});
  Future<String?> readApiKey(String providerId);
  Future<void> deleteApiKey(String providerId);
}

/// In-memory store for tests only. Not for production persistence.
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, String> _keys = <String, String>{};

  @override
  Future<void> saveApiKey({required String providerId, required String apiKey}) async {
    _keys[providerId] = apiKey;
  }

  @override
  Future<String?> readApiKey(String providerId) async => _keys[providerId];

  @override
  Future<void> deleteApiKey(String providerId) async {
    _keys.remove(providerId);
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
