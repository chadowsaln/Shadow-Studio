import 'package:editing_core/editing_core.dart' hide TextAlign;
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';
import 'text_inspector.dart';
import 'transform_inspector.dart';

/// Right-hand Inspector panel displaying contextual parameters for selected clips or sequence.
class InspectorPanel extends StatelessWidget {
  final EditorController controller;

  const InspectorPanel({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    // Find selected clip if any
    Clip? selectedClip;
    Track? selectedTrack;
    if (controller.selectedClipId != null &&
        controller.selectedTrackId != null) {
      for (final track in controller.document.tracks) {
        if (track.id == controller.selectedTrackId) {
          selectedTrack = track;
          for (final clip in track.clips) {
            if (clip.id == controller.selectedClipId) {
              selectedClip = clip;
              break;
            }
          }
          break;
        }
      }
    }

    return Container(
      color: colors.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surface2,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  selectedClip != null ? 'Clip Inspector' : 'Project Settings',
                  style: ShadowTypography.title
                      .copyWith(color: colors.textPrimary, fontSize: 13),
                ),
              ],
            ),
          ),

          // Scrollable Properties Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (selectedClip != null) ...[
                  // Clip Timing Details
                  const _SectionHeader(title: 'TIMING & BOUNDS'),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Timeline Start',
                    timecode: TimecodeFormatter.format(
                        selectedClip.timelineStartTicks),
                    rawTicks: '${selectedClip.timelineStartTicks}t',
                  ),
                  _DetailRow(
                    label: 'Duration',
                    timecode:
                        TimecodeFormatter.format(selectedClip.durationTicks),
                    rawTicks: '${selectedClip.durationTicks}t',
                  ),
                  _DetailRow(
                    label: 'Source In',
                    timecode:
                        TimecodeFormatter.format(selectedClip.sourceInTicks),
                    rawTicks: '${selectedClip.sourceInTicks}t',
                  ),
                  const SizedBox(height: 16),
                  Divider(color: colors.border, height: 1),
                  const SizedBox(height: 16),

                  // Transform Controls
                  const TransformInspector(),
                  const SizedBox(height: 16),
                  Divider(color: colors.border, height: 1),
                  const SizedBox(height: 16),

                  // Text Layer Inspector if Overlay
                  if (selectedTrack?.kind == TrackKind.overlay) ...[
                    const TextInspector(),
                    const SizedBox(height: 16),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: 16),
                  ],

                  // Effects Section
                  const _SectionHeader(title: 'EFFECTS'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surface0,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.blur_on, size: 18, color: colors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gaussian Blur',
                            style: ShadowTypography.body.copyWith(
                                color: colors.textPrimary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Transform.scale(
                          scale: 0.75,
                          child: Switch(
                            value: true,
                            activeColor: colors.accent,
                            onChanged: (_) {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Project Sequence Settings
                  const _SectionHeader(title: 'SEQUENCE PROFILE'),
                  const SizedBox(height: 12),
                  _DetailRow(
                      label: 'Sequence Name',
                      timecode: controller.document.name),
                  _DetailRow(
                    label: 'Resolution',
                    timecode:
                        '${controller.document.profile.width} x ${controller.document.profile.height}',
                  ),
                  _DetailRow(
                    label: 'Timebase',
                    timecode:
                        '${controller.document.timebase.fpsNum} / ${controller.document.timebase.fpsDen} fps',
                  ),
                  _DetailRow(
                    label: 'Audio Profile',
                    timecode:
                        '${controller.document.timebase.sampleRate} Hz · ${controller.document.timebase.channels} ch',
                  ),
                  _DetailRow(
                    label: 'Revision',
                    timecode: 'Rev ${controller.revision}',
                  ),
                  _DetailRow(
                    label: 'Total Tracks',
                    timecode: '${controller.document.tracks.length} tracks',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    return Text(
      title,
      style: ShadowTypography.caption.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String timecode;
  final String? rawTicks;

  const _DetailRow({
    required this.label,
    required this.timecode,
    this.rawTicks,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: ShadowTypography.body
                  .copyWith(color: colors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    timecode,
                    style: ShadowTypography.numeric
                        .copyWith(color: colors.textPrimary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                if (rawTicks != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '($rawTicks)',
                    style: ShadowTypography.numeric
                        .copyWith(color: colors.textMuted, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
