class Trip {
  const Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        start: json['start'] as String,
        end: json['end'] as String,
        amount: json['amount'] as num,
        payment: json['payment'] as String,
        commission: json['commission'] as num,
      );

  final String id;
  final String start;
  final String end;
  final num amount;
  final String payment; // 'cash' | 'card'
  final num commission;

  bool get isCash => payment == 'cash';

  Duration get duration => DateTime.parse(end).difference(DateTime.parse(start));
}

class Bucket {
  const Bucket({
    required this.trips,
    required this.revenue,
    required this.commission,
    required this.net,
  });

  factory Bucket.fromJson(Map<String, dynamic> json) => Bucket(
        trips: json['trips'] as int,
        revenue: json['revenue'] as num,
        commission: json['commission'] as num,
        net: json['net'] as num,
      );

  final int trips;
  final num revenue;
  final num commission;
  final num net;
}

class DaySummary {
  const DaySummary({required this.total, required this.cash, required this.card});

  factory DaySummary.fromJson(Map<String, dynamic> json) {
    final by = json['byPayment'] as Map<String, dynamic>;
    return DaySummary(
      total: Bucket.fromJson(json),
      cash: Bucket.fromJson(by['cash'] as Map<String, dynamic>),
      card: Bucket.fromJson(by['card'] as Map<String, dynamic>),
    );
  }

  final Bucket total;
  final Bucket cash;
  final Bucket card;
}

class DayInfo {
  const DayInfo({required this.date, required this.trips});

  factory DayInfo.fromJson(Map<String, dynamic> json) =>
      DayInfo(date: json['date'] as String, trips: json['trips'] as int);

  final String date;
  final int trips;
}

/// Поездка для отправки на сервер.
class NewTrip {
  const NewTrip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
  });

  final String id;
  final String start;
  final String end;
  final num amount;
  final String payment;
  final num commission;

  Map<String, Object?> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'amount': amount,
        'payment': payment,
        'commission': commission,
      };
}

class AddTripResult {
  const AddTripResult({required this.trip, required this.duplicate});

  final Trip trip;

  /// true — такая поездка уже была записана, дубль не создан.
  final bool duplicate;
}

class FieldError {
  const FieldError(this.field, this.message);

  final String field;
  final String message;
}
