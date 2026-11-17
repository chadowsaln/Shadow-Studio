import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import 'preview_canvas.dart';
import 'transport_controls.dart';

/// Center-top Preview panel combining the 16:9 canvas and transport bar.
class PreviewPanel extends StatelessWidget {
  final EditorController controller;

  const PreviewPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Container(
      color: colors.surface0,
      child: Column(
        children: [
          Expanded(child: PreviewCanvas(controller: controller)),
          TransportControls(controller: controller),
        ],
      ),
    );
  }
}
