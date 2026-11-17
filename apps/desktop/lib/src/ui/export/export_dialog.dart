import 'dart:async';

import 'package:editing_core/editing_core.dart';
import 'package:flutter/material.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Export dialog conforming to MVP UI/UX Design Spec S3.
class ExportDialog extends StatefulWidget {
  final EditorController controller;

  const ExportDialog({super.key, required this.controller});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  String _selectedPreset = 'youtube_1080p';
  bool _isRendering = false;
  double _renderProgress = 0.0;
  Timer? _renderTimer;
  String? _errorMessage;
  bool _isCompleted = false;

  final Map<String, String> _presets = {
    'youtube_1080p': 'YouTube 1080p (H.264 · 1920x1080 · 30fps · 12 Mbps)',
    'master_4k': '4K Master (H.265 / ProRes · 3840x2160 · 30fps)',
    'web_720p': 'Web 720p (H.264 · 1280x720 · 30fps · 4 Mbps)',
  };

  void _startExport() {
    setState(() {
      _isRendering = true;
      _renderProgress = 0.0;
      _errorMessage = null;
      _isCompleted = false;
    });

    try {
      // 1. Pre-flight validation via resolveGraph
      final totalTicks = widget.controller.totalDurationTicks;
      widget.controller.editingService.resolveGraph(
        revision: widget.controller.revision,
        range: RangeTicks(startTicks: 0, durationTicks: totalTicks),
      );

      // 2. Simulate render progress
      _renderTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        setState(() {
          _renderProgress += 0.05;
          if (_renderProgress >= 1.0) {
            _renderProgress = 1.0;
            _isRendering = false;
            _isCompleted = true;
            timer.cancel();
          }
        });
      });
    } catch (e) {
      setState(() {
        _isRendering = false;
        _errorMessage = 'Pre-flight check failed: $e';
      });
    }
  }

  void _cancelExport() {
    _renderTimer?.cancel();
    setState(() {
      _isRendering = false;
      _renderProgress = 0.0;
    });
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final totalTicks = widget.controller.totalDurationTicks;

    return Dialog(
      backgroundColor: colors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.video_settings, color: colors.accent, size: 24),
                  const SizedBox(width: 12),
                  Text('Export Sequence', style: ShadowTypography.display.copyWith(color: colors.textPrimary, fontSize: 18)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: colors.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface0,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Duration', style: ShadowTypography.caption.copyWith(color: colors.textSecondary)),
                        Text(TimecodeFormatter.format(totalTicks), style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sequence Profile', style: ShadowTypography.caption.copyWith(color: colors.textSecondary)),
                        Text('1920x1080 @ 30fps', style: ShadowTypography.numeric.copyWith(color: colors.textPrimary, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Preset Selector
              Text('EXPORT PRESET', style: ShadowTypography.caption.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colors.surface0,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPreset,
                    isExpanded: true,
                    dropdownColor: colors.surface1,
                    items: _presets.entries.map((e) {
                      return DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value, style: ShadowTypography.body.copyWith(color: colors.textPrimary, fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: _isRendering ? null : (val) {
                      if (val != null) setState(() => _selectedPreset = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Progress Bar if rendering
              if (_isRendering || _isCompleted) ...[
                Row(
                  children: [
                    Text(
                      _isCompleted ? 'Export Succeeded ✓' : 'Rendering Plan (${(_renderProgress * 100).round()}%)',
                      style: ShadowTypography.body.copyWith(
                        color: _isCompleted ? colors.success : colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_isRendering)
                      TextButton(
                        onPressed: _cancelExport,
                        child: Text('Cancel', style: TextStyle(color: colors.danger)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _renderProgress,
                  backgroundColor: colors.surface2,
                  valueColor: AlwaysStoppedAnimation(colors.accent),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 20),
              ],

              // Error banner if any
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.danger.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.danger),
                  ),
                  child: Text(_errorMessage!, style: ShadowTypography.caption.copyWith(color: colors.danger)),
                ),
                const SizedBox(height: 16),
              ],

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isRendering ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      side: BorderSide(color: colors.border),
                    ),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isRendering ? null : _startExport,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                    ),
                    child: Text(_isCompleted ? 'Render Again' : 'Start Render'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
