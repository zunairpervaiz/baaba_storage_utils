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

/// Thrown when an operation that only exists on a regular [Box] is called on a
/// box that was opened with [HiveStorage.openLazyBox].
///
/// A lazy box does not keep its values in memory — that is the whole point of
/// it — so any API that hands you a value synchronously (`get`, `getAll`,
/// `listenable`) cannot work. Everything else (`put`, `delete`, `clearBox`,
/// `getKeys`, `containsKey`, `length`, `isEmpty`, `watch`, `closeBox`) works on
/// both flavours and is unaffected.
///
/// Fix: use the async equivalents ([HiveStorage.getLazy],
/// [HiveStorage.getAllLazy]), or open the box eagerly with
/// `BaabaStorage.hive.openBox('boxName')`.
class BoxIsLazyException extends StorageException {
  /// [boxName] is the lazily-opened box; [operation] is the call that failed,
  /// e.g. `'get()'`.
  BoxIsLazyException(String boxName, String operation)
      : super(
          'Hive box "$boxName" was opened lazily, so $operation is not '
          'available — a lazy box does not hold its values in memory. '
          'Use getLazy()/getAllLazy() instead, or open the box with '
          'BaabaStorage.hive.openBox("$boxName").',
        );
}

/// Thrown when a box is already open in a different flavour than the one being
/// requested — lazy vs regular, or a different value type.
///
/// Hive keys boxes by name alone, so a single name can only ever be open as one
/// of `Box<dynamic>`, `Box<T>`, or `LazyBox<dynamic>` at a time. Asking for a
/// different one is a programming error, not a recoverable condition.
///
/// Fix: use the matching opener, or close the box before reopening it in the
/// other flavour.
class BoxTypeMismatchException extends StorageException {
  /// [boxName] is the box in question, [wanted] describes what the caller asked
  /// for, [actual] describes how the box is actually open, and [hint] is an
  /// optional suggestion appended to the message.
  BoxTypeMismatchException(
    String boxName, {
    required String wanted,
    required String actual,
    String? hint,
  }) : super(
          'Hive box "$boxName" is already open as $actual, '
          'but $wanted was requested.${hint == null ? '' : ' $hint'}',
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

/// Thrown when a box that is already open was opened with a different
/// encryption intent than the one now being requested.
///
/// Hive keys boxes by name alone and, crucially, `Hive.openBox` **ignores every
/// parameter — including `encryptionCipher` — when the box is already open**.
/// Left unchecked, that means the following returns the plaintext box, with no
/// error and no encryption:
///
/// ```dart
/// await BaabaStorage.hive.openBox('citizens');                    // cleartext
/// // …later, in a screen that believes it is being careful:
/// await BaabaStorage.hive.openBox(                                // ← same box!
///   'citizens',
///   encryptionCipher: await BaabaStorage.hiveCipher(),
/// );
/// ```
///
/// In an API whose entire purpose is confidentiality, silently handing back a
/// box that is not what was asked for is worse than failing, so this wrapper
/// tracks the encryption intent of every box it opens and throws instead.
///
/// **The unknown case.** A box opened by a bare `Hive.openBox` elsewhere in your
/// app is adopted by this wrapper on first use, and there is no way to ask Hive
/// after the fact whether a cipher was involved. Asking for encryption on such
/// a box therefore also throws — an unverifiable claim of encryption is not one
/// this package will make. Asking for a plaintext box still works, exactly as
/// it did before encryption support existed.
///
/// Fix: open the box once, with the cipher, before anything else touches it —
/// app start is the right place — or `closeBox` it and reopen with the cipher.
/// Note that closing and reopening is only safe if the data on disk already
/// matches the cipher; see [HiveStorage.openBox] for why adopting encryption on
/// a box that already holds cleartext data requires a migration.
class BoxEncryptionMismatchException extends StorageException {
  /// [boxName] is the box in question. [wantedEncrypted] is what this call
  /// asked for, and [actualEncrypted] how the box is actually open — `null`
  /// meaning "opened outside BaabaStorage, so we cannot know".
  BoxEncryptionMismatchException(
    String boxName, {
    bool? wantedEncrypted,
    bool? actualEncrypted,
  }) : super(
          'Hive box "$boxName" is already open '
          '${_describe(actualEncrypted)}, but '
          '${_describe(wantedEncrypted)} was requested. Hive ignores '
          'encryptionCipher on an already-open box, so returning it would hand '
          'you a box that is not what you asked for. Open the box once with '
          'the cipher at app start, or close it before reopening.',
        );

  /// Phrases an encryption intent for the message. `null` is the adopted-box
  /// case: open, but not by us, so its cipher is unknowable.
  static String _describe(bool? encrypted) => switch (encrypted) {
        true => 'encrypted',
        false => 'unencrypted',
        null => 'with an unknown cipher (it was opened outside BaabaStorage)',
      };
}
