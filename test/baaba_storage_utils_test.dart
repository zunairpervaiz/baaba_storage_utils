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
  });
}
