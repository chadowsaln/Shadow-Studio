import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

enum PolicyEffect { allow, requireApproval, deny }

@immutable
class PolicyDecision {
  const PolicyDecision.allow({this.reason})
      : effect = PolicyEffect.allow,
        reasonCode = null;

  const PolicyDecision.requireApproval({
    required this.reasonCode,
    required this.reason,
  }) : effect = PolicyEffect.requireApproval;

  const PolicyDecision.deny({
    required this.reasonCode,
    required this.reason,
  }) : effect = PolicyEffect.deny;

  final PolicyEffect effect;
  final String? reasonCode;
  final String? reason;
}

/// Independent policy (never derived from model responses).
class PermissionPolicy {
  const PermissionPolicy({
    this.defaultWorkspaceRoot,
    this.operationsInvolvingDeclaredSpending = const <String>{},
  });

  /// If null, workspace checks are performed by [WorkspaceGuard] against provided root.
  final String? defaultWorkspaceRoot;

  /// Tool names that involve declared AI spending (restricted).
  final Set<String> operationsInvolvingDeclaredSpending;

  // Tool categories aligned with spec.
  static const Set<String> _safeTools = <String>{
    'get_system_info',
    'inspect_capabilities',
    'list_files',
    'scan_media',
    'get_metadata',
    'save_project',
    'add_clip',
    'trim_clip',
    'split_clip',
    'move_clip',
    'remove_clip',
    'add_effect',
    'remove_effect',
    'add_transition',
    'extract_audio',
    'mix_audio',
    'normalize_audio',
    'add_text',
    'extract_keyframes',
    'detect_scenes',
    'render_preview',
    'get_preview',
  };

  static const Set<String> _restrictedTools = <String>{
    'create_project',
    'open_project',
    'analyze_video',
    'render_video',
    'generate_subtitles',
  };

  static const Set<String> _dangerousTools = <String>{
    'delete_file',
    'delete_original',
    'overwrite_file',
    'export_project',
  };

  ToolRiskLevel classify(String toolName, {ToolRiskLevel? declared}) {
    if (_dangerousTools.contains(toolName)) return ToolRiskLevel.dangerous;
    if (_restrictedTools.contains(toolName) || operationsInvolvingDeclaredSpending.contains(toolName)) {
      return ToolRiskLevel.restricted;
    }
    if (_safeTools.contains(toolName)) return ToolRiskLevel.safe;
    // Trust explicit declaration only as a floor (cannot downscope); unknown -> at least restricted.
    final d = declared ?? ToolRiskLevel.restricted;
    if (d == ToolRiskLevel.safe) return ToolRiskLevel.restricted;
    return d;
  }

  PolicyDecision evaluate({
    required String toolName,
    required ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required bool insideDefaultWorkspace,
    required bool hasValidApproval,
    required bool involvesDeclaredSpending,
  }) {
    final effective = _maxRisk(riskLevel, classify(toolName, declared: riskLevel));

    if (effective == ToolRiskLevel.dangerous) {
      if (!hasValidApproval) {
        return const PolicyDecision.requireApproval(
          reasonCode: ShadowErrorCode.permApprovalRequired,
          reason: 'Dangerous operation requires explicit user approval',
        );
      }
      return const PolicyDecision.allow();
    }

    if (effective == ToolRiskLevel.restricted) {
      final outside = !insideDefaultWorkspace;
      final spending = involvesDeclaredSpending || operationsInvolvingDeclaredSpending.contains(toolName);
      if ((outside || spending) && !hasValidApproval) {
        return const PolicyDecision.requireApproval(
          reasonCode: ShadowErrorCode.permApprovalRequired,
          reason: 'Restricted operation requires explicit approval in this context',
        );
      }
      return const PolicyDecision.allow();
    }

    // SAFE
    return const PolicyDecision.allow();
  }

  ToolRiskLevel _maxRisk(ToolRiskLevel a, ToolRiskLevel b) {
    int rank(ToolRiskLevel r) => switch (r) {
          ToolRiskLevel.safe => 0,
          ToolRiskLevel.restricted => 1,
          ToolRiskLevel.dangerous => 2,
        };
    return rank(a) >= rank(b) ? a : b;
  }

  /// AI data egress always requires separate explicit consent (not inferred from file approvals).
  bool requiresSeparateEgressConsent(EgressRequest request) {
    return request.resourceRefs.isNotEmpty;
  }
}
