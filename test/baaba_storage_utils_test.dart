import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  });
}

// ── Test fixtures ──────────────────────────────────────────────────────────

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
