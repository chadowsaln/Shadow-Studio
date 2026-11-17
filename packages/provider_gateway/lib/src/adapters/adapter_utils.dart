import 'package:shadow_contracts/shadow_contracts.dart';

import '../provider_exception.dart';

/// Appends [relativePath] to [baseUri] without dropping its last segment.
///
/// `Uri.resolve` treats a base without a trailing slash as a file, so
/// resolving `chat/completions` against `https://api.openai.com/v1` would send
/// the request to `/chat/completions`. Provider base URIs are directories.
Uri resolveProviderEndpoint(Uri baseUri, String relativePath) {
  final path = baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
  return baseUri.replace(path: path).resolve(relativePath);
}

abstract final class AdapterHttp {
  static ProviderGatewayException fromStatus(
    int status, {
    required String providerId,
    String? message,
  }) {
    if (status == 401 || status == 403) {
      return ProviderGatewayException(
        code: ShadowErrorCode.providerAuth,
        message: message ?? 'Authentication failed',
        retryable: false,
        statusCode: status,
        providerId: providerId,
      );
    }
    if (status == 429 || status >= 500) {
      return ProviderGatewayException(
        code: ShadowErrorCode.providerRateLimit,
        message: message ?? 'Provider temporarily unavailable',
        retryable: true,
        statusCode: status,
        providerId: providerId,
      );
    }
    if (status == 400 || status == 404 || status == 422) {
      return ProviderGatewayException(
        code: ShadowErrorCode.providerUnsupported,
        message: message ?? 'Provider rejected request',
        retryable: false,
        statusCode: status,
        providerId: providerId,
      );
    }
    return ProviderGatewayException(
      code: ShadowErrorCode.providerStreamBroken,
      message: message ?? 'Provider error',
      retryable: status >= 500,
      statusCode: status,
      providerId: providerId,
    );
  }
}

List<Map<String, Object?>> openAiMessages(AIRequest request) {
  final out = <Map<String, Object?>>[];
  for (final m in request.messages) {
    final role = switch (m.role) {
      AIMessageRole.system => 'system',
      AIMessageRole.user => 'user',
      AIMessageRole.assistant => 'assistant',
      AIMessageRole.tool => 'tool',
    };
    final map = <String, Object?>{'role': role};
    if (m.content != null) map['content'] = m.content;
    if (m.name != null) map['name'] = m.name;
    if (m.toolCallId != null) map['tool_call_id'] = m.toolCallId;
    if (m.toolCalls.isNotEmpty) {
      map['tool_calls'] = [
        for (final tc in m.toolCalls)
          {
            'id': tc.id,
            'type': 'function',
            'function': {'name': tc.name, 'arguments': tc.argumentsJson},
          },
      ];
    }
    out.add(map);
  }
  return out;
}

List<Map<String, Object?>> openAiTools(AIRequest request) => [
  for (final t in request.tools)
    {
      'type': 'function',
      'function': {
        'name': t.name,
        'description': t.description,
        'parameters': t.inputSchema,
      },
    },
];
