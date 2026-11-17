import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../agent/agent_session_controller.dart';
import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../export/export_dialog.dart';
import '../media/media_bin_panel.dart';
import '../preview/preview_panel.dart';
import '../timeline/timeline_panel.dart';
import 'right_dock.dart';
import 'status_bar.dart';
import 'top_bar.dart';

/// Root App Shell implementing responsive multi-panel desktop layout and global keyboard shortcuts.
class AppShell extends StatefulWidget {
  final EditorController controller;
  final AgentSessionController agentSession;
  final VoidCallback onThemeToggle;
  final bool isDarkMode;

  const AppShell({
    super.key,
    required this.controller,
    required this.agentSession,
    required this.onThemeToggle,
    required this.isDarkMode,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final FocusNode _keyboardFocusNode = FocusNode();
  int _rightDockIndex = 0;

  void _setRightDock(int index) {
    if (_rightDockIndex == index) return;
    setState(() => _rightDockIndex = index);
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => ExportDialog(controller: widget.controller),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      widget.controller.togglePlayPause();
      return KeyEventResult.handled;
    }
    if (!isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      widget.controller.setToolMode(ToolMode.select);
      return KeyEventResult.handled;
    }
    if (!isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      widget.controller.setToolMode(ToolMode.razor);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.controller.deleteSelectedClip();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        widget.controller.redo();
      } else {
        widget.controller.undo();
      }
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      widget.controller.redo();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.controller.saveProject();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyE) {
      _showExportDialog();
      return KeyEventResult.handled;
    }
    if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyA) {
      _setRightDock(1);
      return KeyEventResult.handled;
    }
    if (isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.numpadAdd)) {
      widget.controller.zoomIn();
      return KeyEventResult.handled;
    }
    if (isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      widget.controller.zoomOut();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      widget.controller.seek(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      widget.controller.seek(widget.controller.totalDurationTicks);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.controller.stepFrame(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.controller.stepFrame(1);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, widget.agentSession]),
        builder: (context, _) {
          return Scaffold(
            backgroundColor: colors.surface0,
            body: Column(
              children: [
                // 1. Top Bar (48px)
                TopBar(
                  controller: widget.controller,
                  onExportPressed: _showExportDialog,
                  onThemeToggle: widget.onThemeToggle,
                  isDarkMode: widget.isDarkMode,
                  onAiPressed: () => _setRightDock(1),
                  isAiActive: _rightDockIndex == 1,
                ),

                // 2. Middle Workspace Layout
                Expanded(
                  child: Row(
                    children: [
                      // Left: Media Bin (260px)
                      SizedBox(
                        width: 260,
                        child: MediaBinPanel(controller: widget.controller),
                      ),
                      Container(width: 1, color: colors.border),

                      // Center: Preview (Top) + Timeline (Bottom)
                      Expanded(
                        child: Column(
                          children: [
                            // Preview Panel (55% height)
                            Expanded(
                              flex: 55,
                              child:
                                  PreviewPanel(controller: widget.controller),
                            ),
                            Container(height: 1, color: colors.border),

                            // Timeline Panel (45% height)
                            Expanded(
                              flex: 45,
                              child:
                                  TimelinePanel(controller: widget.controller),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: colors.border),

                      // Right: Inspector / AI dock (300px)
                      SizedBox(
                        width: 300,
                        child: RightDock(
                          controller: widget.controller,
                          session: widget.agentSession,
                          index: _rightDockIndex,
                          onTabChanged: _setRightDock,
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Status Bar (28px)
                StatusBar(
                  controller: widget.controller,
                  agentSession: widget.agentSession,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
