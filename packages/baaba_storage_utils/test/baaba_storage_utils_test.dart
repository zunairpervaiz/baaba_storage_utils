import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baaba_storage_utils/baaba_storage_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── PrefsStorage ────────────────────────────────────────────────────────
  group('PrefsStorage', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrefsStorage.init();
    });

    test('set and get String', () async {
      await PrefsStorage.instance.setString('name', 'Zunair');
      expect(PrefsStorage.instance.getString('name'), 'Zunair');
    });

    test('set and get int', () async {
      await PrefsStorage.instance.setInt('age', 25);
      expect(PrefsStorage.instance.getInt('age'), 25);
    });

    test('set and get double', () async {
      await PrefsStorage.instance.setDouble('score', 9.5);
      expect(PrefsStorage.instance.getDouble('score'), 9.5);
    });

    test('set and get bool', () async {
      await PrefsStorage.instance.setBool('loggedIn', true);
      expect(PrefsStorage.instance.getBool('loggedIn'), true);
    });

    test('set and get List<String>', () async {
      await PrefsStorage.instance.setStringList('tags', ['flutter', 'dart']);
      expect(
        PrefsStorage.instance.getStringList('tags'),
        ['flutter', 'dart'],
      );
    });

    test('generic set<T> and get<T>', () async {
      await PrefsStorage.instance.set<String>('city', 'Lahore');
      expect(PrefsStorage.instance.get<String>('city'), 'Lahore');
    });

    test('returns defaultValue for missing key', () {
      expect(
        PrefsStorage.instance.getString('missing', defaultValue: 'N/A'),
        'N/A',
      );
      expect(PrefsStorage.instance.getInt('missing', defaultValue: 0), 0);
      expect(
        PrefsStorage.instance.getBool('missing', defaultValue: false),
        false,
      );
    });

    test('containsKey', () async {
      await PrefsStorage.instance.setString('x', '1');
      expect(PrefsStorage.instance.containsKey('x'), true);
      expect(PrefsStorage.instance.containsKey('y'), false);
    });

    test('remove key', () async {
      await PrefsStorage.instance.setString('temp', 'value');
      await PrefsStorage.instance.remove('temp');
      expect(PrefsStorage.instance.containsKey('temp'), false);
    });

    test('clear all keys', () async {
      await PrefsStorage.instance.setString('a', '1');
      await PrefsStorage.instance.setString('b', '2');
      await PrefsStorage.instance.clear();
      expect(PrefsStorage.instance.getKeys(), isEmpty);
    });

    test('getAll returns map of all stored values', () async {
      SharedPreferences.setMockInitialValues({});
      await PrefsStorage.init();
      await PrefsStorage.instance.setString('k1', 'v1');
      await PrefsStorage.instance.setInt('k2', 42);
      final all = PrefsStorage.instance.getAll();
      expect(all['k1'], 'v1');
      expect(all['k2'], 42);
    });

    test('string lists loaded from the platform read back as List<String>',
        () async {
      // What the platform hands SharedPreferences on a cold start: a list of
      // Object?, not List<String>. A list written in-session is already typed,
      // which is why only a restart showed the bug.
      SharedPreferences.setMockInitialValues({'tags': <Object?>['a', 'b']});
      await PrefsStorage.init();
      expect(PrefsStorage.instance.get<List<String>>('tags'), ['a', 'b']);
      expect(PrefsStorage.instance.getAll()['tags'], isA<List<String>>());
      expect(
        PrefsStorage.instance.listenable('tags').value,
        isA<List<String>>(),
      );
    });

    test('throws UnsupportedTypeException for Map', () {
      expect(
        () => PrefsStorage.instance.set<Map>('map', {}),
        throwsA(isA<UnsupportedTypeException>()),
      );
    });

    // ── Reactive ────────────────────────────────────────────────────────────

    test('watch<String> emits new value on setString', () async {
      final future = PrefsStorage.instance.watch<String>('reactKey').first;
      await PrefsStorage.instance.setString('reactKey', 'hello');
      expect(await future, 'hello');
    });

    test('watch<bool> emits new value on set<T>', () async {
      final future = PrefsStorage.instance.watch<bool>('flag').first;
      await PrefsStorage.instance.set<bool>('flag', true);
      expect(await future, true);
    });

    test('watch emits null when key is removed', () async {
      await PrefsStorage.instance.setString('toRemove', 'bye');
      final future = PrefsStorage.instance.watch<String>('toRemove').first;
      await PrefsStorage.instance.remove('toRemove');
      expect(await future, null);
    });

    test('watch emits null for all keys on clear', () async {
      await PrefsStorage.instance.setString('c1', 'v1');
      await PrefsStorage.instance.setString('c2', 'v2');
      final f1 = PrefsStorage.instance.watch<String>('c1').first;
      final f2 = PrefsStorage.instance.watch<String>('c2').first;
      await PrefsStorage.instance.clear();
      expect(await f1, null);
      expect(await f2, null);
    });

    test('listenable updates value on write', () async {
      await PrefsStorage.instance.setInt('score', 0);
      final notifier = PrefsStorage.instance.listenable('score');
      expect(notifier.value, 0);
      await PrefsStorage.instance.setInt('score', 42);
      expect(notifier.value, 42);
    });

    test('changes stream fires MapEntry for every write', () async {
      final future = PrefsStorage.instance.changes.first;
      await PrefsStorage.instance.setString('evt', 'fired');
      final entry = await future;
      expect(entry.key, 'evt');
      expect(entry.value, 'fired');
    });
  });

  // ── BaabaStorage ──────────────────────────────────────────────────────────
  group('BaabaStorage', () {
    test('getters throw until init() has run', () {
      expect(BaabaStorage.isInitialized, isFalse);
      expect(
        () => BaabaStorage.prefs,
        throwsA(isA<StorageNotInitializedException>()),
      );
      expect(
        () => BaabaStorage.secure,
        throwsA(isA<StorageNotInitializedException>()),
      );
    });

    group('secure-storage configuration', () {
      setUp(() => SharedPreferences.setMockInitialValues({}));
      tearDown(BaabaStorage.dispose);

      test('init() without options keeps an earlier configure()', () async {
        // The README's pattern. init() used to reconfigure with defaults
        // unconditionally, so options set this way — a storageNamespace, say —
        // never took effect.
        SecureStorage.configure(
          androidOptions: const AndroidOptions(storageNamespace: 'mine'),
        );
        final configured = SecureStorage.instance;
        await BaabaStorage.init();
        expect(identical(BaabaStorage.secure, configured), isTrue);
      });

      test('init() with options replaces the configuration', () async {
        SecureStorage.configure(
          androidOptions: const AndroidOptions(storageNamespace: 'mine'),
        );
        final configured = SecureStorage.instance;
        await BaabaStorage.init(
          secureAndroidOptions: const AndroidOptions(resetOnError: false),
        );
        expect(identical(BaabaStorage.secure, configured), isFalse);
      });
    });
  });

  // ── StorageException ─────────────────────────────────────────────────────
  group('StorageException', () {
    test('StorageNotInitializedException message is descriptive', () {
      const ex = StorageNotInitializedException();
      expect(ex.toString(), contains('BaabaStorage is not initialized'));
    });

    test('StorageNotInitializedException.withMessage keeps the type', () {
      const ex = StorageNotInitializedException.withMessage('Call X.init().');
      expect(ex, isA<StorageNotInitializedException>());
      expect(ex.toString(), contains('Call X.init().'));
    });

    test('UnsupportedTypeException includes type name', () {
      final ex = UnsupportedTypeException(Map);
      expect(ex.toString(), contains('Map'));
    });
  });
}
