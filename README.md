# baaba_storage_utils

A unified Flutter storage package that wraps **SharedPreferences**, **Hive**, and **Flutter Secure Storage** behind one clean API.

| Storage | Best for | Reactive? |
|---|---|---|
| `BaabaStorage.prefs` | Simple flags, settings, primitive values | ✅ `watch` / `listenable` |
| `BaabaStorage.hive` | Lists, maps, custom objects — optionally AES-256 encrypted at rest | ✅ `watch` / `listenable` |
| `BaabaStorage.secure` | Tokens, API keys, passwords | — |

---

## Setup

### 1. Add the dependency

```yaml
dependencies:
  baaba_storage_utils:
    path: ../baaba_storage_utils   # or pub.dev version once published
```

Requires Dart 3.8+ and Flutter 3.44+. Hive support comes from
[`hive_ce`](https://pub.dev/packages/hive_ce), the maintained community edition
of Hive. Do not also depend on the original `hive` / `hive_flutter` /
`hive_generator` packages: two Hive copies in one app keep separate adapter
registries and can open the same box file twice. For generated adapters use
`hive_ce_generator`:

```yaml
dev_dependencies:
  build_runner: any
  hive_ce_generator: any
```

### 2. Android — minimum SDK

`flutter_secure_storage` 11 requires `minSdk 24` (Android 7.0), which is also
Flutter's own minimum. If your app pins a lower value, raise it in
`android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdk 24
    }
}
```

### 3. Linux — libsecret

On Linux, `flutter_secure_storage` builds against libsecret. Without its
development package the build fails in CMake with
`libsecret-1>=0.18.4 not found`:

```bash
sudo apt install libsecret-1-dev
```

### 4. Initialize once in `main()`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BaabaStorage.init();
  runApp(const MyApp());
}
```

---

## SharedPreferences — `BaabaStorage.prefs`

Stores primitive values persistently. Supported types: `String`, `int`, `double`, `bool`, `List<String>`.

```dart
// Write
await BaabaStorage.prefs.set<String>('theme', 'dark');
await BaabaStorage.prefs.setInt('loginCount', 5);
await BaabaStorage.prefs.setBool('onboarded', true);
await BaabaStorage.prefs.setStringList('recentSearches', ['flutter', 'dart']);

// Read
final theme    = BaabaStorage.prefs.get<String>('theme');           // 'dark'
final count    = BaabaStorage.prefs.getInt('loginCount', defaultValue: 0);
final onboarded = BaabaStorage.prefs.getBool('onboarded') ?? false;
final searches = BaabaStorage.prefs.getStringList('recentSearches');

// Delete
await BaabaStorage.prefs.remove('theme');
await BaabaStorage.prefs.clear();              // remove everything

// Inspect
BaabaStorage.prefs.containsKey('theme');       // bool
BaabaStorage.prefs.getKeys();                  // Set<String>
BaabaStorage.prefs.getAll();                   // Map<String, dynamic>
```

### Reactive UI with StreamBuilder

Use `watch<T>` to rebuild a widget automatically whenever a pref value changes:

```dart
StreamBuilder<bool?>(
  stream: BaabaStorage.prefs.watch<bool>('darkMode'),
  builder: (context, snapshot) {
    final isDark = snapshot.data ?? false;
    return Switch(
      value: isDark,
      onChanged: (v) => BaabaStorage.prefs.setBool('darkMode', v),
    );
  },
);
```

### Reactive UI with ValueListenableBuilder

```dart
ValueListenableBuilder<dynamic>(
  valueListenable: BaabaStorage.prefs.listenable('darkMode'),
  builder: (context, value, _) {
    return Switch(
      value: value as bool? ?? false,
      onChanged: (v) => BaabaStorage.prefs.setBool('darkMode', v),
    );
  },
);
```

### Listen to all pref changes

```dart
BaabaStorage.prefs.changes.listen((entry) {
  print('${entry.key} → ${entry.value}');  // value is null when removed
});
```

---

## Hive — `BaabaStorage.hive`

Box-based local storage. Supports any type Hive can serialize (primitives, `Map`, `List`, and custom objects with a registered `TypeAdapter`).

### Basic usage

```dart
// Open a box before using it (safe to call multiple times)
await BaabaStorage.hive.openBox('settings');

// Put / get
await BaabaStorage.hive.put('settings', 'fontSize', 16.0);
final size = BaabaStorage.hive.get<double>('settings', 'fontSize');

// Store a map
await BaabaStorage.hive.put('settings', 'user', {'name': 'Ali', 'age': 30});
final user = BaabaStorage.hive.get<Map>('settings', 'user');

// Delete
await BaabaStorage.hive.delete('settings', 'fontSize');
await BaabaStorage.hive.clearBox('settings');

// Inspect
BaabaStorage.hive.containsKey('settings', 'fontSize');  // bool
BaabaStorage.hive.length('settings');                   // int
BaabaStorage.hive.getAll<double>('settings');           // Iterable<double>
BaabaStorage.hive.getKeys('settings');                  // Iterable<dynamic>
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
BaabaStorage.hive.registerAdapter(UserProfileAdapter());

// 3. Open a typed box
await BaabaStorage.hive.openTypedBox<UserProfile>('profiles');

// 4. Store and retrieve
final profile = UserProfile()..name = 'Zunair'..age = 25;
await BaabaStorage.hive.put('profiles', 'current', profile);
final loaded = BaabaStorage.hive.get<UserProfile>('profiles', 'current');
```

### Lazy boxes

A lazy box keeps only its keys in memory and reads each value from disk on
demand — the right choice when values are large blobs or the box holds a lot of
entries.

```dart
await BaabaStorage.hive.openLazyBox('queue');

// Writes and metadata are identical to a regular box
await BaabaStorage.hive.put('queue', 'job-1', payload);
BaabaStorage.hive.length('queue');
BaabaStorage.hive.getKeys('queue');
await BaabaStorage.hive.delete('queue', 'job-1');

// Reads are async, because that is when the disk read happens
final job = await BaabaStorage.hive.getLazy<String>('queue', 'job-1');
final all = await BaabaStorage.hive.getAllLazy<String>('queue');
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
await BaabaStorage.hive.openLazyBox('queue');
await BaabaStorage.hive.openBox('queue');  // throws BoxTypeMismatchException
```

### Encrypting Hive boxes

A Hive box is a plain file in the app's data directory. Anything in it — an ID
number, a biometric template, a health record — is readable by anyone who can
read that file: a rooted or jailbroken device, an ADB backup, a stolen phone, a
forensic image. Pass a cipher to encrypt the box with AES-256 at rest:

```dart
await BaabaStorage.hive.openBox(
  'citizens',
  encryptionCipher: await BaabaStorage.hiveCipher(),
);
```

`openTypedBox` and `openLazyBox` take the same parameter. Everything after the
open is unchanged — `put`, `get`, `watch` and the rest behave exactly as they do
on a plaintext box.

`BaabaStorage.hiveCipher()` resolves a stable per-install AES-256 key: it reads
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
> final old = await BaabaStorage.hive.openBox('citizens');
> final entries = {for (final k in old.keys) k: old.get(k)};
> await BaabaStorage.hive.closeBox('citizens');
>
> // 2. Write it into a new, encrypted box — a NEW NAME, so the original stays
> //    intact until the copy is safely on disk.
> await BaabaStorage.hive.openBox(
>   'citizens_enc',
>   encryptionCipher: await BaabaStorage.hiveCipher(),
> );
> await BaabaStorage.hive.putAll('citizens_enc', entries);
> await BaabaStorage.hive.closeBox('citizens_enc');
>
> // 3. Only now delete the original, and record that the migration ran so a
> //    half-finished attempt can be resumed rather than repeated blindly.
> await BaabaStorage.hive.deleteBox('citizens');
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
final onDisk = await BaabaStorage.hive.boxExistsOnDisk('citizens');
final hasKey = await BaabaStorage.secure.containsKey(BaabaStorage.hiveKeyAlias);

if (onDisk && !hasKey) {
  // Encrypted data that can no longer be read. Tell the user and re-fetch, or
  // delete the box deliberately with deleteBox. Do NOT generate a new key and
  // open it anyway — the open fails, and only the old key can read the file.
}
```

`hiveCipher()` never replaces a key that is present but unreadable; it throws a
`StorageException` instead, because generating a replacement would make every
box encrypted with the original permanently unrecoverable.

### Reactive UI with ValueListenableBuilder

```dart
ValueListenableBuilder<Box>(
  valueListenable: BaabaStorage.hive.listenable('settings'),
  builder: (context, box, _) {
    final theme = box.get('theme', defaultValue: 'light');
    return Text('Theme: $theme');
  },
);
```

### Watch a stream of changes

```dart
BaabaStorage.hive.watch('settings', key: 'theme').listen((event) {
  print('theme changed to ${event.value}');
});
```

---

## Secure Storage — `BaabaStorage.secure`

Hardware-backed encrypted storage. Uses Android Keystore, iOS Keychain, and OS equivalents on other platforms.

### Token shortcuts

```dart
// Save / read / delete a single auth token
await BaabaStorage.secure.saveToken('Bearer eyJhbGci...');
final token = await BaabaStorage.secure.getToken();     // String?
final exists = await BaabaStorage.secure.hasToken();    // bool
await BaabaStorage.secure.deleteToken();
```

### Multiple headers (Authorization + API keys)

```dart
// Save a full set of request headers
await BaabaStorage.secure.saveAuthHeaders({
  'Authorization': 'Bearer eyJhbGci...',
  'X-Api-Key': 'secret-key-123',
});

// Read them back as a Map<String, String>
final headers = await BaabaStorage.secure.getAuthHeaders();
// Use in http / dio:
// dio.options.headers = headers;

// Delete all saved headers
await BaabaStorage.secure.deleteAuthHeaders();
```

### Generic read / write

```dart
await BaabaStorage.secure.write('refresh_token', 'abc123');
final refresh = await BaabaStorage.secure.read('refresh_token');
final fallback = await BaabaStorage.secure.readOrDefault('refresh_token', '');

await BaabaStorage.secure.delete('refresh_token');
await BaabaStorage.secure.deleteAll();

final exists = await BaabaStorage.secure.containsKey('refresh_token');
final all    = await BaabaStorage.secure.readAll();  // Map<String, String>
```

### Custom platform options

```dart
// Call configure() BEFORE BaabaStorage.init() if you need custom options
SecureStorage.configure(
  androidOptions: const AndroidOptions(
    resetOnError: false,
  ),
  iosOptions: const IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);
await BaabaStorage.init();
```

The options are `flutter_secure_storage`'s own. `encryptedSharedPreferences` and
`sharedPreferencesName` were removed in its v11 — use `storageNamespace` to
isolate an instance.

These option types are re-exported, so the example needs only
`import 'package:baaba_storage_utils/baaba_storage_utils.dart';`.

> ⚠️ **`resetOnError` defaults to `true` on Android.** In the plugin's own
> words, when an error is detected it resets all data, which will "PERMANENTLY
> erase the data". That includes the key `hiveCipher()` keeps, leaving every
> encrypted Hive box unreadable for good. Apps with encrypted boxes should
> consider `resetOnError: false`, as the example above does, and handle the
> error that secure-storage calls then throw (sign the user out, re-fetch).

---

## Hive subdirectory

```dart
await BaabaStorage.init(hiveSubDir: 'app_data');
// Hive files are stored in <documents>/app_data/
```

---

## Lifecycle

```dart
// Close all Hive boxes when the app is shutting down
await BaabaStorage.dispose();
```

---

## Error handling

| Exception | When thrown |
|---|---|
| `StorageNotInitializedException` | Any storage accessed before `BaabaStorage.init()` |
| `BoxNotOpenException` | `hive.get/put/delete` called on a box that was never opened |
| `BoxIsLazyException` | `hive.get`, `getAll` or `listenable` called on a lazy box — use `getLazy` / `getAllLazy` |
| `BoxTypeMismatchException` | A box name is already open in another flavour (lazy vs regular, or a different value type) |
| `BoxEncryptionMismatchException` | A box name is already open with a different encryption intent than the one requested — including a box opened outside `BaabaStorage`, whose cipher cannot be verified |
| `UnsupportedTypeException` | `prefs.set<T>` called with an unsupported type |
| `HiveError` | Passed through from Hive when a box cannot be decoded with the cipher given — a wrong key, no key for an encrypted box, or a key for a cleartext file. The file is left untouched |

```dart
try {
  await BaabaStorage.prefs.set<Map>('data', {});
} on UnsupportedTypeException catch (e) {
  // use BaabaStorage.hive instead
}
```

---

## Upgrading from 1.x

2.0.0 swaps the unmaintained `hive` for `hive_ce` and moves to
`flutter_secure_storage` 11. This package's API is unchanged and existing data
stays readable: `hive_ce` uses the same file format, and secrets written through
1.x are already in the format v11 reads. What an app has to change:

1. **SDK:** Dart 3.8+, Flutter 3.44+, Android `minSdk` 24.
2. **Imports:** `package:hive/hive.dart` → `package:hive_ce/hive_ce.dart`,
   `package:hive_flutter/hive_flutter.dart` →
   `package:hive_ce_flutter/hive_ce_flutter.dart`.
3. **Generator:** replace `hive_generator` with `hive_ce_generator` and
   regenerate adapters (`dart run build_runner build`).
4. **Remove every original Hive package.** `flutter pub deps | grep hive` should
   list only `hive_ce` and `hive_ce_flutter`. Two Hive copies in one app keep
   separate adapter registries and can open the same box file twice.
5. **Secure storage options:** drop `encryptedSharedPreferences:` and
   `sharedPreferencesName:` from any `AndroidOptions`.
6. **Only if the app used `flutter_secure_storage` older than v10 directly:**
   v11 cannot read the pre-v10 formats, so users who skip straight to a v11
   build lose those secrets. Ship a v10 build first, or detect the loss with
   `FlutterSecureStorage().checkUpgradeStatus()`.

See [CHANGELOG.md](CHANGELOG.md) for the full list.
