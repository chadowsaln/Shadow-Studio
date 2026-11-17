/// Specialized agents collaborating inside one Shadow Studio task.
///
/// Roles are capabilities, not permissions: an agent may only invoke tools the
/// runtime and permission layer allow for the task.
enum AgentRole {
  projectManager(
    id: 'project_manager',
    specialty:
        'Understands the user goal, decomposes it into steps, delegates to specialists and merges results.',
    defaultTools: <String>{},
  ),
  videoAnalysis(
    id: 'video_analysis',
    specialty:
        'Probes and analyzes real media: metadata, scenes, black frames, motion and visual quality.',
    defaultTools: <String>{'media_probe', 'media_analysis', 'list_files'},
  ),
  videoEditing(
    id: 'video_editing',
    specialty:
        'Builds the timeline: selects shots, arranges clips, trims and splits through validated edits.',
    defaultTools: <String>{'media_probe', 'timeline_edit', 'list_files'},
  ),
  audioEngineering(
    id: 'audio_engineering',
    specialty:
        'Analyzes and balances audio: loudness, waveform peaks, music and voice-over placement.',
    defaultTools: <String>{'media_probe', 'media_analysis'},
  ),
  subtitle(
    id: 'subtitle',
    specialty:
        'Creates and times captions and on-screen text from transcripts or script text.',
    defaultTools: <String>{'timeline_edit'},
  ),
  qualityAssurance(
    id: 'quality_assurance',
    specialty:
        'Verifies the deliverable against the brief: duration, resolution, loudness, black frames and artifacts.',
    defaultTools: <String>{'media_probe', 'media_analysis', 'list_files'},
  );

  const AgentRole({
    required this.id,
    required this.specialty,
    required this.defaultTools,
  });

  final String id;
  final String specialty;
  final Set<String> defaultTools;

  static AgentRole? fromId(String value) {
    for (final role in values) {
      if (role.id == value) return role;
    }
    return null;
  }
}
