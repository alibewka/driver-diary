import 'package:driver_diary_server/validate.dart';
import 'package:test/test.dart';

Map<String, Object?> valid([Map<String, Object?> overrides = const {}]) => {
      'id': 't1',
      'start': '2026-10-01T08:10:00+05:00',
      'end': '2026-10-01T08:32:00+05:00',
      'amount': 2400,
      'payment': 'card',
      'commission': 360,
      ...overrides,
    };

List<String> failedFields(Object? input) =>
    validateTrip(input).errors.map((e) => e.field).toList();

void main() {
  group('validateTrip', () {
    test('корректная поездка проходит', () {
      final r = validateTrip(valid());
      expect(r.ok, isTrue);
      expect(r.trip!.id, 't1');
      expect(r.trip!.amount, 2400);
    });

    test('сумма: 0, отрицательная, строка, null, NaN-подобные значения — ошибка', () {
      expect(failedFields(valid({'amount': 0})), ['amount']);
      expect(failedFields(valid({'amount': -5})), ['amount']);
      expect(failedFields(valid({'amount': '2400'})), ['amount']);
      expect(failedFields(valid({'amount': null})), ['amount']);
      expect(failedFields(valid({'amount': double.nan})), ['amount']);
      expect(failedFields(valid({'amount': double.infinity})), ['amount']);
    });

    test('сумма: не больше двух знаков после запятой, есть верхняя граница', () {
      expect(validateTrip(valid({'amount': 10.5, 'commission': 1})).ok, isTrue);
      expect(failedFields(valid({'amount': 10.123})), ['amount']);
      expect(failedFields(valid({'amount': 99999999})), ['amount']);
    });

    test('окончание должно быть строго позже начала', () {
      expect(failedFields(valid({'end': '2026-10-01T08:10:00+05:00'})), ['end']); // равно
      expect(failedFields(valid({'end': '2026-10-01T08:00:00+05:00'})), ['end']); // раньше
    });

    test('время сравнивается как момент, а не как строка (разные смещения)', () {
      // начало 08:10+05:00 = 03:10Z, поэтому 03:00Z — раньше начала, хотя «03:00» < «08:10» и как текст
      final r = validateTrip(valid({'end': '2026-10-01T03:00:00Z'}));
      expect(r.errors.map((e) => e.field), ['end']);
      expect(validateTrip(valid({'end': '2026-10-01T03:30:00Z'})).ok, isTrue);
    });

    test('некорректные даты и формат', () {
      expect(failedFields(valid({'start': '2026-02-31T08:10:00+05:00'})), ['start']); // 31 февраля
      expect(failedFields(valid({'start': '2026-10-01T25:10:00+05:00'})), ['start']);
      expect(failedFields(valid({'start': '2026-10-01T08:10:00'})), ['start']); // без смещения
      expect(failedFields(valid({'start': 'вчера'})), ['start']);
      expect(failedFields(valid({'start': null})), ['start']);
      expect(failedFields(valid({'end': 12345})), ['end']);
    });

    test('способ оплаты только cash или card', () {
      expect(failedFields(valid({'payment': 'crypto'})), ['payment']);
      expect(failedFields(valid({'payment': null})), ['payment']);
      expect(validateTrip(valid({'payment': 'cash'})).ok, isTrue);
    });

    test('комиссия: не отрицательная, не больше суммы, обязательна', () {
      expect(failedFields(valid({'commission': -1})), ['commission']);
      expect(failedFields(valid({'commission': 2401})), ['commission']);
      expect(failedFields(valid({'commission': null})), ['commission']);
      expect(validateTrip(valid({'commission': 0})).ok, isTrue);
      expect(validateTrip(valid({'commission': 2400})).ok, isTrue);
    });

    test('несколько ошибок возвращаются сразу', () {
      final fields = failedFields(valid({'amount': -1, 'payment': 'x', 'commission': -2}));
      expect(fields, containsAll(['amount', 'payment', 'commission']));
    });

    test('не объект — ошибка body', () {
      expect(failedFields(null), ['body']);
      expect(failedFields('trip'), ['body']);
      expect(failedFields([valid()]), ['body']);
    });

    test('id: допустимые символы и длина', () {
      expect(failedFields(valid({'id': 'a b'})), ['id']);
      expect(failedFields(valid({'id': ''})), ['id']);
      expect(failedFields(valid({'id': 'x' * 65})), ['id']);
      expect(failedFields(valid({'id': 42})), ['id']);
      expect(validateTrip(valid({'id': 'app-123_abc.def'})).ok, isTrue);
    });

    test('без id он выводится из данных: одинаковые данные — одинаковый id', () {
      Map<String, Object?> noId([Map<String, Object?> o = const {}]) => valid({'id': null, ...o});

      final a = validateTrip(noId()).trip!;
      final b = validateTrip(noId()).trip!;
      final c = validateTrip(noId({'amount': 2500, 'commission': 375})).trip!;
      expect(a.id, startsWith('auto-'));
      expect(a.id.length, lessThanOrEqualTo(64));
      expect(a.id, b.id);
      expect(a.id, isNot(c.id));
    });
  });
}
