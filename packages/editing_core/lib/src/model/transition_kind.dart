import 'package:meta/meta.dart';

/// Transition kinds accepted by the RenderGraph v1 contract (§A.7).
///
/// Kept as a closed set so the editor, the AI tools and the renderer agree on
/// the same vocabulary. Unknown kinds are rejected with EDIT_INVALID_OPERATION.
@immutable
class TransitionKinds {
  const TransitionKinds._();

  static const String crossfade = 'crossfade';
  static const String dissolve = 'dissolve';
  static const String wipeLeft = 'wipe_left';
  static const String wipeRight = 'wipe_right';
  static const String fadeBlack = 'fade_black';

  /// Every kind allowed by `rendergraph.schema.json`.
  static const List<String> all = <String>[
    crossfade,
    dissolve,
    wipeLeft,
    wipeRight,
    fadeBlack,
  ];

  static bool isValid(String value) => all.contains(value);

  /// Maps a transition kind to the FFmpeg `xfade` transition name.
  ///
  /// `fade_black` has no `xfade` equivalent; the renderer implements it as a
  /// fade-out/fade-in pair instead.
  static String? toXfade(String value) {
    switch (value) {
      case crossfade:
      case dissolve:
        return 'fade';
      case wipeLeft:
        return 'wipeleft';
      case wipeRight:
        return 'wiperight';
      default:
        return null;
    }
  }
}