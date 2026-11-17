import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';

import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';

/// Asset card item in the Media Bin.
class AssetCard extends StatelessWidget {
  final ImportedMediaAsset asset;
  final VoidCallback onAddToTimeline;

  const AssetCard({
    super.key,
    required this.asset,
    required this.onAddToTimeline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final fileName = asset.sourcePath.split(Platform.pathSeparator).last;
    final hasThumb = asset.thumbnailPath != null && File(asset.thumbnailPath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thumbnail / Preview Banner
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasThumb)
                  Image.file(File(asset.thumbnailPath!), fit: BoxFit.cover)
                else
                  Container(
                    color: colors.surface0,
                    child: Center(
                      child: Icon(
                        asset.kind == MediaKind.video
                            ? Icons.videocam
                            : asset.kind == MediaKind.audio
                                ? Icons.audiotrack
                                : Icons.image,
                        size: 32,
                        color: colors.textMuted,
                      ),
                    ),
                  ),

                // Duration Tag
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      TimecodeFormatter.format(asset.durationTicks),
                      style: ShadowTypography.numeric.copyWith(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),

                // Deduplicated indicator
                if (asset.isDeduplicated)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.accent.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'Dedupe',
                        style: ShadowTypography.caption.copyWith(color: colors.onAccent, fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Metadata & Actions
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        style: ShadowTypography.body.copyWith(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'b3:${asset.blake3Hash.substring(0, 8)}',
                        style: ShadowTypography.numeric.copyWith(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, size: 20),
                  color: colors.accent,
                  tooltip: 'Add to timeline',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onAddToTimeline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
