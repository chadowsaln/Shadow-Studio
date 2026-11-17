/// Classification of media asset types supported by the media core.
enum MediaKind {
  video,
  audio,
  image;

  String get wireName => name;

  static MediaKind fromWireName(String value) {
    return MediaKind.values.firstWhere(
      (k) => k.wireName == value,
      orElse: () => throw ArgumentError('Unknown media kind: $value'),
    );
  }
}
