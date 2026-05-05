# baaba_storage_utils

A unified Flutter storage package that wraps **SharedPreferences**, **Hive**, and **Flutter Secure Storage** behind one clean API.

| Storage | Best for |
|---|---|
| `BaabaStorage.prefs` | Simple flags, settings, primitive values |
| `BaabaStorage.hive` | Lists, maps, custom objects, reactive UI |
| `BaabaStorage.secure` | Tokens, API keys, passwords |

---

## Setup

### 1. Add the dependency

```yaml
dependencies:
  baaba_storage_utils:
    path: ../baaba_storage_utils   # or pub.dev version once published
```

### 2. Android — minimum SDK

`flutter_secure_storage` requires `minSdkVersion 18`. In `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdkVersion 18
    }
}
```

### 3. Initialize once in `main()`

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
// 1. Annotate your model (or write the adapter manually)
@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0) late String name;
  @HiveField(1) late int age;
}

// 2. Register the adapter before opening the box
BaabaStorage.hive.registerAdapter(UserProfileAdapter());

// 3. Open a typed box
await BaabaStorage.hive.openBox<UserProfile>('profiles');

// 4. Store and retrieve
final profile = UserProfile()..name = 'Zunair'..age = 25;
await BaabaStorage.hive.put('profiles', 'current', profile);
final loaded = BaabaStorage.hive.get<UserProfile>('profiles', 'current');
```

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
    encryptedSharedPreferences: true,
    resetOnError: true,
  ),
  iosOptions: const IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);
await BaabaStorage.init();
```

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
| `UnsupportedTypeException` | `prefs.set<T>` called with an unsupported type |

```dart
try {
  await BaabaStorage.prefs.set<Map>('data', {});
} on UnsupportedTypeException catch (e) {
  // use BaabaStorage.hive instead
}
```
