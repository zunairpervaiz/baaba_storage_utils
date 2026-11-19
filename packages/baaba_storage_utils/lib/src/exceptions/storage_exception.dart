// ─────────────────────────────────────────────────────────────────────────────
// storage_exception.dart
//
// Custom exception types thrown by the baaba_storage_utils package. The
// Hive-specific ones (BoxNotOpenException and friends) live in
// baaba_storage_hive and extend [StorageException] from here.
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
///
/// `baaba_storage_hive` throws this too, through [withMessage], when a box is
/// used before `BaabaHive.init()`. Sharing the type keeps one
/// `on StorageNotInitializedException` handler enough for both packages, while
/// the message still names the init call that is actually missing.
class StorageNotInitializedException extends StorageException {
  const StorageNotInitializedException()
      : super(
          'BaabaStorage is not initialized. '
          'Call await BaabaStorage.init() in main() before using storage.',
        );

  /// For a package building on this one whose own `init` is the missing call.
  /// [message] should name that call, as the default message names
  /// [BaabaStorage.init].
  const StorageNotInitializedException.withMessage(super.message);
}

/// Thrown when [PrefsStorage.set] is called with a type that
/// SharedPreferences does not support.
///
/// SharedPreferences only handles: String, int, double, bool, `List<String>`.
/// For anything more complex (Maps, custom objects, nested data), use Hive
/// boxes from the `baaba_storage_hive` package instead.
class UnsupportedTypeException extends StorageException {
  /// [type] is the Dart type that was passed to [PrefsStorage.set].
  UnsupportedTypeException(Type type)
      : super(
          'Type "$type" is not supported by PrefsStorage. '
          'Supported: String, int, double, bool, List<String>. '
          'Use Hive boxes (the baaba_storage_hive package) for complex or '
          'custom types.',
        );
}
