## 1.3.0

### Added — encryption at rest for Hive boxes

A Hive box was previously always a cleartext file in the app's data directory,
and the wrapper offered no way to change that: `Hive.openBox` accepts an
`encryptionCipher`, but none of `openBox`, `openTypedBox` or `openLazyBox`
passed one through. An app storing PII on-device had no route to an encrypted
box except bypassing this package.

All three openers now take an optional cipher:

```dart
await BaabaStorage.hive.openBox(
  'citizens',
  encryptionCipher: await BaabaStorage.hiveCipher(),
);
```

| API | Purpose |
|---|---|
| `hive.openBox(name, {encryptionCipher, crashRecovery})` | Open a regular box, optionally AES-256 encrypted |
| `hive.openTypedBox<E>(name, {encryptionCipher, crashRecovery})` | Same, for a box of custom objects |
| `hive.openLazyBox(name, {encryptionCipher, crashRecovery})` | Same, for a lazy box |
| `BaabaStorage.hiveCipher({key})` | Resolves a stable per-install AES-256 key out of Keystore-backed secure storage, generating one from a CSPRNG on first use. Memoised and single-flight, so concurrent opens cannot race into generating two keys |
| `BaabaStorage.hiveKeyAlias` | The secure-storage key `hiveCipher` uses, so consumers need not hardcode it |
| `hive.boxExistsOnDisk(name)` | Whether a file exists for a box, without opening it — the only way to tell "first run" from "the box is here but its key is gone", which need opposite handling |
| `BoxEncryptionMismatchException` | Thrown when a box is already open with a different encryption intent than the one requested |

The package now also re-exports `HiveCipher` and `HiveAesCipher`, so a consumer
can name those types without adding `hive` to its own pubspec.

### Fixed — the already-open box silently ignored the cipher

Hive documents that on an already-open box "all provided parameters are being
ignored", and that includes `encryptionCipher`. Every opener here short-circuits
on an open box, so this returned a plaintext box with no error and no
encryption:

```dart
await BaabaStorage.hive.openBox('citizens');                    // cleartext
await BaabaStorage.hive.openBox(                                // same box!
  'citizens',
  encryptionCipher: await BaabaStorage.hiveCipher(),
);
```

`HiveStorage` now records the encryption intent of every box it opens and throws
`BoxEncryptionMismatchException` when a later open disagrees, in either
direction. A box adopted from a bare `Hive.openBox` elsewhere in the app counts
as *unknown* rather than unencrypted: requesting it plaintext behaves exactly as
before, requesting it encrypted throws, because an unverifiable claim of
encryption is not one this package will make.

### Changed — `crashRecovery` defaults to `false` on an encrypted open

Only affects the new ciphered code path; a call without a cipher is unchanged.

Hive computes each frame's checksum over the encryption key, so opening a
cleartext box with a cipher — or an encrypted box with the wrong key — fails the
checksum on the first frame. Hive's `crashRecovery` default of `true` reads that
as a corrupt file, **truncates it, and returns an empty box without throwing**.
For a damaged cleartext cache that is a reasonable trade. For an encrypted box,
where a key that does not match is far more likely than a damaged file, it turns
a recoverable problem into silent, permanent data loss.

A ciphered open therefore defaults to `crashRecovery: false`, which raises a
`HiveError` and leaves the file untouched. Pass the flag explicitly to get
Hive's behaviour back.

Note this protection cannot extend across sessions: nothing in a `.hive` file
records whether it is encrypted, so opening an encrypted box *without* its
cipher still looks like corruption to Hive and still truncates. Resolve the
cipher once at startup and pass it to every open of that box.

### Notes for adopting encryption on existing data

Two things a consumer must handle, both documented in the README:

* **A cleartext box cannot be reopened with a cipher.** Adding the parameter to
  a box that already holds data does not migrate it. Migration — read plaintext,
  write to a new encrypted box, then delete the original — belongs in the app,
  and the order matters.
* **`android:allowBackup` must be `false`.** The `.hive` files travel in an
  Android Auto Backup; the Keystore-backed key does not. A restore onto a new
  device would produce encrypted boxes with no key to decrypt them.

Backward compatible: every new parameter is optional and named, and no existing
call site changes behaviour.

## 1.2.0

### Fixed — lazy and typed boxes were unusable through the wrapper

Every data operation resolved its box with `Hive.box(name)`, which only accepts
an eagerly-opened box whose value type is exactly `dynamic`. `Hive.isBoxOpen`,
however, answers `true` for every flavour — so the `BoxNotOpenException` guard
passed and Hive then threw `HiveError: The box "x" is already open and of type
LazyBox<dynamic>`, an error naming neither this package nor the caller's
mistake.

In practice that meant **choosing `openLazyBox` or `openTypedBox<T>` disabled
the entire wrapper**: `put`, `putAll`, `get`, `delete`, `deleteKeys`,
`clearBox`, `getAll`, `getKeys`, `containsKey`, `length`, `isEmpty`, `watch`,
`listenable` and `closeBox` all threw. `closeBox` was the one most likely to
bite first, in a "log out and clear storage" path.

`HiveStorage` now tracks the boxes it opens, along with the value type each was
opened with, and routes every operation to the widest Hive type that supports
it. Operations declared on `BoxBase` — all writes, deletes, and metadata, plus
`watch` and `closeBox` — now work on lazy and typed boxes alike.

Boxes opened outside `BaabaStorage` (a bare `Hive.openLazyBox` elsewhere in your
app) are adopted on first use, so the wrapper works on them too.

Backward compatible: the change only affects paths that previously threw.

### Added

| API | Purpose |
|---|---|
| `hive.getLazy<E>(box, key, {defaultValue})` | Async read; works on lazy *and* regular boxes |
| `hive.getAllLazy<E>(box)` | Async read of every value; works on both flavours |
| `hive.isBoxLazy(box)` | `true` if the box is open and was opened lazily |
| `BoxIsLazyException` | Thrown by `get` / `getAll` / `listenable` on a lazy box, naming the operation and pointing at the async equivalent |
| `BoxTypeMismatchException` | Thrown when a box name is already open in another flavour, replacing a raw `HiveError` |

The package now re-exports the Hive types its own API returns — `Box`,
`LazyBox`, `BoxBase`, `BoxEvent`, `TypeAdapter`, `BinaryReader`,
`BinaryWriter`, `HiveError`, `HiveObject`, `HiveObjectMixin` — so consuming
apps can write those types in their own signatures without adding `hive` to
their pubspec. (Adapters generated by `hive_generator` are the exception: the
generated code emits its own `hive` import.) `hive` is now a direct dependency
so the re-exported version is one this package pins.

### Changed

- `putAll` is now `putAll<E>(String boxName, Map<dynamic, E> entries)`. Hive
  checks the map against the box's value type as a whole, so a
  `Map<dynamic, dynamic>` could never satisfy a `Box<UserProfile>` even when
  every value was one. Inference makes this source-compatible.
- `deleteBox` now calls the initialisation guard, so using it before
  `BaabaStorage.init()` raises `StorageNotInitializedException` instead of
  failing inside Hive.
- README: the custom-objects example called `openBox<UserProfile>`, which does
  not exist — it is `openTypedBox<UserProfile>`.

---

## 1.1.0

### Added — Reactive SharedPreferences

`PrefsStorage` now emits change events so UI widgets can rebuild automatically
without manual `setState` calls, matching the reactive API already available on
`HiveStorage`.

| API | Returns | Use with |
|---|---|---|
| `prefs.watch<T>('key')` | `Stream<T?>` | `StreamBuilder` |
| `prefs.listenable('key')` | `ValueListenable<dynamic>` | `ValueListenableBuilder` |
| `prefs.changes` | `Stream<MapEntry<String, dynamic>>` | general listener |

All write methods (`setString`, `setInt`, `setDouble`, `setBool`,
`setStringList`, `set<T>`, `remove`, `clear`) now dispatch a change event after
a successful write. `remove` and `clear` emit `null` as the value.

---

## 1.0.0

Initial release.

- **`BaabaStorage`** — unified facade that initialises all three backends with a single `await BaabaStorage.init()` call.
- **`PrefsStorage`** — singleton wrapper around `shared_preferences` with typed getters/setters (`getString`, `setInt`, …) and a generic `get<T>` / `set<T>` API. Supports `String`, `int`, `double`, `bool`, and `List<String>`.
- **`HiveStorage`** — singleton wrapper around `hive_flutter` with box management (`openBox`, `openTypedBox`, `openLazyBox`), bulk operations (`putAll`, `getAll`, `deleteKeys`), TypeAdapter registration, and reactive helpers (`watch`, `listenable`).
- **`SecureStorage`** — singleton wrapper around `flutter_secure_storage` with auth-token shortcuts (`saveToken`, `getToken`, `hasToken`, `deleteToken`), HTTP-header storage (`saveAuthHeaders`, `getAuthHeaders`, `deleteAuthHeaders`), and configurable platform options.
- **Exceptions** — `StorageNotInitializedException`, `BoxNotOpenException`, `UnsupportedTypeException` with descriptive messages.
