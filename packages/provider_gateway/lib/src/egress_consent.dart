import 'package:meta/meta.dart';

/// Explicit user consent before sending media/file content to cloud AI providers.
/// Implementations must record consent per request/scope; never implicit.
@immutable
class EgressPayloadDescriptor {
  const EgressPayloadDescriptor({
    required this.kind, // e.g. image, audio, file, frame
    required this.resourceRef, // file name/id only
    this.mimeType,
    this.approxSizeBytes,
  });
  final String kind;
  final String resourceRef;
  final String? mimeType;
  final int? approxSizeBytes;

  Map<String, Object?> toAudit() => <String, Object?>{
        'kind': kind,
        'ref': resourceRef,
        if (mimeType != null) 'mime': mimeType,
        if (approxSizeBytes != null) 'bytes': approxSizeBytes,
      };
}

abstract interface class EgressConsentService {
  /// Returns true only if user explicitly consented to send these resources to [providerId].
  Future<bool> hasConsent({
    required String providerId,
    required List<EgressPayloadDescriptor> payloads,
    String? purpose,
  });

  /// Request consent (UI integration). Must be explicit; returns granted/denied.
  Future<bool> requestConsent({
    required String providerId,
    required List<EgressPayloadDescriptor> payloads,
    String? purpose,
  });
}

/// Default deny-all; use in tests or when no consent flow is wired.
class DenyAllEgressConsentService implements EgressConsentService {
  const DenyAllEgressConsentService();
  @override
  Future<bool> hasConsent({required String providerId, required List<EgressPayloadDescriptor> payloads, String? purpose}) async => false;
  @override
  Future<bool> requestConsent({required String providerId, required List<EgressPayloadDescriptor> payloads, String? purpose}) async => false;
}

class AllowAllEgressConsentService implements EgressConsentService {
  const AllowAllEgressConsentService();
  @override
  Future<bool> hasConsent({required String providerId, required List<EgressPayloadDescriptor> payloads, String? purpose}) async => true;
  @override
  Future<bool> requestConsent({required String providerId, required List<EgressPayloadDescriptor> payloads, String? purpose}) async => true;
}
