import 'dart:async';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

import 'budget_enforcer.dart';
import 'capability_resolver.dart';
import 'credential_store.dart';
import 'egress_consent.dart';
import 'model_selector.dart';
import 'provider_accounting.dart';
import 'provider_exception.dart';

@immutable
class RouteTarget {
  const RouteTarget({required this.provider, required this.model});
  final AIProvider provider;
  final AIModel model;
}

/// Routes requests to providers, enforces budgets/capabilities/consent, and performs
/// fallback only for network/5xx/429 retryable failures (never on auth 401/403).
class ProviderRouter {
  ProviderRouter({
    required List<AIProvider> providers,
    CredentialStore? credentialStore,
    EgressConsentService? egressConsent,
    ProviderBudgetAccounting? accounting,
    Duration defaultTimeout = const Duration(seconds: 60),
  })  : _providers = {for (final p in providers) p.id: p},
        _credentialResolver = ProviderCredentialResolver(credentialStore ?? InMemoryCredentialStore()),
        _egressConsent = egressConsent ?? const DenyAllEgressConsentService(),
        _accounting = accounting ?? ProviderBudgetAccounting(),
        _defaultTimeout = defaultTimeout;

  final Map<String, AIProvider> _providers;
  final ProviderCredentialResolver _credentialResolver;
  final EgressConsentService _egressConsent;
  final ProviderBudgetAccounting _accounting;
  final Duration _defaultTimeout;

  ProviderBudgetAccounting get accounting => _accounting;

  AIProvider? provider(String id) => _providers[id];
  List<AIProvider> get providers => List<AIProvider>.unmodifiable(_providers.values);

  Future<List<AIModel>> listModels({String? providerId, required CancellationToken cancel}) async {
    final targets = providerId != null ? [_providers[providerId]] : _providers.values;
    final out = <AIModel>[];
    for (final p in targets) {
      if (p == null) {
        throw ProviderGatewayException(
          code: ShadowErrorCode.providerUnsupported,
          message: 'Unknown provider',
          retryable: false,
          providerId: providerId,
        );
      }
      out.addAll(await p.getModels(cancel: cancel));
    }
    return out;
  }

  Future<RouteTarget> resolveTarget({
    String? providerId,
    String? modelId,
    Set<ProviderFeature> requiredFeatures = const <ProviderFeature>{},
    required CancellationToken cancel,
  }) async {
    final models = await listModels(providerId: providerId, cancel: cancel);
    final selection = ModelSelector.select(
      providers: providers,
      providerId: providerId,
      modelId: modelId,
      requiredFeatures: requiredFeatures,
      availableModels: models,
    );
    final provider = _providers[selection.providerId];
    if (provider == null) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerUnsupported,
        message: 'Resolved provider not registered',
        retryable: false,
        providerId: selection.providerId,
      );
    }
    return RouteTarget(provider: provider, model: selection.model);
  }

  /// Streams a request with capability checks, egress consent, budget enforcement,
  /// key resolution, timeout and controlled fallback.
  Stream<AIStreamEvent> stream({
    required AIRequest request,
    String? providerId,
    List<String>? fallbackProviderIds,
    required CancellationToken cancel,
    Duration? timeout,
  }) async* {
    final effectiveTimeout = timeout ?? _defaultTimeout;
    final primaryId = providerId;
    final chain = <String>[
      if (primaryId != null) primaryId,
      ...?fallbackProviderIds,
    ];
    // If no explicit chain, pick by model/provider resolution from all.
    if (chain.isEmpty) {
      final target = await resolveTarget(providerId: null, modelId: request.model, cancel: cancel);
      yield* _streamSingle(
        provider: target.provider,
        model: target.model,
        request: request,
        cancel: cancel,
        timeout: effectiveTimeout,
        allowFallbackToNext: false,
      );
      return;
    }

    ProviderGatewayException? lastError;
    for (var i = 0; i < chain.length; i++) {
      final id = chain[i];
      final provider = _providers[id];
      if (provider == null) {
        lastError = ProviderGatewayException(
          code: ShadowErrorCode.providerUnsupported,
          message: 'Unknown provider in route chain',
          retryable: false,
          providerId: id,
        );
        if (i == chain.length - 1) throw lastError;
        continue;
      }
      AIModel model;
      try {
        final models = await provider.getModels(cancel: cancel);
        if (models.isEmpty) {
          throw ProviderGatewayException(
            code: ShadowErrorCode.providerUnsupported,
            message: 'No models available',
            retryable: false,
            providerId: id,
          );
        }
        final exact = models.where((AIModel m) => m.id == request.model).toList();
        model = exact.isNotEmpty ? exact.first : models.first;
      } on ProviderGatewayException catch (e) {
        lastError = e;
        if (e.isAuth) rethrow; // never fallback on auth
        if (!_canFallback(e) || i == chain.length - 1) rethrow;
        continue;
      }

      try {
        await for (final ev in _streamSingle(
          provider: provider,
          model: model,
          request: request,
          cancel: cancel,
          timeout: effectiveTimeout,
          allowFallbackToNext: i < chain.length - 1,
        )) {
          yield ev;
        }
        return;
      } on ProviderGatewayException catch (e) {
        lastError = e;
        if (e.isAuth) rethrow; // never fallback on auth
        if (!_canFallback(e) || i == chain.length - 1) rethrow;
        continue;
      }
    }
    throw lastError ?? const ProviderGatewayException(
      code: ShadowErrorCode.providerStreamBroken,
      message: 'No provider produced a response',
      retryable: true,
    );
  }

  bool _canFallback(ProviderGatewayException e) {
    if (e.isAuth) return false;
    if (e.code == ShadowErrorCode.providerBudgetExceeded) return false;
    if (e.code == ShadowErrorCode.providerUnsupported) return false;
    // network/timeout/5xx/429 -> retryable
    return e.retryable || e.statusCode == 429 || (e.statusCode != null && e.statusCode! >= 500);
  }

  Stream<AIStreamEvent> _streamSingle({
    required AIProvider provider,
    required AIModel model,
    required AIRequest request,
    required CancellationToken cancel,
    required Duration timeout,
    required bool allowFallbackToNext,
  }) async* {
    cancel.throwIfCancelled();
    await _credentialResolver.requireApiKey(provider.id);
    await _enforceEgressConsent(provider.id, request);

    final adapted = CapabilityResolver.applyToolCapability(request, model);
    CapabilityResolver.ensureRequestSupported(model: model, request: adapted);
    BudgetEnforcer.checkPreRequest(request: adapted, accounting: _accounting, model: model);

    final upstream = provider.stream(request: adapted, cancel: cancel);
    final timed = _withTimeout(upstream, timeout, provider.id, cancel);
    TokenUsage? finalUsage;
    await for (final ev in timed) {
      if (cancel.isCancelled) {
        throw ProviderCancelledException(providerId: provider.id, reason: cancel.reason);
      }
      switch (ev) {
        case AIUsageEvent(:final usage):
          finalUsage = usage;
          BudgetEnforcer.checkPostUsage(usage: usage, request: adapted, model: model, accounting: _accounting);
          yield ev;
        case AICompletedEvent(:final usage):
          final u = usage ?? finalUsage;
          if (u != null) {
            finalUsage = u;
            BudgetEnforcer.checkPostUsage(usage: u, request: adapted, model: model, accounting: _accounting);
          }
          yield AICompletedEvent(finishReason: ev.finishReason, usage: u);
        case AIErrorEvent(:final code, :final message, :final retryable):
          final mapped = _mapProviderError(code, message, retryable, provider.id);
          // If we can fallback, throw to outer; else surface error event then throw.
          throw mapped;
        default:
          yield ev;
      }
    }
  }

  Future<void> _enforceEgressConsent(String providerId, AIRequest request) async {
    final payloads = <EgressPayloadDescriptor>[];
    void collectMeta(Map<String, Object?> meta) {
      final raw = meta['egress_payloads'];
      if (raw is! List) return;
      for (final item in raw) {
        if (item is Map) {
          payloads.add(EgressPayloadDescriptor(
            kind: (item['kind'] as String?) ?? 'file',
            resourceRef: (item['ref'] as String?) ?? (item['name'] as String?) ?? 'unknown',
            mimeType: item['mime'] as String?,
            approxSizeBytes: item['bytes'] is int ? item['bytes'] as int : null,
          ));
        } else if (item is String) {
          payloads.add(EgressPayloadDescriptor(kind: 'file', resourceRef: item));
        }
      }
    }
    collectMeta(request.metadata);
    for (final m in request.messages) {
      collectMeta(m.metadata);
    }
    if (payloads.isEmpty) return;
    final ok = await _egressConsent.hasConsent(providerId: providerId, payloads: payloads, purpose: request.metadata['egress_purpose'] as String?);
    if (ok) return;
    final granted = await _egressConsent.requestConsent(providerId: providerId, payloads: payloads, purpose: request.metadata['egress_purpose'] as String?);
    if (!granted) {
      throw EgressConsentRequiredException(resourceRefs: payloads.map((p) => p.resourceRef).toList());
    }
  }

  ProviderGatewayException _mapProviderError(String? code, String message, bool retryable, String providerId) {
    if (code == ShadowErrorCode.providerAuth) {
      return ProviderGatewayException(code: ShadowErrorCode.providerAuth, message: message, retryable: false, providerId: providerId, statusCode: 401);
    }
    if (code == ShadowErrorCode.providerBudgetExceeded) {
      return ProviderGatewayException(code: ShadowErrorCode.providerBudgetExceeded, message: message, retryable: false, providerId: providerId);
    }
    return ProviderGatewayException(
      code: code ?? ShadowErrorCode.providerStreamBroken,
      message: message,
      retryable: retryable,
      providerId: providerId,
      statusCode: code == ShadowErrorCode.providerRateLimit ? 429 : null,
    );
  }

  Stream<AIStreamEvent> _withTimeout(Stream<AIStreamEvent> source, Duration timeout, String providerId, CancellationToken cancel) {
    final controller = StreamController<AIStreamEvent>();
    Timer? timer;
    StreamSubscription<AIStreamEvent>? sub;
    void arm() {
      timer?.cancel();
      timer = Timer(timeout, () {
        sub?.cancel();
        controller.addError(ProviderGatewayException(
          code: ShadowErrorCode.providerRateLimit,
          message: 'Provider response timed out',
          retryable: true,
          providerId: providerId,
        ));
        controller.close();
      });
    }
    arm();
    sub = source.listen((e) {
      arm();
      controller.add(e);
    }, onError: (Object e, StackTrace st) {
      timer?.cancel();
      controller.addError(e, st);
    }, onDone: () {
      timer?.cancel();
      controller.close();
    }, cancelOnError: true);
    controller.onCancel = () {
      timer?.cancel();
      return sub?.cancel();
    };
    return controller.stream;
  }
}
