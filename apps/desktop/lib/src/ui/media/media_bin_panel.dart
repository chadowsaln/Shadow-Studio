import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import 'asset_card.dart';

/// Left panel Media Bin for importing and browsing project media files.
class MediaBinPanel extends StatefulWidget {
  final EditorController controller;

  const MediaBinPanel({super.key, required this.controller});

  @override
  State<MediaBinPanel> createState() => _MediaBinPanelState();
}

class _MediaBinPanelState extends State<MediaBinPanel> {
  final List<ImportedMediaAsset> _assets = [];
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadPreloadedFixtures();
  }

  /// Automatically discovers fixtures in tools/media-spike or loads default demo clips.
  Future<void> _loadPreloadedFixtures() async {
    final fixtureCandidates = [
      'tools/media-spike/out/fixtures/intro-4k.mp4',
      'tools/media-spike/out/fixtures/outro-hd.mp4',
      'tools/media-spike/out/fixtures/vo-take3.wav',
      '../../tools/media-spike/out/fixtures/intro-4k.mp4',
      '../../tools/media-spike/out/fixtures/outro-hd.mp4',
      '../../tools/media-spike/out/fixtures/vo-take3.wav',
    ];

    for (final path in fixtureCandidates) {
      if (File(path).existsSync()) {
        try {
          final asset = await widget.controller.mediaLibrary.importFile(
            path,
            generateProxy: true,
            generateWaveform: true,
          );
          if (!_assets.any((a) => a.blake3Hash == asset.blake3Hash)) {
            _assets.add(asset);
          }
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleImport() async {
    setState(() => _isImporting = true);
    try {
      // In desktop Linux/Windows, user can import sample files or create synthetic test assets
      final tempFile = File('${widget.controller.mediaLibrary.cacheDir.path}/sample_demo.mp4');
      if (!tempFile.existsSync()) {
        tempFile.writeAsStringSync('DEMO_SAMPLE_VIDEO_CONTENT_${DateTime.now().millisecondsSinceEpoch}');
      }
      final imported = await widget.controller.mediaLibrary.importFile(
        tempFile.path,
        generateProxy: false,
        generateWaveform: false,
      );
      if (!_assets.any((a) => a.blake3Hash == imported.blake3Hash)) {
        _assets.add(imported);
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);

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
                Icon(Icons.perm_media, size: 16, color: colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Media Bin',
                    style: ShadowTypography.title.copyWith(color: colors.textPrimary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _isImporting ? null : _handleImport,
                  icon: _isImporting
                      ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onAccent))
                      : const Icon(Icons.add, size: 14),
                  label: const Text('Import'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    textStyle: ShadowTypography.caption.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Asset List / Grid
          Expanded(
            child: _assets.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.video_library_outlined, size: 40, color: colors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'No media imported',
                            style: ShadowTypography.body.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Click Import to add video, audio, or images.',
                            style: ShadowTypography.caption.copyWith(color: colors.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _assets.length,
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      return AssetCard(
                        asset: asset,
                        onAddToTimeline: () => widget.controller.addAssetToTimeline(asset),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
