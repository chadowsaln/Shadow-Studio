import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';

import '../../controller/editor_controller.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';
import '../../utils/timecode_formatter.dart';
import '../common/app_drop_target.dart';
import 'asset_card.dart';

enum AssetFilter {
  all,
  video,
  audio,
  image,
}

enum MediaBinViewMode {
  grid,
  list,
}

/// Left panel Media Bin with external file drag-and-drop, internal dragging to timeline,
/// filtering, and search capabilities.
class MediaBinPanel extends StatefulWidget {
  final EditorController controller;

  const MediaBinPanel({super.key, required this.controller});

  @override
  State<MediaBinPanel> createState() => _MediaBinPanelState();
}

class _MediaBinPanelState extends State<MediaBinPanel> {
  final List<ImportedMediaAsset> _assets = [];
  bool _isImporting = false;
  bool _isDragOver = false;
  AssetFilter _filter = AssetFilter.all;
  MediaBinViewMode _viewMode = MediaBinViewMode.grid;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPreloadedFixtures();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _handleFileDrop(DropDetails details) async {
    final paths = <String>[];
    for (final item in details.items) {
      if (item is DropFileItem && item.localPath != null) {
        paths.add(item.localPath!);
      }
    }
    if (paths.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final imported = await widget.controller.importFiles(paths);
      for (final asset in imported) {
        if (!_assets.any((a) => a.blake3Hash == asset.blake3Hash)) {
          _assets.add(asset);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _isDragOver = false;
        });
      }
    }
  }

  List<ImportedMediaAsset> get _filteredAssets {
    return _assets.where((asset) {
      // Filter by Kind
      if (_filter == AssetFilter.video && asset.kind != MediaKind.video) return false;
      if (_filter == AssetFilter.audio && asset.kind != MediaKind.audio) return false;
      if (_filter == AssetFilter.image && asset.kind != MediaKind.image) return false;

      // Filter by Search Query
      if (_searchQuery.isNotEmpty) {
        final fileName = asset.sourcePath.split(Platform.pathSeparator).last.toLowerCase();
        if (!fileName.contains(_searchQuery.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final displayedAssets = _filteredAssets;

    return AppDropTarget(
      onEnter: (_) => setState(() => _isDragOver = true),
      onLeave: () => setState(() => _isDragOver = false),
      onDrop: _handleFileDrop,
      child: Container(
        color: colors.surface1,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Bar
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    border: Border(bottom: BorderSide(color: colors.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.perm_media, size: 16, color: colors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Media Bin (${displayedAssets.length}/${_assets.length})',
                          style: ShadowTypography.title.copyWith(color: colors.textPrimary, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _viewMode == MediaBinViewMode.grid ? Icons.view_list : Icons.grid_view,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                        tooltip: _viewMode == MediaBinViewMode.grid ? 'Switch to List' : 'Switch to Grid',
                        onPressed: () {
                          setState(() {
                            _viewMode = _viewMode == MediaBinViewMode.grid
                                ? MediaBinViewMode.list
                                : MediaBinViewMode.grid;
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: _isImporting ? null : _handleImport,
                        icon: _isImporting
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: colors.onAccent),
                              )
                            : const Icon(Icons.add, size: 14),
                        label: const Text('Import'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.onAccent,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          textStyle: ShadowTypography.caption.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search & Filter Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.surface1,
                    border: Border(bottom: BorderSide(color: colors.border.withOpacity(0.5))),
                  ),
                  child: Column(
                    children: [
                      // Search Bar
                      SizedBox(
                        height: 28,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: ShadowTypography.caption.copyWith(color: colors.textPrimary, fontSize: 11),
                          decoration: InputDecoration(
                            hintText: 'Search media...',
                            hintStyle: ShadowTypography.caption.copyWith(color: colors.textMuted, fontSize: 11),
                            prefixIcon: Icon(Icons.search, size: 14, color: colors.textMuted),
                            prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 12),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colors.surface0,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(color: colors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide: BorderSide(color: colors.border.withOpacity(0.5)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', AssetFilter.all, colors),
                            const SizedBox(width: 4),
                            _buildFilterChip('Video', AssetFilter.video, colors),
                            const SizedBox(width: 4),
                            _buildFilterChip('Audio', AssetFilter.audio, colors),
                            const SizedBox(width: 4),
                            _buildFilterChip('Image', AssetFilter.image, colors),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Asset List / Grid
                Expanded(
                  child: displayedAssets.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.video_library_outlined, size: 40, color: colors.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  _assets.isEmpty ? 'No media imported' : 'No matching media',
                                  style: ShadowTypography.body.copyWith(
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _assets.isEmpty
                                      ? 'Drag & drop media files here or click Import.'
                                      : 'Try clearing your search or filter.',
                                  style: ShadowTypography.caption.copyWith(color: colors.textMuted),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : _viewMode == MediaBinViewMode.grid
                          ? GridView.builder(
                              padding: const EdgeInsets.all(10),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 1.15,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: displayedAssets.length,
                              itemBuilder: (context, index) {
                                final asset = displayedAssets[index];
                                return AssetCard(
                                  asset: asset,
                                  onAddToTimeline: () => widget.controller.addAssetToTimeline(asset),
                                );
                              },
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: displayedAssets.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final asset = displayedAssets[index];
                                final fileName = asset.sourcePath.split(Platform.pathSeparator).last;
                                return Draggable<ImportedMediaAsset>(
                                  data: asset,
                                  dragAnchorStrategy: pointerDragAnchorStrategy,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: colors.surface2,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: colors.accent, width: 2),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
                                        ],
                                      ),
                                      child: Text(
                                        fileName,
                                        style: ShadowTypography.body.copyWith(color: Colors.white, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: colors.surface2,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: colors.border.withOpacity(0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          asset.kind == MediaKind.video
                                              ? Icons.videocam
                                              : asset.kind == MediaKind.audio
                                                  ? Icons.audiotrack
                                                  : Icons.image,
                                          size: 16,
                                          color: colors.accent,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            fileName,
                                            style: ShadowTypography.caption.copyWith(color: colors.textPrimary),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          TimecodeFormatter.format(asset.durationTicks),
                                          style: ShadowTypography.numeric.copyWith(color: colors.textSecondary, fontSize: 10),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 16),
                                          color: colors.accent,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => widget.controller.addAssetToTimeline(asset),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),

            // Drop Target Overlay on drag hover
            if (_isDragOver)
              Positioned.fill(
                child: Container(
                  color: colors.surface0.withOpacity(0.85),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.accent, width: 2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_download, size: 48, color: colors.accent),
                          const SizedBox(height: 12),
                          Text(
                            'Drop Media Files Here',
                            style: ShadowTypography.title.copyWith(color: colors.textPrimary, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Supports MP4, MOV, WAV, MP3, PNG, JPG',
                            style: ShadowTypography.caption.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, AssetFilter filter, ShadowColors colors) {
    final isSelected = _filter == filter;
    return InkWell(
      onTap: () => setState(() => _filter = filter),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? colors.accent.withOpacity(0.2) : colors.surface0,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? colors.accent : colors.border.withOpacity(0.5),
          ),
        ),
        child: Text(
          label,
          style: ShadowTypography.caption.copyWith(
            color: isSelected ? colors.accent : colors.textSecondary,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
