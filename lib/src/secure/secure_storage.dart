// ─────────────────────────────────────────────────────────────────────────────
// secure_storage.dart
//
// A singleton wrapper around the flutter_secure_storage package.
//
// flutter_secure_storage uses the OS-level secure enclave to encrypt data:
//   - Android : Android Keystore + EncryptedSharedPreferences
//   - iOS/macOS: Keychain
//   - Windows  : DPAPI (Data Protection API)
//   - Linux    : libsecret
//
// This means even if someone extracts your app's data files from the device,
// they cannot read the values stored here without the device's private key.
//
// Ideal for:
//   - Authentication tokens (JWT, OAuth)
//   - API keys / secrets
//   - Refresh tokens
//   - Passwords or PINs
//
// NOT ideal for:
//   - Large amounts of data (each read/write goes through the OS crypto layer)
//   - Non-sensitive data (use PrefsStorage or HiveStorage instead)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Default key used when saving/reading a single auth token.
// Using a constant avoids typos when the same key is used in multiple places.
const _defaultTokenKey = 'baaba_auth_token';

// Prefix added to every header name when saving auth headers as individual keys.
// For example, 'Authorization' becomes 'baaba_header_Authorization' on disk.
// This prefix is stripped back out when reading headers.
const _defaultHeaderPrefix = 'baaba_header_';

/// Wraps [FlutterSecureStorage] with a clean singleton API plus
/// convenience methods for common auth patterns.
///
/// Do not instantiate directly — access via [BaabaStorage.secure]
/// or [SecureStorage.instance] after calling [BaabaStorage.init].
class SecureStorage {
  /// Private constructor — injects the underlying [FlutterSecureStorage].
  ///
  /// If no [storage] is provided, a sensible default is used:
  /// - Android: EncryptedSharedPreferences (stronger than the default AES keystore mode)
  /// - All other platforms: their respective OS defaults
  SecureStorage._({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // encryptedSharedPreferences uses Android's EncryptedSharedPreferences
              // API, which is more secure than the default RSA/AES approach.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// The actual flutter_secure_storage instance that does the real work.
  final FlutterSecureStorage _storage;

  /// The singleton instance — null until first accessed.
  static SecureStorage? _instance;

  /// Returns the singleton instance, creating it with defaults if needed.
  static SecureStorage get instance {
    _instance ??= SecureStorage._();
    return _instance!;
  }

  /// Overrides the default platform options before storage is first used.
  ///
  /// Call this BEFORE [BaabaStorage.init] if you need custom behaviour, e.g.
  /// different keychain accessibility on iOS or a custom Android keystore alias.
  ///
  /// All parameters are optional — omit any platform you don't need to customise.
  ///
  /// Example:
  ///   SecureStorage.configure(
  ///     androidOptions: const AndroidOptions(encryptedSharedPreferences: true),
  ///     iosOptions: const IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  ///   );
  ///   await BaabaStorage.init();
  static void configure({
    AndroidOptions? androidOptions,
    IOSOptions? iosOptions,
    LinuxOptions? linuxOptions,
    WindowsOptions? windowsOptions,
    WebOptions? webOptions,
    MacOsOptions? macOsOptions,
  }) {
    // Replace the singleton with a freshly configured instance.
    _instance = SecureStorage._(
      storage: FlutterSecureStorage(
        // Fall back to sensible defaults for any platform not explicitly configured.
        aOptions: androidOptions ??
            const AndroidOptions(encryptedSharedPreferences: true),
        iOptions: iosOptions ?? const IOSOptions(),
        lOptions: linuxOptions ?? const LinuxOptions(),
        wOptions: windowsOptions ?? const WindowsOptions(),
        webOptions: webOptions ?? const WebOptions(),
        mOptions: macOsOptions ?? const MacOsOptions(),
      ),
    );
  }

  // ── Core CRUD ─────────────────────────────────────────────────────────────
  // Low-level read/write/delete — use these for anything not covered by
  // the token/header convenience methods below.

  /// Encrypts [value] and stores it under [key].
  ///
  /// If a value already exists for [key], it is overwritten.
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  /// Reads and decrypts the value stored under [key].
  ///
  /// Returns `null` if the key has never been written.
  Future<String?> read(String key) => _storage.read(key: key);

  /// Reads the value stored under [key], returning [defaultValue] if absent.
  ///
  /// Useful when you always need a non-null value:
  ///   final locale = await secure.readOrDefault('locale', 'en');
  Future<String> readOrDefault(String key, String defaultValue) async =>
      (await _storage.read(key: key)) ?? defaultValue;

  /// Deletes the value stored under [key].
  /// Does nothing if the key doesn't exist.
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Deletes ALL keys and values from secure storage.
  /// Use with caution — this wipes every secret including tokens.
  Future<void> deleteAll() => _storage.deleteAll();

  /// Reads every key/value pair from secure storage as a [Map<String, String>].
  /// Useful for debugging (log carefully — values are secrets!).
  Future<Map<String, String>> readAll() => _storage.readAll();

  /// Returns `true` if a value has been stored under [key].
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  // ── Auth token shortcuts ──────────────────────────────────────────────────
  // The most common use case for secure storage is a single auth token.
  // These methods give it a dedicated key so you don't need to manage
  // the key string yourself.

  /// Saves an auth/bearer token securely.
  ///
  /// [key] defaults to `'baaba_auth_token'`. Override it if you need
  /// to store multiple independent tokens (e.g. access + refresh).
  ///
  /// Example:
  ///   await secure.saveToken('Bearer eyJhbGciOiJIUzI1NiIs...');
  Future<void> saveToken(String token, {String key = _defaultTokenKey}) =>
      write(key, token);

  /// Reads the saved auth token.
  ///
  /// Returns `null` if no token has been saved yet (user not logged in).
  Future<String?> getToken({String key = _defaultTokenKey}) => read(key);

  /// Returns `true` if an auth token has been saved.
  /// Use this at app start to decide whether to show login or home screen.
  Future<bool> hasToken({String key = _defaultTokenKey}) =>
      containsKey(key);

  /// Deletes the saved auth token.
  /// Call this on logout.
  Future<void> deleteToken({String key = _defaultTokenKey}) => delete(key);

  // ── Multiple header storage ───────────────────────────────────────────────
  // Some APIs need multiple headers per request, e.g.:
  //   Authorization: Bearer <token>
  //   X-Api-Key: <key>
  // These methods let you save and restore that whole map securely.
  // Each header is stored as a separate secure key with a shared prefix,
  // so they can all be retrieved together with a single readAll call.

  /// Saves a [Map] of HTTP headers to secure storage.
  ///
  /// Each entry is stored as its own secure key using [prefix] + header name.
  /// Default prefix: `'baaba_header_'`.
  ///
  /// Example:
  ///   await secure.saveAuthHeaders({
  ///     'Authorization': 'Bearer eyJ...',
  ///     'X-Api-Key': 'my-secret',
  ///   });
  Future<void> saveAuthHeaders(
    Map<String, String> headers, {
    String prefix = _defaultHeaderPrefix,
  }) async {
    // Store each header individually so they can be read back as a group.
    for (final entry in headers.entries) {
      // Key stored on disk: e.g. 'baaba_header_Authorization'
      await write('$prefix${entry.key}', entry.value);
    }
  }

  /// Reads back all headers previously saved with [saveAuthHeaders].
  ///
  /// Strips the [prefix] from keys so the returned map looks like normal
  /// HTTP headers: `{'Authorization': 'Bearer ...', 'X-Api-Key': '...'}`.
  ///
  /// You can pass this map directly to Dio or http:
  ///   dio.options.headers = await secure.getAuthHeaders();
  Future<Map<String, String>> getAuthHeaders({
    String prefix = _defaultHeaderPrefix,
  }) async {
    // Read everything from secure storage, then filter by our prefix.
    final all = await readAll();
    return {
      for (final e in all.entries)
        // Only include entries whose key starts with our prefix.
        if (e.key.startsWith(prefix))
          // Strip the prefix to restore the original header name.
          e.key.substring(prefix.length): e.value,
    };
  }

  /// Deletes all headers that were saved with [saveAuthHeaders].
  /// Call this on logout alongside [deleteToken].
  Future<void> deleteAuthHeaders({
    String prefix = _defaultHeaderPrefix,
  }) async {
    final all = await readAll();
    for (final key in all.keys) {
      // Delete every key that belongs to our headers namespace.
      if (key.startsWith(prefix)) await delete(key);
    }
  }
}
