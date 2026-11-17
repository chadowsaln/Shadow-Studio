import 'dart:io';

import 'package:editing_core/editing_core.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';

import 'agent/agent_session_controller.dart';
import 'controller/editor_controller.dart';
import 'theme/shadow_theme.dart';
import 'ui/shell/app_shell.dart';

/// Root application widget for Shadow Studio desktop video editor.
class ShadowStudioApp extends StatefulWidget {
  final EditingService? customEditingService;
  final MediaWorker? customMediaWorker;
  final Directory? customCacheDir;
  final AgentSessionController? customAgentSession;

  const ShadowStudioApp({
    super.key,
    this.customEditingService,
    this.customMediaWorker,
    this.customCacheDir,
    this.customAgentSession,
  });

  @override
  State<ShadowStudioApp> createState() => _ShadowStudioAppState();
}

class _ShadowStudioAppState extends State<ShadowStudioApp> {
  late final EditorController _controller;
  late final AgentSessionController _agentSession;
  late final bool _ownsAgentSession;
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    final editingService =
        widget.customEditingService ?? _createDefaultEditingService();
    final cacheDir = widget.customCacheDir ??
        Directory.systemTemp.createTempSync('ss_desktop_cache_');
    final mediaWorker = widget.customMediaWorker ?? FfmpegMediaWorker();
    final mediaLibrary =
        MediaLibraryService(worker: mediaWorker, cacheDir: cacheDir);

    _controller = EditorController(
      editingService: editingService,
      mediaLibrary: mediaLibrary,
      initialProjectPath: 'ep12_demo.ssproj',
    );
    _ownsAgentSession = widget.customAgentSession == null;
    _agentSession = widget.customAgentSession ??
        AgentSessionController(editor: _controller);
  }

  static EditingService _createDefaultEditingService() {
    // Initial document with 1 video track, 1 audio track, and 1 overlay track
    final initialDoc = ProjectDocument(
      name: 'ep12_project',
      profile: ProjectProfile.hd1080p(),
      timebase: Timebase.ntsc2997(),
      tracks: [
        Track(
            id: 'track_v1',
            kind: TrackKind.video,
            position: 0,
            name: 'V1 (Video)'),
        Track(
            id: 'track_a1',
            kind: TrackKind.audio,
            position: 1,
            name: 'A1 (Audio)'),
        Track(
            id: 'track_t1',
            kind: TrackKind.overlay,
            position: 2,
            name: 'T1 (Titles)'),
      ],
      assets: const {},
    );

    return DefaultEditingService(initialDocument: initialDoc);
  }

  @override
  void dispose() {
    if (_ownsAgentSession) _agentSession.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() => _isDarkMode = !_isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shadow Studio',
      debugShowCheckedModeBanner: false,
      theme: ShadowTheme.light(),
      darkTheme: ShadowTheme.dark(),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: AppShell(
        controller: _controller,
        agentSession: _agentSession,
        onThemeToggle: _toggleTheme,
        isDarkMode: _isDarkMode,
      ),
    );
  }
}
