import 'package:meta/meta.dart';

/// Project video profile aligned with RenderGraph Profile definition.
///
/// Closed schema properties: width, height, pixel_format, color_space, interlaced.
@immutable
class ProjectProfile {
  final int width;
  final int height;
  final String pixelFormat; // 'yuv420p', 'yuv422p', 'yuv444p', 'rgba'
  final String colorSpace;  // 'bt709', 'bt2020', 'srgb'
  final bool interlaced;    // Must be false per RenderGraph contract

  const ProjectProfile({
    required this.width,
    required this.height,
    this.pixelFormat = 'yuv420p',
    this.colorSpace = 'bt709',
    this.interlaced = false,
  })  : assert(width >= 1, 'width must be at least 1'),
        assert(height >= 1, 'height must be at least 1'),
        assert(!interlaced, 'interlaced must be false');

  /// Standard 1080p full HD profile.
  factory ProjectProfile.hd1080p() => const ProjectProfile(
        width: 1920,
        height: 1080,
        pixelFormat: 'yuv420p',
        colorSpace: 'bt709',
        interlaced: false,
      );

  /// 4K UHD profile.
  factory ProjectProfile.uhd4k() => const ProjectProfile(
        width: 3840,
        height: 2160,
        pixelFormat: 'yuv420p',
        colorSpace: 'bt709',
        interlaced: false,
      );

  /// 720p HD profile.
  factory ProjectProfile.hd720p() => const ProjectProfile(
        width: 1280,
        height: 720,
        pixelFormat: 'yuv420p',
        colorSpace: 'bt709',
        interlaced: false,
      );

  ProjectProfile copyWith({
    int? width,
    int? height,
    String? pixelFormat,
    String? colorSpace,
  }) {
    return ProjectProfile(
      width: width ?? this.width,
      height: height ?? this.height,
      pixelFormat: pixelFormat ?? this.pixelFormat,
      colorSpace: colorSpace ?? this.colorSpace,
      interlaced: false,
    );
  }

  Map<String, Object> toJson() => {
        'width': width,
        'height': height,
        'pixel_format': pixelFormat,
        'color_space': colorSpace,
        'interlaced': false,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectProfile &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height &&
          pixelFormat == other.pixelFormat &&
          colorSpace == other.colorSpace &&
          interlaced == other.interlaced;

  @override
  int get hashCode => Object.hash(width, height, pixelFormat, colorSpace, interlaced);

  @override
  String toString() =>
      'ProjectProfile(${width}x$height, $pixelFormat, $colorSpace, interlaced: $interlaced)';
}
