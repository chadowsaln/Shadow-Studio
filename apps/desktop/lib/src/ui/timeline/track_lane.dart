import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';
import 'clip_widget.dart';

/// Horizontal track lane rendering clips along the time axis and supporting
/// drag-and-drop ingestion of assets from the Media Bin.
class TrackLane extends StatefulWidget {
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
  State<TrackLane> createState() => _TrackLaneState();
}

class _TrackLaneState extends State<TrackLane> {
  Offset? _hoverOffset;
  ImportedMediaAsset? _hoverAsset;

  bool _isCompatible(ImportedMediaAsset asset) {
    if (widget.track.kind == core.TrackKind.video) {
      return asset.kind == MediaKind.video || asset.kind == MediaKind.image;
    }
    if (widget.track.kind == core.TrackKind.audio) {
      return asset.kind == MediaKind.audio;
    }
    return true; // Overlay supports any asset or text
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final pps = widget.controller.pixelsPerSecond;

    return DragTarget<ImportedMediaAsset>(
      onWillAcceptWithDetails: (details) {
        return _isCompatible(details.data);
      },
      onMove: (details) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final local = renderBox.globalToLocal(details.offset);
          setState(() {
            _hoverOffset = local;
            _hoverAsset = details.data;
          });
        }
      },
      onLeave: (_) {
        setState(() {
          _hoverOffset = null;
          _hoverAsset = null;
        });
      },
      onAcceptWithDetails: (details) {
        final renderBox = context.findRenderObject() as RenderBox?;
        final local = renderBox?.globalToLocal(details.offset) ?? Offset.zero;
        final seconds = (local.dx / pps).clamp(0.0, 36000.0);
        int targetTicks = (seconds * 1000000).round();

        // Apply magnetic snapping
        targetTicks = widget.controller.snapTick(targetTicks);

        widget.controller.insertClipAt(
          imported: details.data,
          trackId: widget.track.id,
          timelineStartTicks: targetTicks,
        );

        setState(() {
          _hoverOffset = null;
          _hoverAsset = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty && _hoverOffset != null && _hoverAsset != null;

        // Calculate ghost drop preview position and width
        double ghostLeft = 0;
        double ghostWidth = 60;
        int ghostTicks = 0;
        if (isHovering) {
          final seconds = (_hoverOffset!.dx / pps).clamp(0.0, 36000.0);
          ghostTicks = widget.controller.snapTick((seconds * 1000000).round());
          ghostLeft = (ghostTicks / 1000000.0) * pps;
          ghostWidth = ((_hoverAsset!.durationTicks / 1000000.0) * pps).clamp(24.0, 50000.0);
        }

        return Container(
          height: widget.height,
          width: widget.totalWidth,
          decoration: BoxDecoration(
            color: isHovering ? colors.accent.withOpacity(0.08) : colors.surface0,
            border: Border(
              bottom: BorderSide(
                color: isHovering ? colors.accent : colors.border.withOpacity(0.4),
                width: isHovering ? 1.5 : 1.0,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Subtle time grid lines (every second)
              CustomPaint(
                size: Size(widget.totalWidth, widget.height),
                painter: _TrackGridPainter(
                  pixelsPerSecond: pps,
                  color: colors.border.withOpacity(0.15),
                ),
              ),

              // Render each clip on this track
              for (final clip in widget.track.clips)
                ClipWidget(
                  clip: clip,
                  track: widget.track,
                  controller: widget.controller,
                  height: widget.height - 8,
                ),

              // Ghost Drop Preview Indicator
              if (isHovering)
                Positioned(
                  left: ghostLeft,
                  top: 3,
                  width: ghostWidth,
                  height: widget.height - 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.accent.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.accent, width: 2),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          TimecodeFormatter.format(ghostTicks),
                          style: ShadowTypography.numeric.copyWith(
                            color: colors.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackGridPainter extends CustomPainter {
  final double pixelsPerSecond;
  final Color color;

  _TrackGridPainter({required this.pixelsPerSecond, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelsPerSecond < 10) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    final step = pixelsPerSecond >= 30 ? pixelsPerSecond : pixelsPerSecond * 5;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackGridPainter oldDelegate) {
    return oldDelegate.pixelsPerSecond != pixelsPerSecond || oldDelegate.color != color;
  }
}
