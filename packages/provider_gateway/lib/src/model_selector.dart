import 'package:shadow_contracts/shadow_contracts.dart';

import 'provider_exception.dart';

class ModelSelection {
  const ModelSelection({required this.providerId, required this.model});
  final String providerId;
  final AIModel model;
}

abstract final class ModelSelector {
  /// Selects explicit model if present, else first model satisfying required features.
  static ModelSelection select({
    required List<AIProvider> providers,
    String? providerId,
    String? modelId,
    Set<ProviderFeature> requiredFeatures = const <ProviderFeature>{},
    required List<AIModel> availableModels,
  }) {
    if (modelId != null && modelId.isNotEmpty) {
      final matches = availableModels.where((m) => m.id == modelId && (providerId == null || m.providerId == providerId)).toList();
      if (matches.isEmpty) {
        throw ProviderGatewayException(
          code: ShadowErrorCode.providerUnsupported,
          message: 'Requested model not available',
          retryable: false,
          providerId: providerId,
          details: {'model': modelId},
        );
      }
      final m = matches.first;
      for (final f in requiredFeatures) {
        if (!m.supports(f)) {
          throw ProviderGatewayException(
            code: ShadowErrorCode.providerUnsupported,
            message: 'Requested model lacks required capability',
            retryable: false,
            providerId: m.providerId,
            details: {'model': m.id, 'feature': f.name},
          );
        }
      }
      return ModelSelection(providerId: m.providerId, model: m);
    }
    final candidates = availableModels.where((m) {
      if (providerId != null && m.providerId != providerId) return false;
      return requiredFeatures.every(m.supports);
    }).toList();
    if (candidates.isEmpty) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerUnsupported,
        message: 'No available model satisfies required capabilities',
        retryable: false,
        providerId: providerId,
      );
    }
    return ModelSelection(providerId: candidates.first.providerId, model: candidates.first);
  }
}
