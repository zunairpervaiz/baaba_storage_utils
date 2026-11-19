// ─────────────────────────────────────────────────────────────────────────────
// baaba_hive.dart
//
// The entry point for Hive boxes, kept in a package of its own so that apps
// needing only prefs and secure storage do not carry Hive.
//
// It builds on baaba_storage_utils rather than standing beside it, for one
// reason: the AES key that encrypts boxes lives in that package's
// SecureStorage. So [BaabaStorage.init] still runs first, and [BaabaHive.cipher]
// refuses to run without it.
//
// Dart has no static extension members, so this cannot add a `hive` getter to
// BaabaStorage from outside; it is a sibling facade instead.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:baaba_storage_utils/baaba_storage_utils.dart';
import 'package:hive_ce/hive_ce.dart';

import 'hive_cipher.dart';
import 'hive_storage.dart';

/// The entry point for Hive boxes.
///
/// **Initialise once in main(), after [BaabaStorage.init]:**
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await BaabaStorage.init();
///   await BaabaHive.init();
///   runApp(const MyApp());
/// }
/// ```
///
/// **Then use anywhere:**
/// ```dart
/// await BaabaHive.instance.openBox('cache');
/// await BaabaHive.instance.put('cache', 'user', userMap);
///
/// await BaabaHive.instance.openBox(
///   'citizens',
///   encryptionCipher: await BaabaHive.cipher(),
/// );
/// ```
class BaabaHive {
  // Never instantiated; all members are static.
  BaabaHive._();

  static bool _initialized = false;

  /// Returns `true` if [init] has already been called.
  static bool get isInitialized => _initialized;

  /// Initialises Hive in the app's documents directory.
  ///
  /// [subDir] is an optional folder inside it, e.g. `'hive_data'`. Leave it
  /// null to keep the `.hive` files in the documents root — which is where
  /// `BaabaStorage.init()` put them before 3.0.0, so an app upgrading from 2.x
  /// must pass the same value it passed there as `hiveSubDir`, or it will open
  /// empty boxes in a different directory.
  ///
  /// Does not need [BaabaStorage.init] — opening plaintext boxes works without
  /// it — but [cipher] does, so call that first in any app that encrypts.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> init({String? subDir}) async {
    if (_initialized) return;
    await HiveStorage.init(subDir: subDir);
    _initialized = true;
  }

  /// The Hive box wrapper: open, read, write, watch.
  ///
  /// Throws [StorageNotInitializedException] if [init] has not been called.
  ///
  /// Example:
  ///   await BaabaHive.instance.openBox('orders');
  ///   await BaabaHive.instance.put('orders', 'latest', orderMap);
  static HiveStorage get instance {
    if (!_initialized) throw hiveNotInitializedException;
    return HiveStorage.instance;
  }

  // ── Encryption ────────────────────────────────────────────────────────────

  /// The secure-storage key under which [cipher] keeps its encryption key.
  ///
  /// Use this instead of hardcoding the string when you need to check whether
  /// the key is present:
  ///   final hasKey = await BaabaStorage.secure.containsKey(BaabaHive.keyAlias);
  ///
  /// Same value as 2.x's `BaabaStorage.hiveKeyAlias`, so boxes encrypted
  /// before the split keep opening with the key they were written with.
  static const String keyAlias = defaultHiveKeyAlias;

  /// Returns the [HiveCipher] that encrypts Hive boxes at rest, resolving a
  /// stable per-install AES-256 key out of secure storage and generating one on
  /// first use.
  ///
  /// Pass the result to [HiveStorage.openBox], [HiveStorage.openTypedBox] or
  /// [HiveStorage.openLazyBox]:
  ///
  /// ```dart
  /// await BaabaHive.instance.openBox(
  ///   'citizens',
  ///   encryptionCipher: await BaabaHive.cipher(),
  /// );
  /// ```
  ///
  /// The key is generated from a CSPRNG, stored in the platform's secure
  /// enclave (Keystore / Keychain / DPAPI / libsecret), and never logged or
  /// exposed — what you get back is an opaque cipher. Repeated calls return the
  /// same cipher, so it is safe to call once per box rather than threading one
  /// instance through your app.
  ///
  /// [key] is the secure-storage alias, defaulting to [keyAlias]. Override it
  /// only if you need independently-keyed sets of boxes; two aliases mean two
  /// keys, and a box can only ever be opened with the one it was created with.
  ///
  /// Requires [BaabaStorage.init] — not just [init] — and throws
  /// [StorageNotInitializedException] otherwise. The key is read through the
  /// secure-storage options configured there; reading it with defaults
  /// instead (a different Android `storageNamespace`, say) would find no key,
  /// generate a new one, and leave every existing encrypted box unreadable.
  ///
  /// Throws [StorageException] if a key is already stored under [key] but is
  /// not a valid 32-byte base64 value. That case is deliberately *not* repaired
  /// by generating a new key: any box encrypted with the original would become
  /// permanently unreadable. See also [HiveStorage.boxExistsOnDisk] for telling
  /// "first run" apart from "the key for this box is gone".
  static Future<HiveCipher> cipher({String key = keyAlias}) {
    if (!BaabaStorage.isInitialized) {
      throw const StorageNotInitializedException();
    }
    return HiveKeyStore.resolve(key);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Closes all open Hive boxes, forgets the memoised cipher and resets the
  /// initialisation flag.
  ///
  /// Call this when the app is terminating (e.g. in a WidgetsBindingObserver's
  /// didChangeAppLifecycleState when state == AppLifecycleState.detached).
  ///
  /// If you also re-run [BaabaStorage.init] with different secure-storage
  /// options, call this first: a cipher memoised under the old options would
  /// otherwise keep being returned.
  ///
  /// After calling dispose, [init] must be called again before using Hive.
  static Future<void> dispose() async {
    if (!_initialized) return;
    // Close all Hive boxes to flush pending writes to disk.
    await HiveStorage.instance.closeAll();
    HiveKeyStore.clearCache();
    _initialized = false;
  }
}
