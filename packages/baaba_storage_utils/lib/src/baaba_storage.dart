// ─────────────────────────────────────────────────────────────────────────────
// baaba_storage.dart
//
// The single entry point for the baaba_storage_utils package.
//
// This file does two things:
//   1. Re-exports both storage classes and the exception classes so that
//      consumers only ever need to import 'baaba_storage_utils.dart'.
//   2. Defines [BaabaStorage] — the facade that wires everything together,
//      initialises both backends with one await, and then exposes them as
//      clean, named getters (prefs / secure).
//
// Hive is not here. It lives in the baaba_storage_hive package, which builds on
// this one (its encryption key is kept in [SecureStorage]) and has its own
// facade, BaabaHive. Keeping it out means an app that only needs prefs and
// secure storage does not pull in hive_ce and hive_ce_flutter, does not
// inherit hive_ce_flutter's Flutter floor, and does not resolve or create a
// Hive directory at startup.
//
// Design pattern used: Facade + Singleton.
//   - Facade  : hides the complexity of initialising separate packages.
//   - Singleton: ensures there is only ever one set of storage instances
//               across the whole app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'exceptions/storage_exception.dart';
import 'prefs/prefs_storage.dart';
import 'secure/secure_storage.dart';

// Re-export everything so consumers only need one import:
//   import 'package:baaba_storage_utils/baaba_storage_utils.dart';
export 'exceptions/storage_exception.dart';
export 'prefs/prefs_storage.dart';
export 'secure/secure_storage.dart';

/// The unified entry point for prefs and secure storage.
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
/// // Encrypted secrets (tokens, API keys)
/// await BaabaStorage.secure.saveToken('Bearer eyJ...');
/// ```
///
/// For Hive boxes, add the `baaba_storage_hive` package and use `BaabaHive`.
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

  /// Initialises both storage backends.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// [secureAndroidOptions] through [secureMacOsOptions] — platform-specific
  /// configuration for Flutter Secure Storage. Passing any of them replaces
  /// the whole secure-storage configuration, with each platform left out
  /// falling back to its OS default. Passing none keeps the current one —
  /// whatever an earlier [SecureStorage.configure] call set, or the defaults.
  static Future<void> init({
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

    // 2. SecureStorage — synchronous configuration (actual I/O happens per
    //    read/write). Only when options were actually passed: configuring with
    //    none would replace an earlier SecureStorage.configure() with the
    //    defaults, silently discarding options such as a storageNamespace —
    //    which is where every secret, including baaba_storage_hive's
    //    encryption key, is read from.
    final hasSecureOptions = secureAndroidOptions != null ||
        secureIOSOptions != null ||
        secureLinuxOptions != null ||
        secureWindowsOptions != null ||
        secureWebOptions != null ||
        secureMacOsOptions != null;
    if (hasSecureOptions) {
      SecureStorage.configure(
        androidOptions: secureAndroidOptions,
        iosOptions: secureIOSOptions,
        linuxOptions: secureLinuxOptions,
        windowsOptions: secureWindowsOptions,
        webOptions: secureWebOptions,
        macOsOptions: secureMacOsOptions,
      );
    }

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

  /// Resets the initialisation flag, so the next [init] applies its options
  /// again.
  ///
  /// Neither SharedPreferences nor secure storage holds anything that needs
  /// closing. If the app uses `baaba_storage_hive`, call `BaabaHive.dispose()`
  /// as well — that is what closes Hive boxes and forgets the memoised
  /// encryption cipher.
  ///
  /// After calling dispose, [init] must be called again before using storage.
  static Future<void> dispose() async {
    _initialized = false;
  }
}
