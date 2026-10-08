import 'package:driver_diary_server/summary.dart';
import 'package:driver_diary_server/trip.dart';
import 'package:test/test.dart';

Trip trip(String id, num amount, String payment, num commission) => Trip(
      id: id,
      start: '2026-10-01T08:00:00+05:00',
      end: '2026-10-01T08:30:00+05:00',
      amount: amount,
      payment: payment,
      commission: commission,
    );

void main() {
  group('summarize', () {
    test('пустой день — все нули', () {
      final s = summarize([]);
      expect(s.toJson(), {
        'trips': 0,
        'revenue': 0,
        'commission': 0,
        'net': 0,
        'byPayment': {
          'cash': {'trips': 0, 'revenue': 0, 'commission': 0, 'net': 0},
          'card': {'trips': 0, 'revenue': 0, 'commission': 0, 'net': 0},
        },
      });
    });

    test('пример из задания: две поездки, карта и наличные', () {
      final s = summarize([
        trip('t1', 2400, 'card', 360),
        trip('t2', 1500, 'cash', 225),
      ]);
      expect(s.trips, 2);
      expect(s.revenue, 3900);
      expect(s.commission, 585);
      expect(s.net, 3315); // «на руки» = 3900 − 585
      expect(s.cash.toJson(), {'trips': 1, 'revenue': 1500, 'commission': 225, 'net': 1275});
      expect(s.card.toJson(), {'trips': 1, 'revenue': 2400, 'commission': 360, 'net': 2040});
    });

    test('все поездки одним способом оплаты — второй способ нулевой', () {
      final s = summarize([trip('a', 1000, 'card', 150), trip('b', 500, 'card', 75)]);
      expect(s.card.trips, 2);
      expect(s.card.revenue, 1500);
      expect(s.cash.trips, 0);
      expect(s.cash.revenue, 0);
      expect(s.net, 1275);
    });

    test('разбивка в сумме даёт итог', () {
      final s = summarize([
        trip('a', 1000, 'card', 150),
        trip('b', 700, 'cash', 105),
        trip('c', 300, 'cash', 45),
      ]);
      expect(s.cash.trips + s.card.trips, s.trips);
      expect(s.cash.revenue + s.card.revenue, s.revenue);
      expect(s.cash.commission + s.card.commission, s.commission);
      expect(s.cash.net + s.card.net, s.net);
    });

    test('дробные суммы считаются без ошибок округления double', () {
      // 0.1 + 0.2 в double даёт 0.30000000000000004
      final s = summarize([trip('a', 0.1, 'cash', 0), trip('b', 0.2, 'cash', 0)]);
      expect(s.revenue, 0.3);

      final s2 = summarize([
        trip('a', 19.99, 'card', 3.0),
        trip('b', 19.99, 'card', 3.0),
        trip('c', 19.99, 'card', 3.0),
      ]);
      expect(s2.revenue, 59.97);
      expect(s2.commission, 9);
      expect(s2.net, 50.97);
    });

    test('неизвестный способ оплаты — ошибка, а не молчаливый пропуск', () {
      expect(() => summarize([trip('a', 100, 'crypto', 10)]), throwsArgumentError);
    });
  });
}
