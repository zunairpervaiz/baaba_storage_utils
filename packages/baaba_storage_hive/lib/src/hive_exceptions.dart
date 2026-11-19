// ─────────────────────────────────────────────────────────────────────────────
// hive_exceptions.dart
//
// Exception types specific to Hive boxes. They extend [StorageException] from
// baaba_storage_utils, so an app can still catch every storage failure, from
// either package, with a single `on StorageException` clause.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:baaba_storage_utils/baaba_storage_utils.dart';

/// Thrown when a Hive box is accessed before it has been opened.
///
/// Hive requires boxes to be explicitly opened before reading or writing.
/// This exception tells you exactly which box name was missing.
///
/// Fix: call `await BaabaHive.instance.openBox('boxName')` at app start,
/// or inside the screen/repository that needs that box.
class BoxNotOpenException extends StorageException {
  /// [boxName] is the name of the box that was not open when accessed.
  BoxNotOpenException(String boxName)
      : super(
          'Hive box "$boxName" is not open. '
          'Call await BaabaHive.instance.openBox("$boxName") first.',
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
/// `BaabaHive.instance.openBox('boxName')`.
class BoxIsLazyException extends StorageException {
  /// [boxName] is the lazily-opened box; [operation] is the call that failed,
  /// e.g. `'get()'`.
  BoxIsLazyException(String boxName, String operation)
      : super(
          'Hive box "$boxName" was opened lazily, so $operation is not '
          'available — a lazy box does not hold its values in memory. '
          'Use getLazy()/getAllLazy() instead, or open the box with '
          'BaabaHive.instance.openBox("$boxName").',
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

/// Thrown when a box that is already open was opened with a different
/// encryption intent than the one now being requested.
///
/// Hive keys boxes by name alone and, crucially, `Hive.openBox` **ignores every
/// parameter — including `encryptionCipher` — when the box is already open**.
/// Left unchecked, that means the following returns the plaintext box, with no
/// error and no encryption:
///
/// ```dart
/// await BaabaHive.instance.openBox('citizens');                   // cleartext
/// // …later, in a screen that believes it is being careful:
/// await BaabaHive.instance.openBox(                               // ← same box!
///   'citizens',
///   encryptionCipher: await BaabaHive.cipher(),
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
  /// meaning "opened outside BaabaHive, so we cannot know".
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
        null => 'with an unknown cipher (it was opened outside BaabaHive)',
      };
}
