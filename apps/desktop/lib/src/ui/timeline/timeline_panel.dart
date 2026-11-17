import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../common/app_drop_target.dart';
import 'playhead_widget.dart';
import 'timeline_ruler.dart';
import 'timeline_toolbar.dart';
import 'track_header.dart';
import 'track_lane.dart';

/// Full interactive Timeline surface conforming to MVP UI/UX Design Spec §5.
///
/// Implements RTL app shell while enforcing LTR timeline time axis (Spec §2.4),
/// with external file drop, dynamic track heights, and drag-and-drop lane targeting.
class TimelinePanel extends StatefulWidget {
  final EditorController controller;

  const TimelinePanel({super.key, required this.controller});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  bool _isTimelineDragOver = false;

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _handleTimelineDrop(DropDetails details) async {
    final paths = <String>[];
    for (final item in details.items) {
      if (item is DropFileItem && item.localPath != null) {
        paths.add(item.localPath!);
      }
    }
    if (paths.isEmpty) return;

    final imported = await widget.controller.importFiles(paths);
    for (final asset in imported) {
      await widget.controller.addAssetToTimeline(asset);
    }
    setState(() => _isTimelineDragOver = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final tracks = widget.controller.document.tracks;
    final pps = widget.controller.pixelsPerSecond;
    final trackHeight = widget.controller.trackHeight;

    return AppDropTarget(
      onEnter: (_) => setState(() => _isTimelineDragOver = true),
      onLeave: () => setState(() => _isTimelineDragOver = false),
      onDrop: _handleTimelineDrop,
      child: Container(
        color: colors.surface0,
        child: Column(
          children: [
            // Timeline Toolbar
            TimelineToolbar(
              controller: widget.controller,
              onFitPressed: () {
                final viewportWidth = _horizontalScrollController.hasClients
                    ? _horizontalScrollController.position.viewportDimension
                    : 800.0;
                widget.controller.fitToTimeline(viewportWidth);
              },
            ),

            // Main Timeline Surface: Track Headers on left, Scrollable Canvas on right
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = (widget.controller.totalDurationTicks / 1000000.0 * pps) + 400.0;
                  final totalWidth = contentWidth > constraints.maxWidth - 140
                      ? contentWidth
                      : constraints.maxWidth - 140;

                  return Directionality(
                    // Enforce LTR timeline time axis per Spec §2.4
                    textDirection: TextDirection.ltr,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            // Fixed Track Headers Column (140px)
                            SizedBox(
                              width: 140,
                              child: Column(
                                children: [
                                  // Corner box above track headers (matches ruler height 24px)
                                  Container(
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: colors.surface2,
                                      border: Border(
                                        bottom: BorderSide(color: colors.border),
                                        right: BorderSide(color: colors.border),
                                      ),
                                    ),
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      'TRACKS (${tracks.length})',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),

                                  // Track Header Items
                                  Expanded(
                                    child: ListView.builder(
                                      controller: _verticalScrollController,
                                      itemCount: tracks.length,
                                      itemBuilder: (context, index) {
                                        return TrackHeader(
                                          track: tracks[index],
                                          controller: widget.controller,
                                          height: trackHeight,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Scrollable Tracks and Playhead Canvas
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: totalWidth,
                                  child: Stack(
                                    children: [
                                      Column(
                                        children: [
                                          // Timecode Ruler
                                          TimelineRuler(
                                            controller: widget.controller,
                                            totalWidth: totalWidth,
                                          ),

                                          // Track Lanes
                                          Expanded(
                                            child: ListView.builder(
                                              physics: const NeverScrollableScrollPhysics(),
                                              itemCount: tracks.length,
                                              itemBuilder: (context, index) {
                                                return TrackLane(
                                                  track: tracks[index],
                                                  controller: widget.controller,
                                                  totalWidth: totalWidth,
                                                  height: trackHeight,
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Playhead overlay spanning ruler and lanes
                                      PlayheadWidget(
                                        controller: widget.controller,
                                        totalHeight: constraints.maxHeight,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Drop Overlay when dragging files over the entire timeline
                        if (_isTimelineDragOver)
                          Positioned.fill(
                            child: Container(
                              color: colors.surface0.withOpacity(0.8),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: colors.surface2,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colors.accent, width: 2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.file_download, color: colors.accent, size: 28),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Drop files to add directly to timeline',
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
