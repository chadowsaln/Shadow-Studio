import 'package:shadow_contracts/shadow_contracts.dart';

import 'provider_exception.dart';

class ProviderBudgetAccounting {
  ProviderBudgetAccounting({this.maxInputTokensPerTask = 60000, this.maxCostUsdPerTask});

  final int maxInputTokensPerTask;
  final double? maxCostUsdPerTask;
  int _inputTokensUsed = 0;
  int _outputTokensUsed = 0;
  double _costUsdUsed = 0.0;

  int get inputTokensUsed => _inputTokensUsed;
  int get outputTokensUsed => _outputTokensUsed;
  double get costUsdUsed => _costUsdUsed;

  void ensureWithinTaskInputBudget(int additionalInputTokens) {
    if (_inputTokensUsed + additionalInputTokens > maxInputTokensPerTask) {
      throw BudgetExceededException(
        message: 'Task input token budget exceeded',
        details: {
          'limit': maxInputTokensPerTask,
          'used': _inputTokensUsed,
          'requested_additional': additionalInputTokens,
        },
      );
    }
  }

  void recordUsage({TokenUsage? usage, double? costUsd}) {
    if (usage != null) {
      _inputTokensUsed += usage.inputTokens ?? 0;
      _outputTokensUsed += usage.outputTokens ?? 0;
    }
    if (costUsd != null) {
      _costUsdUsed += costUsd;
      final limit = maxCostUsdPerTask;
      if (limit != null && _costUsdUsed > limit) {
        throw BudgetExceededException(
          message: 'Task cost budget exceeded',
          details: {'limit': limit, 'used': _costUsdUsed},
        );
      }
    }
  }
}

abstract final class BudgetEnforcer {
  static int estimateInputTokens(AIRequest request) {
    // Conservative heuristic: ~4 chars/token over serialized content; no external tokenizer.
    var chars = 0;
    for (final m in request.messages) {
      chars += (m.content ?? '').length;
      for (final tc in m.toolCalls) {
        chars += tc.argumentsJson.length + tc.name.length;
      }
    }
    for (final t in request.tools) {
      chars += t.name.length + t.description.length + t.inputSchema.toString().length;
    }
    final est = (chars / 4).ceil();
    return est < 1 ? 1 : est;
  }

  static void checkPreRequest({
    required AIRequest request,
    required ProviderBudgetAccounting accounting,
    AIModel? model,
  }) {
    final est = estimateInputTokens(request);
    final reqMax = request.budget?.maxInputTokens;
    if (reqMax != null && est > reqMax) {
      throw BudgetExceededException(
        message: 'Request exceeds per-request input token budget',
        details: {'estimate': est, 'limit': reqMax},
      );
    }
    if (request.budget?.maxOutputTokens != null &&
        request.maxOutputTokens > request.budget!.maxOutputTokens!) {
      throw BudgetExceededException(
        message: 'Request max output tokens exceeds budget',
        details: {'requested': request.maxOutputTokens, 'limit': request.budget!.maxOutputTokens},
      );
    }
    final context = model?.contextWindowTokens;
    if (context != null && est > context) {
      throw BudgetExceededException(
        message: 'Estimated input exceeds model context window',
        details: {'estimate': est, 'context': context, 'model': model?.id},
      );
    }
    accounting.ensureWithinTaskInputBudget(est);
  }

  static void checkPostUsage({
    required TokenUsage? usage,
    required AIRequest request,
    required AIModel? model,
    required ProviderBudgetAccounting accounting,
  }) {
    if (usage == null) return;
    final inTok = usage.inputTokens ?? 0;
    final outTok = usage.outputTokens ?? 0;
    final total = usage.totalTokens ?? (inTok + outTok);
    final reqMaxIn = request.budget?.maxInputTokens;
    if (reqMaxIn != null && inTok > reqMaxIn) {
      throw BudgetExceededException(
        message: 'Actual input tokens exceed request budget',
        details: {'actual': inTok, 'limit': reqMaxIn},
      );
    }
    final reqMaxOut = request.budget?.maxOutputTokens;
    if (reqMaxOut != null && outTok > reqMaxOut) {
      throw BudgetExceededException(
        message: 'Actual output tokens exceed request budget',
        details: {'actual': outTok, 'limit': reqMaxOut},
      );
    }
    double? cost;
    if (model != null && (model.inputCostPer1kTokens != null || model.outputCostPer1kTokens != null)) {
      cost = (inTok / 1000.0) * (model.inputCostPer1kTokens ?? 0.0) +
          (outTok / 1000.0) * (model.outputCostPer1kTokens ?? 0.0);
    }
    final maxCost = request.budget?.maxCostUsd;
    if (cost != null && maxCost != null && cost > maxCost) {
      throw BudgetExceededException(
        message: 'Request cost exceeds budget',
        details: {'cost_usd': cost, 'limit': maxCost},
      );
    }
    if (accounting.inputTokensUsed + inTok > accounting.maxInputTokensPerTask) {
      throw BudgetExceededException(
        message: 'Task input token budget exceeded after usage',
        details: {'limit': accounting.maxInputTokensPerTask, 'used': accounting.inputTokensUsed, 'actual': inTok},
      );
    }
    accounting.recordUsage(usage: usage, costUsd: cost);
    // total sanity recorded via parts; no-op
    if (total < 0) {
      throw BudgetExceededException(message: 'Invalid token usage reported');
    }
  }
}
