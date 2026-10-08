import 'package:driver_diary/api.dart';
import 'package:driver_diary/format.dart';
import 'package:driver_diary/main.dart';
import 'package:driver_diary/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Заглушка сервера: один и тот же набор данных для любого дня.
class FakeApi implements DiaryApi {
  int addCalls = 0;

  /// true — запросы завершаются ошибкой, как при остановленном сервере.
  bool fail = false;

  @override
  String baseUrl = 'http://fake';

  @override
  Future<List<Trip>> trips(String date) async {
    if (fail) throw ApiException('Нет связи');
    return const [
      Trip(
        id: 't1',
        start: '2026-10-01T08:10:00+05:00',
        end: '2026-10-01T08:32:00+05:00',
        amount: 2400,
        payment: 'card',
        commission: 360,
      ),
      Trip(
        id: 't2',
        start: '2026-10-01T09:05:00+05:00',
        end: '2026-10-01T09:20:00+05:00',
        amount: 1500,
        payment: 'cash',
        commission: 225,
      ),
    ];
  }

  @override
  Future<DaySummary> summary(String date) async {
    if (fail) throw ApiException('Нет связи');
    return const DaySummary(
      total: Bucket(trips: 2, revenue: 3900, commission: 585, net: 3315),
      cash: Bucket(trips: 1, revenue: 1500, commission: 225, net: 1275),
      card: Bucket(trips: 1, revenue: 2400, commission: 360, net: 2040),
    );
  }

  @override
  Future<List<DayInfo>> days() async {
    if (fail) throw ApiException('Нет связи');
    return const [DayInfo(date: '2026-10-01', trips: 2)];
  }

  @override
  Future<AddTripResult> addTrip(NewTrip trip) async {
    addCalls++;
    throw UnimplementedError();
  }
}

void main() {
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('показывает сводку дня и список поездок', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(DriverDiaryApp(api: FakeApi()));
    await tester.pumpAndSettle();

    expect(find.text(formatMoney(3315)), findsOneWidget); // на руки
    expect(find.text(formatMoney(3900)), findsOneWidget); // выручка
    expect(find.text(formatMoney(585)), findsOneWidget); // комиссия
    expect(find.text('Поездки (2)'), findsOneWidget);
    expect(find.text('08:10 – 08:32'), findsOneWidget);
    expect(find.text(formatMoney(2400)), findsOneWidget);
    expect(find.text(formatMoney(1500)), findsOneWidget);
  });

  testWidgets('при ошибке загрузки нового дня данные прошлого дня не показываются', (tester) async {
    useTallScreen(tester);
    final api = FakeApi();
    await tester.pumpWidget(DriverDiaryApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text(formatMoney(3315)), findsOneWidget);

    api.fail = true;
    await tester.tap(find.byTooltip('Предыдущий день'));
    await tester.pumpAndSettle();

    expect(find.text('Нет связи'), findsOneWidget); // сообщение об ошибке
    expect(find.text(formatMoney(3315)), findsNothing); // цифры прошлого дня убраны
    expect(find.text('Поездки (2)'), findsNothing);
  });

  testWidgets('форма не отправляет пустые данные', (tester) async {
    useTallScreen(tester);
    final api = FakeApi();
    await tester.pumpWidget(DriverDiaryApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Поездка')); // кнопка «+ Поездка»
    await tester.pumpAndSettle();
    expect(find.text('Новая поездка'), findsOneWidget);

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Сумма должна быть больше 0'), findsOneWidget);
    expect(api.addCalls, 0); // на сервер ничего не ушло
  });
}
