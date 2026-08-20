// ─────────────────────────────────────────────────────────────────────────────
// hive_cipher.dart
//
// Resolves the AES-256 key that encrypts Hive boxes at rest, and keeps it in
// the one place on the device that is built to hold it.
//
// Hive will encrypt a box for you, but it will not tell you where to keep the
// key — and that is the whole problem. A key compiled into the app is not a
// secret (anyone can unzip an APK); a key in SharedPreferences or in a plain
// Hive box is stored beside the very data it protects, so an attacker who can
// read one can read the other. Either arrangement encrypts the data while
// leaving it exactly as readable as it was before.
//
// So the key lives in [SecureStorage], which is backed by the Android Keystore,
// the iOS/macOS Keychain, DPAPI on Windows and libsecret on Linux. On Android
// the Keystore key never leaves the secure hardware and cannot be extracted,
// even from a rooted device — the app asks the OS to decrypt on its behalf.
// That is what makes the AES key meaningfully harder to obtain than the box it
// protects.
//
// The key is generated once per install, on first use, from Hive's Fortuna CSPRNG
// (Hive.generateSecureKey — 32 bytes) and stored base64-encoded, because secure
// storage holds strings, not bytes.
//
// Two things this file deliberately does not do:
//
//   * It never logs, prints, returns or otherwise exposes the key material. The
//     only thing handed out is an opaque [HiveCipher]. If you find yourself
//     wanting the bytes, you are about to write them somewhere they should not
//     go.
//   * It never replaces a key that is already stored but unreadable. Generating
//     a fresh key over existing encrypted data does not recover it — it
//     guarantees the data can never be read again. That case throws.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:hive/hive.dart';

import '../exceptions/storage_exception.dart';
import '../secure/secure_storage.dart';

/// Secure-storage key under which the Hive encryption key is stored by default.
///
/// Exposed publicly as [BaabaStorage.hiveKeyAlias] so a consumer can check for
/// the key's presence without hardcoding the string.
const String defaultHiveKeyAlias = 'baaba_hive_key';

/// Internal machinery behind [BaabaStorage.hiveCipher].
///
/// Not exported: the public entry point is on [BaabaStorage], which spans both
/// the hive and secure halves of this package and can enforce the
/// initialisation guard.
class HiveKeyStore {
  HiveKeyStore._();

  /// One resolved cipher per alias, memoised for the life of the isolate.
  ///
  /// Two reasons this cache is not just a micro-optimisation. It keeps a
  /// concurrent pair of `openBox(…, encryptionCipher: await hiveCipher())`
  /// calls — the shape of a normal app start — from racing each other into
  /// generating two keys and writing the second over the first, which would
  /// leave the box opened by the loser undecryptable. And every read otherwise
  /// crosses the platform channel into the Keystore, which is not free.
  ///
  /// The future is cached, not the value, so callers that arrive mid-flight join
  /// the same operation rather than starting another.
  static final Map<String, Future<HiveCipher>> _ciphers =
      <String, Future<HiveCipher>>{};

  /// Returns the cipher for [alias], generating and storing a key on first use.
  static Future<HiveCipher> resolve(String alias) async {
    final cached = _ciphers[alias];
    if (cached != null) return cached;

    final pending = _read(alias);
    _ciphers[alias] = pending;
    try {
      return await pending;
    } catch (_) {
      // A failure must not be cached — a Keystore read can fail transiently
      // (device locked, for instance) and the next attempt deserves a real try.
      _ciphers.remove(alias);
      rethrow;
    }
  }

  /// Forgets every memoised cipher. Called from [BaabaStorage.dispose] so a
  /// re-initialised app does not keep a cipher from the previous lifetime.
  static void clearCache() => _ciphers.clear();

  /// Reads the stored key, or generates and stores one if there is none.
  static Future<HiveCipher> _read(String alias) async {
    // Deliberately SecureStorage.instance rather than BaabaStorage.secure: this
    // file must not import the facade that imports it. The caller is
    // responsible for the initialisation guard.
    final stored = await SecureStorage.instance.read(alias);

    if (stored != null) return HiveAesCipher(_decode(stored, alias));

    final fresh = Hive.generateSecureKey();
    await SecureStorage.instance.write(alias, base64Encode(fresh));
    return HiveAesCipher(fresh);
  }

  /// Decodes a stored key, failing loudly rather than silently replacing it.
  ///
  /// A stored value that is not a 32-byte base64 key means something already
  /// went wrong — a truncated write, a key from an incompatible version, a
  /// collision on the alias. Whatever the cause, the boxes on disk were
  /// encrypted with something, and overwriting it with a new key would turn a
  /// diagnosable problem into permanent data loss. So this throws, and the
  /// message names the alias but never the value.
  static List<int> _decode(String stored, String alias) {
    List<int> bytes;
    try {
      bytes = base64Decode(stored);
    } on FormatException catch (e) {
      throw StorageException(
        'The Hive encryption key stored under "$alias" is not valid base64, '
        'so it cannot be used to open an encrypted box. It has been left '
        'untouched — generating a replacement would make any box encrypted '
        'with the original permanently unreadable.',
        cause: e,
      );
    }

    if (bytes.length != 32) {
      throw StorageException(
        'The Hive encryption key stored under "$alias" is '
        '${bytes.length} bytes; Hive requires exactly 32 (AES-256). It has '
        'been left untouched — generating a replacement would make any box '
        'encrypted with the original permanently unreadable.',
      );
    }

    return bytes;
  }
}
