import 'dart:convert';
import 'dart:io';

import 'package:driver_diary_server/store.dart';
import 'package:test/test.dart';

Map<String, Object?> trip([Map<String, Object?> overrides = const {}]) => {
      'id': 't1',
      'start': '2026-10-01T08:10:00+05:00',
      'end': '2026-10-01T08:32:00+05:00',
      'amount': 2400,
      'payment': 'card',
      'commission': 360,
      ...overrides,
    };

void main() {
  group('защита от дублей', () {
    test('повторная отправка той же поездки не создаёт дубль', () {
      final store = TripStore();
      final first = store.add(trip());
      final second = store.add(trip());

      expect(first.created, isTrue);
      expect(second.created, isFalse);
      expect(second.trip.id, 't1');
      expect(store.all, hasLength(1));
    });

    test('сколько бы раз ни повторяли — в сводке одна поездка', () {
      final store = TripStore();
      for (var i = 0; i < 5; i++) {
        store.add(trip());
      }
      expect(store.tripsOnDay('2026-10-01'), hasLength(1));
    });

    test('тот же id, но другие данные — конфликт, исходная поездка не меняется', () {
      final store = TripStore();
      store.add(trip());

      expect(() => store.add(trip({'amount': 9999, 'commission': 1})), throwsA(isA<ConflictException>()));
      expect(store.all, hasLength(1));
      expect(store.all.single.amount, 2400);
    });

    test('другой id, но те же данные — тоже повтор', () {
      final store = TripStore();
      store.add(trip());
      final r = store.add(trip({'id': 'retry-with-new-id'}));

      expect(r.created, isFalse);
      expect(r.trip.id, 't1'); // возвращается уже существующая запись
      expect(store.all, hasLength(1));
    });

    test('те же данные в другой записи времени (Z вместо +05:00) — повтор', () {
      final store = TripStore();
      store.add(trip());
      final r = store.add(trip({
        'id': 'z',
        'start': '2026-10-01T03:10:00Z',
        'end': '2026-10-01T03:32:00Z',
      }));
      expect(r.created, isFalse);
      expect(store.all, hasLength(1));
    });

    test('без id повтор тех же данных тоже не создаёт дубль', () {
      final store = TripStore();
      final a = store.add(trip({'id': null}));
      final b = store.add(trip({'id': null}));

      expect(a.created, isTrue);
      expect(b.created, isFalse);
      expect(store.all, hasLength(1));
    });

    test('разные поездки не считаются дублями', () {
      final store = TripStore();
      store.add(trip());
      store.add(trip({'id': 't2', 'start': '2026-10-01T09:05:00+05:00', 'end': '2026-10-01T09:20:00+05:00'}));
      store.add(trip({'id': 't3', 'amount': 2500, 'commission': 375})); // то же время, другая сумма
      expect(store.all, hasLength(3));
    });

    test('некорректные данные — ValidationException, в хранилище ничего не попадает', () {
      final store = TripStore();
      expect(() => store.add(trip({'amount': 0})), throwsA(isA<ValidationException>()));
      expect(store.all, isEmpty);
    });
  });

  group('дни', () {
    test('поездки дня отсортированы по началу и принадлежат своему дню', () {
      final store = TripStore();
      store.add(trip({'id': 'b', 'start': '2026-10-01T12:00:00+05:00', 'end': '2026-10-01T12:20:00+05:00'}));
      store.add(trip({'id': 'a', 'start': '2026-10-01T08:00:00+05:00', 'end': '2026-10-01T08:20:00+05:00'}));
      store.add(trip({'id': 'c', 'start': '2026-10-02T08:00:00+05:00', 'end': '2026-10-02T08:20:00+05:00'}));

      expect(store.tripsOnDay('2026-10-01').map((t) => t.id), ['a', 'b']);
      expect(store.tripsOnDay('2026-10-02').map((t) => t.id), ['c']);
      expect(store.tripsOnDay('2026-10-03'), isEmpty);
    });

    test('граница дня считается по часовому поясу водителя (UTC+5), а не по UTC', () {
      final store = TripStore();
      // 23:59 по Алматы — ещё 1 октября, хотя в UTC это 18:59 того же дня
      store.add(trip({'id': 'late', 'start': '2026-10-01T23:59:00+05:00', 'end': '2026-10-02T00:10:00+05:00'}));
      // 00:00 по Алматы — уже 2 октября, хотя в UTC это 1 октября 19:00
      store.add(trip({'id': 'midnight', 'start': '2026-10-02T00:00:00+05:00', 'end': '2026-10-02T00:15:00+05:00'}));
      // 20:00Z = 01:00 по Алматы следующего дня
      store.add(trip({'id': 'utc', 'start': '2026-10-01T20:00:00Z', 'end': '2026-10-01T20:30:00Z'}));

      expect(store.tripsOnDay('2026-10-01').map((t) => t.id), ['late']);
      expect(store.tripsOnDay('2026-10-02').map((t) => t.id), ['midnight', 'utc']);
    });

    test('days() — дни с поездками, новые сверху', () {
      final store = TripStore();
      store.add(trip({'id': 'a'}));
      store.add(trip({'id': 'b', 'start': '2026-10-01T09:00:00+05:00', 'end': '2026-10-01T09:10:00+05:00'}));
      store.add(trip({'id': 'c', 'start': '2026-10-05T09:00:00+05:00', 'end': '2026-10-05T09:10:00+05:00'}));

      expect(store.days(), [(date: '2026-10-05', trips: 1), (date: '2026-10-01', trips: 2)]);
    });
  });

  group('хранение в файле', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('driver_diary_test_');
      path = '${dir.path}/trips.json';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('поездки и защита от дублей переживают перезапуск', () {
      TripStore(file: path).add(trip());

      final reloaded = TripStore(file: path);
      expect(reloaded.all, hasLength(1));
      expect(reloaded.add(trip()).created, isFalse); // повтор после «перезапуска»
      expect(reloaded.all, hasLength(1));
    });

    test('файл — валидный JSON-массив без временных файлов', () {
      TripStore(file: path).add(trip());
      final decoded = jsonDecode(File(path).readAsStringSync());
      expect(decoded, isA<List>());
      expect(decoded, hasLength(1));
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('некорректный файл данных — понятная ошибка при старте', () {
      File(path).writeAsStringSync(jsonEncode([trip({'amount': -1})]));
      expect(() => TripStore(file: path), throwsFormatException);
    });
  });
}
