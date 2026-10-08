import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';

/// Комиссия по умолчанию — 15% от суммы (как в примере данных). Можно изменить вручную.
const _defaultCommissionPercent = 15;

bool _atMostTwoDecimals(num n) => (n * 100 - (n * 100).round()).abs() < 1e-6;

class AddTripPage extends StatefulWidget {
  const AddTripPage({super.key, required this.api});

  final DiaryApi api;

  @override
  State<AddTripPage> createState() => _AddTripPageState();
}

class _AddTripPageState extends State<AddTripPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _commission = TextEditingController();

  /// Один id на всё время жизни формы: если ответ сервера потерялся и водитель нажал
  /// «Сохранить» ещё раз, сервер узнает ту же поездку и не создаст дубль.
  final String _attemptId = newTripId();

  late DateTime _start;
  late DateTime _end;
  String _payment = 'card';
  bool _commissionEdited = false;
  bool _submitting = false;
  List<String> _errors = const [];

  @override
  void initState() {
    super.initState();
    // Всегда сегодняшние дата и время (по Алматы), независимо от открытого на главном
    // экране дня. Другую дату можно выбрать в календаре.
    final now = nowWall();
    _start = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    _end = _start.add(const Duration(minutes: 15));
  }

  @override
  void dispose() {
    _amount.dispose();
    _commission.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null) return null;
    return DateTime.utc(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDateTime(_start);
    if (picked == null) return;
    setState(() {
      _start = picked;
      if (!_end.isAfter(_start)) _end = _start.add(const Duration(minutes: 15));
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(_end);
    if (picked == null) return;
    setState(() => _end = picked);
  }

  void _onAmountChanged(String value) {
    if (_commissionEdited) return;
    final amount = parseNumber(value);
    _commission.text = (amount == null || amount <= 0)
        ? ''
        : plainNumber((amount * _defaultCommissionPercent).round() / 100);
  }

  String? _validateAmount(String? value) {
    final n = parseNumber(value ?? '');
    if (n == null || n <= 0) return 'Сумма должна быть больше 0';
    if (!_atMostTwoDecimals(n)) return 'Не больше двух знаков после запятой';
    return null;
  }

  String? _validateCommission(String? value) {
    final n = parseNumber(value ?? '');
    if (n == null || n < 0) return 'Введите комиссию (0 или больше)';
    if (!_atMostTwoDecimals(n)) return 'Не больше двух знаков после запятой';
    final amount = parseNumber(_amount.text);
    if (amount != null && n > amount) return 'Комиссия не может быть больше суммы';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _errors = const []);
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      setState(() => _errors = ['Окончание должно быть позже начала']);
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await widget.api.addTrip(
        NewTrip(
          id: _attemptId,
          start: wallIso(_start),
          end: wallIso(_end),
          amount: parseNumber(_amount.text)!,
          payment: _payment,
          commission: parseNumber(_commission.text)!,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = e.errors.map((x) => x.message).toList();
        _submitting = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [e.message];
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Новая поездка')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DateTimeField(label: 'Начало', value: _start, onTap: _pickStart),
            const SizedBox(height: 12),
            _DateTimeField(label: 'Окончание', value: _end, onTap: _pickEnd),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'Время по Алматы (UTC+5)',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Сумма, ₸', border: OutlineInputBorder()),
              validator: _validateAmount,
              onChanged: _onAmountChanged,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Наличные'), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: 'card', label: Text('Карта'), icon: Icon(Icons.credit_card)),
              ],
              selected: {_payment},
              onSelectionChanged: (s) => setState(() => _payment = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _commission,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Комиссия, ₸',
                helperText: 'По умолчанию $_defaultCommissionPercent% от суммы',
                border: OutlineInputBorder(),
              ),
              validator: _validateCommission,
              onChanged: (v) => _commissionEdited = v.isNotEmpty,
            ),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final message in _errors)
                        Text(message, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.event),
        ),
        child: Text(formatDateTime(value)),
      ),
    );
  }
}
