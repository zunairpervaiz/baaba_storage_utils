## 3.0.0

First release as a separate package. The Hive support it contains shipped
inside `baaba_storage_utils` up to 2.0.0, and its history is in
[that package's changelog](https://pub.dev/packages/baaba_storage_utils/changelog). Versions
follow `baaba_storage_utils`, and the two are released together.

### Changed — split out of `baaba_storage_utils`

Requires `hive_ce` 2.23.3 and `hive_ce_flutter` 2.5.0 (2.x required 2.20.1
and 2.4.0), and Dart 3.11, which comes from `baaba_storage_utils` 3.0.0. The
Flutter floor stays 3.44.

Behaviour is unchanged from `baaba_storage_utils` 2.0.0: same box wrapper,
same encryption guards, same `crashRecovery` defaults, same on-disk files.
The encryption key stays under the secure-storage alias `baaba_hive_key`, so
boxes encrypted under 2.x open with the key they were written with.

**Breaking for consumers coming from `baaba_storage_utils` 2.x:**

- Depend on `baaba_storage_hive: ^3.0.0` instead of `baaba_storage_utils` and
  import `package:baaba_storage_hive/baaba_storage_hive.dart`. It re-exports
  all of `baaba_storage_utils`, so that import is the only one needed.
- Call `await BaabaHive.init()` after `BaabaStorage.init()`. Pass the old
  `hiveSubDir:` value as `subDir:`, or Hive opens a different directory and the
  boxes appear empty.
- Renames: `BaabaStorage.hive` → `BaabaHive.instance`,
  `BaabaStorage.hiveCipher()` → `BaabaHive.cipher()`,
  `BaabaStorage.hiveKeyAlias` → `BaabaHive.keyAlias`. Closing boxes on
  shutdown moves from `BaabaStorage.dispose()` to `BaabaHive.dispose()`.
- Exception messages name `BaabaHive` instead of `BaabaStorage`. For example,
  a box opened outside the wrapper is now described as
  "opened outside BaabaHive".
- Using `BaabaHive.instance` before `BaabaHive.init()` throws
  `StorageNotInitializedException`, the same type as before, with a message
  naming `BaabaHive.init()`.

### Fixed

- **Concurrent opens of one box bypassed the encryption guard.** While a box
  was still being opened, a second `openBox` / `openTypedBox` / `openLazyBox`
  of the same name saw nothing open. Hive then handed it the same box and
  ignored its cipher. One caller could ask for encryption and get the
  plaintext box (and write to it in the clear), or the reverse. A second open
  now waits for the first and is checked against its result, as if the calls
  had been sequential. A conflicting one throws `BoxEncryptionMismatchException`
  or `BoxTypeMismatchException` (previously a raw `HiveError` for a flavour
  clash), and a matching one gets the same box. The same applies to
  `baaba_storage_utils` 2.x's `BaabaStorage.hive`.
- `BaabaHive.cipher()`: a key lookup that failed after `BaabaHive.dispose()`
  could evict a newer in-flight lookup from the cache. A third caller could
  then generate a second key that overwrote the first. A failure now only
  evicts its own lookup.
- The key now lives in the secure-storage namespace you configured, if you
  configured one with `SecureStorage.configure()` before `BaabaStorage.init()`.
  Before, that configuration was discarded and the key was always stored with
  the default options. See `baaba_storage_utils` 3.0.0 under Fixed **before
  upgrading** if that applies to your app: the existing key would no longer be
  found.

### Unchanged requirement

- `BaabaHive.cipher()` still requires `BaabaStorage.init()`, as
  `hiveCipher()` did. The key must be read through the secure-storage options
  configured there. Reading it with defaults, such as a different Android
  `storageNamespace`, would find no key, generate a new one, and lock every
  existing encrypted box.
