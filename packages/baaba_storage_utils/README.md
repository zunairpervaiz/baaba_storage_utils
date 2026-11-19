# baaba_storage_utils

A unified Flutter storage package that wraps **SharedPreferences** and **Flutter Secure Storage** behind one clean API.

| Storage | Best for | Reactive? |
|---|---|---|
| `BaabaStorage.prefs` | Simple flags, settings, primitive values | ✅ `watch` / `listenable` |
| `BaabaStorage.secure` | Tokens, API keys, passwords | — |

**Need Hive boxes** (lists, maps, custom objects, optionally AES-256 encrypted at
rest)? Use [`baaba_storage_hive`](https://pub.dev/packages/baaba_storage_hive) instead. It builds on
this package and re-exports it, so a Hive app depends on that one package.

---

## Setup

### 1. Add the dependency

```yaml
dependencies:
  baaba_storage_utils: ^3.0.0
```

Requires Dart 3.11+ and Flutter 3.41+ (both set by `shared_preferences` 2.5.6).

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
await BaabaStorage.init(
  secureAndroidOptions: const AndroidOptions(
    resetOnError: false,
  ),
  secureIOSOptions: const IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);
```

`SecureStorage.configure(...)` called before `BaabaStorage.init()` (with no
options passed to `init`) does the same. Options passed to `init` replace an
earlier `configure` entirely.

Choose these once. Options that decide where secrets are kept
(`storageNamespace`, `preferencesKeyPrefix`, iOS `accountName` / `groupId` /
`synchronizable` / `accessibility`) cannot be changed in a later release
without migrating the stored secrets: the app would look for them somewhere
else and find nothing.

The options are `flutter_secure_storage`'s own. `encryptedSharedPreferences` and
`sharedPreferencesName` were removed in its v11 — use `storageNamespace` to
isolate an instance.

These option types are re-exported, so the example needs only
`import 'package:baaba_storage_utils/baaba_storage_utils.dart';`.

> ⚠️ **`resetOnError` defaults to `true` on Android.** In the plugin's own
> words, when an error is detected it resets all data, which will "PERMANENTLY
> erase the data". With `baaba_storage_hive`, that includes the key
> `BaabaHive.cipher()` keeps, leaving every encrypted Hive box unreadable for
> good. Apps with encrypted boxes should consider `resetOnError: false`, as the
> example above does, and handle the error that secure-storage calls then throw
> (sign the user out, re-fetch).

---

## Lifecycle

```dart
// Reset the initialisation flag, e.g. to re-run init() with other options
await BaabaStorage.dispose();
```

---

## Error handling

| Exception | When thrown |
|---|---|
| `StorageNotInitializedException` | Any storage accessed before `BaabaStorage.init()` |
| `UnsupportedTypeException` | `prefs.set<T>` called with an unsupported type |

```dart
try {
  await BaabaStorage.prefs.set<Map>('data', {});
} on UnsupportedTypeException catch (e) {
  // store maps and objects in a Hive box (baaba_storage_hive) instead
}
```

---

## Upgrading from 2.x

3.0.0 moves Hive out of this package into
[`baaba_storage_hive`](https://pub.dev/packages/baaba_storage_hive). Prefs and secure storage are
unchanged, and so is all stored data.

- **The constraint:** `^2.0.0` never resolves to 3.0.0, so apps keep getting
  2.x until you change it to `^3.0.0` (prefs and secure only) or switch to
  `baaba_storage_hive: ^3.0.0` (Hive). Nothing changes for an app until then.
- **App uses only prefs and secure storage:** remove `hiveSubDir:` from
  `BaabaStorage.init` if you passed it. Nothing else changes. Hive and its
  dependencies are no longer in your build, and the Flutter floor drops from
  3.44 to 3.41. The Dart floor rises from 3.8 to 3.11, because
  `shared_preferences` 2.5.6 requires it.
- **App uses Hive:** switch your dependency to `baaba_storage_hive` and follow
  [its upgrade guide](https://pub.dev/packages/baaba_storage_hive#upgrading-from-2x).
  The old `BaabaStorage.hive`, `hiveCipher()` and `hiveKeyAlias` no longer
  exist; `BaabaStorage.dispose()` no longer closes Hive boxes.
- **App calls `SecureStorage.configure(...)` before `BaabaStorage.init()`:**
  read the first Fixed entry in [CHANGELOG.md](CHANGELOG.md) *before*
  upgrading. Those options used to be silently replaced by the defaults and
  now take effect. If they include a storage location such as
  `storageNamespace`, existing secrets, including the Hive encryption key,
  would no longer be found.
- **`PrefsStorage.get<List<String>>`** now returns stored string lists after an
  app restart instead of `defaultValue`.
- **`UnsupportedTypeException`'s message** now points at `baaba_storage_hive`
  rather than `HiveStorage`, in case anything matches on it.

## Upgrading from 1.x

Apply these first, then the 2.x steps above. The Hive steps (2–4) concern apps
that now use `baaba_storage_hive`.

2.0.0 swaps the unmaintained `hive` for `hive_ce` and moves to
`flutter_secure_storage` 11. This package's API is unchanged and existing data
stays readable: `hive_ce` uses the same file format, and secrets written through
1.x are already in the format v11 reads. What an app has to change:

1. **SDK:** Android `minSdk` 24, and the Dart/Flutter floors in Setup.
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
