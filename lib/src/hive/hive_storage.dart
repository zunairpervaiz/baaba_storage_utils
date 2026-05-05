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
import 'package:hive_flutter/hive_flutter.dart';

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

  /// Internal helper that retrieves an already-open box as `Box<dynamic>`.
  ///
  /// We always use `Box<dynamic>` internally (never `Box<String>`, `Box<int>`, etc.)
  /// because Hive throws a runtime error if the same box is opened with
  /// one type and then accessed with a different generic parameter.
  /// By using dynamic everywhere internally and casting at the Dart level
  /// when reading, we avoid that class of errors entirely.
  Box<dynamic> _box(String name) {
    _ensureInitialized();
    // Hive requires the box to be open before any read/write.
    if (!Hive.isBoxOpen(name)) throw BoxNotOpenException(name);
    // Hive.box(name) with no type param returns Box<dynamic>.
    return Hive.box(name);
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
  /// Example (using hive_generator):
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
  Future<Box<dynamic>> openBox(String name) async {
    _ensureInitialized();
    // If the box is already open (e.g. called twice), just return it.
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
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
  Future<Box<E>> openTypedBox<E>(String name) async {
    _ensureInitialized();
    if (Hive.isBoxOpen(name)) return Hive.box<E>(name);
    return Hive.openBox<E>(name);
  }

  /// Opens a lazy box — values are only read from disk when accessed,
  /// making it more memory-efficient for large data sets.
  Future<LazyBox<dynamic>> openLazyBox(String name) async {
    _ensureInitialized();
    if (Hive.isBoxOpen(name)) return Hive.lazyBox(name);
    return Hive.openLazyBox(name);
  }

  /// Returns `true` if the box with [name] is currently open.
  bool isBoxOpen(String name) {
    _ensureInitialized();
    return Hive.isBoxOpen(name);
  }

  /// Closes the box with [name], flushing any pending writes to disk.
  /// Does nothing if the box is already closed.
  Future<void> closeBox(String name) async {
    if (Hive.isBoxOpen(name)) await Hive.box(name).close();
  }

  /// Permanently deletes the box file from disk.
  /// All data in that box is lost and cannot be recovered.
  Future<void> deleteBox(String name) => Hive.deleteBoxFromDisk(name);

  /// Closes all open boxes. Call this when the app is shutting down
  /// to ensure all data is safely flushed to disk.
  Future<void> closeAll() => Hive.close();

  // ── Data operations ───────────────────────────────────────────────────────

  /// Stores [value] in [boxName] under [key].
  ///
  /// [key] can be a [String] or an [int] (Hive supports both).
  /// The box must be open before calling this — see [openBox].
  ///
  /// Example:
  ///   await BaabaStorage.hive.put('settings', 'fontSize', 16.0);
  Future<void> put<E>(String boxName, dynamic key, E value) =>
      _box(boxName).put(key, value);

  /// Stores multiple key/value pairs in [boxName] in a single write operation.
  /// More efficient than calling [put] in a loop.
  ///
  /// Example:
  ///   await BaabaStorage.hive.putAll('config', {'a': 1, 'b': 2, 'c': 3});
  Future<void> putAll(String boxName, Map<dynamic, dynamic> entries) =>
      _box(boxName).putAll(entries);

  /// Reads the value stored under [key] in [boxName] and casts it to [E].
  ///
  /// Returns [defaultValue] if:
  ///   - the key does not exist in the box
  ///   - the stored value cannot be cast to [E]
  ///
  /// Example:
  ///   final theme = BaabaStorage.hive.get`<String>`('settings', 'theme', defaultValue: 'light');
  E? get<E>(String boxName, dynamic key, {E? defaultValue}) {
    // Retrieve raw value (untyped) from the box.
    final raw = _box(boxName).get(key);

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
      _box(boxName).delete(key);

  /// Removes all entries whose keys are in [keys] from [boxName].
  Future<void> deleteKeys(String boxName, Iterable<dynamic> keys) =>
      _box(boxName).deleteAll(keys);

  /// Removes every entry from [boxName].
  /// Returns the number of entries that were deleted.
  /// The box itself remains open and can be reused.
  Future<int> clearBox(String boxName) => _box(boxName).clear();

  /// Returns all values stored in [boxName], cast to [E].
  ///
  /// Example:
  ///   final allScores = BaabaStorage.hive.getAll`<int>`('scores');
  Iterable<E> getAll<E>(String boxName) => _box(boxName).values.cast<E>();

  /// Returns all keys in [boxName].
  /// Keys can be Strings or ints depending on how data was stored.
  Iterable<dynamic> getKeys(String boxName) => _box(boxName).keys;

  /// Returns `true` if [key] exists in [boxName].
  bool containsKey(String boxName, dynamic key) =>
      _box(boxName).containsKey(key);

  /// Returns the number of entries currently stored in [boxName].
  int length(String boxName) => _box(boxName).length;

  /// Returns `true` if [boxName] has no entries.
  bool isEmpty(String boxName) => _box(boxName).isEmpty;

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
      _box(boxName).watch(key: key);

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
  ValueListenable<Box<dynamic>> listenable(
    String boxName, {
    List<dynamic>? keys,
  }) =>
      _box(boxName).listenable(keys: keys);
}
