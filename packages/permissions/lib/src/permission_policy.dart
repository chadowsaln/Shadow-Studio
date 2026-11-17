import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// Result an independent policy can reach for a tool call.
enum PolicyEffect { allow, requireApproval, deny }

@immutable
class PolicyDecision {
  const PolicyDecision.allow({this.reason, this.reasonCode})
    : effect = PolicyEffect.allow;

  const PolicyDecision.requireApproval({
    required this.reasonCode,
    required this.reason,
  }) : effect = PolicyEffect.requireApproval;

  const PolicyDecision.deny({required this.reasonCode, required this.reason})
    : effect = PolicyEffect.deny;

  final PolicyEffect effect;
  final String? reasonCode;
  final String? reason;
}

/// Risk classification declared by the spec (LOW / MEDIUM / HIGH).
///
/// `safe` = LOW, `restricted` = MEDIUM, `dangerous` = HIGH.
@immutable
class ToolPolicy {
  const ToolPolicy(this.riskLevel, {this.requiresApprovalAlways = false});

  final ToolRiskLevel riskLevel;

  /// Force an approval even when the call otherwise looks in-workspace.
  final bool requiresApprovalAlways;
}

/// Central, code-owned policy. It is never derived from model output.
///
/// Rules:
/// * Classification is a *floor*: a tool cannot declare itself safer than the
///   table says. Unknown tools are at least `restricted` and require approval
///   (fail closed).
/// * Protected tools (policy/approval/audit manipulation) are always denied.
/// * Shell/process execution is always HIGH risk, even when an unknown alias is
///   used, and is additionally validated by `ShellCommandGuard`.
class PermissionPolicy {
  const PermissionPolicy({
    this.toolPolicies = builtinToolPolicies,
    this.protectedTools = builtinProtectedTools,
    this.defaultWorkspaceRoot,
    this.operationsInvolvingDeclaredSpending = const <String>{},
    this.requireApprovalForUnknownTools = true,
  });

  /// Per-tool policy table. Overrides replace the built-in entry.
  final Map<String, ToolPolicy> toolPolicies;

  /// Tools that can weaken the security boundary itself; always denied.
  final Set<String> protectedTools;

  /// If null, workspace checks are performed by [WorkspaceGuard] against the
  /// caller-provided root.
  final String? defaultWorkspaceRoot;

  /// Tool names that involve declared AI spending (restricted / MEDIUM).
  final Set<String> operationsInvolvingDeclaredSpending;

  /// Fail closed: an unclassified tool cannot be allowed silently.
  final bool requireApprovalForUnknownTools;

  // ---------------------------------------------------------------------------
  // Built-in table (spec §8 plus the Shadow Studio risk taxonomy).
  // ---------------------------------------------------------------------------

  /// LOW risk: read-only metadata, listing, analysis, previews.
  static const Map<String, ToolPolicy> builtinToolPolicies =
      <String, ToolPolicy>{
        // Read-only inspection.
        'get_system_info': ToolPolicy(ToolRiskLevel.safe),
        'inspect_capabilities': ToolPolicy(ToolRiskLevel.safe),
        'list_files': ToolPolicy(ToolRiskLevel.safe),
        'scan_media': ToolPolicy(ToolRiskLevel.safe),
        'get_metadata': ToolPolicy(ToolRiskLevel.safe),
        'analyze_video': ToolPolicy(ToolRiskLevel.safe),
        'detect_scenes': ToolPolicy(ToolRiskLevel.safe),
        'extract_keyframes': ToolPolicy(ToolRiskLevel.safe),
        'get_preview': ToolPolicy(ToolRiskLevel.safe),
        'render_preview': ToolPolicy(ToolRiskLevel.safe),
        'read_media_metadata': ToolPolicy(ToolRiskLevel.safe),

        // Shadow Studio real media tools.
        'media_probe': ToolPolicy(ToolRiskLevel.safe),
        'media_analysis': ToolPolicy(ToolRiskLevel.restricted),
        'timeline_edit': ToolPolicy(ToolRiskLevel.restricted),

        // MEDIUM risk: timeline mutation, temp files, generated artifacts.
        'create_project': ToolPolicy(ToolRiskLevel.restricted),
        'open_project': ToolPolicy(ToolRiskLevel.restricted),
        'add_clip': ToolPolicy(ToolRiskLevel.restricted),
        'trim_clip': ToolPolicy(ToolRiskLevel.restricted),
        'split_clip': ToolPolicy(ToolRiskLevel.restricted),
        'move_clip': ToolPolicy(ToolRiskLevel.restricted),
        'remove_clip': ToolPolicy(ToolRiskLevel.restricted),
        'add_effect': ToolPolicy(ToolRiskLevel.restricted),
        'remove_effect': ToolPolicy(ToolRiskLevel.restricted),
        'add_transition': ToolPolicy(ToolRiskLevel.restricted),
        'add_text': ToolPolicy(ToolRiskLevel.restricted),
        'extract_audio': ToolPolicy(ToolRiskLevel.restricted),
        'mix_audio': ToolPolicy(ToolRiskLevel.restricted),
        'normalize_audio': ToolPolicy(ToolRiskLevel.restricted),
        'render_video': ToolPolicy(ToolRiskLevel.restricted),
        'generate_subtitles': ToolPolicy(ToolRiskLevel.restricted),
        'create_temp_file': ToolPolicy(ToolRiskLevel.restricted),
        'write_temp_file': ToolPolicy(ToolRiskLevel.restricted),

        // HIGH risk: destruction, overwrite, external processes, escaping the
        // workspace. Every entry requires explicit, single-use approval.
        'delete_file': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'delete_original': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'delete_directory': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'remove_file': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'overwrite_file': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'overwrite_media': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'replace_media': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'export_project': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'write_outside_workspace': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'move_file': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),

        // External command execution. Aliases are intentionally redundant; the
        // manager also detects shell-shaped names dynamically.
        'run_command': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'execute_command': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'execute_external_command': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'run_shell': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'shell_exec': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'spawn_process': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
        'kill_process': ToolPolicy(
          ToolRiskLevel.dangerous,
          requiresApprovalAlways: true,
        ),
      };

  /// Tools that would let a model rewrite the rules mid-run.
  static const Set<String> builtinProtectedTools = <String>{
    'grant_permission',
    'set_permission_policy',
    'disable_permission',
    'disable_audit',
    'disable_sandbox',
    'write_permission',
    'approve_self',
    'bypass_approval',
  };

  // ---------------------------------------------------------------------------
  // Classification
  // ---------------------------------------------------------------------------

  ToolPolicy? policyFor(String toolName) => toolPolicies[toolName];

  bool isProtected(String toolName) => protectedTools.contains(toolName);

  bool isKnown(String toolName) => toolPolicies.containsKey(toolName);

  /// Declared risk is only honoured as a floor; unknown tools are `restricted`.
  ToolRiskLevel classify(String toolName, {ToolRiskLevel? declared}) {
    final table = toolPolicies[toolName]?.riskLevel;
    var effective = table ?? ToolRiskLevel.restricted;
    if (declared != null) {
      effective = _maxRisk(effective, declared);
    }
    if (isProtected(toolName)) return ToolRiskLevel.dangerous;
    return effective;
  }

  bool requiresApprovalAlways(String toolName) =>
      toolPolicies[toolName]?.requiresApprovalAlways ?? false;

  /// Pure decision function. Inputs that cannot be established are denied by
  /// [PermissionManager] before reaching here; this class fails closed too.
  PolicyDecision evaluate({
    required String toolName,
    required ToolRiskLevel riskLevel,
    required Map<String, Object?> arguments,
    required bool insideDefaultWorkspace,
    required bool hasValidApproval,
    required bool involvesDeclaredSpending,
    required bool toolKnown,
    bool shellExecution = false,
  }) {
    if (isProtected(toolName)) {
      return const PolicyDecision.deny(
        reasonCode: ShadowErrorCode.permPolicyDenied,
        reason: 'Tool may not modify the permission boundary',
      );
    }

    var effective = _maxRisk(
      riskLevel,
      classify(toolName, declared: riskLevel),
    );
    if (shellExecution) effective = ToolRiskLevel.dangerous;

    final needsApproval = switch (effective) {
      ToolRiskLevel.safe =>
        requiresApprovalAlways(toolName) && !hasValidApproval,
      ToolRiskLevel.dangerous => !hasValidApproval,
      ToolRiskLevel.restricted =>
        (!insideDefaultWorkspace ||
                involvesDeclaredSpending ||
                operationsInvolvingDeclaredSpending.contains(toolName) ||
                requiresApprovalAlways(toolName) ||
                (!toolKnown && requireApprovalForUnknownTools)) &&
            !hasValidApproval,
    };

    if (needsApproval) {
      return PolicyDecision.requireApproval(
        reasonCode: !toolKnown
            ? ShadowErrorCode.permPolicyUnknown
            : ShadowErrorCode.permApprovalRequired,
        reason: !toolKnown
            ? 'Unclassified tool requires explicit approval'
            : 'Operation requires explicit approval',
      );
    }

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

  /// AI data egress always requires separate explicit consent (not inferred
  /// from file approvals).
  bool requiresSeparateEgressConsent(EgressRequest request) =>
      request.resourceRefs.isNotEmpty;
}
