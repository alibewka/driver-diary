import 'dart:convert';
import 'dart:io';

import 'trip.dart';
import 'validate.dart';

class ValidationException implements Exception {
  ValidationException(this.errors);

  final List<FieldError> errors;

  @override
  String toString() => 'ValidationException: ${errors.map((e) => '${e.field}: ${e.message}').join('; ')}';
}

class ConflictException implements Exception {
  ConflictException(this.message);

  final String message;

  @override
  String toString() => 'ConflictException: $message';
}

class AddResult {
  const AddResult(this.trip, {required this.created});

  final Trip trip;

  /// false — такая поездка уже была, дубль не создан.
  final bool created;
}

/// Часовой пояс водителя для границ дня: Алматы, UTC+05:00.
const defaultTzOffset = Duration(hours: 5);

/// Календарный день поездки (YYYY-MM-DD) в часовом поясе водителя. Определяется по началу.
String dayOf(String startIso, Duration tzOffset) {
  final ms = DateTime.parse(startIso).millisecondsSinceEpoch + tzOffset.inMilliseconds;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String().substring(0, 10);
}

class TripStore {
  /// [file] — JSON-файл для хранения; null — только в памяти (для тестов).
  TripStore({this.file, this.tzOffset = defaultTzOffset}) {
    final path = file;
    if (path != null && File(path).existsSync()) _load(path);
  }

  final String? file;
  final Duration tzOffset;

  final Map<String, Trip> _byId = {};
  final Map<String, Trip> _byFingerprint = {};

  List<Trip> get all => _byId.values.toList();

  void _load(String path) {
    final raw = jsonDecode(File(path).readAsStringSync());
    if (raw is! List) throw FormatException('$path: ожидается JSON-массив поездок');
    for (var i = 0; i < raw.length; i++) {
      final result = validateTrip(raw[i]);
      final trip = result.trip;
      if (trip == null) {
        final details = result.errors.map((e) => '${e.field}: ${e.message}').join('; ');
        throw FormatException('$path: поездка №${i + 1} некорректна — $details');
      }
      _insert(trip);
    }
  }

  void _insert(Trip trip) {
    _byId[trip.id] = trip;
    _byFingerprint[trip.fingerprint] = trip;
  }

  void _remove(Trip trip) {
    _byId.remove(trip.id);
    _byFingerprint.remove(trip.fingerprint);
  }

  void _persist() {
    final path = file;
    if (path == null) return;
    File(path).parent.createSync(recursive: true);
    final tmp = File('$path.tmp');
    final json = const JsonEncoder.withIndent('  ').convert(all.map((t) => t.toJson()).toList());
    tmp.writeAsStringSync('$json\n');
    tmp.renameSync(path); // атомарная замена: файл не остаётся полузаписанным
  }

  /// Добавляет поездку. Идемпотентно:
  ///  * тот же id и те же данные    -> created: false (повторная отправка);
  ///  * тот же id, другие данные    -> ConflictException;
  ///  * другой id, те же данные     -> created: false (водитель не может ехать две
  ///    одинаковые поездки в одно и то же время, это повтор).
  /// Некорректные данные -> ValidationException.
  AddResult add(Object? input) {
    final result = validateTrip(input);
    final trip = result.trip;
    if (trip == null) throw ValidationException(result.errors);

    final sameId = _byId[trip.id];
    if (sameId != null) {
      if (sameId.fingerprint == trip.fingerprint) return AddResult(sameId, created: false);
      throw ConflictException('Поездка с id «${trip.id}» уже существует, но с другими данными');
    }
    final sameContent = _byFingerprint[trip.fingerprint];
    if (sameContent != null) return AddResult(sameContent, created: false);

    _insert(trip);
    try {
      _persist();
    } catch (_) {
      _remove(trip); // не оставляем в памяти то, что не удалось сохранить
      rethrow;
    }
    return AddResult(trip, created: true);
  }

  /// Поездки выбранного дня (YYYY-MM-DD), по возрастанию времени начала.
  List<Trip> tripsOnDay(String date) {
    final list = all.where((t) => dayOf(t.start, tzOffset) == date).toList();
    list.sort((a, b) => DateTime.parse(a.start).compareTo(DateTime.parse(b.start)));
    return list;
  }

  /// Дни, в которые есть поездки: [{date, trips}], новые сверху.
  List<({String date, int trips})> days() {
    final counts = <String, int>{};
    for (final t in all) {
      final d = dayOf(t.start, tzOffset);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => (date: e.key, trips: e.value)).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }
}
