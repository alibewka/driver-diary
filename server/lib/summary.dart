import 'trip.dart';

/// Итоги по группе поездок (весь день или один способ оплаты).
class Bucket {
  const Bucket({
    required this.trips,
    required this.revenue,
    required this.commission,
    required this.net,
  });

  final int trips;
  final num revenue;
  final num commission;

  /// «На руки» = выручка − комиссия.
  final num net;

  Map<String, Object?> toJson() => {
        'trips': trips,
        'revenue': revenue,
        'commission': commission,
        'net': net,
      };
}

class DaySummary {
  const DaySummary({required this.total, required this.cash, required this.card});

  final Bucket total;
  final Bucket cash;
  final Bucket card;

  int get trips => total.trips;
  num get revenue => total.revenue;
  num get commission => total.commission;
  num get net => total.net;

  Map<String, Object?> toJson() => {
        'trips': trips,
        'revenue': revenue,
        'commission': commission,
        'net': net,
        'byPayment': {'cash': cash.toJson(), 'card': card.toJson()},
      };
}

class _Acc {
  int trips = 0;
  int revenue = 0; // копейки
  int commission = 0; // копейки

  void add(int amountCents, int commissionCents) {
    trips += 1;
    revenue += amountCents;
    commission += commissionCents;
  }

  Bucket toBucket() => Bucket(
        trips: trips,
        revenue: fromCents(revenue),
        commission: fromCents(commission),
        net: fromCents(revenue - commission),
      );
}

/// Сводка по списку поездок: число, выручка, комиссия, «на руки»,
/// разбивка наличные/карта.
DaySummary summarize(Iterable<Trip> trips) {
  final total = _Acc();
  final byPayment = {'cash': _Acc(), 'card': _Acc()};

  for (final trip in trips) {
    final bucket = byPayment[trip.payment];
    if (bucket == null) {
      throw ArgumentError.value(trip.payment, 'payment', 'Неизвестный способ оплаты');
    }
    final amount = toCents(trip.amount);
    final commission = toCents(trip.commission);
    total.add(amount, commission);
    bucket.add(amount, commission);
  }

  return DaySummary(
    total: total.toBucket(),
    cash: byPayment['cash']!.toBucket(),
    card: byPayment['card']!.toBucket(),
  );
}
