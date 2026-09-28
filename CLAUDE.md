# baaba_storage_utils

Flutter package: one facade (`BaabaStorage`) over SharedPreferences, Hive
(`hive_ce`) and `flutter_secure_storage`. Consumed by other apps as a path/git
dependency. Not yet on pub.dev.

## Commands

```bash
flutter pub get
flutter analyze              # must report "No issues found!"
flutter test                 # single file: test/baaba_storage_utils_test.dart
flutter pub publish --dry-run  # 2 known warnings: uncommitted files, empty homepage
```

## Layout

- `lib/baaba_storage_utils.dart` — public entry point. Re-exports selected Hive
  types (`Box`, `LazyBox`, `TypeAdapter`, `HiveAesCipher`, …) and
  `flutter_secure_storage` option types (`AndroidOptions`, `IOSOptions`,
  `KeychainAccessibility`, …) with explicit `show` lists, because the public API
  takes or returns them. Adding a type to a signature means adding it here.
- `lib/src/baaba_storage.dart` — the static facade: `init`, `prefs`, `hive`,
  `secure`, `hiveCipher`, `hiveKeyAlias`, `dispose`.
- `lib/src/hive/hive_storage.dart` — box wrapper (regular, typed, lazy) with
  its own per-session bookkeeping of box flavour and encryption intent.
- `lib/src/hive/hive_cipher.dart` — `HiveKeyStore`: per-install AES-256 key in
  secure storage, memoised and single-flight.
- `lib/src/prefs/`, `lib/src/secure/` — thin singletons over the plugins.
- `lib/src/exceptions/storage_exception.dart` — every exception the package
  throws. Messages name the fix, not just the fault.

## Dependencies — read before touching pubspec

- **Hive is `hive_ce`, never `hive`.** Import `package:hive_ce/hive_ce.dart` /
  `package:hive_ce_flutter/hive_ce_flutter.dart`. The original `hive` and
  `hive_generator` must not come back, even transitively: two Hive copies in one
  app have separate singletons and adapter registries.
- `hive_ce` shares Hive 2.x's file format, in both directions. Keep type IDs
  within 0–223 in examples and tests: higher IDs are `hive_ce`-only.
- `flutter_secure_storage` is v11. `encryptedSharedPreferences` and
  `sharedPreferencesName` no longer exist; default Android options are plain
  `AndroidOptions()`.
- Floors: Dart 3.8 (`flutter_secure_storage` 11), Flutter 3.44
  (`hive_ce_flutter`), Android `minSdk` 24. A dependency bump that raises one
  of these must also update `pubspec.yaml`, the README's Setup section and the
  CHANGELOG.

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
- `hiveCipher()` never replaces a key that exists but can't be decoded; it
  throws instead.

## Testing

- Everything runs on the VM with fakes: `SharedPreferences.setMockInitialValues`,
  `FlutterSecureStorage.setMockInitialValues` (keeps the map by reference, so
  tests inspect it), and `HiveStorage.initForTest(tempDir)` per group.
- Custom types use hand-written `TypeAdapter`s so tests need no build_runner.
- These fakes never touch Keystore/Keychain. Changes to secure storage,
  `hiveCipher` or a dependency bump also need an upgrade run on a real device
  or emulator (a `Pixel_9` AVD exists): build a small app APK against the
  previous release (`git archive <tag>`) that writes data, install it, launch
  it; rebuild against the working tree, `adb install -r` (keeps app data),
  launch, and check everything reads back. Don't use `flutter test` for this:
  it uninstalls the app afterwards, wiping the data. Target the emulator with
  `-s emulator-5554`; a physical phone may also be attached.
- Linux desktop builds need `libsecret-1-dev` installed.
- The office proxy sometimes refuses `dl.google.com`, which makes Android
  Gradle builds fail while downloading artifacts. That's the network, not the
  code; retry later.

## Conventions

- Doc comments explain *why*, including the Hive/plugin behaviour a decision
  relies on. Match the existing density; comments in `hive_storage.dart` are
  long on purpose.
- Every user-visible change gets a CHANGELOG entry under the top version,
  grouped `Changed` / `Added` / `Fixed` / `Documentation`, with breaking
  consumer impact called out explicitly.
- README code must compile for a consumer that imports only
  `package:baaba_storage_utils/baaba_storage_utils.dart`.
