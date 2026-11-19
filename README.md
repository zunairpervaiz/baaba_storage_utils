# baaba_storage_utils

This repository holds two Flutter storage packages, versioned and released
together.

| Package | What it gives you | Depends on |
|---|---|---|
| [`baaba_storage_utils`](packages/baaba_storage_utils) | `BaabaStorage.prefs` (SharedPreferences) and `BaabaStorage.secure` (Flutter Secure Storage) | — |
| [`baaba_storage_hive`](packages/baaba_storage_hive) | `BaabaHive`: Hive boxes (regular, typed, lazy), optionally AES-256 encrypted with a key kept in secure storage | `baaba_storage_utils` |

**Pick one dependency:**

- Prefs and secure storage only → `baaba_storage_utils`.
- Also Hive → `baaba_storage_hive`. It brings `baaba_storage_utils` with it and
  re-exports it, so you need one dependency and one import.

```yaml
dependencies:
  baaba_storage_hive: ^3.0.0     # or baaba_storage_utils: ^3.0.0
```

Both are published on pub.dev. Developing here: this repository is a pub
workspace, so run `flutter pub get` once at the root, and `baaba_storage_hive`
resolves its `baaba_storage_utils` dependency to `packages/baaba_storage_utils`
rather than the published version.

Upgrading from 2.x, where Hive was part of `baaba_storage_utils`? See
[the core package's upgrade guide](packages/baaba_storage_utils/README.md#upgrading-from-2x).
