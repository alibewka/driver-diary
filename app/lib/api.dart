import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Сервер отклонил данные (HTTP 400): [errors] — ошибки по полям.
class ApiValidationException extends ApiException {
  ApiValidationException(this.errors) : super(errors.map((e) => e.message).join('\n'));

  final List<FieldError> errors;
}

/// Интерфейс доступа к серверу. Отдельный тип нужен, чтобы в тестах подставлять заглушку.
abstract class DiaryApi {
  String get baseUrl;
  set baseUrl(String value);

  Future<List<Trip>> trips(String date);
  Future<DaySummary> summary(String date);
  Future<List<DayInfo>> days();
  Future<AddTripResult> addTrip(NewTrip trip);
}

const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

/// Адрес сервера по умолчанию. Переопределяется: --dart-define=API_BASE_URL=http://192.168.0.10:8080
/// или в приложении (иконка в шапке).
String defaultBaseUrl() {
  if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
  // Эмулятор Android видит localhost компьютера по адресу 10.0.2.2.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8080';
  return 'http://localhost:8080';
}

class HttpDiaryApi implements DiaryApi {
  HttpDiaryApi({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultBaseUrl(),
        _client = client ?? http.Client();

  @override
  String baseUrl;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: query);

  Future<Map<String, dynamic>> _request(Future<http.Response> Function() call) async {
    final http.Response response;
    try {
      response = await call().timeout(const Duration(seconds: 10));
    } catch (_) {
      throw ApiException('Нет связи с сервером ($baseUrl). Проверьте, что сервер запущен и адрес верный.');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        'По адресу $baseUrl отвечает не сервер дневника (HTTP ${response.statusCode}). '
            'Проверьте адрес и порт: возможно, он занят другой программой.',
      );
    }

    if (response.statusCode >= 400) {
      if (body['error'] == 'validation_error') {
        final errors = (body['errors'] as List)
            .map((e) => FieldError(e['field'] as String, e['message'] as String))
            .toList();
        throw ApiValidationException(errors);
      }
      throw ApiException((body['message'] as String?) ?? 'Ошибка сервера (${response.statusCode})');
    }
    return body;
  }

  @override
  Future<List<Trip>> trips(String date) async {
    final body = await _request(() => _client.get(_uri('/api/trips', {'date': date})));
    return (body['trips'] as List).map((j) => Trip.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<DaySummary> summary(String date) async {
    final body = await _request(() => _client.get(_uri('/api/summary', {'date': date})));
    return DaySummary.fromJson(body);
  }

  @override
  Future<List<DayInfo>> days() async {
    final body = await _request(() => _client.get(_uri('/api/days')));
    return (body['days'] as List).map((j) => DayInfo.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<AddTripResult> addTrip(NewTrip trip) async {
    final body = await _request(
          () => _client.post(
        _uri('/api/trips'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(trip.toJson()),
      ),
    );
    return AddTripResult(
      trip: Trip.fromJson(body['trip'] as Map<String, dynamic>),
      duplicate: body['duplicate'] as bool,
    );
  }
}
