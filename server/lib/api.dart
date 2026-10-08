import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'store.dart';
import 'summary.dart';

const _maxBodyBytes = 100 * 1024;
final _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool _isRealDate(String? value) {
  final m = _dateRe.firstMatch(value ?? '');
  if (m == null) return false;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final probe = DateTime.utc(y, mo, d);
  return probe.year == y && probe.month == mo && probe.day == d;
}

class _HttpError implements Exception {
  _HttpError(this.status, this.code, this.message, {this.allow});

  final int status;
  final String code;
  final String message;
  final String? allow;
}

/// HTTP API на чистом dart:io.
///
///   GET  /api/trips?date=YYYY-MM-DD    список поездок дня
///   GET  /api/summary?date=YYYY-MM-DD  сводка дня
///   GET  /api/days                     дни, в которые есть поездки
///   POST /api/trips                    добавить поездку (идемпотентно)
class TripApiServer {
  TripApiServer(this.store);

  final TripStore store;
  HttpServer? _server;

  /// Запускает сервер. port: 0 — выбрать свободный порт (удобно в тестах).
  Future<HttpServer> start({Object host = '127.0.0.1', int port = 8080}) async {
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handle);
    return server;
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    // CORS: клиент на Flutter Web ходит на сервер с другого origin.
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');

    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }
      switch (req.uri.path) {
        case '/api/trips':
          if (req.method == 'GET') {
            await _listTrips(req);
          } else if (req.method == 'POST') {
            await _addTrip(req);
          } else {
            throw _methodNotAllowed('GET, POST, OPTIONS');
          }
        case '/api/summary':
          if (req.method != 'GET') throw _methodNotAllowed('GET, OPTIONS');
          await _summary(req);
        case '/api/days':
          if (req.method != 'GET') throw _methodNotAllowed('GET, OPTIONS');
          await _sendJson(res, 200, {
            'days': [
              for (final d in store.days()) {'date': d.date, 'trips': d.trips},
            ],
          });
        default:
          throw _HttpError(404, 'not_found', 'Не найдено');
      }
    } on _HttpError catch (e) {
      if (e.allow != null) res.headers.set('Allow', e.allow!);
      await _sendJson(res, e.status, {'error': e.code, 'message': e.message});
    } on ValidationException catch (e) {
      await _sendJson(res, 400, {
        'error': 'validation_error',
        'errors': [for (final err in e.errors) err.toJson()],
      });
    } on ConflictException catch (e) {
      await _sendJson(res, 409, {'error': 'conflict', 'message': e.message});
    } catch (e, st) {
      stderr.writeln('Ошибка при обработке ${req.method} ${req.uri}: $e\n$st');
      try {
        await _sendJson(res, 500, {'error': 'internal_error', 'message': 'Внутренняя ошибка сервера'});
      } catch (_) {
        // ответ уже частично отправлен — ничего не поделать
      }
    }
  }

  _HttpError _methodNotAllowed(String allow) =>
      _HttpError(405, 'method_not_allowed', 'Метод не поддерживается', allow: allow);

  String _requireDate(HttpRequest req) {
    final date = req.uri.queryParameters['date'];
    if (!_isRealDate(date)) {
      throw _HttpError(400, 'invalid_date', 'Параметр date обязателен, формат YYYY-MM-DD');
    }
    return date!;
  }

  Future<void> _listTrips(HttpRequest req) async {
    final date = _requireDate(req);
    await _sendJson(req.response, 200, {
      'date': date,
      'trips': [for (final t in store.tripsOnDay(date)) t.toJson()],
    });
  }

  Future<void> _summary(HttpRequest req) async {
    final date = _requireDate(req);
    final summary = summarize(store.tripsOnDay(date));
    await _sendJson(req.response, 200, {'date': date, ...summary.toJson()});
  }

  Future<void> _addTrip(HttpRequest req) async {
    final body = await _readJson(req);
    final result = store.add(body);
    await _sendJson(req.response, result.created ? 201 : 200, {
      'trip': result.trip.toJson(),
      'duplicate': !result.created,
    });
  }

  Future<Object?> _readJson(HttpRequest req) async {
    final builder = BytesBuilder(copy: false);
    var tooLarge = false;
    await for (final chunk in req) {
      if (tooLarge || builder.length + chunk.length > _maxBodyBytes) {
        tooLarge = true; // дочитываем и выбрасываем, чтобы корректно ответить
        continue;
      }
      builder.add(chunk);
    }
    if (tooLarge) throw _HttpError(413, 'payload_too_large', 'Тело запроса слишком большое');
    try {
      return jsonDecode(utf8.decode(builder.takeBytes()));
    } on FormatException {
      throw _HttpError(400, 'invalid_json', 'Тело запроса — не корректный JSON');
    }
  }

  Future<void> _sendJson(HttpResponse res, int status, Object body) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.headers.set('Cache-Control', 'no-store');
    res.write(jsonEncode(body));
    await res.close();
  }
}
