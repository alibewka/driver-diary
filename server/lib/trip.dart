/// Деньги считаем в целых копейках, чтобы 0.1 + 0.2 не давало 0.30000000000000004.
int toCents(num value) => (value * 100).round();

/// Копейки обратно в число: целые суммы остаются int (2400), дробные — double (19.99).
num fromCents(int cents) => cents % 100 == 0 ? cents ~/ 100 : cents / 100;

class Trip {
  const Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.payment,
    required this.commission,
  });

  final String id;

  /// ISO 8601 со смещением, например 2026-10-01T08:10:00+05:00.
  final String start;
  final String end;
  final num amount;

  /// 'cash' или 'card'.
  final String payment;
  final num commission;

  Trip withId(String newId) => Trip(
        id: newId,
        start: start,
        end: end,
        amount: amount,
        payment: payment,
        commission: commission,
      );

  /// Отпечаток содержимого (без id): одинаковые данные => одинаковая строка.
  /// Время сравнивается как момент, поэтому +05:00 и Z дают один отпечаток.
  String get fingerprint => [
        DateTime.parse(start).millisecondsSinceEpoch,
        DateTime.parse(end).millisecondsSinceEpoch,
        toCents(amount),
        payment,
        toCents(commission),
      ].join('|');

  Map<String, Object?> toJson() => {
        'id': id,
        'start': start,
        'end': end,
        'amount': amount,
        'payment': payment,
        'commission': commission,
      };
}
