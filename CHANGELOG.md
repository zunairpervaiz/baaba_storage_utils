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
