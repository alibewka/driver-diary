import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';

/// Переключатель дней: ‹ вторник, 6 октября ›
class DayNav extends StatelessWidget {
  const DayNav({
    super.key,
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  final String date;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Предыдущий день',
              icon: const Icon(Icons.chevron_left),
              onPressed: onPrev,
            ),
            Expanded(
              child: TextButton(
                onPressed: onPick,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatDayLong(date), style: text.titleMedium),
                    Text(date, style: text.bodySmall),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Следующий день',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
          ],
        ),
        if (date != todayKey())
          TextButton.icon(
            onPressed: onToday,
            icon: const Icon(Icons.today, size: 18),
            label: const Text('Сегодня'),
          ),
      ],
    );
  }
}

/// Быстрый переход к дням, в которые есть поездки.
class DayChips extends StatelessWidget {
  const DayChips({super.key, required this.days, required this.selected, required this.onSelect});

  final List<DayInfo> days;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${formatDayShort(d.date)} · ${d.trips}'),
                selected: d.date == selected,
                onSelected: (_) => onSelect(d.date),
              ),
            ),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = summary.total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('На руки', style: text.labelLarge),
            Text(
              formatMoney(s.net),
              style: text.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Поездок', value: '${s.trips}')),
                Expanded(child: _Stat(label: 'Выручка', value: formatMoney(s.revenue))),
                Expanded(child: _Stat(label: 'Комиссия', value: formatMoney(s.commission))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

/// Разбивка наличные / карта.
class BreakdownCard extends StatelessWidget {
  const BreakdownCard({super.key, required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('По способу оплаты, ₸', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.3),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.3),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(children: [
                  _cell(context, '', header: true),
                  _cell(context, 'Выручка', header: true),
                  _cell(context, 'Комиссия', header: true),
                  _cell(context, 'На руки', header: true),
                ]),
                _row(context, 'Наличные', Icons.payments_outlined, summary.cash),
                _row(context, 'Карта', Icons.credit_card, summary.card),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _row(BuildContext context, String label, IconData icon, Bucket b) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text('$label · ${b.trips}', overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      _cell(context, formatNumber(b.revenue)),
      _cell(context, formatNumber(b.commission)),
      _cell(context, formatNumber(b.net), bold: true),
    ]);
  }

  Widget _cell(BuildContext context, String text, {bool header = false, bool bold = false}) {
    final theme = Theme.of(context);
    final style = header
        ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)
        : theme.textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w600 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: style, textAlign: TextAlign.right),
    );
  }
}

class TripTile extends StatelessWidget {
  const TripTile({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final start = formatTime(toWall(trip.start));
    final end = formatTime(toWall(trip.end));
    final method = trip.isCash ? 'Наличные' : 'Карта';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(trip.isCash ? Icons.payments_outlined : Icons.credit_card),
        ),
        title: Text('$start – $end'),
        subtitle: Text('$method · ${trip.duration.inMinutes} мин · комиссия ${formatMoney(trip.commission)}'),
        trailing: Text(
          formatMoney(trip.amount),
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class EmptyDay extends StatelessWidget {
  const EmptyDay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.directions_car_outlined, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text('В этот день поездок нет', style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
