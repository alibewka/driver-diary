import 'dart:math';

/// Часовой пояс водителя (Алматы). Сервер считает границы дней в нём же.
const kTzOffset = Duration(hours: 5);
const kTzSuffix = '+05:00';

String two(int n) => n.toString().padLeft(2, '0');

/// «Настенное» время в UTC+5. Хранится как DateTime в UTC-режиме, чтобы не зависеть
/// от часового пояса телефона: поля hour/minute — это именно время по Алматы.
DateTime toWall(String iso) => DateTime.parse(iso).toUtc().add(kTzOffset);

DateTime nowWall() => DateTime.now().toUtc().add(kTzOffset);

/// Ключ дня YYYY-MM-DD.
String dayKey(DateTime wall) => '${wall.year.toString().padLeft(4, '0')}-${two(wall.month)}-${two(wall.day)}';

String todayKey() => dayKey(nowWall());

/// Ключ дня, к которому относится поездка (по времени начала).
String dayKeyOf(String iso) => dayKey(toWall(iso));

DateTime parseDayKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

String shiftDay(String key, int days) {
  final d = parseDayKey(key);
  return dayKey(DateTime.utc(d.year, d.month, d.day + days));
}

/// Время для отправки на сервер: 2026-10-01T08:10:00+05:00.
String wallIso(DateTime wall) => '${dayKey(wall)}T${two(wall.hour)}:${two(wall.minute)}:00$kTzSuffix';

String formatTime(DateTime wall) => '${two(wall.hour)}:${two(wall.minute)}';

String formatDateTime(DateTime wall) =>
    '${two(wall.day)}.${two(wall.month)}.${wall.year} ${formatTime(wall)}';

const _weekdays = [
  'понедельник',
  'вторник',
  'среда',
  'четверг',
  'пятница',
  'суббота',
  'воскресенье',
];

const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// «вторник, 6 октября»
String formatDayLong(String key) {
  final d = parseDayKey(key);
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
}

/// «06.10»
String formatDayShort(String key) {
  final d = parseDayKey(key);
  return '${two(d.day)}.${two(d.month)}';
}

/// 2400 -> «2 400», 19.9 -> «19,90». Разделитель тысяч — неразрывный пробел.
String formatNumber(num value) {
  final cents = (value * 100).round();
  final whole = cents ~/ 100;
  final frac = cents % 100;
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  if (frac != 0) buf.write(',${two(frac)}');
  return buf.toString();
}

String formatMoney(num value) => '${formatNumber(value)} ₸';

/// Число из поля ввода: допускает запятую как разделитель.
num? parseNumber(String text) => num.tryParse(text.trim().replaceAll(',', '.'));

/// Число для поля ввода без лишних «.0»: 360.0 -> «360».
String plainNumber(num value) => value == value.roundToDouble() ? value.round().toString() : value.toString();

/// Идентификатор попытки добавления. Один и тот же, пока форма не отправлена успешно:
/// повторное нажатие после обрыва связи не создаст дубль на сервере.
String newTripId() {
  final random = Random().nextInt(1 << 31).toRadixString(36);
  return 'app-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$random';
}
