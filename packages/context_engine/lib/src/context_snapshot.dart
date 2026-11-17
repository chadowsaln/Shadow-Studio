import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Reproducible, budgeted snapshot of agent context for a project/task turn.
class ContextSnapshot {
  ContextSnapshot({
    required this.projectId,
    required this.projectRevision,
    required this.workspaceRoot,
    required this.mediaAssets,
    required this.selectedTimelineClipIds,
    required this.timelineStructure,
    required this.availableEditingTools,
    required this.environmentCapabilities,
    required this.currentTaskProgress,
    required this.previousToolExecutionResults,
    required this.relevantMemorySummaries,
    required this.createdAt,
    required this.estimatedTokens,
    required this.tokenBudget,
    required this.truncatedSections,
  }) : contextHash = _computeHash(
          projectId: projectId,
          projectRevision: projectRevision,
          workspaceRoot: workspaceRoot,
          mediaAssets: mediaAssets,
          selectedTimelineClipIds: selectedTimelineClipIds,
          timelineStructure: timelineStructure,
          availableEditingTools: availableEditingTools,
          environmentCapabilities: environmentCapabilities,
          currentTaskProgress: currentTaskProgress,
          previousToolExecutionResults: previousToolExecutionResults,
          relevantMemorySummaries: relevantMemorySummaries,
        );

  final String projectId;
  final int projectRevision;
  final String workspaceRoot;
  final List<Map<String, Object?>> mediaAssets;
  final List<String> selectedTimelineClipIds;
  final Map<String, Object?> timelineStructure;
  final List<Map<String, Object?>> availableEditingTools;
  final Map<String, Object?> environmentCapabilities;
  final Map<String, Object?> currentTaskProgress;
  final List<Map<String, Object?>> previousToolExecutionResults;
  final List<Map<String, Object?>> relevantMemorySummaries;
  final DateTime createdAt;
  final int estimatedTokens;
  final int tokenBudget;
  final List<String> truncatedSections;

  /// Stable hash over the reproducible context content (excludes createdAt/timestamps).
  final String contextHash;

  Map<String, Object?> toJson() => <String, Object?>{
        'projectId': projectId,
        'project_revision': projectRevision,
        'workspace_root': workspaceRoot,
        'mediaAssets': mediaAssets,
        'selectedTimelineClipIds': selectedTimelineClipIds,
        'timelineStructure': timelineStructure,
        'availableEditingTools': availableEditingTools,
        'environmentCapabilities': environmentCapabilities,
        'currentTaskProgress': currentTaskProgress,
        'previousToolExecutionResults': previousToolExecutionResults,
        'relevantMemorySummaries': relevantMemorySummaries,
        'estimatedTokens': estimatedTokens,
        'tokenBudget': tokenBudget,
        'truncatedSections': truncatedSections,
        'context_hash': contextHash,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static String _computeHash({
    required String projectId,
    required int projectRevision,
    required String workspaceRoot,
    required List<Map<String, Object?>> mediaAssets,
    required List<String> selectedTimelineClipIds,
    required Map<String, Object?> timelineStructure,
    required List<Map<String, Object?>> availableEditingTools,
    required Map<String, Object?> environmentCapabilities,
    required Map<String, Object?> currentTaskProgress,
    required List<Map<String, Object?>> previousToolExecutionResults,
    required List<Map<String, Object?>> relevantMemorySummaries,
  }) {
    final canonical = <String, Object?>{
      'projectId': projectId,
      'project_revision': projectRevision,
      'workspace_root': workspaceRoot,
      'mediaAssets': mediaAssets,
      'selectedTimelineClipIds': selectedTimelineClipIds,
      'timelineStructure': timelineStructure,
      'availableEditingTools': availableEditingTools,
      'environmentCapabilities': environmentCapabilities,
      'currentTaskProgress': currentTaskProgress,
      'previousToolExecutionResults': previousToolExecutionResults,
      'relevantMemorySummaries': relevantMemorySummaries,
    };
    final encoded = jsonEncode(_normalize(canonical));
    return sha256.convert(utf8.encode(encoded)).toString();
  }
}

/// Recursively normalizes maps/lists so JSON encoding is deterministic.
Object? _normalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final out = <String, Object?>{};
    for (final k in keys) {
      out[k] = _normalize(value[k]);
    }
    return out;
  } else if (value is List) {
    return value.map(_normalize).toList(growable: false);
  }
  return value;
}

/// Rough token estimator (~4 chars/token). Deterministic and cheap.
int estimateTokens(Object? value) {
  final s = value is String ? value : jsonEncode(_normalize(value));
  if (s.isEmpty) return 0;
  return (s.length / 4).ceil();
}
