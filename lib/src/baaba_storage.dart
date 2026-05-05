// ─────────────────────────────────────────────────────────────────────────────
// baaba_storage.dart
//
// The single entry point for the entire baaba_storage_utils package.
//
// This file does two things:
//   1. Re-exports all three storage classes and the exception classes so that
//      consumers only ever need to import 'baaba_storage_utils.dart'.
//   2. Defines [BaabaStorage] — the facade that wires everything together,
//      initialises all three backends with one await, and then exposes them
//      as clean, named getters (prefs / hive / secure).
//
// Design pattern used: Facade + Singleton.
//   - Facade  : hides the complexity of initialising three separate packages.
//   - Singleton: ensures there is only ever one set of storage instances
//               across the whole app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'exceptions/storage_exception.dart';
import 'hive/hive_storage.dart';
import 'prefs/prefs_storage.dart';
import 'secure/secure_storage.dart';

// Re-export everything so consumers only need one import:
//   import 'package:baaba_storage_utils/baaba_storage_utils.dart';
export 'exceptions/storage_exception.dart';
export 'hive/hive_storage.dart';
export 'prefs/prefs_storage.dart';
export 'secure/secure_storage.dart';

/// The unified entry point for all storage operations.
///
/// **Step 1 — initialise once in main():**
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await BaabaStorage.init();
///   runApp(const MyApp());
/// }
/// ```
///
/// **Step 2 — use anywhere:**
/// ```dart
/// // Lightweight key/value settings
/// await BaabaStorage.prefs.setBool('darkMode', true);
///
/// // Structured data (lists, maps, custom objects)
/// await BaabaStorage.hive.openBox('cache');
/// await BaabaStorage.hive.put('cache', 'user', userMap);
///
/// // Encrypted secrets (tokens, API keys)
/// await BaabaStorage.secure.saveToken('Bearer eyJ...');
/// ```
class BaabaStorage {
  // Private constructor — this class is never instantiated.
  // All members are static; it acts purely as a namespace.
  BaabaStorage._();

  /// Tracks whether [init] has been called successfully.
  /// Prevents double-initialisation and guards all getters.
  static bool _initialized = false;

  /// Returns `true` if [init] has already been called.
  /// Useful for conditional checks during app startup.
  static bool get isInitialized => _initialized;

  /// Initialises all three storage backends in the correct order.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// **Parameters (all optional):**
  ///
  /// [hiveSubDir] — subfolder inside the app's documents directory where
  /// Hive will store its `.hive` files. Leave null to use the root.
  ///
  /// [secureAndroidOptions] through [secureMacOsOptions] — platform-specific
  /// configuration for Flutter Secure Storage. Sensible defaults are applied
  /// when these are omitted (e.g. `encryptedSharedPreferences: true` on Android).
  static Future<void> init({
    String? hiveSubDir,
    AndroidOptions? secureAndroidOptions,
    IOSOptions? secureIOSOptions,
    LinuxOptions? secureLinuxOptions,
    WindowsOptions? secureWindowsOptions,
    WebOptions? secureWebOptions,
    MacOsOptions? secureMacOsOptions,
  }) async {
    // Guard — if init was already called, do nothing.
    if (_initialized) return;

    // 1. SharedPreferences — async because it reads from disk on first call.
    await PrefsStorage.init();

    // 2. Hive — async because it resolves the storage path via path_provider.
    await HiveStorage.init(subDir: hiveSubDir);

    // 3. SecureStorage — synchronous configuration (actual I/O happens per read/write).
    SecureStorage.configure(
      androidOptions: secureAndroidOptions,
      iosOptions: secureIOSOptions,
      linuxOptions: secureLinuxOptions,
      windowsOptions: secureWindowsOptions,
      webOptions: secureWebOptions,
      macOsOptions: secureMacOsOptions,
    );

    _initialized = true;
  }

  /// Throws [StorageNotInitializedException] if [init] was never called.
  /// Every public getter calls this before returning an instance,
  /// so the developer gets a clear error message instead of a null crash.
  static void _ensureInitialized() {
    if (!_initialized) throw const StorageNotInitializedException();
  }

  // ── Storage accessors ─────────────────────────────────────────────────────
  // These getters are the primary way consumers interact with storage.
  // They all guard against uninitialised access via _ensureInitialized().

  /// Access SharedPreferences for lightweight key/value storage.
  ///
  /// Best for: settings, flags, primitive values.
  /// Supported value types: `String`, `int`, `double`, `bool`, `List<String>`.
  ///
  /// Example:
  ///   await BaabaStorage.prefs.setBool('onboarded', true);
  ///   final onboarded = BaabaStorage.prefs.getBool('onboarded') ?? false;
  static PrefsStorage get prefs {
    _ensureInitialized();
    return PrefsStorage.instance;
  }

  /// Access Hive for structured local storage.
  ///
  /// Best for: lists, maps, custom objects, large or complex data.
  /// Remember to call [HiveStorage.openBox] before reading/writing.
  ///
  /// Example:
  ///   await BaabaStorage.hive.openBox('orders');
  ///   await BaabaStorage.hive.put('orders', 'latest', orderMap);
  static HiveStorage get hive {
    _ensureInitialized();
    return HiveStorage.instance;
  }

  /// Access Flutter Secure Storage for encrypted secrets.
  ///
  /// Best for: auth tokens, API keys, passwords, refresh tokens.
  /// Data is encrypted using the device's secure hardware enclave.
  ///
  /// Example:
  ///   await BaabaStorage.secure.saveToken(response.accessToken);
  ///   final token = await BaabaStorage.secure.getToken();
  static SecureStorage get secure {
    _ensureInitialized();
    return SecureStorage.instance;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Closes all open Hive boxes and resets the initialisation flag.
  ///
  /// Call this when the app is terminating (e.g. in a WidgetsBindingObserver's
  /// didChangeAppLifecycleState when state == AppLifecycleState.detached).
  ///
  /// After calling dispose, [init] must be called again before using storage.
  static Future<void> dispose() async {
    if (!_initialized) return;
    // Close all Hive boxes to flush pending writes to disk.
    await HiveStorage.instance.closeAll();
    _initialized = false;
  }
}
