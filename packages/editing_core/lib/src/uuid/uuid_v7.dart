import 'dart:math';

/// UUIDv7 generator and validator adhering to RFC 9562 and the RenderGraph contract.
///
/// Pattern: ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$
abstract final class UuidV7 {
  static final Random _random = Random.secure();
  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Validates whether a given string is a valid UUIDv7.
  static bool isValid(String value) => _pattern.hasMatch(value);

  /// Generates a new UUIDv7 string.
  ///
  /// Optional [timestampMs] can be provided for deterministic tests.
  static String generate([int? timestampMs]) {
    final ms = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

    // 48-bit timestamp in milliseconds
    final timeHex = ms.toRadixString(16).padLeft(12, '0');
    final timeHigh = timeHex.substring(0, 8);
    final timeMid = timeHex.substring(8, 12);

    // 12-bit rand_a
    final randA = _random.nextInt(0x1000).toRadixString(16).padLeft(3, '0');

    // 2-bit variant (0b10 -> 8, 9, a, or b) + 62-bit rand_b
    final variantNibble = (8 + _random.nextInt(4)).toRadixString(16);
    final randB1 = _random.nextInt(0x1000).toRadixString(16).padLeft(3, '0');
    final randB2 = _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final randB3 = _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');
    final randB4 = _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');

    return '$timeHigh-$timeMid-7$randA-$variantNibble$randB1-$randB2$randB3$randB4';
  }
}
