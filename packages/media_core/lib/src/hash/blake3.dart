import 'dart:io';
import 'dart:typed_data';

/// High-performance pure Dart BLAKE3 cryptographic hash implementation.
///
/// Implements standard BLAKE3 tree hashing (1024-byte chunk size, 7 rounds,
/// little-endian words, binary tree parent node combination).
/// Fully compatible with standard BLAKE3 reference implementations (e.g. b3sum,
/// python-blake3, Rust blake3).
class Blake3 {
  static const int chunkSize = 1024;
  static const int blockSize = 64;

  static const List<int> _iv = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
  ];

  static const List<int> _msgPermutation = [
    2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8
  ];

  static const int _flagChunkStart = 1 << 0;
  static const int _flagChunkEnd = 1 << 1;
  static const int _flagParent = 1 << 2;
  static const int _flagRoot = 1 << 3;

  static int _rotr32(int w, int b) {
    return ((w >> b) | (w << (32 - b))) & 0xFFFFFFFF;
  }

  static void _g(List<int> state, int a, int b, int c, int d, int mx, int my) {
    state[a] = (state[a] + state[b] + mx) & 0xFFFFFFFF;
    state[d] = _rotr32(state[d] ^ state[a], 16);
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF;
    state[b] = _rotr32(state[b] ^ state[c], 12);
    state[a] = (state[a] + state[b] + my) & 0xFFFFFFFF;
    state[d] = _rotr32(state[d] ^ state[a], 8);
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF;
    state[b] = _rotr32(state[b] ^ state[c], 7);
  }

  static void _round(List<int> state, List<int> msg) {
    // Columns
    _g(state, 0, 4, 8, 12, msg[0], msg[1]);
    _g(state, 1, 5, 9, 13, msg[2], msg[3]);
    _g(state, 2, 6, 10, 14, msg[4], msg[5]);
    _g(state, 3, 7, 11, 15, msg[6], msg[7]);
    // Diagonals
    _g(state, 0, 5, 10, 15, msg[8], msg[9]);
    _g(state, 1, 6, 11, 12, msg[10], msg[11]);
    _g(state, 2, 7, 8, 13, msg[12], msg[13]);
    _g(state, 3, 4, 9, 14, msg[14], msg[15]);
  }

  static List<int> _permute(List<int> m) {
    final next = List<int>.filled(16, 0);
    for (int i = 0; i < 16; i++) {
      next[i] = m[_msgPermutation[i]];
    }
    return next;
  }

  static List<int> _compress(
    List<int> cv,
    List<int> blockWords,
    int blockLen,
    int counter,
    int flags,
  ) {
    final state = List<int>.filled(16, 0);
    for (int i = 0; i < 8; i++) {
      state[i] = cv[i];
      state[i + 8] = _iv[i];
    }
    state[12] = counter & 0xFFFFFFFF;
    state[13] = (counter >> 32) & 0xFFFFFFFF;
    state[14] = blockLen;
    state[15] = flags;

    var msg = List<int>.from(blockWords);
    for (int r = 0; r < 7; r++) {
      _round(state, msg);
      if (r < 6) {
        msg = _permute(msg);
      }
    }

    final out = List<int>.filled(16, 0);
    for (int i = 0; i < 8; i++) {
      out[i] = state[i] ^ state[i + 8];
      out[i + 8] = state[i + 8] ^ cv[i];
    }
    return out;
  }

  final List<int> _key;
  final List<List<int>> _cvStack = [];
  final Uint8List _buf = Uint8List(chunkSize);
  int _bufLen = 0;
  int _chunkCounter = 0;

  Blake3([List<int>? key]) : _key = key ?? List<int>.from(_iv);

  /// Appends bytes to the running hash state.
  void update(List<int> input) {
    int offset = 0;
    while (offset < input.length) {
      if (_bufLen == chunkSize) {
        final chunkCv = _outputCvForChunk(_buf, chunkSize, _chunkCounter, 0);
        _addChunkCv(chunkCv);
        _chunkCounter++;
        _bufLen = 0;
      }
      final want = chunkSize - _bufLen;
      final available = input.length - offset;
      final toCopy = want < available ? want : available;
      _buf.setRange(_bufLen, _bufLen + toCopy, input, offset);
      _bufLen += toCopy;
      offset += toCopy;
    }
  }

  void _addChunkCv(List<int> newCv) {
    var cv = newCv;
    var totalChunks = _chunkCounter + 1;
    while ((totalChunks & 1) == 0) {
      final left = _cvStack.removeLast();
      cv = _parentCv(left, cv, _key, 0);
      totalChunks >>= 1;
    }
    _cvStack.add(cv);
  }

  static List<int> _wordsFromBytes(Uint8List bytes, int len) {
    final words = List<int>.filled(16, 0);
    final byteData = ByteData.sublistView(bytes, 0, len);
    final fullWords = len ~/ 4;
    for (int i = 0; i < fullWords; i++) {
      words[i] = byteData.getUint32(i * 4, Endian.little);
    }
    final remainder = len % 4;
    if (remainder > 0) {
      int lastWord = 0;
      final start = fullWords * 4;
      for (int i = 0; i < remainder; i++) {
        lastWord |= bytes[start + i] << (i * 8);
      }
      words[fullWords] = lastWord;
    }
    return words;
  }

  List<int> _outputCvForChunk(Uint8List chunkBytes, int len, int counter, int extraFlags) {
    var cv = List<int>.from(_key);
    final totalBlocks = (len == 0) ? 1 : ((len + blockSize - 1) ~/ blockSize);
    for (int i = 0; i < totalBlocks; i++) {
      final blockStart = i * blockSize;
      final blockEnd = (blockStart + blockSize <= len) ? blockStart + blockSize : len;
      final blockLen = blockEnd - blockStart;
      final slice = Uint8List(blockSize);
      if (blockLen > 0) {
        slice.setRange(0, blockLen, chunkBytes, blockStart);
      }
      final words = _wordsFromBytes(slice, blockSize);
      int flags = extraFlags;
      if (i == 0) flags |= _flagChunkStart;
      if (i == totalBlocks - 1) flags |= _flagChunkEnd;
      final fullOutput = _compress(cv, words, blockLen, counter, flags);
      cv = fullOutput.sublist(0, 8);
    }
    return cv;
  }

  static List<int> _parentCv(List<int> leftCv, List<int> rightCv, List<int> key, int flags) {
    final blockWords = List<int>.filled(16, 0);
    for (int i = 0; i < 8; i++) {
      blockWords[i] = leftCv[i];
      blockWords[i + 8] = rightCv[i];
    }
    final full = _compress(key, blockWords, blockSize, 0, flags | _flagParent);
    return full.sublist(0, 8);
  }

  /// Finalizes the hash and returns the raw 32-byte digest.
  Uint8List finalize({int outputBytes = 32}) {
    if (_cvStack.isEmpty) {
      return _rootOutputForChunk(_buf, _bufLen, 0);
    }

    var rightCv = _outputCvForChunk(_buf, _bufLen, _chunkCounter, 0);
    int numParents = _cvStack.length;
    for (int i = numParents - 1; i >= 0; i--) {
      final left = _cvStack[i];
      final isRoot = (i == 0);
      if (isRoot) {
        final blockWords = List<int>.filled(16, 0);
        for (int j = 0; j < 8; j++) {
          blockWords[j] = left[j];
          blockWords[j + 8] = rightCv[j];
        }
        final full = _compress(_key, blockWords, blockSize, 0, _flagParent | _flagRoot);
        final outBytes = Uint8List(32);
        final bd = ByteData.sublistView(outBytes);
        for (int j = 0; j < 8; j++) {
          bd.setUint32(j * 4, full[j], Endian.little);
        }
        return outBytes;
      } else {
        rightCv = _parentCv(left, rightCv, _key, 0);
      }
    }
    return Uint8List(32);
  }

  Uint8List _rootOutputForChunk(Uint8List chunkBytes, int len, int counter) {
    var cv = List<int>.from(_key);
    final totalBlocks = (len == 0) ? 1 : ((len + blockSize - 1) ~/ blockSize);
    for (int i = 0; i < totalBlocks; i++) {
      final blockStart = i * blockSize;
      final blockEnd = (blockStart + blockSize <= len) ? blockStart + blockSize : len;
      final blockLen = blockEnd - blockStart;
      final slice = Uint8List(blockSize);
      if (blockLen > 0) {
        slice.setRange(0, blockLen, chunkBytes, blockStart);
      }
      final words = _wordsFromBytes(slice, blockSize);
      int flags = 0;
      if (i == 0) flags |= _flagChunkStart;
      if (i == totalBlocks - 1) flags |= _flagChunkEnd | _flagRoot;
      final fullOutput = _compress(cv, words, blockLen, counter, flags);
      if (i == totalBlocks - 1) {
        final outBytes = Uint8List(32);
        final bd = ByteData.sublistView(outBytes);
        for (int j = 0; j < 8; j++) {
          bd.setUint32(j * 4, fullOutput[j], Endian.little);
        }
        return outBytes;
      }
      cv = fullOutput.sublist(0, 8);
    }
    return Uint8List(32);
  }

  /// Convenience method to compute lowercase hexadecimal BLAKE3 hash of bytes.
  static String hash(List<int> data) {
    final b3 = Blake3();
    b3.update(data);
    final bytes = b3.finalize();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Asynchronously computes lowercase hexadecimal BLAKE3 hash of a file by streaming.
  static Future<String> hashFile(File file, {int bufferSize = 64 * 1024}) async {
    final b3 = Blake3();
    final stream = file.openRead();
    await for (final chunk in stream) {
      b3.update(chunk);
    }
    final bytes = b3.finalize();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Synchronously computes lowercase hexadecimal BLAKE3 hash of a file.
  static String hashFileSync(File file, {int bufferSize = 64 * 1024}) {
    final b3 = Blake3();
    final raf = file.openSync(mode: FileMode.read);
    try {
      final buffer = Uint8List(bufferSize);
      int bytesRead;
      while ((bytesRead = raf.readIntoSync(buffer)) > 0) {
        if (bytesRead == bufferSize) {
          b3.update(buffer);
        } else {
          b3.update(buffer.sublist(0, bytesRead));
        }
      }
      final bytes = b3.finalize();
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } finally {
      raf.closeSync();
    }
  }
}
