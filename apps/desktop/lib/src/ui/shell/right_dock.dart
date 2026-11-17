import 'package:flutter/material.dart';

import '../../agent/agent_session_controller.dart';
import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../ai/ai_panel.dart';
import '../inspector/inspector_panel.dart';

/// Right-side dock hosting the Inspector and AI Agent surfaces.
class RightDock extends StatelessWidget {
  const RightDock({
    super.key,
    required this.controller,
    required this.session,
    required this.index,
    required this.onTabChanged,
  });

  final EditorController controller;
  final AgentSessionController session;
  final int index;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    return Container(
      color: colors.surface1,
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: colors.surface2,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DockTab(
                    label: 'Inspector',
                    icon: Icons.tune,
                    selected: index == 0,
                    onTap: () => onTabChanged(0),
                  ),
                ),
                Container(width: 1, color: colors.border),
                Expanded(
                  child: _DockTab(
                    label: 'AI',
                    icon: Icons.auto_awesome,
                    selected: index == 1,
                    onTap: () => onTabChanged(1),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                InspectorPanel(controller: controller),
                AiPanel(session: session),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: ShadowTypography.caption.copyWith(
                color: selected ? colors.textPrimary : colors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
