import 'package:editing_core/editing_core.dart';
import 'package:test/test.dart';

void main() {
  group('UuidV7', () {
    test('generated IDs match RenderGraph UuidV7 regex', () {
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );

      for (var i = 0; i < 500; i++) {
        final id = UuidV7.generate();
        expect(pattern.hasMatch(id), isTrue, reason: 'Generated ID "$id" does not match UUIDv7 regex');
        expect(UuidV7.isValid(id), isTrue);
      }
    });

    test('deterministic timestamp generates matching prefix', () {
      // 2026-11-16T00:00:00.000Z in ms = 1794787200000 = 0x01a1e1a74c00
      const fixedMs = 1794787200000;
      final id = UuidV7.generate(fixedMs);
      expect(id.startsWith('01a1e1a7-4c00-7'), isTrue, reason: 'Prefix mismatch for ID: $id');
    });

    test('uniqueness over 1,000 rapid generations', () {
      final generated = <String>{};
      for (var i = 0; i < 1000; i++) {
        final id = UuidV7.generate();
        expect(generated.add(id), isTrue, reason: 'Collision detected: $id');
      }
    });
  });
}
