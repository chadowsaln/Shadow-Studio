import 'package:editing_core/editing_core.dart' as core;
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Interactive clip rectangle rendered within a track lane, featuring:
/// - Horizontal drag to move clip along the timeline with magnetic snapping
/// - Left & right trim handles for interactive in/out trimming
/// - Simulated audio waveform peaks for audio tracks
/// - Filmstrip perforation markers for video tracks
/// - Text layer preview for overlay tracks
class ClipWidget extends StatefulWidget {
  final core.Clip clip;
  final core.Track track;
  final EditorController controller;
  final double height;

  const ClipWidget({
    super.key,
    required this.clip,
    required this.track,
    required this.controller,
    this.height = 40.0,
  });

  @override
  State<ClipWidget> createState() => _ClipWidgetState();
}

class _ClipWidgetState extends State<ClipWidget> {
  double _dragDeltaX = 0.0;
  bool _isDragging = false;
  double _trimLeftDeltaX = 0.0;
  bool _isTrimmingLeft = false;
  double _trimRightDeltaX = 0.0;
  bool _isTrimmingRight = false;

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final pps = widget.controller.pixelsPerSecond;

    final startSeconds = widget.clip.timelineStartTicks / 1000000.0;
    final durationSeconds = widget.clip.durationTicks / 1000000.0;

    // Calculate effective visual left and width during drag or trim
    double visualLeft = (startSeconds * pps) + (_isDragging ? _dragDeltaX : (_isTrimmingLeft ? _trimLeftDeltaX : 0.0));
    double visualWidth = (durationSeconds * pps) +
        (_isTrimmingRight ? _trimRightDeltaX : (_isTrimmingLeft ? -_trimLeftDeltaX : 0.0));

    visualWidth = visualWidth.clamp(14.0, 50000.0);
    visualLeft = visualLeft.clamp(0.0, 50000.0);

    final isSelected = widget.controller.selectedClipId == widget.clip.id;
    final isVideo = widget.track.kind == core.TrackKind.video;
    final isAudio = widget.track.kind == core.TrackKind.audio;

    final bgColor = isVideo
        ? colors.trackVideo
        : isAudio
            ? colors.trackAudio
            : colors.trackOverlay;

    return Positioned(
      left: visualLeft,
      top: 4,
      width: visualWidth,
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          if (widget.controller.toolMode == ToolMode.razor) {
            // Razor tool clicked: compute timeline tick from local tap X
            final localX = details.localPosition.dx;
            final tapSeconds = startSeconds + (localX / pps);
            final tapTicks = (tapSeconds * 1000000).round();
            widget.controller.seek(tapTicks);
            widget.controller.splitClipAtPlayhead(widget.track.id, widget.clip.id);
          } else {
            // Select tool: select clip
            widget.controller.selectClip(widget.clip.id, trackId: widget.track.id);
          }
        },
        onHorizontalDragStart: (details) {
          if (widget.controller.toolMode == ToolMode.select) {
            setState(() {
              _isDragging = true;
              _dragDeltaX = 0.0;
            });
            widget.controller.selectClip(widget.clip.id, trackId: widget.track.id);
          }
        },
        onHorizontalDragUpdate: (details) {
          if (_isDragging) {
            setState(() {
              _dragDeltaX += details.delta.dx;
            });
          }
        },
        onHorizontalDragEnd: (details) {
          if (_isDragging) {
            final shiftSeconds = _dragDeltaX / pps;
            final shiftTicks = (shiftSeconds * 1000000).round();
            final targetTicks = (widget.clip.timelineStartTicks + shiftTicks).clamp(0, 1000000000);
            final snappedTicks = widget.controller.snapTick(targetTicks, ignoreClipId: widget.clip.id);

            setState(() {
              _isDragging = false;
              _dragDeltaX = 0.0;
            });

            if (snappedTicks != widget.clip.timelineStartTicks) {
              widget.controller.moveClip(
                trackId: widget.track.id,
                clipId: widget.clip.id,
                newTimelineStartTicks: snappedTicks,
              );
            }
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colors.selection : colors.border.withOpacity(0.8),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colors.selection.withOpacity(0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 1. Audio Waveform Background for Audio Clips
              if (isAudio)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AudioWaveformPainter(
                      color: Colors.white.withOpacity(0.22),
                      seed: widget.clip.id.hashCode,
                    ),
                  ),
                ),

              // 2. Filmstrip Sprocket Holes for Video Clips
              if (isVideo)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FilmstripPainter(
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                ),

              // 3. Clip Content (Icon, Label, Timecode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      isVideo
                          ? Icons.videocam
                          : isAudio
                              ? Icons.graphic_eq
                              : Icons.title,
                      size: 13,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.clip.label ?? widget.clip.id,
                            style: ShadowTypography.body.copyWith(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            TimecodeFormatter.format(widget.clip.durationTicks),
                            style: ShadowTypography.numeric.copyWith(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Left Trim Handle
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    setState(() {
                      _isTrimmingLeft = true;
                      _trimLeftDeltaX = 0.0;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _trimLeftDeltaX += details.delta.dx;
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_isTrimmingLeft) {
                      final deltaTicks = ((_trimLeftDeltaX / pps) * 1000000).round();
                      final newStart = (widget.clip.timelineStartTicks + deltaTicks).clamp(0, 1000000000);
                      final newDur = widget.clip.durationTicks - deltaTicks;
                      final newSourceIn = widget.clip.sourceInTicks + deltaTicks;

                      setState(() {
                        _isTrimmingLeft = false;
                        _trimLeftDeltaX = 0.0;
                      });

                      if (newDur > 100000 && newSourceIn >= 0) {
                        widget.controller.trimClip(
                          trackId: widget.track.id,
                          clipId: widget.clip.id,
                          newTimelineStartTicks: newStart,
                          newDurationTicks: newDur,
                          newSourceInTicks: newSourceIn,
                        );
                      }
                    }
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? colors.selection.withOpacity(0.6) : Colors.black.withOpacity(0.2),
                        border: Border(
                          right: BorderSide(
                            color: isSelected ? colors.selection : Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 5. Right Trim Handle
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    setState(() {
                      _isTrimmingRight = true;
                      _trimRightDeltaX = 0.0;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _trimRightDeltaX += details.delta.dx;
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_isTrimmingRight) {
                      final deltaTicks = ((_trimRightDeltaX / pps) * 1000000).round();
                      final newDur = widget.clip.durationTicks + deltaTicks;

                      setState(() {
                        _isTrimmingRight = false;
                        _trimRightDeltaX = 0.0;
                      });

                      if (newDur > 100000) {
                        widget.controller.trimClip(
                          trackId: widget.track.id,
                          clipId: widget.clip.id,
                          newTimelineStartTicks: widget.clip.timelineStartTicks,
                          newDurationTicks: newDur,
                          newSourceInTicks: widget.clip.sourceInTicks,
                        );
                      }
                    }
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? colors.selection.withOpacity(0.6) : Colors.black.withOpacity(0.2),
                        border: Border(
                          left: BorderSide(
                            color: isSelected ? colors.selection : Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for rendering authentic audio waveform peak bars.
class _AudioWaveformPainter extends CustomPainter {
  final Color color;
  final int seed;

  _AudioWaveformPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    const barSpacing = 4.0;
    final barCount = (size.width / barSpacing).floor();

    for (int i = 0; i < barCount; i++) {
      final x = i * barSpacing + 2.0;
      // Deterministic pseudorandom waveform peak based on clip seed & bar index
      final phase = (seed + i * 37) % 100;
      final amplitudeFraction = (0.2 + (phase / 100.0) * 0.75).clamp(0.1, 0.95);
      final barHalfHeight = (centerY * 0.8) * amplitudeFraction;

      canvas.drawLine(
        Offset(x, centerY - barHalfHeight),
        Offset(x, centerY + barHalfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.seed != seed;
  }
}

/// Custom painter for rendering video filmstrip sprocket perforations.
class _FilmstripPainter extends CustomPainter {
  final Color color;

  _FilmstripPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const sprocketWidth = 4.0;
    const sprocketHeight = 2.5;
    const step = 14.0;

    for (double x = 4.0; x < size.width - 6.0; x += step) {
      // Top perforation
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 1.5, sprocketWidth, sprocketHeight),
          const Radius.circular(1),
        ),
        paint,
      );
      // Bottom perforation
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - 4.0, sprocketWidth, sprocketHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FilmstripPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
