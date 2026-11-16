import '../common/cancellation.dart';
import 'provider_models.dart';

abstract interface class AIProvider {
  String get id;
  String get displayName;
  Set<ProviderFeature> get features;

  Future<List<AIModel>> getModels({required CancellationToken cancel});

  Stream<AIStreamEvent> stream({
    required AIRequest request,
    required CancellationToken cancel,
  });
}
