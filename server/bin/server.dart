import 'dart:io';

import 'package:driver_diary_server/api.dart';
import 'package:driver_diary_server/store.dart';

/// Запуск: `dart run bin/server.dart`
/// Переменные окружения: PORT (по умолчанию 8080), HOST (127.0.0.1), DATA_FILE.
Future<void> main() async {
  final root = File(Platform.script.toFilePath()).parent.parent.path; // папка server/
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final host = env['HOST'] ?? '127.0.0.1';
  final dataFile = env['DATA_FILE'] ?? '$root/data/trips.json';
  final seed = File('$root/data/seed.json');

  // Первый запуск: рабочий файл данных создаётся из демо-набора.
  if (!File(dataFile).existsSync() && seed.existsSync()) {
    File(dataFile).parent.createSync(recursive: true);
    seed.copySync(dataFile);
  }

  final store = TripStore(file: dataFile);
  await TripApiServer(store).start(host: host, port: port);
  print('Дневник смен водителя: сервер на http://$host:$port');
  print('Данные: $dataFile');
}
