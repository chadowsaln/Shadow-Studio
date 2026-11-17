import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import 'clip_widget.dart';

/// Horizontal track lane rendering clips along the time axis.
class TrackLane extends StatelessWidget {
  final core.Track track;
  final EditorController controller;
  final double totalWidth;
  final double height;

  const TrackLane({
    super.key,
    required this.track,
    required this.controller,
    required this.totalWidth,
    this.height = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Container(
      height: height,
      width: totalWidth,
      decoration: BoxDecoration(
        color: colors.surface0,
        border: Border(bottom: BorderSide(color: colors.border.withOpacity(0.5))),
      ),
      child: Stack(
        children: [
          // Render each clip on this track
          for (final clip in track.clips)
            ClipWidget(
              clip: clip,
              track: track,
              controller: controller,
              height: height - 8,
            ),
        ],
      ),
    );
  }
}
