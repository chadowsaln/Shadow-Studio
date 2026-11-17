import 'dart:io';

import 'package:media_core/media_core.dart';
import 'package:test/test.dart';

void main() {
  group('Blake3 Hash Tests', () {
    test('computes exact canonical hashes for standard test vectors', () {
      // Empty input
      expect(
        Blake3.hash([]),
        equals('af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262'),
      );

      // Simple ASCII string
      expect(
        Blake3.hash('hello'.codeUnits),
        equals('ea8f163db38682925e4491c5e58d4bb3506ef8c14eb78a86e908c5624a67200f'),
      );

      // Exactly 1 chunk (1024 bytes)
      expect(
        Blake3.hash(List.filled(1024, 97)),
        equals('5a1c9e5d85d9898297037e8e24f69bb0e604a84c91c3b3ef4784a374812900d9'),
      );

      // Exactly 2 chunks (2048 bytes - binary tree parent node combination)
      expect(
        Blake3.hash(List.filled(2048, 97)),
        equals('11654ac17d073b0905429320fee0a34776cb5f10a9767287c70b627fc4f45539'),
      );

      // Multi-chunk string vector
      final fox = 'The quick brown fox jumps over the lazy dog' * 100;
      expect(
        Blake3.hash(fox.codeUnits),
        equals('bc526326fc97164e6a4e5de961ae7c4da141c999632c5337ce16d05a6cc532ff'),
      );
    });

    test('streaming file hash matches in-memory hash', () async {
      final tempDir = Directory.systemTemp.createTempSync('blake3_test_');
      try {
        final file = File('${tempDir.path}/test.bin');
        final data = List<int>.generate(5000, (i) => i % 256);
        file.writeAsBytesSync(data);

        final memHash = Blake3.hash(data);
        final fileHashAsync = await Blake3.hashFile(file);
        final fileHashSync = Blake3.hashFileSync(file);

        expect(fileHashAsync, equals(memHash));
        expect(fileHashSync, equals(memHash));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
