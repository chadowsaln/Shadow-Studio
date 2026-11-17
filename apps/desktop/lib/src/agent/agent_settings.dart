import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shadow_provider_gateway/provider_gateway.dart';

/// Static description of a supported AI provider.
class AgentProviderDescriptor {
  const AgentProviderDescriptor({
    required this.id,
    required this.label,
    required this.defaultModel,
    required this.defaultBaseUri,
  });

  final String id;
  final String label;
  final String defaultModel;
  final String defaultBaseUri;
}

/// Providers wired through `provider_gateway` adapters.
const List<AgentProviderDescriptor> agentProviders = <AgentProviderDescriptor>[
  AgentProviderDescriptor(
    id: 'openai',
    label: 'OpenAI',
    defaultModel: 'gpt-4o-mini',
    defaultBaseUri: 'https://api.openai.com/v1',
  ),
  AgentProviderDescriptor(
    id: 'anthropic',
    label: 'Anthropic',
    defaultModel: 'claude-3-5-sonnet-latest',
    defaultBaseUri: 'https://api.anthropic.com/v1',
  ),
  AgentProviderDescriptor(
    id: 'gemini',
    label: 'Google Gemini',
    defaultModel: 'gemini-1.5-flash',
    defaultBaseUri: 'https://generativelanguage.googleapis.com/v1beta',
  ),
  AgentProviderDescriptor(
    id: 'openrouter',
    label: 'OpenRouter',
    defaultModel: 'openai/gpt-4o-mini',
    defaultBaseUri: 'https://openrouter.ai/api/v1',
  ),
];

AgentProviderDescriptor agentProviderFor(String id) {
  for (final provider in agentProviders) {
    if (provider.id == id) return provider;
  }
  return agentProviders.first;
}

/// Non-secret AI agent configuration.
///
/// API keys are deliberately absent: they live only in the encrypted credential
/// store and must never be serialized into this object.
class AgentSettings {
  const AgentSettings({
    required this.providerId,
    required this.model,
    this.baseUri,
  });

  final String providerId;
  final String model;
  final Uri? baseUri;

  AgentProviderDescriptor get provider => agentProviderFor(providerId);

  factory AgentSettings.defaults({
    Map<String, String> environment = const <String, String>{},
  }) {
    final requested = environment['SHADOW_AI_PROVIDER']?.trim();
    final provider = agentProviderFor(
      requested == null || requested.isEmpty ? 'openai' : requested,
    );
    final model = environment['SHADOW_AI_MODEL']?.trim();
    final base = environment['SHADOW_AI_BASE_URL']?.trim();
    return AgentSettings(
      providerId: provider.id,
      model: model == null || model.isEmpty ? provider.defaultModel : model,
      baseUri: base == null || base.isEmpty ? null : Uri.tryParse(base),
    );
  }

  AgentSettings copyWith({String? providerId, String? model, Uri? baseUri}) {
    return AgentSettings(
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      baseUri: baseUri ?? this.baseUri,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'provider': providerId,
        'model': model,
        if (baseUri != null) 'baseUri': baseUri.toString(),
      };

  factory AgentSettings.fromJson(Map<String, Object?> json) {
    final provider = agentProviderFor(json['provider'] as String? ?? 'openai');
    final rawModel = json['model'];
    final model = rawModel is String && rawModel.trim().isNotEmpty
        ? rawModel.trim()
        : provider.defaultModel;
    final rawBase = json['baseUri'];
    final baseUri = rawBase is String && rawBase.trim().isNotEmpty
        ? Uri.tryParse(rawBase)
        : null;
    return AgentSettings(
      providerId: provider.id,
      model: model,
      baseUri: baseUri,
    );
  }

  @override
  String toString() =>
      'AgentSettings(provider: $providerId, model: $model, baseUri: $baseUri)';
}

/// Default per-user configuration directory for the desktop app.
String defaultAgentConfigDirectory({
  Map<String, String> environment = const <String, String>{},
}) {
  if (Platform.isWindows) {
    final appData = environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return p.join(appData, 'ShadowStudio');
    }
    return p.join(
      environment['USERPROFILE'] ?? Directory.current.path,
      'AppData',
      'Roaming',
      'ShadowStudio',
    );
  }
  final xdg = environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.trim().isNotEmpty) {
    return p.join(xdg, 'shadow_studio');
  }
  final home = environment['HOME'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return p.join(home, '.config', 'shadow_studio');
}

/// Loads non-secret settings from `agent.json` and API keys from the encrypted
/// credential store.
///
/// Environment variables are used only when no settings file exists yet; after
/// the first save the file is authoritative.
class AgentSettingsStore {
  AgentSettingsStore({
    String? configDirectory,
    Map<String, String>? environment,
    CredentialStore? credentialStore,
  })  : environment = Map<String, String>.unmodifiable(
          environment ?? Platform.environment,
        ),
        configDirectory = configDirectory ?? defaultAgentConfigDirectory(),
        _credentialStore = credentialStore ??
            SecureFileCredentialStore(
              directory: p.join(
                configDirectory ?? defaultAgentConfigDirectory(),
                'secrets',
              ),
            );

  final Map<String, String> environment;
  final String configDirectory;
  final CredentialStore _credentialStore;
  final Random _random = Random.secure();

  bool _environmentFallbackActive = false;
  String? _lastWarning;

  String get configFilePath => p.join(configDirectory, 'agent.json');

  CredentialStore get credentialStore => _credentialStore;

  /// A non-fatal problem encountered while loading (for example a corrupt file).
  String? get lastWarning => _lastWarning;

  Future<AgentSettings> load() async {
    _lastWarning = null;
    final file = File(configFilePath);
    if (!await file.exists()) {
      _environmentFallbackActive = true;
      return AgentSettings.defaults(environment: environment);
    }
    _environmentFallbackActive = false;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('agent.json root must be an object');
      }
      return AgentSettings.fromJson(decoded.cast<String, Object?>());
    } catch (error) {
      _lastWarning = 'Ignoring unreadable agent settings: $error';
      return AgentSettings.defaults(environment: environment);
    }
  }

  /// Persists provider/model/base URI. When [apiKey] is non-empty it is written
  /// to the encrypted credential store instead of the settings file.
  Future<void> save(AgentSettings settings, {String? apiKey}) async {
    await Directory(configDirectory).create(recursive: true);
    final path = configFilePath;
    final temp = File(
      '$path.tmp.${List<int>.generate(8, (_) => _random.nextInt(256)).join('-')}',
    );
    final payload = jsonEncode(<String, Object?>{
      'version': 1,
      'provider': settings.providerId,
      'model': settings.model,
      if (settings.baseUri != null) 'baseUri': settings.baseUri.toString(),
    });
    await temp.writeAsString(payload, flush: true);
    try {
      await temp.rename(path);
    } on FileSystemException {
      final target = File(path);
      if (await target.exists()) await target.delete();
      await temp.rename(path);
    }
    _environmentFallbackActive = false;
    final key = apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      await _credentialStore.saveApiKey(
        providerId: settings.providerId,
        apiKey: key,
      );
    }
  }

  Future<bool> hasApiKey(String providerId) async =>
      (await readApiKey(providerId)) != null;

  Future<String?> readApiKey(String providerId) async {
    final stored = await _credentialStore.readApiKey(providerId);
    if (stored != null && stored.trim().isNotEmpty) return stored;
    if (!_environmentFallbackActive) return null;
    final envProvider =
        environment['SHADOW_AI_PROVIDER']?.trim().toLowerCase() ?? 'openai';
    final envKey = environment['SHADOW_AI_API_KEY']?.trim();
    if (envKey != null && envKey.isNotEmpty && envProvider == providerId) {
      return envKey;
    }
    return null;
  }

  Future<void> deleteApiKey(String providerId) =>
      _credentialStore.deleteApiKey(providerId);
}
