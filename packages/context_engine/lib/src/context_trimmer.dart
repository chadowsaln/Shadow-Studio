import 'context_snapshot.dart';

/// Trims assembled context sections to fit within [tokenBudget].
///
/// Policy: remove old tool results before important project context.
/// Project/timeline/selection/capabilities/tools/progress/revision/workspace are
/// treated as important and preserved whenever possible.
class ContextTrimmer {
  const ContextTrimmer({this.defaultBudget = 60000});

  final int defaultBudget;

  TrimResult trim({
    required String projectId,
    required int projectRevision,
    required String workspaceRoot,
    required List<Map<String, Object?>> mediaAssets,
    required List<String> selectedTimelineClipIds,
    required Map<String, Object?> timelineStructure,
    required List<Map<String, Object?>> availableEditingTools,
    required Map<String, Object?> environmentCapabilities,
    required List<Map<String, Object?>> currentTaskProgressList,
    required List<Map<String, Object?>> previousToolExecutionResults,
    required List<Map<String, Object?>> relevantMemorySummaries,
    int? tokenBudget,
  }) {
    final budget = tokenBudget ?? defaultBudget;
    final truncated = <String>[];

    // Work on mutable copies (oldest-first tool results assumed; we drop from front).
    var toolResults = List<Map<String, Object?>>.from(
      previousToolExecutionResults,
    );
    var memories = List<Map<String, Object?>>.from(relevantMemorySummaries);
    var media = List<Map<String, Object?>>.from(mediaAssets);
    var timeline = Map<String, Object?>.from(timelineStructure);
    var progress = currentTaskProgressList.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(currentTaskProgressList.last);

    int total() => estimateTokens(<String, Object?>{
      'p': projectId,
      'r': projectRevision,
      'w': workspaceRoot,
      'm': media,
      's': selectedTimelineClipIds,
      't': timeline,
      'a': availableEditingTools,
      'e': environmentCapabilities,
      'g': progress,
      'o': toolResults,
      'mem': memories,
    });

    // 1) Drop oldest tool results first (before important project context).
    while (total() > budget && toolResults.isNotEmpty) {
      toolResults.removeAt(0);
      if (!truncated.contains('previousToolExecutionResults')) {
        truncated.add('previousToolExecutionResults');
      }
    }

    // 2) Drop oldest/least-relevant memories next.
    while (total() > budget && memories.isNotEmpty) {
      memories.removeLast();
      if (!truncated.contains('relevantMemorySummaries')) {
        truncated.add('relevantMemorySummaries');
      }
    }

    // 3) Reduce media asset detail (keep ids/names/metadata summaries, never blobs/paths payloads).
    while (total() > budget && media.isNotEmpty) {
      // progressively trim largest entries to minimal metadata
      final idx = _largestIndex(media);
      media[idx] = _minimalMedia(media[idx]);
      if (media.every(_isMinimalMedia) && total() > budget) {
        media.removeLast();
      }
      if (!truncated.contains('mediaAssets')) {
        truncated.add('mediaAssets');
      }
      if (media.isEmpty) break;
    }

    // 4) Trim timeline structure detail (never drop identity/structure keys entirely if possible).
    if (total() > budget && timeline.isNotEmpty) {
      timeline = _trimTimeline(timeline);
      truncated.add('timelineStructure');
    }

    // 5) As last resort, truncate progress details (preserve revision/workspace/project id elsewhere).
    if (total() > budget && progress.isNotEmpty) {
      progress = <String, Object?>{
        'status': progress['status'],
        'step': progress['step'],
        'truncated': true,
      };
      truncated.add('currentTaskProgress');
    }

    return TrimResult(
      projectId: projectId,
      projectRevision: projectRevision,
      workspaceRoot: workspaceRoot,
      mediaAssets: media,
      selectedTimelineClipIds: selectedTimelineClipIds,
      timelineStructure: timeline,
      availableEditingTools: availableEditingTools,
      environmentCapabilities: environmentCapabilities,
      currentTaskProgress: progress,
      previousToolExecutionResults: toolResults,
      relevantMemorySummaries: memories,
      estimatedTokens: total(),
      tokenBudget: budget,
      truncatedSections: truncated,
    );
  }

  int _largestIndex(List<Map<String, Object?>> items) {
    var maxIdx = 0;
    var max = -1;
    for (var i = 0; i < items.length; i++) {
      final t = estimateTokens(items[i]);
      if (t > max) {
        max = t;
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  Map<String, Object?> _minimalMedia(Map<String, Object?> m) =>
      <String, Object?>{
        if (m['id'] != null) 'id': m['id'],
        if (m['name'] != null) 'name': m['name'],
        if (m['kind'] != null) 'kind': m['kind'],
        if (m['durationMs'] != null) 'durationMs': m['durationMs'],
        if (m['keyframes'] != null) 'keyframes': m['keyframes'],
      };

  bool _isMinimalMedia(Map<String, Object?> m) => m.keys.every(
    (k) => const {'id', 'name', 'kind', 'durationMs', 'keyframes'}.contains(k),
  );

  Map<String, Object?> _trimTimeline(Map<String, Object?> t) {
    final out = <String, Object?>{};
    // keep structural counts/ids if present
    for (final key in [
      'tracks',
      'trackCount',
      'clipCount',
      'selected',
      'durationTicks',
    ]) {
      if (t.containsKey(key)) out[key] = t[key];
    }
    if (out.isEmpty) {
      out['summary'] = 'timeline_present';
      if (t['clipCount'] != null) out['clipCount'] = t['clipCount'];
    }
    return out;
  }
}

class TrimResult {
  const TrimResult({
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
    required this.estimatedTokens,
    required this.tokenBudget,
    required this.truncatedSections,
  });

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
  final int estimatedTokens;
  final int tokenBudget;
  final List<String> truncatedSections;
}
