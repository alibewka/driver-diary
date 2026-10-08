import 'dart:convert';
import 'dart:io';

import 'package:driver_diary_server/api.dart';
import 'package:driver_diary_server/store.dart';
import 'package:test/test.dart';

typedef Reply = ({int status, Map<String, dynamic> body});

void main() {
  late TripApiServer api;
  late HttpClient client;
  late String base;

  Future<Reply> send(String method, String path, {Object? json, String? raw}) async {
    final req = await client.openUrl(method, Uri.parse('$base$path'));
    if (json != null || raw != null) {
      req.headers.contentType = ContentType.json;
      req.write(raw ?? jsonEncode(json));
    }
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    return (status: res.statusCode, body: jsonDecode(text) as Map<String, dynamic>);
  }

  Map<String, Object?> newTrip([Map<String, Object?> overrides = const {}]) => {
        'id': 'new-1',
        'start': '2026-10-01T14:00:00+05:00',
        'end': '2026-10-01T14:25:00+05:00',
        'amount': 2000,
        'payment': 'cash',
        'commission': 300,
        ...overrides,
      };

  setUp(() async {
    final store = TripStore();
    // пример из задания
    store.add({
      'id': 't1',
      'start': '2026-10-01T08:10:00+05:00',
      'end': '2026-10-01T08:32:00+05:00',
      'amount': 2400,
      'payment': 'card',
      'commission': 360,
    });
    store.add({
      'id': 't2',
      'start': '2026-10-01T09:05:00+05:00',
      'end': '2026-10-01T09:20:00+05:00',
      'amount': 1500,
      'payment': 'cash',
      'commission': 225,
    });
    api = TripApiServer(store);
    final server = await api.start(port: 0);
    base = 'http://127.0.0.1:${server.port}';
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await api.close();
  });

  group('GET', () {
    test('/api/trips — список поездок дня', () async {
      final r = await send('GET', '/api/trips?date=2026-10-01');
      expect(r.status, 200);
      expect(r.body['date'], '2026-10-01');
      final trips = r.body['trips'] as List;
      expect(trips.map((t) => t['id']), ['t1', 't2']);
    });

    test('/api/trips — день без поездок даёт пустой список', () async {
      final r = await send('GET', '/api/trips?date=2026-10-09');
      expect(r.status, 200);
      expect(r.body['trips'], isEmpty);
    });

    test('/api/summary — сводка дня', () async {
      final r = await send('GET', '/api/summary?date=2026-10-01');
      expect(r.status, 200);
      expect(r.body['trips'], 2);
      expect(r.body['revenue'], 3900);
      expect(r.body['commission'], 585);
      expect(r.body['net'], 3315);
      expect(r.body['byPayment']['cash'], {'trips': 1, 'revenue': 1500, 'commission': 225, 'net': 1275});
      expect(r.body['byPayment']['card'], {'trips': 1, 'revenue': 2400, 'commission': 360, 'net': 2040});
    });

    test('/api/summary — пустой день: нули', () async {
      final r = await send('GET', '/api/summary?date=2026-10-09');
      expect(r.status, 200);
      expect(r.body['trips'], 0);
      expect(r.body['net'], 0);
    });

    test('/api/days — дни с поездками', () async {
      final r = await send('GET', '/api/days');
      expect(r.status, 200);
      expect(r.body['days'], [
        {'date': '2026-10-01', 'trips': 2},
      ]);
    });

    test('некорректная или отсутствующая дата — 400', () async {
      expect((await send('GET', '/api/trips')).status, 400);
      expect((await send('GET', '/api/trips?date=вчера')).status, 400);
      expect((await send('GET', '/api/summary?date=2026-02-31')).status, 400);
      expect((await send('GET', '/api/summary?date=2026-02-31')).body['error'], 'invalid_date');
    });
  });

  group('POST /api/trips', () {
    test('создаёт поездку: 201, она появляется в списке и сводке', () async {
      final r = await send('POST', '/api/trips', json: newTrip());
      expect(r.status, 201);
      expect(r.body['duplicate'], false);
      expect(r.body['trip']['id'], 'new-1');

      final list = await send('GET', '/api/trips?date=2026-10-01');
      expect(list.body['trips'], hasLength(3));
      final summary = await send('GET', '/api/summary?date=2026-10-01');
      expect(summary.body['revenue'], 5900);
    });

    test('повторная отправка той же поездки: 200, duplicate=true, дубля нет', () async {
      final first = await send('POST', '/api/trips', json: newTrip());
      final second = await send('POST', '/api/trips', json: newTrip());
      final third = await send('POST', '/api/trips', json: newTrip());

      expect(first.status, 201);
      expect(second.status, 200);
      expect(second.body['duplicate'], true);
      expect(third.status, 200);

      final list = await send('GET', '/api/trips?date=2026-10-01');
      expect(list.body['trips'], hasLength(3)); // 2 исходных + 1, а не 5
      final summary = await send('GET', '/api/summary?date=2026-10-01');
      expect(summary.body['trips'], 3);
      expect(summary.body['revenue'], 5900); // выручка не удвоилась
    });

    test('повтор без id тоже не создаёт дубль', () async {
      final a = await send('POST', '/api/trips', json: newTrip({'id': null}));
      final b = await send('POST', '/api/trips', json: newTrip({'id': null}));
      expect(a.status, 201);
      expect(b.status, 200);
      expect(b.body['duplicate'], true);
      expect(a.body['trip']['id'], b.body['trip']['id']);
    });

    test('тот же id с другими данными — 409', () async {
      await send('POST', '/api/trips', json: newTrip());
      final r = await send('POST', '/api/trips', json: newTrip({'amount': 5000, 'commission': 750}));
      expect(r.status, 409);
      expect(r.body['error'], 'conflict');
    });

    test('сумма не больше 0 — 400 с указанием поля', () async {
      final r = await send('POST', '/api/trips', json: newTrip({'amount': 0}));
      expect(r.status, 400);
      expect(r.body['error'], 'validation_error');
      expect((r.body['errors'] as List).map((e) => e['field']), contains('amount'));
    });

    test('окончание не позже начала — 400', () async {
      final r = await send('POST', '/api/trips', json: newTrip({'end': '2026-10-01T14:00:00+05:00'}));
      expect(r.status, 400);
      expect((r.body['errors'] as List).map((e) => e['field']), contains('end'));
    });

    test('невалидная поездка не попадает в хранилище', () async {
      await send('POST', '/api/trips', json: newTrip({'amount': -10}));
      final list = await send('GET', '/api/trips?date=2026-10-01');
      expect(list.body['trips'], hasLength(2));
    });

    test('битый JSON — 400 invalid_json', () async {
      final r = await send('POST', '/api/trips', raw: '{ это не json');
      expect(r.status, 400);
      expect(r.body['error'], 'invalid_json');
    });

    test('JSON не объект — 400', () async {
      final r = await send('POST', '/api/trips', json: [1, 2, 3]);
      expect(r.status, 400);
    });
  });

  group('прочее', () {
    test('неизвестный путь — 404', () async {
      expect((await send('GET', '/api/nope')).status, 404);
    });

    test('неподдерживаемый метод — 405', () async {
      expect((await send('DELETE', '/api/trips')).status, 405);
      expect((await send('POST', '/api/summary', json: {})).status, 405);
    });
  });
}
