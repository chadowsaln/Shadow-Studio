import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

import '../../agent/agent_session_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import 'agent_settings_dialog.dart';

/// Right-dock AI assistant surface.
class AiPanel extends StatefulWidget {
  const AiPanel({super.key, required this.session});

  final AgentSessionController session;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final TextEditingController _requestController = TextEditingController();

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AgentSettingsDialog(session: widget.session),
    );
  }

  Future<void> _startTask() async {
    final text = _requestController.text.trim();
    if (text.isEmpty) return;
    try {
      await widget.session.run(text);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
          SnackBar(content: Text('AI task could not start: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final session = widget.session;
        return Container(
          color: colors.surface1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, session, colors),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (session.isLoading)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              size: 16,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Loading AI settings…',
                                textAlign: TextAlign.center,
                                style: ShadowTypography.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _configurationCard(context, session, colors),
                      const SizedBox(height: 12),
                      if (session.pendingApproval != null) ...[
                        _ApprovalCard(session: session),
                        const SizedBox(height: 12),
                      ],
                      _taskCard(context, session, colors),
                      if (session.plan.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _planSection(session, colors),
                      ],
                      if (session.summary != null ||
                          session.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        _resultCard(session, colors),
                      ],
                      if (session.activity.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _activitySection(session, colors),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    AgentSessionController session,
    ShadowColors colors,
  ) {
    final statusColor = _statusColor(session.status, colors);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface2,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: colors.accent),
          const SizedBox(width: 8),
          Text(
            'AI Agent',
            style: ShadowTypography.title.copyWith(
              color: colors.textPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _statusLabel(session.status),
              overflow: TextOverflow.ellipsis,
              style: ShadowTypography.caption.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'AI provider settings',
            iconSize: 18,
            color: colors.textSecondary,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  Widget _configurationCard(
    BuildContext context,
    AgentSessionController session,
    ShadowColors colors,
  ) {
    final settings = session.settings;
    final provider = settings?.provider;
    final configured = session.isConfigured;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                configured ? Icons.check_circle_outline : Icons.key_off,
                size: 16,
                color: configured ? colors.success : colors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  configured
                      ? '${provider?.label ?? 'AI'} · ${settings?.model ?? 'default model'}'
                      : 'AI provider not configured',
                  style: ShadowTypography.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openSettings,
                child: Text(configured ? 'Change' : 'Configure'),
              ),
            ],
          ),
          if (!configured) ...[
            const SizedBox(height: 4),
            Text(
              'Choose a provider and save an encrypted API key to enable the agent.',
              style: ShadowTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          if (session.notice != null) ...[
            const SizedBox(height: 6),
            Text(
              session.notice!,
              style: ShadowTypography.caption.copyWith(color: colors.warning),
            ),
          ],
          if (session.configurationError != null) ...[
            const SizedBox(height: 6),
            Text(
              session.configurationError!,
              style: ShadowTypography.caption.copyWith(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskCard(
    BuildContext context,
    AgentSessionController session,
    ShadowColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TASK',
            style: ShadowTypography.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _requestController,
            enabled: !session.isRunning,
            minLines: 3,
            maxLines: 6,
            style: ShadowTypography.body.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText:
                  'e.g. Trim the selected clip by one second and list the project media.',
              hintStyle: ShadowTypography.caption.copyWith(
                color: colors.textMuted,
              ),
              filled: true,
              fillColor: colors.surface1,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: session.egressConsentGranted,
                onChanged: session.isRunning
                    ? null
                    : (value) => session.setEgressConsent(value ?? false),
                activeColor: colors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Allow sending task text, project metadata and tool results to ${session.providerLabel}.',
                    style: ShadowTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  session.totalSteps > 0
                      ? '${session.completedSteps}/${session.totalSteps} steps · ${session.toolCallsUsed} tool calls'
                      : 'One task at a time; risky edits require approval.',
                  style: ShadowTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (session.isRunning)
                OutlinedButton.icon(
                  onPressed: session.cancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(color: colors.danger),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: session.canRun ? _startTask : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Run'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planSection(AgentSessionController session, ShadowColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PLAN',
            style: ShadowTypography.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < session.plan.length; i++)
            _PlanRow(
              index: i + 1,
              step: session.plan[i],
              colors: colors,
            ),
        ],
      ),
    );
  }

  Widget _resultCard(AgentSessionController session, ShadowColors colors) {
    final failed = session.status == AgentSessionStatus.failed;
    final cancelled = session.status == AgentSessionStatus.cancelled;
    final color = failed
        ? colors.danger
        : cancelled
            ? colors.warning
            : colors.success;
    final icon = failed
        ? Icons.error_outline
        : cancelled
            ? Icons.cancel_outlined
            : Icons.check_circle_outline;
    final message = failed
        ? '${session.errorCode ?? 'Error'}: ${session.errorMessage ?? 'AI task failed'}'
        : session.summary ?? session.errorMessage ?? 'Task finished.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ShadowTypography.body.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activitySection(
    AgentSessionController session,
    ShadowColors colors,
  ) {
    final entries = session.activity.reversed.take(20).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface0,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ACTIVITY',
            style: ShadowTypography.caption.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _activityIcon(entry.kind),
                    size: 13,
                    color: _activityColor(entry.kind, colors),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.message,
                      style: ShadowTypography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Color _statusColor(
    AgentSessionStatus status,
    ShadowColors colors,
  ) {
    return switch (status) {
      AgentSessionStatus.unconfigured => colors.textMuted,
      AgentSessionStatus.idle => colors.success,
      AgentSessionStatus.running => colors.accent,
      AgentSessionStatus.succeeded => colors.success,
      AgentSessionStatus.failed => colors.danger,
      AgentSessionStatus.cancelled => colors.warning,
    };
  }

  static String _statusLabel(AgentSessionStatus status) {
    return switch (status) {
      AgentSessionStatus.unconfigured => 'Not configured',
      AgentSessionStatus.idle => 'Ready',
      AgentSessionStatus.running => 'Running',
      AgentSessionStatus.succeeded => 'Completed',
      AgentSessionStatus.failed => 'Error',
      AgentSessionStatus.cancelled => 'Cancelled',
    };
  }

  static IconData _activityIcon(AgentActivityKind kind) {
    return switch (kind) {
      AgentActivityKind.info => Icons.info_outline,
      AgentActivityKind.tool => Icons.build_outlined,
      AgentActivityKind.approval => Icons.shield_outlined,
      AgentActivityKind.success => Icons.check,
      AgentActivityKind.error => Icons.error_outline,
    };
  }

  static Color _activityColor(AgentActivityKind kind, ShadowColors colors) {
    return switch (kind) {
      AgentActivityKind.info => colors.textMuted,
      AgentActivityKind.tool => colors.selection,
      AgentActivityKind.approval => colors.warning,
      AgentActivityKind.success => colors.success,
      AgentActivityKind.error => colors.danger,
    };
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.index,
    required this.step,
    required this.colors,
  });

  final int index;
  final PlanStep step;
  final ShadowColors colors;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.status) {
      PlanStepStatus.completed => (Icons.check_circle, colors.success),
      PlanStepStatus.inProgress => (Icons.play_circle_outline, colors.accent),
      PlanStepStatus.failed => (Icons.error, colors.danger),
      PlanStepStatus.skipped => (Icons.skip_next, colors.textMuted),
      PlanStepStatus.pending => (Icons.circle_outlined, colors.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$index. ${step.description}',
                  style: ShadowTypography.body.copyWith(
                    color: colors.textPrimary,
                    fontSize: 12,
                  ),
                ),
                if (step.error != null)
                  Text(
                    step.error!,
                    style: ShadowTypography.caption.copyWith(
                      color: colors.danger,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.session});

  final AgentSessionController session;

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final pending = session.pendingApproval!;
    var args = pending.arguments;
    var raw = const JsonEncoder.withIndent('  ').convert(args);
    if (raw.length > 1600) raw = '${raw.substring(0, 1600)}\n…';
    final expires = pending.expiresAt.toLocal();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Approval required: ${pending.toolName}',
                  style: ShadowTypography.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  pending.riskLevel.name.toUpperCase(),
                  style: ShadowTypography.caption.copyWith(
                    color: colors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.border),
            ),
            child: SingleChildScrollView(
              child: Text(
                raw,
                style: ShadowTypography.numeric.copyWith(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Expires ${expires.hour.toString().padLeft(2, '0')}:'
            '${expires.minute.toString().padLeft(2, '0')}',
            style: ShadowTypography.caption.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: session.rejectPending,
                style: TextButton.styleFrom(foregroundColor: colors.danger),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: session.approvePending,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.warning,
                  foregroundColor: colors.surface0,
                ),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
