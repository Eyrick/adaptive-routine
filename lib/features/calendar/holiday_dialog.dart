import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/fixed_rule.dart';
import '../../domain/holiday.dart';
import '../../domain/scheduling.dart';
import 'block_style.dart';
import 'calendar_controller.dart';

/// Abre a pergunta de feriado ou evento para [day] (tocar no nome do dia).
Future<void> showHolidayDialog(BuildContext context, DateTime day) =>
    showDialog<void>(context: context, builder: (_) => HolidayDialog(day: day));

class HolidayDialog extends ConsumerStatefulWidget {
  const HolidayDialog({super.key, required this.day});
  final DateTime day;

  @override
  ConsumerState<HolidayDialog> createState() => _HolidayDialogState();
}

class _HolidayDialogState extends ConsumerState<HolidayDialog> {
  late final TextEditingController _name;
  late final List<FixedRule> _affected; // compromissos fixos que existem nesse dia da semana
  late final Map<String, bool> _happens; // id da regra -> acontece neste dia?
  late DayKind _kind;
  bool _touched = false; // o usuário já mexeu nos interruptores?

  @override
  void initState() {
    super.initState();
    final st = ref.read(calendarProvider);
    final key = dateKey(widget.day);
    final existing = st.holidays[key];
    _name = TextEditingController(text: existing?.name ?? '');
    _kind = existing?.kind ?? DayKind.holiday;
    _affected = st.rules
        .where((r) => r.weekdays.contains(widget.day.weekday) && !r.skipDates.contains(key))
        .toList();
    // Dia novo: feriado começa com nada acontecendo. Num evento, o usuário liga o que acontece.
    _happens = {for (final r in _affected) r.id: existing == null ? false : !existing.hides(r.id)};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setAll(bool v) => setState(() {
        _touched = true;
        _happens.updateAll((_, __) => v);
      });

  void _save() {
    final hiddenCount = _happens.values.where((v) => !v).length;
    // Regra geral do dia: a que a maioria das escolhas indica (empate: não acontece).
    final hidesFixed = _affected.isEmpty || hiddenCount * 2 >= _affected.length;
    final exceptions = [
      for (final r in _affected)
        if (hidesFixed ? _happens[r.id]! : !_happens[r.id]!) r.id,
    ];
    ref.read(calendarProvider.notifier).setHoliday(
          widget.day,
          name: _name.text,
          kind: _kind,
          hidesFixed: hidesFixed,
          exceptions: exceptions,
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(calendarProvider.select((s) => s.holidays[dateKey(widget.day)]));
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isEvent = _kind == DayKind.event;

    return AlertDialog(
      title: Text(existing == null
          ? 'Marcar feriado ou evento'
          : (existing.kind == DayKind.event ? 'Evento' : 'Feriado')),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dayDate(widget.day), style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              SegmentedButton<DayKind>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: DayKind.holiday,
                    label: const Text('Feriado'),
                    icon: Icon(Icons.circle, size: 10, color: dayKindAccent(cs, DayKind.holiday)),
                  ),
                  ButtonSegment(
                    value: DayKind.event,
                    label: const Text('Evento'),
                    icon: Icon(Icons.circle, size: 10, color: dayKindAccent(cs, DayKind.event)),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  // Dia novo e sem mexer nos interruptores: feriado = nada acontece; evento = tudo acontece.
                  if (existing == null && !_touched) {
                    _happens.updateAll((_, __) => _kind == DayKind.event);
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nome (opcional)',
                  hintText: isEvent ? 'Ex.: Semana de provas, Congresso' : 'Ex.: Proclamação da República',
                ),
              ),
              if (_affected.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Quais compromissos fixos acontecem neste dia?', style: text.labelLarge),
                Row(children: [
                  TextButton(onPressed: () => _setAll(false), child: const Text('Nenhum')),
                  TextButton(onPressed: () => _setAll(true), child: const Text('Todos')),
                ]),
                for (final r in _affected)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.title),
                    subtitle: Text(
                      '${fmtMinutes(r.startMin)}–${fmtMinutes(r.endMin)} · '
                      '${_happens[r.id]! ? 'acontece' : 'não acontece'}',
                    ),
                    value: _happens[r.id]!,
                    onChanged: (v) => setState(() {
                      _touched = true;
                      _happens[r.id] = v;
                    }),
                  ),
                const SizedBox(height: 4),
                Text(
                  'O que não acontece some do calendário neste dia. Se você desmarcar o dia, volta.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cs.error),
            onPressed: () {
              ref.read(calendarProvider.notifier).removeHoliday(widget.day);
              Navigator.pop(context);
            },
            child: const Text('Remover'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}
