import 'package:shadow_contracts/shadow_contracts.dart';

import 'provider_exception.dart';

abstract final class CapabilityResolver {
  static void ensureRequestSupported({
    required AIModel model,
    required AIRequest request,
  }) {
    if (request.tools.isNotEmpty && !model.supports(ProviderFeature.toolCalling)) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerUnsupported,
        message: 'Model does not support tool calling',
        retryable: false,
        providerId: model.providerId,
        details: {'model': model.id, 'feature': 'toolCalling'},
      );
    }
    if (_hasVisionContent(request) && !model.supports(ProviderFeature.vision)) {
      throw ProviderGatewayException(
        code: ShadowErrorCode.providerUnsupported,
        message: 'Model does not support vision/media input',
        retryable: false,
        providerId: model.providerId,
        details: {'model': model.id, 'feature': 'vision'},
      );
    }
  }

  /// Returns request with tools stripped when model lacks native tool calling support context? 
  /// Spec: "Tool calling ... absent: tool hidden from request, not sent" (capability map).
  static AIRequest applyToolCapability(AIRequest request, AIModel model) {
    if (request.tools.isEmpty) return request;
    if (model.supports(ProviderFeature.toolCalling)) return request;
    return AIRequest(
      model: request.model,
      messages: request.messages,
      tools: const <AIToolDefinition>[],
      temperature: request.temperature,
      maxOutputTokens: request.maxOutputTokens,
      budget: request.budget,
      metadata: {...request.metadata, 'tools_omitted': true, 'tools_omitted_reason': 'provider_unsupported'},
    );
  }

  static bool _hasVisionContent(AIRequest request) {
    for (final m in request.messages) {
      final meta = m.metadata;
      if (meta['has_vision'] == true) return true;
      if (meta['egress_payloads'] is List && (meta['egress_payloads'] as List).isNotEmpty) return true;
      if (meta['images'] is List && (meta['images'] as List).isNotEmpty) return true;
    }
    return request.metadata['has_vision'] == true || request.metadata['egress_payloads'] is List;
  }
}
