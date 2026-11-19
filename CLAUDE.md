# baaba_storage_utils (repository)

Two Flutter packages, versioned and released together (same version number,
one git tag `vX.Y.Z` for both). **Both are published on pub.dev** and consumed
from there (`baaba_storage_utils` since 1.0.0; `baaba_storage_hive` from 3.0.0).
A change to a published API breaks real apps: check pub.dev
(`https://pub.dev/api/packages/<name>`) rather than assuming.

- `packages/baaba_storage_utils` — core: one facade (`BaabaStorage`) over
  SharedPreferences and `flutter_secure_storage`. No Hive, ever.
- `packages/baaba_storage_hive` — `BaabaHive`: Hive (`hive_ce`) boxes with
  optional encryption. Depends on the core (the AES key lives in
  `SecureStorage`) and re-exports all of it, so a Hive app needs one
  dependency and one import.

Hive was split out in 3.0.0 so apps without Hive don't carry its dependencies,
its Flutter 3.44 floor, or its startup work.

## Commands

The repository root is a pub workspace (`pubspec.yaml` with `workspace:`, each
package `resolution: workspace`). One `flutter pub get` anywhere resolves both,
with one `pubspec.lock` and `.dart_tool` at the root. Inside the workspace
`baaba_storage_hive`'s hosted `baaba_storage_utils: ^X.Y.Z` constraint is met
by `packages/baaba_storage_utils`, so never turn it into a `path:` dependency.

Run the rest per package (`cd packages/<name>` first):

```bash
flutter analyze              # must report "No issues found!" in both
flutter test                 # one file each: test/<package>_test.dart
flutter pub publish --dry-run  # 2 known warnings each: uncommitted files, empty homepage
```

Releasing: bump both versions together, publish `baaba_storage_utils` first
(the Hive package's constraint must exist on pub.dev), then
`baaba_storage_hive`, then tag. Package READMEs and CHANGELOGs render on
pub.dev, so cross-package links use pub.dev URLs, never `../`.

## Layout

- `packages/baaba_storage_utils/lib/baaba_storage_utils.dart` — public entry.
  Re-exports the `flutter_secure_storage` option types (`AndroidOptions`,
  `IOSOptions`, `KeychainAccessibility`, …) with an explicit `show` list.
- `.../lib/src/baaba_storage.dart` — `init`, `prefs`, `secure`, `dispose`.
- `.../lib/src/prefs/`, `.../lib/src/secure/` — thin singletons over the plugins.
- `.../lib/src/exceptions/storage_exception.dart` — `StorageException` (the base
  of every exception in both packages), `StorageNotInitializedException`
  (`.withMessage` lets the Hive package name `BaabaHive.init()`),
  `UnsupportedTypeException`.
- `packages/baaba_storage_hive/lib/baaba_storage_hive.dart` — public entry.
  Re-exports the whole core library plus selected Hive types (`Box`,
  `LazyBox`, `TypeAdapter`, `HiveAesCipher`, …) with a `show` list, and only
  `HiveStorage` from `hive_storage.dart`.
- `.../lib/src/baaba_hive.dart` — `init(subDir:)`, `instance`, `cipher`,
  `keyAlias`, `dispose`.
- `.../lib/src/hive_storage.dart` — box wrapper (regular, typed, lazy) with
  its own per-session bookkeeping of box flavour and encryption intent.
- `.../lib/src/hive_cipher.dart` — `HiveKeyStore`: per-install AES-256 key in
  secure storage, memoised and single-flight.
- `.../lib/src/hive_exceptions.dart` — the `Box*` exceptions.

Adding a type to a public signature means adding it to that package's
re-export list.

## Dependencies — read before touching a pubspec

- **The core must not depend on Hive** (`hive_ce`, `hive_ce_flutter`),
  directly or transitively. Check with `flutter pub deps | grep -i hive` in
  the core: it must print nothing. (`path_provider` does stay in the core's
  tree: `flutter_secure_storage`'s Linux and Windows implementations use it.)
- **Hive is `hive_ce`, never `hive`.** Import `package:hive_ce/hive_ce.dart` /
  `package:hive_ce_flutter/hive_ce_flutter.dart`. The original `hive` and
  `hive_generator` must not come back, even transitively: two Hive copies in one
  app have separate singletons and adapter registries.
- `hive_ce` shares Hive 2.x's file format, in both directions. Keep type IDs
  within 0–223 in examples and tests: higher IDs are `hive_ce`-only.
- `flutter_secure_storage` is v11. `encryptedSharedPreferences` and
  `sharedPreferencesName` no longer exist; default Android options are plain
  `AndroidOptions()`.
- Floors: core Dart 3.11 / Flutter 3.41 (`shared_preferences` 2.5.6); Hive
  package Flutter 3.44 (`hive_ce_flutter`); Android `minSdk` 24 for both. A
  bump that raises one must also update that package's `pubspec.yaml`, its
  README Setup section and its CHANGELOG.

## Behaviour the tests pin (don't "fix" these)

- `crashRecovery` defaults to `false` when a cipher is passed, `true` otherwise
  (`_resolveCrashRecovery`).
- `hive_ce` 2.20.1+ throws `HiveError` on a wrong or missing cipher without
  truncating the file. The original `hive` silently wiped the box. Tests assert
  the data survives.
- A box name is open in exactly one flavour and one encryption intent per
  session; a conflicting open throws `BoxTypeMismatchException` /
  `BoxEncryptionMismatchException`. A box opened outside the wrapper counts as
  *unknown* encryption and cannot be claimed as encrypted.
- `BaabaHive.cipher()` never replaces a key that exists but can't be decoded;
  it throws instead.
- `BaabaHive.cipher()` requires `BaabaStorage.init()` (not just
  `BaabaHive.init()`): the key must be read with the app's secure-storage
  options, or it lands in a different namespace and existing boxes are lost.
- `BaabaHive.keyAlias` is `'baaba_hive_key'` forever. Every encrypted box
  since 1.3.0 depends on it.
- Concurrent opens of one box name behave as if sequential: the second waits
  for the first (`_opening` / `_awaitOpening` / `_openGuarded`) and is checked
  against its result. Hive itself returns the in-flight box and ignores the
  second caller's cipher. Two rules keep this race-free: nothing is awaited
  between the in-flight check and `_openGuarded`, and `_remember` runs inside
  the guarded callback so waiters find the box already tracked.
- `HiveKeyStore.resolve` caches the in-flight future (single-flight) and, on
  failure, evicts only its own entry (`identical` check).
- `BaabaStorage.init()` reconfigures secure storage only when given options.
  With none, it keeps an earlier `SecureStorage.configure()`. Before 3.0.0 it
  always reset to defaults, so apps that used `configure()` have their
  secrets under the defaults; see the core CHANGELOG's Fixed entry.
- `PrefsStorage.get` / `getAll` / `listenable` return string lists as
  `List<String>`. SharedPreferences hands lists loaded from the platform over
  as `List<Object?>`; only its own `getStringList` casts.

## Testing

- Everything runs on the VM with fakes: `SharedPreferences.setMockInitialValues`,
  `FlutterSecureStorage.setMockInitialValues` (keeps the map by reference, so
  tests inspect it), and `HiveStorage.initForTest(tempDir)` per group.
- Custom types use hand-written `TypeAdapter`s so tests need no build_runner.
- These fakes never touch Keystore/Keychain. Changes to secure storage,
  `BaabaHive.cipher`, the box directory or a dependency bump also need an
  upgrade run on a real device or emulator: build a small app APK against the
  previous release (`git archive <tag>`) that writes data, install it, launch
  it; rebuild against the working tree, `adb install -r` (keeps app data),
  launch, and check everything reads back. Don't use `flutter test` for this:
  it uninstalls the app afterwards, wiping the data. Target the emulator with
  `-s emulator-5554`; a physical phone may also be attached. AVDs differ per
  machine (`flutter emulators` lists them).
- README code must compile for a consumer that imports only that package's
  library. Check it by analyzing the snippets in a scratch app with path
  dependencies on both packages.
- A scratch app outside the workspace that uses the unreleased Hive package
  (snippet checks, device upgrade runs) needs
  `dependency_overrides: baaba_storage_utils: {path: .../packages/baaba_storage_utils}`:
  pub will not satisfy the Hive package's hosted constraint with a path
  dependency.
- Linux desktop builds need `libsecret-1-dev` installed.
- The office proxy sometimes refuses `dl.google.com`, which makes Android
  Gradle builds fail while downloading artifacts. That's the network, not the
  code; retry later.

## Conventions

- Doc comments explain *why*, including the Hive/plugin behaviour a decision
  relies on. Match the existing density; comments in `hive_storage.dart` are
  long on purpose.
- Every user-visible change gets a CHANGELOG entry under the top version of
  each affected package, grouped `Changed` / `Added` / `Fixed` /
  `Documentation`, with breaking consumer impact called out explicitly.
