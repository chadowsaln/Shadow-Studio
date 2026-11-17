import 'context_snapshot.dart';
import 'context_trimmer.dart';
import 'memory_manager.dart';

/// Inputs required to build an agent context snapshot.
class ContextBuildInput {
  const ContextBuildInput({
    required this.projectId,
    required this.projectRevision,
    required this.workspaceRoot,
    this.mediaAssets = const <Map<String, Object?>>[],
    this.selectedTimelineClipIds = const <String>[],
    this.timelineStructure = const <String, Object?>{},
    this.availableEditingTools = const <Map<String, Object?>>[],
    this.environmentCapabilities = const <String, Object?>{},
    this.currentTaskProgress = const <String, Object?>{},
    this.previousToolExecutionResults = const <Map<String, Object?>>[],
    this.memoryQuery,
    this.egressConsentGranted = false,
  });

  final String projectId;
  final int projectRevision;
  final String workspaceRoot;

  /// Metadata and/or extracted keyframe references only. Must not contain raw
  /// video/audio file bytes.
  final List<Map<String, Object?>> mediaAssets;
  final List<String> selectedTimelineClipIds;
  final Map<String, Object?> timelineStructure;
  final List<Map<String, Object?>> availableEditingTools;
  final Map<String, Object?> environmentCapabilities;
  final Map<String, Object?> currentTaskProgress;

  /// Oldest-first recommended so trimming can drop oldest results first.
  final List<Map<String, Object?>> previousToolExecutionResults;
  final String? memoryQuery;

  /// Explicit data-egress consent for this context/build. Media/content must
  /// never be uploaded without explicit consent; when false, assets are reduced
  /// to local metadata only.
  final bool egressConsentGranted;
}

/// Builds reproducible, budgeted [ContextSnapshot]s.
class ContextBuilder {
  ContextBuilder({
    ContextTrimmer? trimmer,
    MemoryManager? memoryManager,
  })  : _trimmer = trimmer ?? const ContextTrimmer(),
        _memoryManager = memoryManager;

  final ContextTrimmer _trimmer;
  final MemoryManager? _memoryManager;

  ContextSnapshot build(ContextBuildInput input, {int? tokenBudget}) {
    final memories = _memoryManager?.retrieveRelevantSummaries(
          projectId: input.projectId,
          query: input.memoryQuery,
        ) ??
        const <Map<String, Object?>>[];

    final sanitizedAssets = input.mediaAssets
        .map((a) => _sanitizeMediaAsset(a, egressConsentGranted: input.egressConsentGranted))
        .toList(growable: false);

    final trimmed = _trimmer.trim(
      projectId: input.projectId,
      projectRevision: input.projectRevision,
      workspaceRoot: input.workspaceRoot,
      mediaAssets: sanitizedAssets,
      selectedTimelineClipIds: List<String>.from(input.selectedTimelineClipIds),
      timelineStructure: Map<String, Object?>.from(input.timelineStructure),
      availableEditingTools: input.availableEditingTools
          .map((t) => Map<String, Object?>.from(t))
          .toList(growable: false),
      environmentCapabilities: Map<String, Object?>.from(input.environmentCapabilities),
      currentTaskProgressList: [Map<String, Object?>.from(input.currentTaskProgress)],
      previousToolExecutionResults: input.previousToolExecutionResults
          .map((r) => _sanitizeToolResult(r))
          .toList(growable: false),
      relevantMemorySummaries: memories,
      tokenBudget: tokenBudget,
    );

    return ContextSnapshot(
      projectId: trimmed.projectId,
      projectRevision: trimmed.projectRevision,
      workspaceRoot: trimmed.workspaceRoot,
      mediaAssets: trimmed.mediaAssets,
      selectedTimelineClipIds: trimmed.selectedTimelineClipIds,
      timelineStructure: trimmed.timelineStructure,
      availableEditingTools: trimmed.availableEditingTools,
      environmentCapabilities: trimmed.environmentCapabilities,
      currentTaskProgress: trimmed.currentTaskProgress,
      previousToolExecutionResults: trimmed.previousToolExecutionResults,
      relevantMemorySummaries: trimmed.relevantMemorySummaries,
      createdAt: DateTime.now().toUtc(),
      estimatedTokens: trimmed.estimatedTokens,
      tokenBudget: trimmed.tokenBudget,
      truncatedSections: trimmed.truncatedSections,
    );
  }

  Map<String, Object?> _sanitizeMediaAsset(
    Map<String, Object?> asset, {
    required bool egressConsentGranted,
  }) {
    // Never include raw file bytes/entire media payloads. Keep metadata and
    // extracted keyframes references/metadata only.
    const blockedKeys = {
      'bytes', 'data', 'binary', 'contentBytes', 'fileBytes', 'raw', 'base64',
      'blob',
    };
    final out = <String, Object?>{};
    for (final e in asset.entries) {
      if (blockedKeys.contains(e.key)) continue;
      // Large opaque inline content fields are not allowed in context.
      if (e.key == 'inlineContent' || e.key == 'fullTranscript') continue;
      out[e.key] = e.value;
    }
    out['egressConsentGranted'] = egressConsentGranted;
    return out;
  }

  Map<String, Object?> _sanitizeToolResult(Map<String, Object?> r) {
    // Avoid carrying huge blobs from previous tool results.
    final out = Map<String, Object?>.from(r);
    final data = out['data'];
    if (data is String && data.length > 4000) {
      out['data'] = '${data.substring(0, 4000)}…[truncated]';
    }
    return out;
  }
}
