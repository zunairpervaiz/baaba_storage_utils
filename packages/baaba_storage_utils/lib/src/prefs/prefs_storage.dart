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
// For those, use Hive boxes from the baaba_storage_hive package instead.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Broadcast stream controller that fires whenever a value is written or deleted.
  /// Using broadcast so multiple listeners (widgets) can subscribe simultaneously.
  static final StreamController<MapEntry<String, dynamic>> _changeController =
      StreamController<MapEntry<String, dynamic>>.broadcast();

  /// Per-key ValueNotifiers for use with [ValueListenableBuilder].
  /// Stored as dynamic so any value type can be held.
  static final Map<String, ValueNotifier<dynamic>> _notifiers = {};

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

  // ── Reactive helpers ──────────────────────────────────────────────────────
  // These allow UI widgets to respond to pref changes automatically,
  // without manually calling setState.

  /// A broadcast [Stream] of every write or delete as [MapEntry<key, value>].
  /// The value is `null` when a key is removed or the store is cleared.
  ///
  /// Most consumers should prefer [watch] to scope events to a single key.
  Stream<MapEntry<String, dynamic>> get changes => _changeController.stream;

  /// Returns a typed [Stream<T?>] that emits whenever [key]'s value changes.
  /// Emits `null` when [key] is removed or the store is cleared.
  ///
  /// Use with [StreamBuilder] to auto-rebuild a widget:
  /// ```dart
  /// StreamBuilder<bool?>(
  ///   stream: BaabaStorage.prefs.watch<bool>('darkMode'),
  ///   builder: (context, snapshot) {
  ///     final isDark = snapshot.data ?? false;
  ///     return Switch(value: isDark, onChanged: (v) => ...);
  ///   },
  /// );
  /// ```
  Stream<T?> watch<T>(String key) => _changeController.stream
      .where((e) => e.key == key)
      .map((e) => e.value == null ? null : e.value as T?);

  /// Returns a [ValueListenable<dynamic>] for [key], suitable for
  /// [ValueListenableBuilder]. The notifier's value updates whenever [key]
  /// changes. Cast `.value` to the expected type inside the builder.
  ///
  /// Example:
  /// ```dart
  /// ValueListenableBuilder<dynamic>(
  ///   valueListenable: BaabaStorage.prefs.listenable('darkMode'),
  ///   builder: (context, value, _) {
  ///     return Switch(value: value as bool? ?? false, onChanged: ...);
  ///   },
  /// );
  /// ```
  ValueListenable<dynamic> listenable(String key) {
    return _notifiers.putIfAbsent(
      key,
      () => ValueNotifier<dynamic>(get<dynamic>(key)),
    );
  }

  /// Dispatches [value] (or `null` on delete) to the stream and updates
  /// any active [ValueNotifier] for [key].
  void _notify(String key, dynamic value) {
    _changeController.add(MapEntry(key, value));
    _notifiers[key]?.value = value;
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
  Future<bool> set<T>(String key, T value) async {
    final sp = _sp;
    bool result;

    // Check the runtime type of value and delegate to the matching
    // SharedPreferences method. On native platforms the types are disjoint.
    // On the web numbers are JS numbers, so a whole double such as 5.0 also
    // passes `is int` and is stored with setInt, being checked first.
    if (value is String) {
      result = await sp.setString(key, value);
    } else if (value is int) {
      result = await sp.setInt(key, value);
    } else if (value is double) {
      result = await sp.setDouble(key, value);
    } else if (value is bool) {
      result = await sp.setBool(key, value);
    } else if (value is List<String>) {
      result = await sp.setStringList(key, value);
    } else {
      // If none of the above matched, the type is not supported.
      throw UnsupportedTypeException(T);
    }

    if (result) _notify(key, value);
    return result;
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
      final value = _raw(sp, key);
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

  /// The value stored under [key], with a string list as a real
  /// `List<String>`.
  ///
  /// SharedPreferences keeps what it loaded from the platform as-is, and a
  /// string list arrives from there as a `List<Object?>`; only its own
  /// getStringList casts. Without this, `get<List<String>>` would work for a
  /// list written in this session and silently return the default for the
  /// same list after an app restart. A list is the only collection
  /// SharedPreferences stores, so every list here is a string list.
  static Object? _raw(SharedPreferences sp, String key) {
    final value = sp.get(key);
    // toList forces the lazy cast, so a non-string element fails here, inside
    // the caller's TypeError handling, rather than later in the caller's code.
    if (value is List && value is! List<String>) {
      return value.cast<String>().toList();
    }
    return value;
  }

  // ── Typed convenience methods ─────────────────────────────────────────────
  // These mirror the underlying SharedPreferences API directly.
  // Prefer these over the generic get/set when you know the type at compile time,
  // as they are slightly more readable and avoid runtime type checks.

  /// Reads a [String] value. Returns [defaultValue] if the key is absent.
  String? getString(String key, {String? defaultValue}) =>
      _sp.getString(key) ?? defaultValue;

  /// Writes a [String] value. Returns `true` on success.
  Future<bool> setString(String key, String value) async {
    final result = await _sp.setString(key, value);
    if (result) _notify(key, value);
    return result;
  }

  /// Reads an [int] value. Returns [defaultValue] if the key is absent.
  int? getInt(String key, {int? defaultValue}) =>
      _sp.getInt(key) ?? defaultValue;

  /// Writes an [int] value. Returns `true` on success.
  Future<bool> setInt(String key, int value) async {
    final result = await _sp.setInt(key, value);
    if (result) _notify(key, value);
    return result;
  }

  /// Reads a [double] value. Returns [defaultValue] if the key is absent.
  double? getDouble(String key, {double? defaultValue}) =>
      _sp.getDouble(key) ?? defaultValue;

  /// Writes a [double] value. Returns `true` on success.
  Future<bool> setDouble(String key, double value) async {
    final result = await _sp.setDouble(key, value);
    if (result) _notify(key, value);
    return result;
  }

  /// Reads a [bool] value. Returns [defaultValue] if the key is absent.
  bool? getBool(String key, {bool? defaultValue}) =>
      _sp.getBool(key) ?? defaultValue;

  /// Writes a [bool] value. Returns `true` on success.
  Future<bool> setBool(String key, bool value) async {
    final result = await _sp.setBool(key, value);
    if (result) _notify(key, value);
    return result;
  }

  /// Reads a [List<String>] value. Returns [defaultValue] if the key is absent.
  List<String>? getStringList(String key, {List<String>? defaultValue}) =>
      _sp.getStringList(key) ?? defaultValue;

  /// Writes a [List<String>] value. Returns `true` on success.
  Future<bool> setStringList(String key, List<String> value) async {
    final result = await _sp.setStringList(key, value);
    if (result) _notify(key, value);
    return result;
  }

  // ── Deletion ──────────────────────────────────────────────────────────────

  /// Removes the value stored under [key].
  /// Does nothing if the key doesn't exist.
  Future<bool> remove(String key) async {
    final result = await _sp.remove(key);
    if (result) _notify(key, null);
    return result;
  }

  /// Removes ALL stored key/value pairs.
  /// Use with caution — this cannot be undone.
  Future<bool> clear() async {
    // Capture keys before clearing — they'll be gone afterwards.
    final keys = _sp.getKeys().toList();
    final result = await _sp.clear();
    if (result) {
      for (final key in keys) {
        _notify(key, null);
      }
    }
    return result;
  }

  // ── Inspection ────────────────────────────────────────────────────────────

  /// Returns `true` if a value has been saved under [key].
  bool containsKey(String key) => _sp.containsKey(key);

  /// Returns the set of all keys that currently have saved values.
  Set<String> getKeys() => _sp.getKeys();

  /// Returns every stored key/value pair as a [Map].
  /// Useful for debugging or bulk operations.
  ///
  /// String lists come back as `List<String>`, as [get] returns them.
  Map<String, dynamic> getAll() {
    final sp = _sp;
    return {for (final k in sp.getKeys()) k: _raw(sp, k)};
  }

  /// Forces a reload from disk.
  ///
  /// Normally you don't need this — SharedPreferences keeps an in-memory
  /// cache that is always in sync. Call this only if another process or
  /// isolate may have written to the same storage.
  Future<void> reload() => _sp.reload();
}
