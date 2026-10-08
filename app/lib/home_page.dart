import 'package:flutter/material.dart';

import 'add_trip_page.dart';
import 'api.dart';
import 'format.dart';
import 'models.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api});

  final DiaryApi api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String _date = todayKey();
  DaySummary? _summary;
  List<Trip> _trips = const [];
  List<DayInfo> _days = const [];
  bool _loading = true;
  String? _error;
  int _seq = 0; // номер последнего запроса: устаревшие ответы игнорируем

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.api.trips(_date),
        widget.api.summary(_date),
        widget.api.days(),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _trips = results[0] as List<Trip>;
        _summary = results[1] as DaySummary;
        _days = (results[2] as List<DayInfo>).take(14).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = 'Не удалось разобрать ответ сервера.';
        _loading = false;
      });
    }
  }

  void _goTo(String date) {
    if (date == _date) return;
    setState(() {
      _date = date;
      // Данные прошлого дня не показываем под новой датой, даже если загрузка не удастся.
      _summary = null;
      _trips = const [];
    });
    _load();
  }

  Future<void> _pickDate() async {
    final current = parseDayKey(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) _goTo(dayKey(DateTime.utc(picked.year, picked.month, picked.day)));
  }

  Future<void> _addTrip() async {
    final result = await Navigator.of(context).push<AddTripResult>(
      MaterialPageRoute(builder: (_) => AddTripPage(api: widget.api)),
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.duplicate ? 'Такая поездка уже записана — дубль не создан' : 'Поездка добавлена',
        ),
      ),
    );
    final day = dayKeyOf(result.trip.start);
    if (day == _date) {
      await _load();
    } else {
      _goTo(day); // перейти на день добавленной поездки
    }
  }

  Future<void> _editServer() async {
    final controller = TextEditingController(text: widget.api.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Адрес сервера'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'http://192.168.0.10:8080'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    widget.api.baseUrl = value;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дневник смен'),
        actions: [
          IconButton(
            tooltip: 'Адрес сервера',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: _editServer,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTrip,
        icon: const Icon(Icons.add),
        label: const Text('Поездка'),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  DayNav(
                    date: _date,
                    onPrev: () => _goTo(shiftDay(_date, -1)),
                    onNext: () => _goTo(shiftDay(_date, 1)),
                    onPick: _pickDate,
                    onToday: () => _goTo(todayKey()),
                  ),
                  DayChips(days: _days, selected: _date, onSelect: _goTo),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.onErrorContainer),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: _load, child: const Text('Повторить')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (summary != null) ...[
                    SummaryCard(summary: summary),
                    BreakdownCard(summary: summary),
                    const SizedBox(height: 16),
                    Text('Поездки (${_trips.length})', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_trips.isEmpty) const EmptyDay(),
                    for (final trip in _trips) TripTile(trip: trip),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
