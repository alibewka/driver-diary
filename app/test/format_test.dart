import 'package:driver_diary/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('дни', () {
    test('shiftDay переходит через границы месяца и года', () {
      expect(shiftDay('2026-10-31', 1), '2026-11-01');
      expect(shiftDay('2026-11-01', -1), '2026-10-31');
      expect(shiftDay('2026-12-31', 1), '2027-01-01');
      expect(shiftDay('2026-03-01', -1), '2026-02-28');
    });

    test('день поездки определяется по времени Алматы, а не по UTC', () {
      expect(dayKeyOf('2026-10-01T23:30:00+05:00'), '2026-10-01');
      expect(dayKeyOf('2026-10-02T00:00:00+05:00'), '2026-10-02');
      expect(dayKeyOf('2026-10-01T20:00:00Z'), '2026-10-02'); // 01:00 по Алматы
    });

    test('wallIso отправляет время со смещением +05:00', () {
      expect(wallIso(DateTime.utc(2026, 10, 1, 8, 10)), '2026-10-01T08:10:00+05:00');
      expect(wallIso(DateTime.utc(2026, 1, 5, 0, 5)), '2026-01-05T00:05:00+05:00');
    });

    test('toWall показывает время по Алматы независимо от пояса телефона', () {
      final wall = toWall('2026-10-01T03:10:00Z');
      expect(formatTime(wall), '08:10');
    });
  });

  group('числа', () {
    test('formatMoney: разделитель тысяч и знак тенге', () {
      expect(formatMoney(2400), '2 400 ₸');
      expect(formatMoney(0), '0 ₸');
      expect(formatMoney(1234567), '1 234 567 ₸');
      expect(formatMoney(19.9), '19,90 ₸');
    });

    test('parseNumber принимает запятую', () {
      expect(parseNumber('2400'), 2400);
      expect(parseNumber(' 19,99 '), 19.99);
      expect(parseNumber(''), isNull);
      expect(parseNumber('abc'), isNull);
    });

    test('plainNumber без лишнего «.0»', () {
      expect(plainNumber(360.0), '360');
      expect(plainNumber(37.5), '37.5');
    });

    test('newTripId уникален и подходит под правила id сервера', () {
      final a = newTripId();
      final b = newTripId();
      expect(a, isNot(b));
      expect(RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(a), isTrue);
    });
  });
}
