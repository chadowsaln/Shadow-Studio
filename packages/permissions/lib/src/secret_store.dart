import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

/// Platform secret storage contract. Implementations must never write plaintext
/// keys to project files, SQLite, logs, or crash reports.
abstract interface class SecretStore {
  Future<void> saveApiKey({required String providerId, required String apiKey});

  Future<String?> readApiKey(String providerId);

  Future<void> deleteApiKey(String providerId);
}

class SecretStoreException implements Exception {
  const SecretStoreException(this.code, this.message);

  final String code;
  final String message;

  /// Deliberately excludes secret material.
  @override
  String toString() => 'SecretStoreException($code): $message';
}

/// Encrypted file store for API keys, used when an OS keyring is unavailable.
///
/// Security properties:
/// * AES is not used directly; payloads are encrypted with an HMAC-SHA256
///   keystream (a PRF-based stream cipher) and authenticated with
///   encrypt-then-MAC over `nonce || ciphertext`;
/// * a random 256-bit device key lives in `<directory>/device.key`, created and
///   chmodded `0600` on POSIX; every secret file is `0600` as well;
/// * provider identifiers are base64url-encoded into filenames, so `../`,
///   absolute paths, or separators cannot escape the directory;
/// * writes are atomic (temp file in the same directory, then rename);
/// * a missing/corrupt key or tag mismatch fails closed with
///   [SecretStoreException] and never returns partial plaintext.
///
/// This is defense in depth, not a replacement for an OS keyring: an attacker
/// who can read the user's home directory can read the device key too.
class FileSecretStore implements SecretStore {
  FileSecretStore({
    required this.directory,
    this.restrictPermissions = true,
    Random? random,
  }) : _random = random ?? Random.secure();

  final String directory;
  final bool restrictPermissions;
  final Random _random;
  Uint8List? _deviceKey;

  static const int _keyLength = 32;
  static const int _nonceLength = 16;
  static const int _maxProviderIdLength = 128;
  static const String _version = 'v1';

  Future<Uint8List> _key() async {
    final cached = _deviceKey;
    if (cached != null) return cached;

    final dir = Directory(directory);
    await dir.create(recursive: true);
    _chmod(dir.path, '700');

    final keyFile = File(_join(directory, 'device.key'));
    if (await keyFile.exists()) {
      try {
        final decoded = base64.decode((await keyFile.readAsString()).trim());
        if (decoded.length != _keyLength) {
          throw const SecretStoreException(
            ShadowErrorCode.storeCorrupt,
            'Device key has an invalid length',
          );
        }
        _deviceKey = Uint8List.fromList(decoded);
        return _deviceKey!;
      } on FormatException {
        throw const SecretStoreException(
          ShadowErrorCode.storeCorrupt,
          'Device key is corrupt',
        );
      }
    }

    final key = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => _random.nextInt(256)),
    );
    await keyFile.writeAsString(base64.encode(key), flush: true);
    _chmod(keyFile.path, '600');
    _deviceKey = key;
    return key;
  }

  @override
  Future<void> saveApiKey({
    required String providerId,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const SecretStoreException(
        ShadowErrorCode.permInvalidArgument,
        'API key must not be empty',
      );
    }
    final path = _pathFor(providerId);
    final key = await _key();
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => _random.nextInt(256)),
    );
    final ciphertext = _crypt(
      key: key,
      nonce: nonce,
      input: Uint8List.fromList(utf8.encode(apiKey)),
    );
    final tag = _mac(key, nonce, ciphertext);
    final payload = jsonEncode(<String, Object?>{
      'v': _version,
      'n': base64.encode(nonce),
      'c': base64.encode(ciphertext),
      't': base64.encode(tag),
    });

    await Directory(directory).create(recursive: true);
    final tempPath =
        '$path.tmp.${base64Url.encode(List<int>.generate(8, (_) => _random.nextInt(256)))}';
    final temp = File(tempPath);
    await temp.writeAsString(payload, flush: true);
    _chmod(tempPath, '600');
    try {
      await temp.rename(path);
    } on FileSystemException {
      // Windows cannot rename over an existing file. Remove then rename; the
      // window is small and the content is encrypted either way.
      final target = File(path);
      if (await target.exists()) await target.delete();
      await temp.rename(path);
    }
    _chmod(path, '600');
  }

  @override
  Future<String?> readApiKey(String providerId) async {
    final path = _pathFor(providerId);
    final file = File(path);
    if (!await file.exists()) return null;

    final key = await _key();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['v'] != _version) {
        throw const SecretStoreException(
          ShadowErrorCode.storeCorrupt,
          'Secret payload is malformed',
        );
      }
      final rawNonce = decoded['n'];
      final rawCiphertext = decoded['c'];
      final rawTag = decoded['t'];
      if (rawNonce is! String ||
          rawCiphertext is! String ||
          rawTag is! String) {
        throw const SecretStoreException(
          ShadowErrorCode.storeCorrupt,
          'Secret payload is missing fields',
        );
      }
      final nonce = base64.decode(rawNonce);
      final ciphertext = base64.decode(rawCiphertext);
      final tag = base64.decode(rawTag);
      if (nonce.length != _nonceLength) {
        throw const SecretStoreException(
          ShadowErrorCode.storeCorrupt,
          'Secret nonce is malformed',
        );
      }
      final expected = _mac(
        key,
        Uint8List.fromList(nonce),
        Uint8List.fromList(ciphertext),
      );
      if (!_constantTimeEquals(expected, Uint8List.fromList(tag))) {
        throw const SecretStoreException(
          ShadowErrorCode.storeCorrupt,
          'Secret authentication failed',
        );
      }
      final plaintext = _crypt(
        key: key,
        nonce: Uint8List.fromList(nonce),
        input: Uint8List.fromList(ciphertext),
      );
      return utf8.decode(plaintext);
    } on SecretStoreException {
      rethrow;
    } on FormatException {
      throw const SecretStoreException(
        ShadowErrorCode.storeCorrupt,
        'Secret payload cannot be decoded',
      );
    } on FileSystemException {
      throw const SecretStoreException(
        ShadowErrorCode.storeCorrupt,
        'Secret payload cannot be read',
      );
    }
  }

  @override
  Future<void> deleteApiKey(String providerId) async {
    final file = File(_pathFor(providerId));
    if (await file.exists()) await file.delete();
  }

  String _pathFor(String providerId) {
    if (providerId.isEmpty ||
        providerId.length > _maxProviderIdLength ||
        providerId.contains('..')) {
      throw const SecretStoreException(
        ShadowErrorCode.permInvalidArgument,
        'Invalid provider identifier',
      );
    }
    final encoded = base64Url
        .encode(utf8.encode(providerId))
        .replaceAll('=', '');
    return _join(directory, '$encoded.secret');
  }

  String _join(String dir, String name) => dir.endsWith(Platform.pathSeparator)
      ? '$dir$name'
      : '$dir${Platform.pathSeparator}$name';

  Uint8List _crypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List input,
  }) {
    final out = Uint8List(input.length);
    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      final block = _hmac(key, <int>[...nonce, ..._uint32be(counter)]);
      final take = min(block.length, input.length - offset);
      for (var i = 0; i < take; i++) {
        out[offset + i] = input[offset + i] ^ block[i];
      }
      offset += take;
      counter++;
    }
    return out;
  }

  Uint8List _mac(Uint8List key, Uint8List nonce, Uint8List ciphertext) {
    return _hmac(key, <int>[...nonce, ...ciphertext]);
  }

  Uint8List _hmac(Uint8List key, List<int> data) =>
      Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

  List<int> _uint32be(int value) => <int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  void _chmod(String path, String mode) {
    if (!restrictPermissions || Platform.isWindows) return;
    try {
      Process.runSync('chmod', <String>[mode, path]);
    } on ProcessException {
      // Best effort; the encryption boundary still holds.
    }
  }

  /// Never exposes key material.
  @override
  String toString() => 'FileSecretStore(directory: $directory)';
}
