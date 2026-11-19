# baaba_storage_hive

Hive boxes for [`baaba_storage_utils`](https://pub.dev/packages/baaba_storage_utils): regular, typed
and lazy boxes behind one wrapper, with optional AES-256 encryption at rest
whose key is kept in secure storage.

Use this package only if your app needs Hive. Apps that need only
SharedPreferences and secure storage should depend on `baaba_storage_utils`
alone, and skip Hive's dependencies and its higher Flutter floor.

| Entry point | What it is |
|---|---|
| `BaabaHive.instance` | The box wrapper: open, read, write, watch |
| `BaabaHive.cipher()` | A per-install AES-256 cipher for encrypted boxes |
| `BaabaStorage.prefs` / `BaabaStorage.secure` | Re-exported from `baaba_storage_utils` |

---

## Setup

### 1. Add the dependency

`baaba_storage_utils` comes along with this package, so this is the only line
you add:

```yaml
dependencies:
  baaba_storage_hive: ^3.0.0
```

Requires Dart 3.11+ and Flutter 3.44+ (`hive_ce_flutter` needs 3.44), plus
everything `baaba_storage_utils` needs: Android `minSdk` 24 and, on Linux,
`libsecret-1-dev`. See [its Setup section](https://pub.dev/packages/baaba_storage_utils#setup).

Hive support comes from [`hive_ce`](https://pub.dev/packages/hive_ce), the
maintained community edition of Hive. Do not also depend on the original
`hive` / `hive_flutter` / `hive_generator` packages: two Hive copies in one app
keep separate adapter registries and can open the same box file twice. For
generated adapters use `hive_ce_generator`:

```yaml
dev_dependencies:
  build_runner: any
  hive_ce_generator: any
```

### 2. Import one library

```dart
import 'package:baaba_storage_hive/baaba_storage_hive.dart';
```

It re-exports all of `baaba_storage_utils` (`BaabaStorage`, `PrefsStorage`,
`SecureStorage`, the exceptions, the secure-storage option types) and the Hive
types the API uses (`Box`, `LazyBox`, `TypeAdapter`, `HiveAesCipher`, …).

### 3. Initialize once in `main()`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BaabaStorage.init();   // prefs + secure storage
  await BaabaHive.init();      // Hive
  runApp(const MyApp());
}
```

`BaabaStorage.init()` comes first because `BaabaHive.cipher()` reads its key
through the secure-storage options configured there, and throws
`StorageNotInitializedException` without them.

To keep the `.hive` files in a subfolder of the documents directory:

```dart
await BaabaHive.init(subDir: 'app_data');
// Hive files are stored in <documents>/app_data/
```

---

## Boxes

Box-based local storage. Supports any type Hive can serialize (primitives, `Map`, `List`, and custom objects with a registered `TypeAdapter`).

### Basic usage

```dart
// Open a box before using it (safe to call multiple times)
await BaabaHive.instance.openBox('settings');

// Put / get
await BaabaHive.instance.put('settings', 'fontSize', 16.0);
final size = BaabaHive.instance.get<double>('settings', 'fontSize');

// Store a map
await BaabaHive.instance.put('settings', 'user', {'name': 'Ali', 'age': 30});
final user = BaabaHive.instance.get<Map>('settings', 'user');

// Delete
await BaabaHive.instance.delete('settings', 'fontSize');
await BaabaHive.instance.clearBox('settings');

// Inspect
BaabaHive.instance.containsKey('settings', 'fontSize');  // bool
BaabaHive.instance.length('settings');                   // int
BaabaHive.instance.getAll<double>('settings');           // Iterable<double>
BaabaHive.instance.getKeys('settings');                  // Iterable<dynamic>
```

### Custom objects

```dart
// 1. Annotate your model (or write the adapter manually).
//    HiveType / HiveField come from `package:hive_ce/hive_ce.dart`;
//    run `dart run build_runner build` to generate UserProfileAdapter.
@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0) late String name;
  @HiveField(1) late int age;
}

// 2. Register the adapter before opening the box
BaabaHive.instance.registerAdapter(UserProfileAdapter());

// 3. Open a typed box
await BaabaHive.instance.openTypedBox<UserProfile>('profiles');

// 4. Store and retrieve
final profile = UserProfile()..name = 'Zunair'..age = 25;
await BaabaHive.instance.put('profiles', 'current', profile);
final loaded = BaabaHive.instance.get<UserProfile>('profiles', 'current');
```

### Lazy boxes

A lazy box keeps only its keys in memory and reads each value from disk on
demand — the right choice when values are large blobs or the box holds a lot of
entries.

```dart
await BaabaHive.instance.openLazyBox('queue');

// Writes and metadata are identical to a regular box
await BaabaHive.instance.put('queue', 'job-1', payload);
BaabaHive.instance.length('queue');
BaabaHive.instance.getKeys('queue');
await BaabaHive.instance.delete('queue', 'job-1');

// Reads are async, because that is when the disk read happens
final job = await BaabaHive.instance.getLazy<String>('queue', 'job-1');
final all = await BaabaHive.instance.getAllLazy<String>('queue');
```

`get`, `getAll` and `listenable` hand back values synchronously, so they cannot
work on a lazy box and throw `BoxIsLazyException`. Everything else — `put`,
`putAll`, `delete`, `deleteKeys`, `clearBox`, `getKeys`, `containsKey`,
`length`, `isEmpty`, `watch`, `closeBox`, `deleteBox` — works on both flavours.

`getLazy` and `getAllLazy` also accept regular boxes, so code that does not know
how a box was opened can always use them. `isBoxLazy('queue')` answers if it
needs to branch.

A box name can only be open in one flavour at a time. Asking for another one
throws `BoxTypeMismatchException` rather than a raw `HiveError`:

```dart
await BaabaHive.instance.openLazyBox('queue');
await BaabaHive.instance.openBox('queue');  // throws BoxTypeMismatchException
```

### Encrypting boxes

A Hive box is a plain file in the app's data directory. Anything in it — an ID
number, a biometric template, a health record — is readable by anyone who can
read that file: a rooted or jailbroken device, an ADB backup, a stolen phone, a
forensic image. Pass a cipher to encrypt the box with AES-256 at rest:

```dart
await BaabaHive.instance.openBox(
  'citizens',
  encryptionCipher: await BaabaHive.cipher(),
);
```

`openTypedBox` and `openLazyBox` take the same parameter. Everything after the
open is unchanged — `put`, `get`, `watch` and the rest behave exactly as they do
on a plaintext box.

`BaabaHive.cipher()` resolves a stable per-install AES-256 key: it reads
one from secure storage, generating it from a CSPRNG on first use. The key lives
in the platform's secure enclave (Android Keystore, iOS Keychain, DPAPI,
libsecret), which is the point — a key kept next to the data it protects, in
SharedPreferences or in another Hive box, encrypts nothing in practice. The key
is never logged or exposed; you get an opaque cipher. Repeated calls return the
same one, so calling it per box is fine.

Encrypt what needs it: PII, credentials, anything regulated. A cache of public
reference data does not need a cipher, and encryption is not free — every read
and write pays for it.

> ⚠️ **An existing cleartext box cannot be reopened with a cipher.**
>
> Hive folds the encryption key into every frame's checksum, so a file written
> in the clear fails to decode under a cipher. Adding `encryptionCipher:` to a
> box that already holds data does not migrate it — the open throws a
> `HiveError` (the file is left untouched). Adopting encryption on live data
> means migrating it yourself:
>
> ```dart
> // 1. Read the cleartext box.
> final old = await BaabaHive.instance.openBox('citizens');
> final entries = {for (final k in old.keys) k: old.get(k)};
> await BaabaHive.instance.closeBox('citizens');
>
> // 2. Write it into a new, encrypted box — a NEW NAME, so the original stays
> //    intact until the copy is safely on disk.
> await BaabaHive.instance.openBox(
>   'citizens_enc',
>   encryptionCipher: await BaabaHive.cipher(),
> );
> await BaabaHive.instance.putAll('citizens_enc', entries);
> await BaabaHive.instance.closeBox('citizens_enc');
>
> // 3. Only now delete the original, and record that the migration ran so a
> //    half-finished attempt can be resumed rather than repeated blindly.
> await BaabaHive.instance.deleteBox('citizens');
> await BaabaStorage.prefs.setBool('citizens_migrated', true);
> ```
>
> Migrate in that order. Deleting before the encrypted copy is closed loses the
> data if the app is killed mid-way.

> ⚠️ **Set `android:allowBackup="false"`.**
>
> ```xml
> <application android:allowBackup="false" android:fullBackupContent="false">
> ```
>
> The `.hive` files are ordinary app data and travel in an Android Auto Backup.
> The Keystore-backed key does not — Keystore keys never leave the device. A
> restore onto a new phone therefore yields encrypted boxes and no key to
> decrypt them. Without this flag, encryption converts a confidentiality risk
> into permanent, unrecoverable data loss for the user.
>
> On iOS the trade-off differs: Keychain items are included in encrypted device
> and iCloud backups, so a restore usually keeps the key. Do not rely on it for
> data you cannot re-fetch.

**Every open of an encrypted box must pass the cipher.** Within one session the
wrapper enforces this: a second open whose encryption intent disagrees with the
first throws `BoxEncryptionMismatchException` instead of quietly returning a box
that is not what was asked for — Hive itself ignores `encryptionCipher` on an
already-open box, which is what makes that guard necessary. Across sessions
nothing can enforce it, because a `.hive` file does not record whether it is
encrypted: opening an encrypted box with no cipher looks like a corrupt file to
Hive, and the open fails with a `HiveError`. (hive_ce leaves the file intact;
the original `hive` package truncated it.) Resolve the cipher once at startup
and use it for every open of that box.

**When the key is missing.** Use `boxExistsOnDisk` to tell a first run apart from
a box whose key is gone — a restored device, a wiped Keystore — because those
need opposite responses and are otherwise indistinguishable:

```dart
final onDisk = await BaabaHive.instance.boxExistsOnDisk('citizens');
final hasKey = await BaabaStorage.secure.containsKey(BaabaHive.keyAlias);

if (onDisk && !hasKey) {
  // Encrypted data that can no longer be read. Tell the user and re-fetch, or
  // delete the box deliberately with deleteBox. Do NOT generate a new key and
  // open it anyway — the open fails, and only the old key can read the file.
}
```

`BaabaHive.cipher()` never replaces a key that is present but unreadable; it throws a
`StorageException` instead, because generating a replacement would make every
box encrypted with the original permanently unrecoverable.

### Reactive UI with ValueListenableBuilder

```dart
ValueListenableBuilder<Box>(
  valueListenable: BaabaHive.instance.listenable('settings'),
  builder: (context, box, _) {
    final theme = box.get('theme', defaultValue: 'light');
    return Text('Theme: $theme');
  },
);
```

### Watch a stream of changes

```dart
BaabaHive.instance.watch('settings', key: 'theme').listen((event) {
  print('theme changed to ${event.value}');
});
```

---

## Lifecycle

```dart
// Close all Hive boxes and forget the memoised cipher when the app shuts down
await BaabaHive.dispose();
```

`BaabaStorage.dispose()` no longer touches Hive. If you re-run
`BaabaStorage.init()` with different secure-storage options, call
`BaabaHive.dispose()` first so a cipher resolved under the old options is not
reused.

---

## Error handling

All of these extend `StorageException` from `baaba_storage_utils`.

| Exception | When thrown |
|---|---|
| `StorageNotInitializedException` | `BaabaHive.instance` before `BaabaHive.init()`, or `BaabaHive.cipher()` before `BaabaStorage.init()`. The message names the missing call |
| `BoxNotOpenException` | `get/put/delete` called on a box that was never opened |
| `BoxIsLazyException` | `get`, `getAll` or `listenable` called on a lazy box — use `getLazy` / `getAllLazy` |
| `BoxTypeMismatchException` | A box name is already open in another flavour (lazy vs regular, or a different value type) |
| `BoxEncryptionMismatchException` | A box name is already open with a different encryption intent than the one requested — including a box opened outside `BaabaHive`, whose cipher cannot be verified |
| `StorageException` | `BaabaHive.cipher()` found a stored key that is not a valid 32-byte base64 value. The key is left untouched |
| `HiveError` | Passed through from Hive when a box cannot be decoded with the cipher given — a wrong key, no key for an encrypted box, or a key for a cleartext file. The file is left untouched |

---

## Upgrading from 2.x

Hive moved out of `baaba_storage_utils` into this package in 3.0.0. Stored data
is unaffected: same box files, same encryption key under the same
secure-storage alias (`baaba_hive_key`).

1. **Dependency:** replace `baaba_storage_utils: ^2.0.0` with
   `baaba_storage_hive: ^3.0.0` in your pubspec (it brings
   `baaba_storage_utils` 3.x along), and change the import
   to `package:baaba_storage_hive/baaba_storage_hive.dart`.
2. **Init:** add `await BaabaHive.init();` after `BaabaStorage.init()`. If you
   passed `hiveSubDir:` to `BaabaStorage.init`, pass the same value as
   `BaabaHive.init(subDir: ...)` — otherwise Hive looks in a different
   directory and your boxes appear empty.
3. **Renames:**

   | 2.x | 3.0.0 |
   |---|---|
   | `BaabaStorage.hive` | `BaabaHive.instance` |
   | `BaabaStorage.hiveCipher()` | `BaabaHive.cipher()` |
   | `BaabaStorage.hiveKeyAlias` | `BaabaHive.keyAlias` |
   | `BaabaStorage.init(hiveSubDir: ...)` | `BaabaHive.init(subDir: ...)` |
   | `BaabaStorage.dispose()` closing boxes | `BaabaHive.dispose()` |

4. **Flutter floor** is unchanged for Hive apps: Flutter 3.44.
5. **If the app calls `SecureStorage.configure(...)` before
   `BaabaStorage.init()`**, read the core package's
   [upgrade notes](https://pub.dev/packages/baaba_storage_utils#upgrading-from-2x) first.
   Those options now take effect, and a storage-location option would hide
   the existing encryption key.

See [CHANGELOG.md](CHANGELOG.md) for the full list.
