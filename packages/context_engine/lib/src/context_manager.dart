import 'context_builder.dart';
import 'context_snapshot.dart';

/// Manages generation of reproducible, budgeted context snapshots.
class ContextManager {
  ContextManager({
    ContextBuilder? builder,
    this.defaultTokenBudget = 60000,
  }) : _builder = builder ?? ContextBuilder();

  final ContextBuilder _builder;
  final int defaultTokenBudget;

  ContextSnapshot snapshotFor(ContextBuildInput input, {int? tokenBudget}) {
    return _builder.build(input, tokenBudget: tokenBudget ?? defaultTokenBudget);
  }
}
