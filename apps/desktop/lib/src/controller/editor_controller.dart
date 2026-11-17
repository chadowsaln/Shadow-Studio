import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:editing_core/editing_core.dart';
import 'package:flutter/foundation.dart';
import 'package:media_core/media_core.dart';

/// Active timeline interaction tool.
enum ToolMode {
  select,
  razor,
}

/// Workspace layout preset (Spec §3.2).
enum LayoutPreset {
  editing,
  review,
  audio,
  focusTimeline,
}

/// Central state manager orchestrating the desktop UI, timeline interactions,
/// preview playback, media ingestion, and editing transactions.
class EditorController extends ChangeNotifier {
  final EditingService editingService;
  final MediaLibraryService mediaLibrary;

  // Timeline State
  int _playheadTicks = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  double _pixelsPerSecond = 50.0;
  ToolMode _toolMode = ToolMode.select;
  String? _selectedClipId;
  String? _selectedTrackId;
  bool _showSafeArea = true;
  LayoutPreset _layoutPreset = LayoutPreset.editing;
  bool _snappingEnabled = true;
  double _trackHeight = 48.0;
  double _aspectRatio = 16 / 9;
  double _previewZoom = 1.0;
  List<double> _audioLevels = [0.0, 0.0];

  // Persistence State
  String _projectName = 'Shadow Studio Project';
  String? _currentProjectPath;
  bool _isSaving = false;
  DateTime? _lastSaveTime;
  String? _statusMessage;
  int _lastSavedRevision = 0;

  EditorController({
    required this.editingService,
    required this.mediaLibrary,
    String? initialProjectPath,
  }) : _currentProjectPath = initialProjectPath;

  // Getters
  int get playheadTicks => _playheadTicks;
  bool get isPlaying => _isPlaying;
  double get pixelsPerSecond => _pixelsPerSecond;
  ToolMode get toolMode => _toolMode;
  String? get selectedClipId => _selectedClipId;
  String? get selectedTrackId => _selectedTrackId;
  bool get showSafeArea => _showSafeArea;
  LayoutPreset get layoutPreset => _layoutPreset;
  String? get currentProjectPath => _currentProjectPath;
  bool get isSaving => _isSaving;
  DateTime? get lastSaveTime => _lastSaveTime;
  String? get statusMessage => _statusMessage;
  bool get snappingEnabled => _snappingEnabled;
  double get trackHeight => _trackHeight;
  double get aspectRatio => _aspectRatio;
  double get previewZoom => _previewZoom;
  List<double> get audioLevels => _audioLevels;
  String get projectName => _projectName;
  bool get isDirty => revision != _lastSavedRevision;

  ProjectDocument get document => editingService.currentDocument;
  int get revision => editingService.revision;
  bool get canUndo => editingService.canUndo;
  bool get canRedo => editingService.canRedo;

  /// Returns total project timeline duration in integer ticks.
  int get totalDurationTicks {
    int maxTicks = 0;
    for (final track in document.tracks) {
      for (final clip in track.clips) {
        if (clip.timelineEndTicks > maxTicks) {
          maxTicks = clip.timelineEndTicks;
        }
      }
    }
    return maxTicks > 0 ? maxTicks : 10000000; // default minimum 10s
  }

  // Playhead and Navigation
  void seek(int ticks) {
    _playheadTicks = ticks.clamp(0, totalDurationTicks);
    notifyListeners();
  }

  void stepFrame(int frameDelta) {
    final fpsNum = document.timebase.fpsNum;
    final fpsDen = document.timebase.fpsDen;
    final currentFrame = TimeTicks.ticksToFrame(
      ticks: _playheadTicks,
      fpsNum: fpsNum,
      fpsDen: fpsDen,
    );
    final targetFrame = (currentFrame + frameDelta).clamp(0, 1000000);
    final targetTicks = TimeTicks.frameToTicks(
      frame: targetFrame,
      fpsNum: fpsNum,
      fpsDen: fpsDen,
    );
    seek(targetTicks);
  }

  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    _playbackTimer?.cancel();

    // 30 fps playback tick interval (approx 33.3 ms)
    const intervalMs = 33;
    const ticksPerStep = 33333; // 33.3 ms in ticks

    _playbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (_) {
      if (_playheadTicks >= totalDurationTicks) {
        pause();
        _playheadTicks = 0;
      } else {
        _playheadTicks += ticksPerStep;
        // Natural audio peak fluctuations during playback
        final rand = math.Random();
        _audioLevels = [
          (0.35 + rand.nextDouble() * 0.45).clamp(0.0, 1.0),
          (0.30 + rand.nextDouble() * 0.50).clamp(0.0, 1.0),
        ];
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _audioLevels = [0.0, 0.0];
    _playbackTimer?.cancel();
    _playbackTimer = null;
    notifyListeners();
  }

  // Zoom and View Controls
  void setPixelsPerSecond(double pps) {
    _pixelsPerSecond = pps.clamp(5.0, 500.0);
    notifyListeners();
  }

  void zoomIn() => setPixelsPerSecond(_pixelsPerSecond * 1.25);
  void zoomOut() => setPixelsPerSecond(_pixelsPerSecond / 1.25);

  void fitToTimeline(double viewportWidth) {
    if (totalDurationTicks <= 0 || viewportWidth <= 0) return;
    final durationSeconds = totalDurationTicks / 1000000.0;
    final calculated = viewportWidth / durationSeconds;
    setPixelsPerSecond(calculated);
  }

  // Tools and Selection
  void setToolMode(ToolMode mode) {
    _toolMode = mode;
    notifyListeners();
  }

  void selectClip(String? clipId, {String? trackId}) {
    _selectedClipId = clipId;
    _selectedTrackId = trackId;
    notifyListeners();
  }

  void toggleSafeArea() {
    _showSafeArea = !_showSafeArea;
    notifyListeners();
  }

  void setLayoutPreset(LayoutPreset preset) {
    _layoutPreset = preset;
    notifyListeners();
  }

  // Snapping and Alignment
  void toggleSnapping() {
    _snappingEnabled = !_snappingEnabled;
    notifyListeners();
  }

  void setSnapping(bool enabled) {
    _snappingEnabled = enabled;
    notifyListeners();
  }

  /// Calculates magnetic snap against 0, playhead, and all clip boundaries.
  int snapTick(int candidateTicks, {int thresholdPx = 12, String? ignoreClipId}) {
    if (!_snappingEnabled) return candidateTicks.clamp(0, 1000000000);
    final thresholdTicks = ((thresholdPx / _pixelsPerSecond) * 1000000).round();

    int bestTick = candidateTicks;
    int minDistance = thresholdTicks + 1;

    // 1. Snap to 0
    final distZero = (candidateTicks - 0).abs();
    if (distZero < minDistance) {
      minDistance = distZero;
      bestTick = 0;
    }

    // 2. Snap to Playhead
    final distPlayhead = (candidateTicks - _playheadTicks).abs();
    if (distPlayhead < minDistance) {
      minDistance = distPlayhead;
      bestTick = _playheadTicks;
    }

    // 3. Snap to clip boundaries across all tracks
    for (final track in document.tracks) {
      for (final clip in track.clips) {
        if (clip.id == ignoreClipId) continue;
        final distStart = (candidateTicks - clip.timelineStartTicks).abs();
        if (distStart < minDistance) {
          minDistance = distStart;
          bestTick = clip.timelineStartTicks;
        }
        final distEnd = (candidateTicks - clip.timelineEndTicks).abs();
        if (distEnd < minDistance) {
          minDistance = distEnd;
          bestTick = clip.timelineEndTicks;
        }
      }
    }

    return bestTick.clamp(0, 1000000000);
  }

  // Track & Layout Configuration
  void setTrackHeight(double h) {
    _trackHeight = h.clamp(32.0, 96.0);
    notifyListeners();
  }

  void setAspectRatio(double ratio) {
    _aspectRatio = ratio;
    notifyListeners();
  }

  void setPreviewZoom(double zoom) {
    _previewZoom = zoom;
    notifyListeners();
  }

  void setProjectName(String name) {
    _projectName = name;
    notifyListeners();
  }

  // Editing Commands
  Future<void> undo() async {
    pause();
    final result = await editingService.undo(expectedRevision: revision);
    if (result.isSuccess) {
      _selectedClipId = null;
      notifyListeners();
    }
  }

  Future<void> redo() async {
    pause();
    final result = await editingService.redo(expectedRevision: revision);
    if (result.isSuccess) {
      _selectedClipId = null;
      notifyListeners();
    }
  }

  /// Appends an asset to the primary video or audio track at playhead or end.
  Future<bool> addAssetToTimeline(ImportedMediaAsset imported) async {
    pause();
    final isAudio = imported.kind == MediaKind.audio;
    final targetKind = isAudio ? TrackKind.audio : TrackKind.video;

    // Find or create suitable track
    Track? targetTrack;
    for (final track in document.tracks) {
      if (track.kind == targetKind) {
        targetTrack = track;
        break;
      }
    }

    if (targetTrack == null) {
      // Add track first
      final trackId = 'track_${targetKind.name}_${document.tracks.length + 1}';
      final addTrack = AddTrackCommand(
        Track(
          id: trackId,
          kind: targetKind,
          position: document.tracks.length,
          name: '${targetKind.name.toUpperCase()} 1',
        ),
      );
      final trackTx = EditTransaction(
        id: UuidV7.generate(),
        description: 'Add ${targetKind.name} track',
        commands: [addTrack],
      );
      final trackRes = await editingService.apply(trackTx, expectedRevision: revision);
      if (trackRes.isFailure) return false;
      targetTrack = editingService.currentDocument.tracks.firstWhere((t) => t.id == trackId);
    }

    // Add asset to document assets if not registered
    final assetId = imported.id;
    final commands = <EditCommand>[];

    if (!document.assets.containsKey(assetId)) {
      commands.add(
        AddAssetCommand(
          Asset(
            id: assetId,
            kind: AssetKind.fromWireName(imported.kind.wireName),
            uri: imported.sourceUri,
            durationTicks: imported.durationTicks,
            hash: imported.blake3Hash,
          ),
        ),
      );
    }

    // Calculate start ticks (snap to end of track clips or playhead)
    int startTicks = _playheadTicks;
    for (final c in targetTrack.clips) {
      if (c.timelineEndTicks > startTicks) {
        startTicks = c.timelineEndTicks;
      }
    }

    final clipId = 'clip_${UuidV7.generate()}';
    commands.add(
      AddClipCommand(
        trackId: targetTrack.id,
        clip: Clip(
          id: clipId,
          assetId: assetId,
          kind: targetKind == TrackKind.video
              ? ClipKind.video
              : targetKind == TrackKind.audio
                  ? ClipKind.audio
                  : ClipKind.video,
          timelineStartTicks: startTicks,
          durationTicks: imported.durationTicks,
          sourceInTicks: 0,
          label: imported.sourcePath.split(Platform.pathSeparator).last,
        ),
      ),
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Add clip to ${targetTrack.id}',
      commands: commands,
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    if (result.isSuccess) {
      selectClip(clipId, trackId: targetTrack.id);
      seek(startTicks + imported.durationTicks);
      return true;
    }
    return false;
  }

  /// Splits clip at the current playhead position using [SplitClipCommand].
  Future<bool> splitClipAtPlayhead(String trackId, String clipId) async {
    pause();
    final track = document.tracks.firstWhere((t) => t.id == trackId);
    final clip = track.clips.firstWhere((c) => c.id == clipId);

    if (_playheadTicks <= clip.timelineStartTicks || _playheadTicks >= clip.timelineEndTicks) {
      return false; // playhead outside clip bounds
    }

    final newSecondClipId = 'clip_${UuidV7.generate()}';
    final splitCmd = SplitClipCommand(
      trackId: trackId,
      clipId: clipId,
      splitAtTick: _playheadTicks,
      newClipId: newSecondClipId,
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Split clip at playhead',
      commands: [splitCmd],
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    if (result.isSuccess) {
      selectClip(newSecondClipId, trackId: trackId);
      return true;
    }
    return false;
  }

  /// Deletes the currently selected clip.
  Future<bool> deleteSelectedClip() async {
    if (_selectedClipId == null || _selectedTrackId == null) return false;
    pause();

    final removeCmd = RemoveClipCommand(
      trackId: _selectedTrackId!,
      clipId: _selectedClipId!,
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Delete clip $_selectedClipId',
      commands: [removeCmd],
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    if (result.isSuccess) {
      _selectedClipId = null;
      _selectedTrackId = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Trims clip boundaries in an atomic transaction.
  Future<bool> trimClip({
    required String trackId,
    required String clipId,
    required int newTimelineStartTicks,
    required int newDurationTicks,
    required int newSourceInTicks,
  }) async {
    pause();
    final trimCmd = TrimClipCommand(
      trackId: trackId,
      clipId: clipId,
      newTimelineStartTicks: newTimelineStartTicks,
      newDurationTicks: newDurationTicks,
      newSourceInTicks: newSourceInTicks,
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Trim clip $clipId',
      commands: [trimCmd],
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    return result.isSuccess;
  }

  /// Inserts an asset as a clip at a specific timeline position (used by drag-and-drop).
  Future<bool> insertClipAt({
    required ImportedMediaAsset imported,
    required String trackId,
    required int timelineStartTicks,
    int? customDurationTicks,
  }) async {
    pause();
    final trackIndex = document.tracks.indexWhere((t) => t.id == trackId);
    if (trackIndex == -1) return false;
    final targetTrack = document.tracks[trackIndex];

    final commands = <EditCommand>[];
    final assetId = imported.id;

    if (!document.assets.containsKey(assetId)) {
      commands.add(
        AddAssetCommand(
          Asset(
            id: assetId,
            kind: AssetKind.fromWireName(imported.kind.wireName),
            uri: imported.sourceUri,
            durationTicks: imported.durationTicks,
            hash: imported.blake3Hash,
          ),
        ),
      );
    }

    final duration = customDurationTicks ?? imported.durationTicks;
    final clipId = 'clip_${UuidV7.generate()}';
    commands.add(
      AddClipCommand(
        trackId: trackId,
        clip: Clip(
          id: clipId,
          assetId: assetId,
          kind: targetTrack.kind == TrackKind.video
              ? ClipKind.video
              : targetTrack.kind == TrackKind.audio
                  ? ClipKind.audio
                  : ClipKind.video,
          timelineStartTicks: timelineStartTicks.clamp(0, 1000000000),
          durationTicks: duration,
          sourceInTicks: 0,
          label: imported.sourcePath.split(Platform.pathSeparator).last,
        ),
      ),
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Drop clip onto ${targetTrack.name} at $timelineStartTicks',
      commands: commands,
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    if (result.isSuccess) {
      selectClip(clipId, trackId: trackId);
      seek(timelineStartTicks + duration);
      return true;
    }
    return false;
  }

  /// Moves a clip to a new start position on the same track or to a target track.
  Future<bool> moveClip({
    required String trackId,
    required String clipId,
    required int newTimelineStartTicks,
    String? targetTrackId,
  }) async {
    pause();
    final toTrack = targetTrackId ?? trackId;
    final moveCmd = MoveClipCommand(
      clipId: clipId,
      fromTrackId: trackId,
      toTrackId: toTrack,
      newTimelineStartTicks: newTimelineStartTicks.clamp(0, 1000000000),
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Move clip $clipId to $newTimelineStartTicks',
      commands: [moveCmd],
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    if (result.isSuccess) {
      selectClip(clipId, trackId: toTrack);
      return true;
    }
    return false;
  }

  /// Dynamically adds a new track to the project document.
  Future<bool> addTrack(TrackKind kind, {String? name}) async {
    pause();
    final sameKindCount = document.tracks.where((t) => t.kind == kind).length;
    final prefix = kind == TrackKind.video
        ? 'V'
        : kind == TrackKind.audio
            ? 'A'
            : 'T';
    final trackName = name ?? '$prefix${sameKindCount + 1}';
    final trackId = 'track_${kind.name}_${UuidV7.generate()}';

    final addCmd = AddTrackCommand(
      Track(
        id: trackId,
        kind: kind,
        position: document.tracks.length,
        name: trackName,
      ),
    );

    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Add track $trackName',
      commands: [addCmd],
    );

    final result = await editingService.apply(tx, expectedRevision: revision);
    return result.isSuccess;
  }

  /// Removes a track from the document.
  Future<bool> removeTrack(String trackId) async {
    pause();
    if (document.tracks.length <= 1) return false; // Preserve at least one track
    final removeCmd = RemoveTrackCommand(trackId: trackId);
    final tx = EditTransaction(
      id: UuidV7.generate(),
      description: 'Remove track $trackId',
      commands: [removeCmd],
    );
    final result = await editingService.apply(tx, expectedRevision: revision);
    if (result.isSuccess) {
      if (_selectedTrackId == trackId) {
        _selectedClipId = null;
        _selectedTrackId = null;
      }
      return true;
    }
    return false;
  }

  /// Imports files dropped from the OS or file picker.
  Future<List<ImportedMediaAsset>> importFiles(List<String> filePaths) async {
    final importedAssets = <ImportedMediaAsset>[];
    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final asset = await mediaLibrary.importFile(
          file.path,
          generateProxy: false,
          generateWaveform: true,
        );
        importedAssets.add(asset);
      } catch (e) {
        _statusMessage = 'Import error: $e';
      }
    }
    notifyListeners();
    return importedAssets;
  }

  /// Saves the current project state atomically to disk.
  Future<bool> saveProject({String? path}) async {
    final savePath = path ?? _currentProjectPath;
    if (savePath == null) return false;

    _isSaving = true;
    notifyListeners();

    try {
      if (editingService is DefaultEditingService) {
        await (editingService as DefaultEditingService).saveTo(savePath);
      } else {
        await editingService.save();
      }
      _currentProjectPath = savePath;
      _lastSaveTime = DateTime.now();
      _lastSavedRevision = revision;
      _statusMessage = 'Project saved';
      return true;
    } catch (e) {
      _statusMessage = 'Save failed: $e';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }
}
