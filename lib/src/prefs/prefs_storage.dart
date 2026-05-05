// ─────────────────────────────────────────────────────────────────────────────
// prefs_storage.dart
//
// A singleton wrapper around Flutter's SharedPreferences package.
//
// SharedPreferences stores data as simple key/value pairs on disk.
// It is ideal for lightweight app settings and flags such as:
//   - theme mode (dark/light)
//   - onboarding completed flag
//   - last selected tab
//   - user display preferences
//
// It does NOT support complex types like Maps or custom objects.
// For those, use HiveStorage instead.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:shared_preferences/shared_preferences.dart';

import '../exceptions/storage_exception.dart';

/// Wraps [SharedPreferences] with a clean singleton API.
///
/// Do not instantiate directly — access via [BaabaStorage.prefs]
/// or [PrefsStorage.instance] after calling [BaabaStorage.init].
class PrefsStorage {
  // Private constructor — prevents instantiation from outside this class.
  // This enforces the singleton pattern: only one instance ever exists.
  PrefsStorage._();

  /// The single instance of this class (created on first access).
  static PrefsStorage? _instance;

  /// The underlying SharedPreferences object from the Flutter plugin.
  /// It is null until [init] is called.
  static SharedPreferences? _prefs;

  /// Returns the singleton instance, creating it if it doesn't exist yet.
  ///
  /// Uses the `??=` operator — equivalent to:
  ///   if (_instance == null) _instance = PrefsStorage._();
  static PrefsStorage get instance {
    _instance ??= PrefsStorage._();
    return _instance!;
  }

  /// Initialises the underlying SharedPreferences plugin.
  ///
  /// Called automatically by [BaabaStorage.init] — you don't need to call
  /// this yourself unless you're using PrefsStorage standalone.
  static Future<void> init() async {
    // SharedPreferences.getInstance() opens the platform storage
    // (NSUserDefaults on iOS, SharedPreferences on Android, etc.)
    _prefs = await SharedPreferences.getInstance();
  }

  /// Internal getter that returns the SharedPreferences instance.
  /// Throws [StorageNotInitializedException] if [init] was never called.
  /// This guard prevents silent null-pointer crashes.
  SharedPreferences get _sp {
    if (_prefs == null) throw const StorageNotInitializedException();
    return _prefs!;
  }

  // ── Generic API ───────────────────────────────────────────────────────────

  /// Stores [value] under [key]. The type [T] is inferred automatically.
  ///
  /// Supported types: [String], [int], [double], [bool], [List<String>].
  /// Passing any other type throws [UnsupportedTypeException].
  ///
  /// Returns `true` if the write succeeded, `false` otherwise.
  ///
  /// Example:
  ///   await prefs.set`<String>`('username', 'Zunair');
  ///   await prefs.set`<bool>`('darkMode', true);
  Future<bool> set<T>(String key, T value) {
    final sp = _sp;

    // Check the runtime type of value and delegate to the correct
    // SharedPreferences method. Order matters — check bool before int
    // because bool is a subtype of Object but not int.
    if (value is String) return sp.setString(key, value);
    if (value is int) return sp.setInt(key, value);
    if (value is double) return sp.setDouble(key, value);
    if (value is bool) return sp.setBool(key, value);
    if (value is List<String>) return sp.setStringList(key, value);

    // If none of the above matched, the type is not supported.
    throw UnsupportedTypeException(T);
  }

  /// Reads the value stored under [key] and casts it to [T].
  ///
  /// Returns [defaultValue] if:
  ///   - the key does not exist
  ///   - the stored value cannot be cast to [T]
  ///
  /// Example:
  ///   final theme = prefs.get`<String>`('theme', defaultValue: 'light');
  T? get<T>(String key, {T? defaultValue}) {
    final sp = _sp;

    // Return early with defaultValue if the key was never saved.
    if (!sp.containsKey(key)) return defaultValue;

    try {
      final value = sp.get(key); // returns Object? (the raw stored value)
      if (value == null) return defaultValue;

      // `as T?` performs a runtime type cast.
      // If the cast fails (wrong type stored), the catch block handles it.
      return value as T? ?? defaultValue;
    } on TypeError {
      // Type mismatch — e.g. key holds an int but caller asked for String.
      // Return defaultValue instead of crashing.
      return defaultValue;
    }
  }

  // ── Typed convenience methods ─────────────────────────────────────────────
  // These mirror the underlying SharedPreferences API directly.
  // Prefer these over the generic get/set when you know the type at compile time,
  // as they are slightly more readable and avoid runtime type checks.

  /// Reads a [String] value. Returns [defaultValue] if the key is absent.
  String? getString(String key, {String? defaultValue}) =>
      _sp.getString(key) ?? defaultValue;

  /// Writes a [String] value. Returns `true` on success.
  Future<bool> setString(String key, String value) =>
      _sp.setString(key, value);

  /// Reads an [int] value. Returns [defaultValue] if the key is absent.
  int? getInt(String key, {int? defaultValue}) =>
      _sp.getInt(key) ?? defaultValue;

  /// Writes an [int] value. Returns `true` on success.
  Future<bool> setInt(String key, int value) => _sp.setInt(key, value);

  /// Reads a [double] value. Returns [defaultValue] if the key is absent.
  double? getDouble(String key, {double? defaultValue}) =>
      _sp.getDouble(key) ?? defaultValue;

  /// Writes a [double] value. Returns `true` on success.
  Future<bool> setDouble(String key, double value) =>
      _sp.setDouble(key, value);

  /// Reads a [bool] value. Returns [defaultValue] if the key is absent.
  bool? getBool(String key, {bool? defaultValue}) =>
      _sp.getBool(key) ?? defaultValue;

  /// Writes a [bool] value. Returns `true` on success.
  Future<bool> setBool(String key, bool value) => _sp.setBool(key, value);

  /// Reads a [List<String>] value. Returns [defaultValue] if the key is absent.
  List<String>? getStringList(String key, {List<String>? defaultValue}) =>
      _sp.getStringList(key) ?? defaultValue;

  /// Writes a [List<String>] value. Returns `true` on success.
  Future<bool> setStringList(String key, List<String> value) =>
      _sp.setStringList(key, value);

  // ── Deletion ──────────────────────────────────────────────────────────────

  /// Removes the value stored under [key].
  /// Does nothing if the key doesn't exist.
  Future<bool> remove(String key) => _sp.remove(key);

  /// Removes ALL stored key/value pairs.
  /// Use with caution — this cannot be undone.
  Future<bool> clear() => _sp.clear();

  // ── Inspection ────────────────────────────────────────────────────────────

  /// Returns `true` if a value has been saved under [key].
  bool containsKey(String key) => _sp.containsKey(key);

  /// Returns the set of all keys that currently have saved values.
  Set<String> getKeys() => _sp.getKeys();

  /// Returns every stored key/value pair as a [Map].
  /// Useful for debugging or bulk operations.
  Map<String, dynamic> getAll() {
    final keys = _sp.getKeys();
    // Build a map by iterating all keys and fetching each value.
    return {for (final k in keys) k: _sp.get(k)};
  }

  /// Forces a reload from disk.
  ///
  /// Normally you don't need this — SharedPreferences keeps an in-memory
  /// cache that is always in sync. Call this only if another process or
  /// isolate may have written to the same storage.
  Future<void> reload() => _sp.reload();
}
