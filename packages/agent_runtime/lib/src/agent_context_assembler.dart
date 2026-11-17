import 'package:shadow_context_engine/context_engine.dart';

/// Mutable hand-off point for the context snapshot of the running task.
///
/// The execution loop owns the snapshot (it sees every tool result); the brain
/// reads it when building a prompt. Keeping it behind this tiny holder avoids
/// giving the model layer access to the whole controller.
class AgentContextHolder {
  ContextSnapshot? snapshot;

  /// Compact, provider-safe projection of the snapshot.
  ///
  /// Never includes media bytes, raw file content, or tool payloads; only
  /// metadata the model needs to stay oriented.
  Map<String, Object?> toPromptJson() {
    final current = snapshot;
    if (current == null) return const <String, Object?>{};
    return <String, Object?>{
      'project_id': current.projectId,
      'project_revision': current.projectRevision,
      'workspace_root': current.workspaceRoot,
      'estimated_tokens': current.estimatedTokens,
      'token_budget': current.tokenBudget,
      'media_assets': current.mediaAssets
          .map(
            (a) => <String, Object?>{
              for (final key in const <String>[
                'id',
                'name',
                'kind',
                'duration_ticks',
                'uri',
                'hash',
              ])
                if (a.containsKey(key)) key: a[key],
            },
          )
          .toList(growable: false),
      'selected_clip_ids': current.selectedTimelineClipIds,
      'task_progress': current.currentTaskProgress,
      'recent_tool_results': current.previousToolExecutionResults
          .map(
            (r) => <String, Object?>{
              'tool': r['tool'] ?? r['tool_name'],
              'success': r['success'],
              'error_code': r['error_code'],
            },
          )
          .toList(growable: false),
      'relevant_memory': current.relevantMemorySummaries
          .map((m) => m['summary'])
          .toList(),
    };
  }
}

/// Builds reproducible, budgeted context snapshots for a running task.
class AgentContextAssembler {
  AgentContextAssembler({
    ContextManager? manager,
    this.defaultTokenBudget = 60000,
  }) : _manager =
           manager ?? ContextManager(defaultTokenBudget: defaultTokenBudget);

  final ContextManager _manager;
  final int defaultTokenBudget;

  ContextSnapshot build({
    required String projectId,
    required int projectRevision,
    required String workspaceRoot,
    List<Map<String, Object?>> mediaAssets = const <Map<String, Object?>>[],
    List<String> selectedClipIds = const <String>[],
    Map<String, Object?> timelineStructure = const <String, Object?>{},
    List<Map<String, Object?>> availableTools = const <Map<String, Object?>>[],
    Map<String, Object?> currentTaskProgress = const <String, Object?>{},
    List<Map<String, Object?>> previousToolResults =
        const <Map<String, Object?>>[],
    String? memoryQuery,
    bool egressConsentGranted = false,
    int? tokenBudget,
  }) {
    return _manager.snapshotFor(
      ContextBuildInput(
        projectId: projectId,
        projectRevision: projectRevision,
        workspaceRoot: workspaceRoot,
        mediaAssets: mediaAssets,
        selectedTimelineClipIds: selectedClipIds,
        timelineStructure: timelineStructure,
        availableEditingTools: availableTools,
        currentTaskProgress: currentTaskProgress,
        previousToolExecutionResults: previousToolResults,
        memoryQuery: memoryQuery,
        egressConsentGranted: egressConsentGranted,
      ),
      tokenBudget: tokenBudget ?? defaultTokenBudget,
    );
  }
}
