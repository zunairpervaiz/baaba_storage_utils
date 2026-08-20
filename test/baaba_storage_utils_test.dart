import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baaba_storage_utils/baaba_storage_utils.dart';
// Reaching into src is deliberate: the key-store logic is package-internal, and
// testing it directly avoids having to stand up a fake path_provider just to
// satisfy the BaabaStorage.init() guard on the public entry point. The guard
// itself is tested through the public API below.
import 'package:baaba_storage_utils/src/hive/hive_cipher.dart';

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

  // ── HiveStorage ─────────────────────────────────────────────────────────
  group('HiveStorage', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_test_');
      HiveStorage.initForTest(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('open box and put/get String', () async {
      await HiveStorage.instance.openBox('strBox');
      await HiveStorage.instance.put('strBox', 'name', 'Zunair');
      expect(HiveStorage.instance.get<String>('strBox', 'name'), 'Zunair');
    });

    test('put/get int', () async {
      await HiveStorage.instance.openBox('intBox');
      await HiveStorage.instance.put('intBox', 'count', 42);
      expect(HiveStorage.instance.get<int>('intBox', 'count'), 42);
    });

    test('put/get Map (dynamic box)', () async {
      await HiveStorage.instance.openBox('mapBox');
      await HiveStorage.instance
          .put('mapBox', 'user', {'name': 'Ali', 'age': 30});
      final user = HiveStorage.instance.get<Map>('mapBox', 'user');
      expect(user?['name'], 'Ali');
    });

    test('containsKey', () async {
      await HiveStorage.instance.openBox('ckBox');
      await HiveStorage.instance.put('ckBox', 'exists', true);
      expect(HiveStorage.instance.containsKey('ckBox', 'exists'), true);
      expect(HiveStorage.instance.containsKey('ckBox', 'missing'), false);
    });

    test('delete key', () async {
      await HiveStorage.instance.openBox('delBox');
      await HiveStorage.instance.put('delBox', 'temp', 'val');
      await HiveStorage.instance.delete('delBox', 'temp');
      expect(HiveStorage.instance.containsKey('delBox', 'temp'), false);
    });

    test('clearBox empties all entries', () async {
      await HiveStorage.instance.openBox('clrBox');
      await HiveStorage.instance.put('clrBox', 'k1', 'v1');
      await HiveStorage.instance.put('clrBox', 'k2', 'v2');
      await HiveStorage.instance.clearBox('clrBox');
      expect(HiveStorage.instance.length('clrBox'), 0);
    });

    test('getAll returns all values', () async {
      await HiveStorage.instance.openBox('allBox');
      await HiveStorage.instance.put('allBox', 'a', 1);
      await HiveStorage.instance.put('allBox', 'b', 2);
      expect(HiveStorage.instance.getAll<int>('allBox'), containsAll([1, 2]));
    });

    test('putAll stores multiple entries at once', () async {
      await HiveStorage.instance.openBox('paBox');
      await HiveStorage.instance.putAll('paBox', {'x': 10, 'y': 20, 'z': 30});
      expect(HiveStorage.instance.length('paBox'), 3);
    });

    test('throws BoxNotOpenException for closed box', () {
      expect(
        () => HiveStorage.instance.get('notOpenBox', 'key'),
        throwsA(isA<BoxNotOpenException>()),
      );
    });

    test('isBoxOpen reflects actual state', () async {
      await HiveStorage.instance.openBox('openCheck');
      expect(HiveStorage.instance.isBoxOpen('openCheck'), true);
      await HiveStorage.instance.closeBox('openCheck');
      expect(HiveStorage.instance.isBoxOpen('openCheck'), false);
    });

    test('watch emits event on put', () async {
      await HiveStorage.instance.openBox('watchBox');
      final eventFuture = HiveStorage.instance.watch('watchBox').first;
      await HiveStorage.instance.put('watchBox', 'signal', 'ping');
      final event = await eventFuture;
      expect(event, isA<BoxEvent>());
      expect(event.value, 'ping');
    });
  });

  // ── HiveStorage: lazy boxes ─────────────────────────────────────────────
  //
  // Everything on BoxBase (writes, deletes, keys, watch, close) is legal on a
  // lazy box; only the three synchronous value reads are not.
  group('HiveStorage — lazy boxes', () {
    late Directory tempDir;
    final hive = HiveStorage.instance;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_lazy_test_');
      HiveStorage.initForTest(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('put then getLazy round-trips', () async {
      await hive.openLazyBox('lazyBox');
      await hive.put('lazyBox', 'name', 'Zunair');
      expect(await hive.getLazy<String>('lazyBox', 'name'), 'Zunair');
    });

    test('getLazy returns defaultValue for a missing key', () async {
      await hive.openLazyBox('lazyDefault');
      expect(
        await hive.getLazy<String>('lazyDefault', 'nope', defaultValue: 'N/A'),
        'N/A',
      );
    });

    test('getLazy returns defaultValue on a type mismatch', () async {
      await hive.openLazyBox('lazyMismatch');
      await hive.put('lazyMismatch', 'n', 'not-an-int');
      expect(await hive.getLazy<int>('lazyMismatch', 'n', defaultValue: -1), -1);
    });

    test('getLazy also works on a regular box', () async {
      await hive.openBox('eagerViaLazyGet');
      await hive.put('eagerViaLazyGet', 'k', 7);
      expect(await hive.getLazy<int>('eagerViaLazyGet', 'k'), 7);
    });

    test('putAll / getKeys / length / isEmpty / containsKey', () async {
      await hive.openLazyBox('lazyMeta');
      expect(hive.isEmpty('lazyMeta'), true);
      await hive.putAll('lazyMeta', {'x': 10, 'y': 20, 'z': 30});
      expect(hive.length('lazyMeta'), 3);
      expect(hive.isEmpty('lazyMeta'), false);
      expect(hive.getKeys('lazyMeta'), containsAll(['x', 'y', 'z']));
      expect(hive.containsKey('lazyMeta', 'x'), true);
      expect(hive.containsKey('lazyMeta', 'absent'), false);
    });

    test('getAllLazy returns every value', () async {
      await hive.openLazyBox('lazyAll');
      await hive.putAll('lazyAll', {'a': 1, 'b': 2, 'c': 3});
      expect(await hive.getAllLazy<int>('lazyAll'), containsAll([1, 2, 3]));
    });

    test('getAllLazy skips values of the wrong type', () async {
      await hive.openLazyBox('lazyMixed');
      await hive.putAll('lazyMixed', {'a': 1, 'b': 'two', 'c': 3});
      expect(await hive.getAllLazy<int>('lazyMixed'), [1, 3]);
    });

    test('getAllLazy also works on a regular box', () async {
      await hive.openBox('eagerViaLazyAll');
      await hive.putAll('eagerViaLazyAll', {'a': 1, 'b': 2});
      expect(await hive.getAllLazy<int>('eagerViaLazyAll'), containsAll([1, 2]));
    });

    test('delete / deleteKeys / clearBox', () async {
      await hive.openLazyBox('lazyDelete');
      await hive.putAll('lazyDelete', {'a': 1, 'b': 2, 'c': 3, 'd': 4});
      await hive.delete('lazyDelete', 'a');
      expect(hive.containsKey('lazyDelete', 'a'), false);
      await hive.deleteKeys('lazyDelete', ['b', 'c']);
      expect(hive.length('lazyDelete'), 1);
      await hive.clearBox('lazyDelete');
      expect(hive.length('lazyDelete'), 0);
    });

    test('watch emits an event on put', () async {
      await hive.openLazyBox('lazyWatch');
      final eventFuture = hive.watch('lazyWatch').first;
      await hive.put('lazyWatch', 'signal', 'ping');
      final event = await eventFuture;
      expect(event, isA<BoxEvent>());
      expect(event.key, 'signal');
    });

    test('closeBox closes a lazy box — the logout path', () async {
      await hive.openLazyBox('lazyClose');
      expect(hive.isBoxOpen('lazyClose'), true);
      await hive.closeBox('lazyClose');
      expect(hive.isBoxOpen('lazyClose'), false);
    });

    test('deleteBox removes a lazy box from disk', () async {
      await hive.openLazyBox('lazyDeleteBox');
      await hive.put('lazyDeleteBox', 'k', 'v');
      await hive.deleteBox('lazyDeleteBox');
      expect(hive.isBoxOpen('lazyDeleteBox'), false);
    });

    test('isBoxLazy distinguishes the two flavours', () async {
      await hive.openLazyBox('flavourLazy');
      await hive.openBox('flavourEager');
      expect(hive.isBoxLazy('flavourLazy'), true);
      expect(hive.isBoxLazy('flavourEager'), false);
      expect(hive.isBoxLazy('flavourNeverOpened'), false);
    });

    test('a box opened directly via Hive is adopted by the wrapper', () async {
      await Hive.openLazyBox<dynamic>('adopted');
      await hive.put('adopted', 'k', 'v');
      expect(await hive.getLazy<String>('adopted', 'k'), 'v');
      expect(hive.isBoxLazy('adopted'), true);
    });

    test('box names are matched case-insensitively, as Hive does', () async {
      await hive.openLazyBox('MixedCase');
      await hive.put('mixedcase', 'k', 'v');
      expect(await hive.getLazy<String>('MIXEDCASE', 'k'), 'v');
    });

    // ── The synchronous reads that a lazy box cannot serve ──────────────────

    test('get throws BoxIsLazyException', () async {
      await hive.openLazyBox('lazyGet');
      expect(
        () => hive.get<String>('lazyGet', 'k'),
        throwsA(isA<BoxIsLazyException>()),
      );
    });

    test('getAll throws BoxIsLazyException', () async {
      await hive.openLazyBox('lazyGetAll');
      expect(
        () => hive.getAll<String>('lazyGetAll'),
        throwsA(isA<BoxIsLazyException>()),
      );
    });

    test('listenable throws BoxIsLazyException', () async {
      await hive.openLazyBox('lazyListenable');
      expect(
        () => hive.listenable('lazyListenable'),
        throwsA(isA<BoxIsLazyException>()),
      );
    });

    test('BoxIsLazyException names the box and the operation', () async {
      await hive.openLazyBox('lazyNamed');
      try {
        hive.get<String>('lazyNamed', 'k');
        fail('expected BoxIsLazyException');
      } on BoxIsLazyException catch (e) {
        expect(e.toString(), contains('lazyNamed'));
        expect(e.toString(), contains('get()'));
        expect(e.toString(), contains('getLazy()'));
      }
    });

    // ── Flavour mismatches on open ──────────────────────────────────────────

    test('openBox on an already-lazy box throws BoxTypeMismatchException',
        () async {
      await hive.openLazyBox('clashLazy');
      expect(
        () => hive.openBox('clashLazy'),
        throwsA(isA<BoxTypeMismatchException>()),
      );
    });

    test('openLazyBox on an already-regular box throws BoxTypeMismatchException',
        () async {
      await hive.openBox('clashEager');
      expect(
        () => hive.openLazyBox('clashEager'),
        throwsA(isA<BoxTypeMismatchException>()),
      );
    });

    test('reopening a lazy box returns the same instance', () async {
      final first = await hive.openLazyBox('lazyReopen');
      final second = await hive.openLazyBox('lazyReopen');
      expect(identical(first, second), true);
    });
  });

  // ── HiveStorage: typed boxes ────────────────────────────────────────────
  group('HiveStorage — typed boxes', () {
    late Directory tempDir;
    final hive = HiveStorage.instance;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_typed_test_');
      HiveStorage.initForTest(tempDir.path);
      if (!hive.isAdapterRegistered(_PointAdapter.id)) {
        hive.registerAdapter(_PointAdapter());
      }
    });

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('put/get through the wrapper on a Box<T>', () async {
      await hive.openTypedBox<_Point>('points');
      await hive.put('points', 'origin', const _Point(1, 2));
      final point = hive.get<_Point>('points', 'origin');
      expect(point?.x, 1);
      expect(point?.y, 2);
    });

    test('metadata operations work on a Box<T>', () async {
      await hive.openTypedBox<_Point>('pointsMeta');
      await hive.put('pointsMeta', 'a', const _Point(1, 1));
      expect(hive.length('pointsMeta'), 1);
      expect(hive.containsKey('pointsMeta', 'a'), true);
      expect(hive.getKeys('pointsMeta'), contains('a'));
      await hive.closeBox('pointsMeta');
      expect(hive.isBoxOpen('pointsMeta'), false);
    });

    test('getAll casts to the box type', () async {
      await hive.openTypedBox<_Point>('pointsAll');
      await hive.putAll('pointsAll',
          {'a': const _Point(1, 1), 'b': const _Point(2, 2)});
      expect(hive.getAll<_Point>('pointsAll').length, 2);
    });

    test('reopening with a different type throws BoxTypeMismatchException',
        () async {
      await hive.openTypedBox<_Point>('pointsClash');
      expect(
        () => hive.openBox('pointsClash'),
        throwsA(isA<BoxTypeMismatchException>()),
      );
      expect(
        () => hive.openLazyBox('pointsClash'),
        throwsA(isA<BoxTypeMismatchException>()),
      );
    });
  });

  // ── HiveStorage — encryption at rest ──────────────────────────────────────
  group('HiveStorage — encrypted boxes', () {
    late Directory tempDir;
    final hive = HiveStorage.instance;

    // Fixed keys rather than Hive.generateSecureKey(), so that "reopen with the
    // same key" and "reopen with a different key" are both expressible. Real
    // apps get theirs from BaabaStorage.hiveCipher(); a test wants determinism.
    final keyA = List<int>.filled(32, 1);
    final keyB = List<int>.filled(32, 2);

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_enc_test_');
      HiveStorage.initForTest(tempDir.path);
      if (!hive.isAdapterRegistered(_PointAdapter.id)) {
        hive.registerAdapter(_PointAdapter());
      }
    });

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    test('encrypted box round-trips across a close and reopen', () async {
      await hive.openBox('enc_round_trip',
          encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_round_trip', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_round_trip');

      // A fresh cipher object with the same key — the box is matched on the
      // key, not on the identity of the cipher instance.
      await hive.openBox('enc_round_trip',
          encryptionCipher: HiveAesCipher(keyA));
      expect(hive.get<String>('enc_round_trip', 'nid'), '35202-1234567-1');
      await hive.closeBox('enc_round_trip');
    });

    test('the value is unreadable in the file on disk', () async {
      const canary = 'CANARY-35202-1234567-1';

      await hive.openBox('enc_on_disk', encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_on_disk', 'nid', canary);
      await hive.closeBox('enc_on_disk');

      final encrypted =
          await File('${tempDir.path}/enc_on_disk.hive').readAsBytes();
      expect(String.fromCharCodes(encrypted), isNot(contains(canary)));

      // The control: the same write without a cipher leaves the value sitting
      // in the file in the clear. This is the finding being fixed.
      await hive.openBox('plain_on_disk');
      await hive.put('plain_on_disk', 'nid', canary);
      await hive.closeBox('plain_on_disk');

      final plain =
          await File('${tempDir.path}/plain_on_disk.hive').readAsBytes();
      expect(String.fromCharCodes(plain), contains(canary));
    });

    test('reopening with a different key throws, and leaves the data intact',
        () async {
      await hive.openBox('enc_wrong_key',
          encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_wrong_key', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_wrong_key');

      expect(
        await _errorFromOpen(() => hive.openBox('enc_wrong_key',
            encryptionCipher: HiveAesCipher(keyB))),
        isA<HiveError>(),
      );

      // The point of defaulting crashRecovery to false: the failed open did not
      // truncate the file, so the data is still there for the right key.
      await hive.openBox('enc_wrong_key',
          encryptionCipher: HiveAesCipher(keyA));
      expect(hive.get<String>('enc_wrong_key', 'nid'), '35202-1234567-1');
      await hive.closeBox('enc_wrong_key');
    });

    test('an existing cleartext box cannot be reopened with a cipher',
        () async {
      await hive.openBox('enc_migrate');
      await hive.put('enc_migrate', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_migrate');

      // Pinning Hive's actual behaviour, because a consumer's migration logic
      // depends on it: the encryption key is folded into every frame checksum,
      // so a cleartext file fails to decode. Adding the parameter is not a
      // migration.
      expect(
        await _errorFromOpen(() =>
            hive.openBox('enc_migrate', encryptionCipher: HiveAesCipher(keyA))),
        isA<HiveError>(),
      );

      // Still readable as cleartext, so a migration can still run.
      await hive.openBox('enc_migrate');
      expect(hive.get<String>('enc_migrate', 'nid'), '35202-1234567-1');
      await hive.closeBox('enc_migrate');
    });

    test(
        'crashRecovery: true silently empties a mismatched box — the loss the '
        'default guards against', () async {
      await hive.openBox('enc_recovery');
      await hive.put('enc_recovery', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_recovery');

      // Hive's own default. The checksum fails, Hive reads that as corruption,
      // truncates the file and returns an empty box — no exception. (It prints
      // "Recovering corrupted box." while doing so; that line in the test log
      // is expected here and nowhere else.)
      final box = await hive.openBox(
        'enc_recovery',
        encryptionCipher: HiveAesCipher(keyA),
        crashRecovery: true,
      );
      expect(box.isEmpty, isTrue);
      await hive.closeBox('enc_recovery');

      // And it is gone for good — not merely undecryptable.
      await hive.openBox('enc_recovery');
      expect(hive.isEmpty('enc_recovery'), isTrue);
      await hive.closeBox('enc_recovery');
    });

    test('openTypedBox works encrypted', () async {
      await hive.openTypedBox<_Point>('enc_typed',
          encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_typed', 'origin', const _Point(3, 4));
      await hive.closeBox('enc_typed');

      await hive.openTypedBox<_Point>('enc_typed',
          encryptionCipher: HiveAesCipher(keyA));
      expect(hive.get<_Point>('enc_typed', 'origin')?.x, 3);
      await hive.closeBox('enc_typed');
    });

    test('openLazyBox works encrypted', () async {
      await hive.openLazyBox('enc_lazy', encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_lazy', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_lazy');

      await hive.openLazyBox('enc_lazy', encryptionCipher: HiveAesCipher(keyA));
      expect(await hive.getLazy<String>('enc_lazy', 'nid'), '35202-1234567-1');
      await hive.closeBox('enc_lazy');
    });

    test('mismatch guard: open unencrypted, then ask for a cipher', () async {
      await hive.openBox('enc_guard_a');
      await expectLater(
        hive.openBox('enc_guard_a', encryptionCipher: HiveAesCipher(keyA)),
        throwsA(isA<BoxEncryptionMismatchException>()),
      );
      await hive.closeBox('enc_guard_a');
    });

    test('mismatch guard: open encrypted, then ask without a cipher', () async {
      await hive.openBox('enc_guard_b', encryptionCipher: HiveAesCipher(keyA));
      await expectLater(
        hive.openBox('enc_guard_b'),
        throwsA(isA<BoxEncryptionMismatchException>()),
      );
      await hive.closeBox('enc_guard_b');
    });

    test('mismatch guard applies to lazy and typed boxes too', () async {
      await hive.openLazyBox('enc_guard_lazy',
          encryptionCipher: HiveAesCipher(keyA));
      await expectLater(
        hive.openLazyBox('enc_guard_lazy'),
        throwsA(isA<BoxEncryptionMismatchException>()),
      );
      await hive.closeBox('enc_guard_lazy');

      await hive.openTypedBox<_Point>('enc_guard_typed');
      await expectLater(
        hive.openTypedBox<_Point>('enc_guard_typed',
            encryptionCipher: HiveAesCipher(keyA)),
        throwsA(isA<BoxEncryptionMismatchException>()),
      );
      await hive.closeBox('enc_guard_typed');
    });

    test('the encryption guard is per-session: closing a box clears it',
        () async {
      // An empty box, so only the wrapper's own bookkeeping is in play — with
      // no frames on disk there is no checksum for Hive to object to.
      await hive.openBox('enc_reopen', encryptionCipher: HiveAesCipher(keyA));
      await hive.closeBox('enc_reopen');

      // No BoxEncryptionMismatchException: the first open is no longer in
      // force. The guard stops a *live* box from being handed out with the
      // wrong encryption; it cannot vet a file, because nothing in a .hive file
      // records whether it is encrypted.
      final box = await hive.openBox('enc_reopen');
      expect(box.isEmpty, isTrue);
      await hive.closeBox('enc_reopen');
    });

    test('opening an encrypted box without its cipher destroys it — the hazard '
        'a consumer must design around', () async {
      await hive.openBox('enc_no_cipher',
          encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_no_cipher', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_no_cipher');

      // Hive cannot tell an encrypted file from a corrupt one, and an open with
      // no cipher keeps Hive's crashRecovery default of true, so the file is
      // truncated rather than refused. No exception is thrown.
      final box = await hive.openBox('enc_no_cipher');
      expect(box.isEmpty, isTrue);
      await hive.closeBox('enc_no_cipher');

      // Gone for good — the right key does not bring it back. This is why every
      // open of an encrypted box must pass the cipher: the wrapper's guard only
      // spans a single session, and there is nothing it can check afterwards.
      final withKey = await hive.openBox('enc_no_cipher',
          encryptionCipher: HiveAesCipher(keyA));
      expect(withKey.isEmpty, isTrue);
      await hive.closeBox('enc_no_cipher');
    });

    test('a box adopted from Hive cannot be claimed as encrypted', () async {
      // Opened outside the wrapper, so its cipher is unknowable.
      await Hive.openBox<dynamic>('enc_adopted');

      // Asking for it unencrypted still works, exactly as before 1.3.0.
      await hive.openBox('enc_adopted');

      // Asking for it encrypted does not: the wrapper will not certify
      // encryption it cannot verify.
      await expectLater(
        hive.openBox('enc_adopted', encryptionCipher: HiveAesCipher(keyA)),
        throwsA(isA<BoxEncryptionMismatchException>()),
      );
      await hive.closeBox('enc_adopted');
    });

    test('boxExistsOnDisk separates first run from a box with no key', () async {
      expect(await hive.boxExistsOnDisk('enc_never_opened'), isFalse);

      await hive.openBox('enc_exists', encryptionCipher: HiveAesCipher(keyA));
      await hive.put('enc_exists', 'nid', '35202-1234567-1');
      await hive.closeBox('enc_exists');

      // Present on disk while closed — which is what makes it usable at app
      // start, before anything has been opened.
      expect(await hive.boxExistsOnDisk('enc_exists'), isTrue);

      await hive.deleteBox('enc_exists');
      expect(await hive.boxExistsOnDisk('enc_exists'), isFalse);
    });
  });

  // ── The encryption key ────────────────────────────────────────────────────
  group('hiveCipher / HiveKeyStore', () {
    setUp(() {
      HiveKeyStore.clearCache();
    });

    test('BaabaStorage.hiveCipher throws until init() has run', () {
      expect(BaabaStorage.isInitialized, isFalse);
      expect(
        () => BaabaStorage.hiveCipher(),
        throwsA(isA<StorageNotInitializedException>()),
      );
    });

    test('generates one key and returns the same cipher afterwards', () async {
      // setMockInitialValues keeps this map by reference, so it doubles as a
      // window onto what was written to secure storage.
      final store = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(store);

      final first = await HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias);
      final second = await HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias);
      expect(second.calculateKeyCrc(), first.calculateKeyCrc());

      // Exactly one 256-bit key, under the documented alias.
      expect(store.keys, [BaabaStorage.hiveKeyAlias]);
      expect(base64Decode(store.values.single).length, 32);

      // Not just the in-memory memo: after forgetting it, the key is read back
      // from secure storage rather than regenerated.
      HiveKeyStore.clearCache();
      final third = await HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias);
      expect(third.calculateKeyCrc(), first.calculateKeyCrc());
      expect(store.length, 1);
    });

    test('concurrent callers share a single generated key', () async {
      final store = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(store);

      // The shape of a real app start: several openBox calls resolving the
      // cipher at once. Without single-flight, the later write wins and every
      // box opened with the earlier key becomes unreadable.
      final ciphers = await Future.wait([
        HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias),
        HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias),
        HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias),
      ]);

      expect(ciphers.map((c) => c.calculateKeyCrc()).toSet(), hasLength(1));
      expect(store.length, 1);
    });

    test('separate aliases get separate keys', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final a = await HiveKeyStore.resolve('alias_a');
      final b = await HiveKeyStore.resolve('alias_b');
      expect(a.calculateKeyCrc(), isNot(b.calculateKeyCrc()));
    });

    test('a stored key that is not base64 throws and is left alone', () async {
      final store = <String, String>{BaabaStorage.hiveKeyAlias: 'not base64!!'};
      FlutterSecureStorage.setMockInitialValues(store);

      await expectLater(
        HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias),
        throwsA(isA<StorageException>()),
      );
      // Untouched — replacing it would make existing boxes unreadable forever.
      expect(store[BaabaStorage.hiveKeyAlias], 'not base64!!');
    });

    test('a stored key of the wrong length throws and is left alone', () async {
      final short = base64Encode(List<int>.filled(16, 7));
      final store = <String, String>{BaabaStorage.hiveKeyAlias: short};
      FlutterSecureStorage.setMockInitialValues(store);

      await expectLater(
        HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias),
        throwsA(isA<StorageException>()),
      );
      expect(store[BaabaStorage.hiveKeyAlias], short);
    });

    test('the failure message never contains the key material', () async {
      final secret = base64Encode(List<int>.filled(16, 7));
      FlutterSecureStorage.setMockInitialValues(
        <String, String>{BaabaStorage.hiveKeyAlias: secret},
      );

      try {
        await HiveKeyStore.resolve(BaabaStorage.hiveKeyAlias);
        fail('expected a StorageException');
      } on StorageException catch (e) {
        expect(e.toString(), isNot(contains(secret)));
        expect(e.toString(), contains(BaabaStorage.hiveKeyAlias));
      }
    });
  });

  // ── StorageException ─────────────────────────────────────────────────────
  group('StorageException', () {
    test('StorageNotInitializedException message is descriptive', () {
      const ex = StorageNotInitializedException();
      expect(ex.toString(), contains('BaabaStorage is not initialized'));
    });

    test('BoxNotOpenException includes box name', () {
      final ex = BoxNotOpenException('myBox');
      expect(ex.toString(), contains('myBox'));
    });

    test('UnsupportedTypeException includes type name', () {
      final ex = UnsupportedTypeException(Map);
      expect(ex.toString(), contains('Map'));
    });

    test('BoxTypeMismatchException reports both flavours', () {
      final ex = BoxTypeMismatchException(
        'myBox',
        wanted: 'a regular box',
        actual: 'a lazy box',
        hint: 'Use openLazyBox("myBox").',
      );
      expect(ex.toString(), contains('myBox'));
      expect(ex.toString(), contains('a lazy box'));
      expect(ex.toString(), contains('a regular box'));
      expect(ex.toString(), contains('openLazyBox'));
    });

    test('BoxEncryptionMismatchException reports both intents', () {
      final ex = BoxEncryptionMismatchException(
        'citizens',
        wantedEncrypted: true,
        actualEncrypted: false,
      );
      expect(ex.toString(), contains('citizens'));
      expect(ex.toString(), contains('unencrypted'));
      expect(ex.toString(), contains('encrypted'));
    });

    test('BoxEncryptionMismatchException names the unknown case', () {
      final ex = BoxEncryptionMismatchException(
        'citizens',
        wantedEncrypted: true,
        actualEncrypted: null,
      );
      expect(ex.toString(), contains('opened outside BaabaStorage'));
    });
  });
}

// ── Test fixtures ──────────────────────────────────────────────────────────

/// Runs [open] and returns the error it threw, or `null` if it succeeded.
///
/// Needed because a failed `Hive.openBox` in hive 2.2.3 reports its error
/// twice: once to the caller, and once as an unhandled async error. Its
/// `HiveImpl._openBox` parks a `Completer` in an internal map so that concurrent
/// opens can join, and on failure completes that completer with the error —
/// but when nothing joined, no one is listening, so the error is orphaned. The
/// awaited call throws as expected; the orphan then lands in the enclosing
/// zone, which in a test means failing it even when the throw is exactly what
/// is being asserted.
///
/// So the open runs inside its own guarded zone that swallows the duplicate.
/// Worth knowing in an app too: expect a logged unhandled HiveError alongside
/// the one you catch.
Future<Object?> _errorFromOpen(Future<void> Function() open) async {
  Object? thrown;
  await runZonedGuarded(() async {
    try {
      await open();
    } catch (error) {
      thrown = error;
    }
    // Give the orphaned error a turn of the event loop to surface inside this
    // zone rather than after it has been torn down.
    await Future<void>.delayed(Duration.zero);
  }, (_, __) {});
  return thrown;
}

/// A minimal custom type, hand-written rather than generated, so the typed-box
/// tests do not pull in hive_generator/build_runner.
class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;
}

class _PointAdapter extends TypeAdapter<_Point> {
  static const int id = 42;

  @override
  int get typeId => id;

  @override
  _Point read(BinaryReader reader) => _Point(reader.readInt(), reader.readInt());

  @override
  void write(BinaryWriter writer, _Point obj) {
    writer.writeInt(obj.x);
    writer.writeInt(obj.y);
  }
}
