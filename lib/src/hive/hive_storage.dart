// ─────────────────────────────────────────────────────────────────────────────
// hive_storage.dart
//
// A singleton wrapper around the Hive local database package.
//
// Hive stores data in typed "boxes" (think of each box as a table or file).
// Unlike SharedPreferences, Hive supports any serializable type:
//   - Primitives (String, int, double, bool)
//   - Collections (List, Map)
//   - Custom Dart objects (with a registered TypeAdapter)
//
// It also supports reactive UI via ValueListenable and Stream<BoxEvent>,
// meaning your widgets can automatically rebuild when data changes.
//
// Typical usage:
//   await BaabaStorage.hive.openBox('settings');
//   await BaabaStorage.hive.put('settings', 'theme', 'dark');
//   final theme = BaabaStorage.hive.get<String>('settings', 'theme');
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../exceptions/storage_exception.dart';

/// Wraps [Hive] with a clean singleton API.
///
/// Do not instantiate directly — access via [BaabaStorage.hive]
/// or [HiveStorage.instance] after calling [BaabaStorage.init].
class HiveStorage {
  // Private constructor — prevents instantiation from outside this class.
  HiveStorage._();

  /// The single instance of this class.
  static HiveStorage? _instance;

  /// Tracks whether [init] has been called.
  /// Guards all methods against being used before initialisation.
  static bool _initialized = false;

  /// Returns the singleton instance, creating it if needed.
  static HiveStorage get instance {
    _instance ??= HiveStorage._();
    return _instance!;
  }

  /// Initialises Hive using the app's documents directory.
  ///
  /// [subDir] is an optional folder name inside documents, e.g. 'hive_data'.
  /// If omitted, Hive files are stored directly in the documents root.
  ///
  /// Called automatically by [BaabaStorage.init].
  static Future<void> init({String? subDir}) async {
    // initFlutter resolves the correct storage path for each platform
    // (Documents on Android/iOS, AppData on Windows, etc.)
    await Hive.initFlutter(subDir);
    _initialized = true;
  }

  /// Initialises Hive with a raw file system path.
  ///
  /// Only use this in unit tests where path_provider is not available.
  /// The @visibleForTesting annotation signals that this is test-only code.
  @visibleForTesting
  static void initForTest(String path) {
    Hive.init(path);
    _initialized = true;
  }

  /// Guards every method — throws [StorageNotInitializedException]
  /// if someone tries to use Hive before calling [init].
  void _ensureInitialized() {
    if (!_initialized) throw const StorageNotInitializedException();
  }

  // ── Box bookkeeping ───────────────────────────────────────────────────────
  //
  // Hive keys every box by name alone, but a name can be open as any one of
  // Box<dynamic>, Box<T> or LazyBox<dynamic> — and Hive gives us no accessor
  // that works across all three. Hive.box<E>(name) throws unless the box is
  // eager *and* its value type is exactly E; Hive.lazyBox<E>(name) is the
  // mirror image. Hive.isBoxOpen, meanwhile, answers for all three.
  //
  // So we remember what we opened — the box *and* the value type it was opened
  // with, because Dart generics are covariant and `box is Box<dynamic>` is
  // therefore true of a Box<UserProfile> as well. Recording the type is the
  // only way to tell the two apart.
  //
  // That bookkeeping lets us route each operation to the widest type that
  // supports it (BoxBase for anything both flavours share, Box only for the
  // value-in-memory reads) and raise our own exception naming the caller's
  // mistake, instead of a HiveError from Hive's internals.

  /// Every box this wrapper knows to be open, keyed by [_key].
  final Map<String, _OpenBox> _openedBoxes = <String, _OpenBox>{};

  /// Canonical map key for a box name.
  ///
  /// Hive lower-cases box names when opening them, so `openBox('Cache')` and
  /// `get('cache', …)` are the same box. We follow the same rule so our
  /// bookkeeping can never drift from Hive's.
  static String _key(String name) => name.toLowerCase();

  /// Records [box] — opened with value type [valueType] and encryption intent
  /// [encrypted] — and returns it.
  ///
  /// [encrypted] is `null` for a box this wrapper adopted rather than opened
  /// itself: Hive gives us no way to ask an open box whether it has a cipher,
  /// so "unknown" is the only honest answer there. See [_checkEncryption].
  B _remember<B extends BoxBase<dynamic>>(
    String name,
    B box,
    Type valueType,
    bool? encrypted,
  ) {
    _openedBoxes[_key(name)] = _OpenBox(box, valueType, encrypted);
    return box;
  }

  /// Returns the record for the open box named [name], or `null` if there is
  /// none this wrapper can reach.
  ///
  /// Prefers our own record — the only thing that knows the box's flavour and
  /// value type — and falls back to probing Hive so that boxes opened outside
  /// this wrapper (e.g. a bare `Hive.openLazyBox` elsewhere in your app) still
  /// work through the facade. A box opened elsewhere with a non-dynamic value
  /// type cannot be adopted; that returns `null` too, and callers report it
  /// separately from "not open".
  _OpenBox? _lookup(String name) {
    final key = _key(name);

    final tracked = _openedBoxes[key];
    if (tracked != null) {
      if (tracked.box.isOpen) return tracked;
      // Closed behind our back — box.close(), Hive.close(), deleteFromDisk().
      _openedBoxes.remove(key);
    }

    if (!Hive.isBoxOpen(key)) return null;

    // Open, but not by us. Probe both flavours; at most one can succeed, and
    // only for a dynamic box — the probes ask for value type dynamic.
    try {
      _remember(key, Hive.box<dynamic>(key), dynamic, null);
      return _openedBoxes[key];
    } on HiveError {
      // Not an eager dynamic box.
    }
    try {
      _remember(key, Hive.lazyBox<dynamic>(key), dynamic, null);
      return _openedBoxes[key];
    } on HiveError {
      // Open with some value type other than dynamic — out of our reach.
      return null;
    }
  }

  /// Thrown when a box is open with a value type we cannot address.
  Never _throwUnadoptable(String name) => throw BoxTypeMismatchException(
        name,
        wanted: 'a dynamic box',
        actual: 'a typed box opened outside BaabaStorage',
        hint: 'Open it with BaabaStorage.hive.openTypedBox<T>("$name") so '
            'BaabaStorage can track it, or use the Box<T> that Hive returned.',
      );

  // ── Encryption bookkeeping ────────────────────────────────────────────────
  //
  // Hive's own openBox short-circuits on an already-open box and, in its words,
  // "all provided parameters are being ignored" — encryptionCipher included.
  // For every other parameter that is merely surprising; for a cipher it is a
  // confidentiality hole, because the caller gets a plaintext box back and no
  // indication that the encryption they asked for did not happen.
  //
  // So the flavour we record per box (see [_OpenBox]) carries its encryption
  // intent too, and every opener checks the request against it.

  /// Throws [BoxEncryptionMismatchException] if reusing an already-open box
  /// whose encryption intent was [actual] would not honour a request made with
  /// [cipher].
  ///
  /// `actual == null` is the adopted-box case — open, but not opened by us, so
  /// its cipher is unknowable. Requesting encryption on such a box throws: an
  /// unverifiable claim of encryption is not one this package will make.
  /// Requesting a plaintext box does not, which is what keeps every pre-1.3.0
  /// call site behaving exactly as it did.
  void _checkEncryption(String name, bool? actual, HiveCipher? cipher) {
    final wanted = cipher != null;
    if (actual == wanted) return;
    if (actual == null && !wanted) return;
    throw BoxEncryptionMismatchException(
      name,
      wantedEncrypted: wanted,
      actualEncrypted: actual,
    );
  }

  /// Resolves the `crashRecovery` flag handed to Hive.
  ///
  /// Hive defaults this to `true`. A box's frame checksums are computed over
  /// the encryption key (`cipher.calculateKeyCrc()`), so opening a cleartext
  /// box with a cipher — or an encrypted box with the wrong key — fails the
  /// checksum on the very first frame. Original Hive treated that as
  /// corruption under crash recovery and truncated the file to an empty box,
  /// silently. hive_ce (2.20.1+) instead throws a `HiveError` when the first
  /// frame is complete but unreadable, before touching the file, and keeps
  /// truncation for what a crash can actually leave: an incomplete frame at
  /// the end.
  ///
  /// A ciphered open still defaults to `false`, as defence in depth: for an
  /// encrypted box a key that does not match is overwhelmingly more likely
  /// than a damaged file — a Keystore entry lost to a device restore, say — so
  /// any checksum failure should reach the caller as a `HiveError` rather than
  /// be "recovered" by discarding frames. Callers who want Hive's default can
  /// still pass it explicitly.
  static bool _resolveCrashRecovery(bool? crashRecovery, HiveCipher? cipher) =>
      crashRecovery ?? (cipher == null);

  /// Internal helper for every operation that exists on both `Box` and
  /// `LazyBox` — i.e. everything declared on [BoxBase]: put, putAll, delete,
  /// deleteAll, clear, keys, containsKey, length, isEmpty, watch, close.
  ///
  /// These are legal on a lazy box, so routing them through [BoxBase] rather
  /// than [Box] is what makes lazy boxes usable through this wrapper at all.
  BoxBase<dynamic> _boxBase(String name) {
    _ensureInitialized();
    final entry = _lookup(name);
    if (entry != null) return entry.box;
    if (Hive.isBoxOpen(name)) _throwUnadoptable(name);
    throw BoxNotOpenException(name);
  }

  /// Internal helper for the three operations that only a regular [Box] can
  /// serve — `get`, `getAll` and `listenable` — because they hand back values
  /// synchronously, which a lazy box cannot do.
  ///
  /// A typed `Box<T>` is fine here: reading from it through a `Box<dynamic>`
  /// view is safe, it is only writes that have to respect T.
  ///
  /// [operation] names the caller for the error message, e.g. `'get()'`.
  Box<dynamic> _box(String name, String operation) {
    final box = _boxBase(name);
    if (box is! Box<dynamic>) throw BoxIsLazyException(name, operation);
    return box;
  }

  // ── Adapter registration ──────────────────────────────────────────────────
  // TypeAdapters tell Hive how to serialise/deserialise custom Dart objects.
  // You must register an adapter before opening a box that stores that type.

  /// Registers a [TypeAdapter] so Hive can serialise/deserialise type [T].
  ///
  /// Call this before [openTypedBox] for that type.
  /// If [override] is true, replaces an already-registered adapter for the
  /// same typeId — useful during development.
  ///
  /// Example (using hive_ce_generator):
  ///   BaabaStorage.hive.registerAdapter(UserProfileAdapter());
  void registerAdapter<T>(TypeAdapter<T> adapter, {bool override = false}) {
    _ensureInitialized();
    Hive.registerAdapter<T>(adapter, override: override);
  }

  /// Returns `true` if an adapter with [typeId] has already been registered.
  /// Use this to avoid duplicate registration errors on hot restart.
  bool isAdapterRegistered(int typeId) {
    _ensureInitialized();
    return Hive.isAdapterRegistered(typeId);
  }

  // ── Box management ────────────────────────────────────────────────────────
  // A "box" is Hive's equivalent of a table or a file.
  // You must open a box before reading from or writing to it.
  // It is safe to call openBox multiple times — if the box is already open,
  // it simply returns the existing instance.

  /// Opens (or returns the already-open) dynamic box named [name].
  ///
  /// Use this for storing primitives, Maps, and Lists.
  /// The box persists on disk across app restarts.
  ///
  /// Example:
  ///   await BaabaStorage.hive.openBox('settings');
  ///
  /// **Encryption.** Pass [encryptionCipher] to store the box AES-256 encrypted
  /// on disk — the fix for a box holding anything a device thief should not be
  /// able to read (identity documents, biometrics, health data). Keys, tokens
  /// and PII belong behind a cipher; a cache of public reference data does not
  /// need one. [BaabaStorage.hiveCipher] resolves a per-install key out of
  /// Keystore-backed secure storage:
  ///
  /// ```dart
  /// await BaabaStorage.hive.openBox(
  ///   'citizens',
  ///   encryptionCipher: await BaabaStorage.hiveCipher(),
  /// );
  /// ```
  ///
  /// **A box that already holds cleartext data cannot simply be reopened with a
  /// cipher.** Hive folds the encryption key into every frame's checksum, so an
  /// existing plaintext file fails to decode and the open throws. Adopting
  /// encryption on live data means migrating it: read every entry from the
  /// plaintext box, write it to a new encrypted box, then delete the original.
  /// Adding the parameter on its own does not migrate anything.
  ///
  /// [crashRecovery] defaults to `false` when a cipher is supplied and `true`
  /// otherwise — see [_resolveCrashRecovery] for why that difference matters
  /// far more than it looks.
  ///
  /// Throws [BoxTypeMismatchException] if [name] is already open as a lazy box
  /// or as a typed box, and [BoxEncryptionMismatchException] if it is already
  /// open with a different encryption intent than the one requested here.
  Future<Box<dynamic>> openBox(
    String name, {
    HiveCipher? encryptionCipher,
    bool? crashRecovery,
  }) async {
    _ensureInitialized();
    // If the box is already open (e.g. called twice), just return it.
    final existing = _lookup(name);
    if (existing != null) {
      if (existing.box is! Box<dynamic> || existing.valueType != dynamic) {
        throw BoxTypeMismatchException(
          name,
          wanted: 'a regular box',
          actual: existing.describe(),
          hint: 'Use ${existing.opener(name)}, or close the box first.',
        );
      }
      _checkEncryption(name, existing.encrypted, encryptionCipher);
      return existing.box as Box<dynamic>;
    }
    if (Hive.isBoxOpen(name)) _throwUnadoptable(name);
    return _remember(
      name,
      await Hive.openBox<dynamic>(
        name,
        encryptionCipher: encryptionCipher,
        crashRecovery: _resolveCrashRecovery(crashRecovery, encryptionCipher),
      ),
      dynamic,
      encryptionCipher != null,
    );
  }

  /// Opens (or returns the already-open) typed box named [name].
  ///
  /// Use this when [E] has a registered [TypeAdapter] (custom objects).
  /// The generic parameter [E] must match the type used when this box
  /// was first opened — mixing types on the same box name will throw.
  ///
  /// Example:
  ///   BaabaStorage.hive.registerAdapter(UserProfileAdapter());
  ///   await BaabaStorage.hive.openTypedBox`<UserProfile>`('profiles');
  ///
  /// Pass [encryptionCipher] to encrypt the box at rest — the same rules and
  /// the same migration caveat as [openBox], which documents both. A box of
  /// custom objects is the usual home for the PII worth encrypting.
  Future<Box<E>> openTypedBox<E>(
    String name, {
    HiveCipher? encryptionCipher,
    bool? crashRecovery,
  }) async {
    _ensureInitialized();
    final key = _key(name);

    final tracked = _openedBoxes[key];
    if (tracked != null && tracked.box.isOpen) {
      final box = tracked.box;
      if (box is! Box<E> || tracked.valueType != E) {
        throw BoxTypeMismatchException(
          name,
          wanted: 'Box<$E>',
          actual: tracked.describe(),
          hint: 'Close the box before reopening it with another type.',
        );
      }
      _checkEncryption(name, tracked.encrypted, encryptionCipher);
      return box;
    }
    _openedBoxes.remove(key);

    // Opened elsewhere — let Hive resolve it against the requested type. Its
    // cipher is unknowable, so the box is recorded as such and the encryption
    // check decides whether it can be handed out for this request.
    if (Hive.isBoxOpen(key)) {
      final Box<E> adopted;
      try {
        adopted = _remember(key, Hive.box<E>(key), E, null);
      } on HiveError catch (e) {
        throw BoxTypeMismatchException(
          name,
          wanted: 'Box<$E>',
          actual: 'a box of another type',
          hint: e.message,
        );
      }
      _checkEncryption(name, null, encryptionCipher);
      return adopted;
    }
    return _remember(
      key,
      await Hive.openBox<E>(
        name,
        encryptionCipher: encryptionCipher,
        crashRecovery: _resolveCrashRecovery(crashRecovery, encryptionCipher),
      ),
      E,
      encryptionCipher != null,
    );
  }

  /// Opens a lazy box — values are only read from disk when accessed,
  /// making it more memory-efficient for large data sets.
  ///
  /// Every write and metadata operation on this wrapper works on a lazy box.
  /// Reads must use the async [getLazy] / [getAllLazy]; the synchronous [get],
  /// [getAll] and [listenable] throw [BoxIsLazyException].
  ///
  /// Pass [encryptionCipher] to encrypt the box at rest — the same rules and
  /// the same migration caveat as [openBox], which documents both. A lazy box
  /// pays the decryption cost per read rather than all at once on open, which
  /// is usually what you want for a large encrypted box.
  ///
  /// Throws [BoxTypeMismatchException] if [name] is already open eagerly, and
  /// [BoxEncryptionMismatchException] if it is already open with a different
  /// encryption intent than the one requested here.
  Future<LazyBox<dynamic>> openLazyBox(
    String name, {
    HiveCipher? encryptionCipher,
    bool? crashRecovery,
  }) async {
    _ensureInitialized();
    final existing = _lookup(name);
    if (existing != null) {
      final box = existing.box;
      if (box is! LazyBox<dynamic> || existing.valueType != dynamic) {
        throw BoxTypeMismatchException(
          name,
          wanted: 'a lazy box',
          actual: existing.describe(),
          hint: 'Use ${existing.opener(name)}, or close the box first.',
        );
      }
      _checkEncryption(name, existing.encrypted, encryptionCipher);
      return box;
    }
    if (Hive.isBoxOpen(name)) _throwUnadoptable(name);
    return _remember(
      name,
      await Hive.openLazyBox<dynamic>(
        name,
        encryptionCipher: encryptionCipher,
        crashRecovery: _resolveCrashRecovery(crashRecovery, encryptionCipher),
      ),
      dynamic,
      encryptionCipher != null,
    );
  }

  /// Returns `true` if a file for the box named [name] is present on disk,
  /// without opening it.
  ///
  /// This exists to tell two situations apart that need completely different
  /// handling, and that are otherwise indistinguishable:
  ///
  ///   * **No box, first run.** Nothing on disk. Generate a key, open an
  ///     encrypted box, carry on.
  ///   * **Box on disk, key gone.** The `.hive` file is there but the key that
  ///     decrypts it is not — a restore onto a new device, a wiped Keystore, a
  ///     cleared app data directory. Opening it with a freshly generated key
  ///     cannot work and must not be attempted.
  ///
  /// In the second case the data is unrecoverable, and the only correct
  /// responses are to tell the user and re-fetch, or to delete the box
  /// deliberately with [deleteBox]. What you must not do is generate a new key
  /// and open the box anyway: the open throws, and the old key is still the
  /// only thing that can ever read the file.
  ///
  /// ```dart
  /// final onDisk = await BaabaStorage.hive.boxExistsOnDisk('citizens');
  /// final hasKey = await BaabaStorage.secure.containsKey('baaba_hive_key');
  /// if (onDisk && !hasKey) {
  ///   // Encrypted data we can no longer read. Do not open it.
  /// }
  /// ```
  ///
  /// Note this reports on any file Hive keeps for the name — `.hive`, `.hivec`
  /// or a leftover `.lock` — so it answers "something is on disk for this box",
  /// which is the question that matters here.
  Future<bool> boxExistsOnDisk(String name) async {
    _ensureInitialized();
    return Hive.boxExists(name);
  }

  /// Returns `true` if the box with [name] is currently open.
  bool isBoxOpen(String name) {
    _ensureInitialized();
    return Hive.isBoxOpen(name);
  }

  /// Returns `true` if [name] is open *and* was opened lazily.
  ///
  /// Use this when generic code needs to choose between [get] and [getLazy].
  /// Returns `false` for a box that is not open.
  bool isBoxLazy(String name) {
    _ensureInitialized();
    return _lookup(name)?.box.lazy ?? false;
  }

  /// Closes the box with [name], flushing any pending writes to disk.
  /// Does nothing if the box is already closed.
  ///
  /// Works on lazy and typed boxes as well as plain ones — this is the call a
  /// "log out and clear storage" path usually reaches for.
  Future<void> closeBox(String name) async {
    final entry = _lookup(name);
    _openedBoxes.remove(_key(name));
    if (entry != null) await entry.box.close();
  }

  /// Permanently deletes the box file from disk.
  /// All data in that box is lost and cannot be recovered.
  Future<void> deleteBox(String name) async {
    _ensureInitialized();
    _openedBoxes.remove(_key(name));
    await Hive.deleteBoxFromDisk(name);
  }

  /// Closes all open boxes. Call this when the app is shutting down
  /// to ensure all data is safely flushed to disk.
  Future<void> closeAll() async {
    _openedBoxes.clear();
    await Hive.close();
  }

  // ── Data operations ───────────────────────────────────────────────────────

  /// Stores [value] in [boxName] under [key].
  ///
  /// [key] can be a [String] or an [int] (Hive supports both).
  /// The box must be open before calling this — see [openBox].
  ///
  /// Example:
  ///   await BaabaStorage.hive.put('settings', 'fontSize', 16.0);
  Future<void> put<E>(String boxName, dynamic key, E value) =>
      _boxBase(boxName).put(key, value);

  /// Stores multiple key/value pairs in [boxName] in a single write operation.
  /// More efficient than calling [put] in a loop.
  ///
  /// [E] is normally inferred from [entries]. It is generic rather than
  /// `Map<dynamic, dynamic>` so that a typed box works too: Hive checks the map
  /// against the box's value type as a whole, and a `Map<dynamic, dynamic>`
  /// never satisfies a `Box<UserProfile>` even when every value is one.
  ///
  /// Example:
  ///   await BaabaStorage.hive.putAll('config', {'a': 1, 'b': 2, 'c': 3});
  Future<void> putAll<E>(String boxName, Map<dynamic, E> entries) =>
      _boxBase(boxName).putAll(entries);

  /// Reads the value stored under [key] in [boxName] and casts it to [E].
  ///
  /// Returns [defaultValue] if:
  ///   - the key does not exist in the box
  ///   - the stored value cannot be cast to [E]
  ///
  /// Not available on a lazy box — throws [BoxIsLazyException]. Use [getLazy].
  ///
  /// Example:
  ///   final theme = BaabaStorage.hive.get`<String>`('settings', 'theme', defaultValue: 'light');
  E? get<E>(String boxName, dynamic key, {E? defaultValue}) {
    // Retrieve raw value (untyped) from the box.
    final raw = _box(boxName, 'get()').get(key);

    return _cast<E>(raw, defaultValue);
  }

  /// Reads the value stored under [key] in [boxName] and casts it to [E],
  /// awaiting the disk read that a lazy box defers until now.
  ///
  /// Works on both lazy and regular boxes, so code that does not know (or care)
  /// how a box was opened can always use this. Returns [defaultValue] on a
  /// missing key or a type mismatch, exactly like [get].
  ///
  /// Example:
  ///   await BaabaStorage.hive.openLazyBox('blobs');
  ///   final blob = await BaabaStorage.hive.getLazy`<String>`('blobs', 'report');
  Future<E?> getLazy<E>(String boxName, dynamic key, {E? defaultValue}) async {
    final box = _boxBase(boxName);
    final raw =
        box is LazyBox<dynamic> ? await box.get(key) : (box as Box<dynamic>).get(key);

    return _cast<E>(raw, defaultValue);
  }

  /// Shared cast used by [get] and [getLazy].
  static E? _cast<E>(dynamic raw, E? defaultValue) {
    if (raw == null) return defaultValue;

    try {
      // Cast the raw dynamic value to the expected type E.
      return raw as E;
    } on TypeError {
      // The stored type doesn't match E — return default instead of crashing.
      return defaultValue;
    }
  }

  /// Removes the entry with [key] from [boxName].
  Future<void> delete(String boxName, dynamic key) =>
      _boxBase(boxName).delete(key);

  /// Removes all entries whose keys are in [keys] from [boxName].
  Future<void> deleteKeys(String boxName, Iterable<dynamic> keys) =>
      _boxBase(boxName).deleteAll(keys);

  /// Removes every entry from [boxName].
  /// Returns the number of entries that were deleted.
  /// The box itself remains open and can be reused.
  Future<int> clearBox(String boxName) => _boxBase(boxName).clear();

  /// Returns all values stored in [boxName], cast to [E].
  ///
  /// Not available on a lazy box — throws [BoxIsLazyException]. Use [getAllLazy].
  ///
  /// Example:
  ///   final allScores = BaabaStorage.hive.getAll`<int>`('scores');
  Iterable<E> getAll<E>(String boxName) =>
      _box(boxName, 'getAll()').values.cast<E>();

  /// Returns all values stored in [boxName], reading each one from disk.
  ///
  /// Works on both lazy and regular boxes. Unlike [getAll], which casts lazily
  /// and throws on the first value that is not an [E], this **skips** values of
  /// the wrong type — a lazy box has already paid for the read by the time the
  /// mismatch is visible, and skipping keeps one bad row from killing the scan.
  ///
  /// Example:
  ///   final pending = await BaabaStorage.hive.getAllLazy`<String>`('queue');
  Future<List<E>> getAllLazy<E>(String boxName) async {
    final box = _boxBase(boxName);
    if (box is! LazyBox<dynamic>) {
      return (box as Box<dynamic>).values.cast<E>().toList();
    }

    final values = <E>[];
    for (final key in box.keys) {
      final raw = await box.get(key);
      if (raw is E) values.add(raw);
    }
    return values;
  }

  /// Returns all keys in [boxName].
  /// Keys can be Strings or ints depending on how data was stored.
  Iterable<dynamic> getKeys(String boxName) => _boxBase(boxName).keys;

  /// Returns `true` if [key] exists in [boxName].
  bool containsKey(String boxName, dynamic key) =>
      _boxBase(boxName).containsKey(key);

  /// Returns the number of entries currently stored in [boxName].
  int length(String boxName) => _boxBase(boxName).length;

  /// Returns `true` if [boxName] has no entries.
  bool isEmpty(String boxName) => _boxBase(boxName).isEmpty;

  // ── Reactive helpers ──────────────────────────────────────────────────────
  // These allow your UI to react automatically when Hive data changes,
  // without manually calling setState or notifyListeners.

  /// Returns a [Stream] of [BoxEvent]s that fires whenever data in
  /// [boxName] changes (put or delete).
  ///
  /// Pass [key] to only listen to changes on a specific key.
  ///
  /// Example — log every change in a box:
  ///   BaabaStorage.hive.watch('orders').listen((event) {
  ///     print('Key ${event.key} changed to ${event.value}');
  ///   });
  Stream<BoxEvent> watch(String boxName, {dynamic key}) =>
      _boxBase(boxName).watch(key: key);

  /// Returns a [ValueListenable] for use with [ValueListenableBuilder].
  ///
  /// The widget rebuilds automatically whenever the box changes.
  /// Pass [keys] to limit rebuilds to specific keys only.
  ///
  /// Example:
  ///   `ValueListenableBuilder<Box<dynamic>>`(
  ///     valueListenable: BaabaStorage.hive.listenable('settings'),
  ///     builder: (context, box, _) {
  ///       return Text(box.get('theme') ?? 'light');
  ///     },
  ///   );
  /// Not available on a lazy box — throws [BoxIsLazyException]. Listen with
  /// [watch] instead and read values through [getLazy].
  ValueListenable<Box<dynamic>> listenable(
    String boxName, {
    List<dynamic>? keys,
  }) =>
      _box(boxName, 'listenable()').listenable(keys: keys);
}

/// One open box, plus the value type it was opened with.
///
/// The type has to be carried alongside the box because Dart generics are
/// covariant: `Box<UserProfile> is Box<dynamic>` is `true`, so the box object
/// alone cannot tell us whether `openBox` may hand it out as a dynamic box.
class _OpenBox {
  const _OpenBox(this.box, this.valueType, this.encrypted);

  final BoxBase<dynamic> box;

  /// The `E` in `Box<E>` / `LazyBox<E>`, i.e. `dynamic` for an untyped box.
  final Type valueType;

  /// Whether this box was opened with an [HiveCipher].
  ///
  /// `null` means unknown: the box was already open when this wrapper first
  /// saw it, and Hive exposes nothing that would tell us after the fact whether
  /// a cipher was involved. That is a third state, not a `false` — treating
  /// "unknown" as "unencrypted" would let a caller believe a box is plaintext
  /// when it is not, and treating it as `true` would be worse still.
  final bool? encrypted;

  /// How this box is open, phrased for an exception message.
  String describe() {
    if (valueType == dynamic) return box.lazy ? 'a lazy box' : 'a regular box';
    return box.lazy ? 'LazyBox<$valueType>' : 'Box<$valueType>';
  }

  /// The call that would return this box, suggested in an exception message.
  String opener(String name) {
    if (valueType != dynamic) return 'openTypedBox<$valueType>("$name")';
    return box.lazy ? 'openLazyBox("$name")' : 'openBox("$name")';
  }
}
