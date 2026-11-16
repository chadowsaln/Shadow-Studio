import 'dart:async';

import 'package:shadow_contracts/shadow_contracts.dart';

import '../provider_exception.dart';

/// Configurable mock provider for unit tests (no real API keys, no network).
class MockProvider implements AIProvider {
  MockProvider({
    required this.id,
    this.displayName = 'Mock Provider',
    Set<ProviderFeature>? features,
    List<AIModel>? models,
    this.onStream,
    this.latency = Duration.zero,
    this.failWith,
  })  : features = features ?? const {ProviderFeature.textGeneration, ProviderFeature.streaming, ProviderFeature.toolCalling},
        models = models ?? const [];

  @override
  final String id;
  @override
  final String displayName;
  @override
  final Set<ProviderFeature> features;
  final List<AIModel> models;

  /// If provided, generates stream events; otherwise emits a simple completion.
  final Stream<AIStreamEvent> Function(AIRequest request, CancellationToken cancel)? onStream;
  final Duration latency;
  final ProviderGatewayException? failWith;

  final List<AIRequest> requests = <AIRequest>[];

  @override
  Future<List<AIModel>> getModels({required CancellationToken cancel}) async {
    cancel.throwIfCancelled();
    if (models.isNotEmpty) return models;
    return [
      AIModel(
        id: '${id}-model',
        providerId: id,
        displayName: '$displayName Model',
        features: features,
        contextWindowTokens: 128000,
        inputCostPer1kTokens: 0.001,
        outputCostPer1kTokens: 0.002,
      ),
    ];
  }

  @override
  Stream<AIStreamEvent> stream({required AIRequest request, required CancellationToken cancel}) async* {
    requests.add(request);
    cancel.throwIfCancelled();
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    cancel.throwIfCancelled();
    final failure = failWith;
    if (failure != null) throw failure;
    final custom = onStream;
    if (custom != null) {
      yield* custom(request, cancel);
      return;
    }
    yield const AITextDeltaEvent('ok');
    yield const AICompletedEvent(finishReason: 'stop', usage: TokenUsage(inputTokens: 10, outputTokens: 2, totalTokens: 12));
  }
}
