import 'package:meta/meta.dart';

/// Append-only edit operation entry in a `.ssproj` file (`edit_ops` table).
@immutable
class StoredEditOp {
  final int? seq;
  final String projectId;
  final int revision;
  final String batchId;
  final String opType;
  final String payloadJson;
  final String inverseJson;
  final String origin; // 'ui', 'ai', 'import', 'system'
  final String createdAt;

  const StoredEditOp({
    this.seq,
    required this.projectId,
    required this.revision,
    required this.batchId,
    required this.opType,
    required this.payloadJson,
    required this.inverseJson,
    required this.origin,
    required this.createdAt,
  });

  StoredEditOp copyWith({
    int? seq,
    String? projectId,
    int? revision,
    String? batchId,
    String? opType,
    String? payloadJson,
    String? inverseJson,
    String? origin,
    String? createdAt,
  }) {
    return StoredEditOp(
      seq: seq ?? this.seq,
      projectId: projectId ?? this.projectId,
      revision: revision ?? this.revision,
      batchId: batchId ?? this.batchId,
      opType: opType ?? this.opType,
      payloadJson: payloadJson ?? this.payloadJson,
      inverseJson: inverseJson ?? this.inverseJson,
      origin: origin ?? this.origin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredEditOp &&
          runtimeType == other.runtimeType &&
          seq == other.seq &&
          projectId == other.projectId &&
          revision == other.revision &&
          batchId == other.batchId &&
          opType == other.opType &&
          payloadJson == other.payloadJson &&
          inverseJson == other.inverseJson &&
          origin == other.origin &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        seq,
        projectId,
        revision,
        batchId,
        opType,
        payloadJson,
        inverseJson,
        origin,
        createdAt,
      );

  @override
  String toString() =>
      'StoredEditOp(seq: $seq, rev: $revision, batch: $batchId, op: $opType, origin: $origin)';
}
