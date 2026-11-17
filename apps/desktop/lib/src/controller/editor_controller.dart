import 'dart:async';
import 'dart:io';

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

  // Persistence State
  String? _currentProjectPath;
  bool _isSaving = false;
  DateTime? _lastSaveTime;
  String? _statusMessage;

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

    _playbackTimer =
        Timer.periodic(const Duration(milliseconds: intervalMs), (_) {
      if (_playheadTicks >= totalDurationTicks) {
        pause();
        _playheadTicks = 0;
      } else {
        _playheadTicks += ticksPerStep;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
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
      final trackRes =
          await editingService.apply(trackTx, expectedRevision: revision);
      if (trackRes.isFailure) return false;
      targetTrack = editingService.currentDocument.tracks
          .firstWhere((t) => t.id == trackId);
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

    if (_playheadTicks <= clip.timelineStartTicks ||
        _playheadTicks >= clip.timelineEndTicks) {
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

  /// Refreshes UI state after a non-UI caller (the AI agent) changed the
  /// document through [EditingService]. Clears a selection that no longer
  /// exists and stops playback so the timeline does not advance over stale
  /// frame data.
  void refreshAfterExternalEdit() {
    if (_isPlaying) {
      _isPlaying = false;
      _playbackTimer?.cancel();
      _playbackTimer = null;
    }
    final clipId = _selectedClipId;
    if (clipId != null) {
      var found = false;
      for (final track in document.tracks) {
        if (track.clips.any((clip) => clip.id == clipId)) {
          found = true;
          break;
        }
      }
      if (!found) {
        _selectedClipId = null;
        _selectedTrackId = null;
      }
    }
    _statusMessage = 'Project updated by AI';
    notifyListeners();
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
