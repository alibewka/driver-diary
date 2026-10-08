import 'trip.dart';

const paymentMethods = ['cash', 'card'];

const _maxAmount = 10000000;
const _dateHint = 'формат ISO 8601 со смещением, например 2026-10-01T08:10:00+05:00';

final _isoRe = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-](\d{2}):(\d{2}))$',
);
final _idRe = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

class FieldError {
  const FieldError(this.field, this.message);

  final String field;
  final String message;

  Map<String, String> toJson() => {'field': field, 'message': message};
}

class ValidationResult {
  const ValidationResult.ok(Trip this.trip) : errors = const [];
  const ValidationResult.failure(this.errors) : trip = null;

  final Trip? trip;
  final List<FieldError> errors;

  bool get ok => trip != null;
}

/// Разбирает ISO 8601 со смещением. Возвращает null, если строка некорректна.
DateTime? parseDateTime(Object? value) {
  if (value is! String) return null;
  final m = _isoRe.firstMatch(value);
  if (m == null) return null;

  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final h = int.parse(m[4]!);
  final mi = int.parse(m[5]!);
  final s = int.parse(m[6] ?? '0');

  // Календарную дату проверяем сами: DateTime.parse «переносит» 31 февраля на март.
  final probe = DateTime.utc(y, mo, d);
  if (probe.year != y || probe.month != mo || probe.day != d) return null;
  if (h > 23 || mi > 59 || s > 59) return null;

  final offsetHours = m[7];
  final offsetMinutes = m[8];
  if (offsetHours != null && (int.parse(offsetHours) > 23 || int.parse(offsetMinutes!) > 59)) {
    return null;
  }
  return DateTime.tryParse(value);
}

bool _atMostTwoDecimals(num n) => (n * 100 - (n * 100).round()).abs() < 1e-6;

/// Проверяет входные данные поездки.
/// Если id не передан, он выводится из содержимого: повтор тех же данных даёт тот же id.
ValidationResult validateTrip(Object? input) {
  if (input is! Map) {
    return const ValidationResult.failure([FieldError('body', 'Ожидается JSON-объект поездки')]);
  }

  final errors = <FieldError>[];
  void fail(String field, String message) => errors.add(FieldError(field, message));

  final id = input['id'];
  if (id != null && (id is! String || !_idRe.hasMatch(id))) {
    fail('id', 'id — строка из букв, цифр, «_», «.», «-», до 64 символов');
  }

  final start = parseDateTime(input['start']);
  final end = parseDateTime(input['end']);
  if (start == null) fail('start', 'Некорректное время начала: $_dateHint');
  if (end == null) fail('end', 'Некорректное время окончания: $_dateHint');
  if (start != null && end != null && !end.isAfter(start)) {
    fail('end', 'Окончание должно быть позже начала');
  }

  final rawAmount = input['amount'];
  final num? amount = (rawAmount is num && rawAmount.isFinite) ? rawAmount : null;
  // Сумма, прошедшая все проверки. Только с ней сравниваем комиссию, чтобы из-за
  // одной плохой суммы не сыпались ещё и ошибки по комиссии.
  num? validAmount;
  if (amount == null || amount <= 0) {
    fail('amount', 'Сумма должна быть числом больше 0');
  } else if (amount > _maxAmount) {
    fail('amount', 'Сумма не может превышать $_maxAmount');
  } else if (!_atMostTwoDecimals(amount)) {
    fail('amount', 'Сумма — не больше двух знаков после запятой');
  } else {
    validAmount = amount;
  }

  final payment = input['payment'];
  if (payment is! String || !paymentMethods.contains(payment)) {
    fail('payment', 'Способ оплаты: «cash» (наличные) или «card» (карта)');
  }

  final rawCommission = input['commission'];
  final num? commission = (rawCommission is num && rawCommission.isFinite) ? rawCommission : null;
  if (commission == null || commission < 0) {
    fail('commission', 'Комиссия должна быть числом не меньше 0');
  } else if (!_atMostTwoDecimals(commission)) {
    fail('commission', 'Комиссия — не больше двух знаков после запятой');
  } else if (validAmount != null && commission > validAmount) {
    fail('commission', 'Комиссия не может быть больше суммы поездки');
  }

  if (errors.isNotEmpty) return ValidationResult.failure(errors);

  final trip = Trip(
    id: (id as String?) ?? '',
    start: input['start'] as String,
    end: input['end'] as String,
    amount: amount!,
    payment: payment as String,
    commission: commission!,
  );
  if (id != null) return ValidationResult.ok(trip);
  return ValidationResult.ok(trip.withId('auto-${trip.fingerprint.replaceAll('|', '-')}'));
}
