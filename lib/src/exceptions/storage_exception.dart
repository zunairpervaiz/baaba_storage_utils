// ─────────────────────────────────────────────────────────────────────────────
// storage_exception.dart
//
// Custom exception types thrown by the baaba_storage_utils package.
// Having dedicated exception classes lets callers catch specific errors
// instead of generic Exceptions, making error handling much cleaner.
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all storage-related exceptions in this package.
///
/// Every exception carries a human-readable [message] and an optional [cause]
/// (the original error that triggered this one, useful for debugging).
class StorageException implements Exception {
  /// A description of what went wrong.
  final String message;

  /// The underlying error that caused this exception, if any.
  /// For example, a platform exception from the OS-level storage API.
  final Object? cause;

  const StorageException(this.message, {this.cause});

  /// Returns a readable string like:
  ///   "StorageException: something went wrong"
  /// or, when a cause is present:
  ///   "StorageException: something went wrong\nCaused by: ..."
  @override
  String toString() => cause != null
      ? 'StorageException: $message\nCaused by: $cause'
      : 'StorageException: $message';
}

/// Thrown when any storage method is called before [BaabaStorage.init].
///
/// Example scenario:
///   BaabaStorage.prefs.getString('key');  // ← throws this if init() wasn't called
///
/// Fix: always call `await BaabaStorage.init()` in main() before runApp().
class StorageNotInitializedException extends StorageException {
  const StorageNotInitializedException()
      : super(
          'BaabaStorage is not initialized. '
          'Call await BaabaStorage.init() in main() before using storage.',
        );
}

/// Thrown when a Hive box is accessed before it has been opened.
///
/// Hive requires boxes to be explicitly opened before reading or writing.
/// This exception tells you exactly which box name was missing.
///
/// Fix: call `await BaabaStorage.hive.openBox('boxName')` at app start,
/// or inside the screen/repository that needs that box.
class BoxNotOpenException extends StorageException {
  /// [boxName] is the name of the box that was not open when accessed.
  BoxNotOpenException(String boxName)
      : super(
          'Hive box "$boxName" is not open. '
          'Call await BaabaStorage.hive.openBox("$boxName") first.',
        );
}

/// Thrown when [PrefsStorage.set] is called with a type that
/// SharedPreferences does not support.
///
/// SharedPreferences only handles: String, int, double, bool, `List<String>`.
/// For anything more complex (Maps, custom objects, nested data), use
/// [HiveStorage] instead.
class UnsupportedTypeException extends StorageException {
  /// [type] is the Dart type that was passed to [PrefsStorage.set].
  UnsupportedTypeException(Type type)
      : super(
          'Type "$type" is not supported by PrefsStorage. '
          'Supported: String, int, double, bool, List<String>. '
          'Use HiveStorage for complex or custom types.',
        );
}
