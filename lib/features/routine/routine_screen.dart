import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/fixed_rule.dart';
import '../../domain/scheduling.dart';
import '../../domain/week.dart';
import '../calendar/calendar_controller.dart';

/// Tela de cadastro da rotina fixa (Camada 1). Só o usuário edita aqui:
/// o chat nunca altera estes compromissos.
class RoutineScreen extends ConsumerWidget {
  const RoutineScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, FixedRule? rule) async {
    final result = await showDialog<FixedRule>(
      context: context,
      builder: (_) => RuleEditorDialog(initial: rule),
    );
    if (result != null) ref.read(calendarProvider.notifier).saveRule(result);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, FixedRule r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da rotina fixa?'),
        content: Text('"${r.title}" deixa de aparecer em todas as semanas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) ref.read(calendarProvider.notifier).deleteRule(r.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(calendarProvider.select((s) => s.rules));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Rotina fixa')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: rules.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Cadastre o que se repete toda semana: aulas, trabalho, estágio.\n\n'
                  'Esses compromissos ficam protegidos. O app encaixa as tarefas '
                  'extras ao redor deles e nunca os move.\n\n'
                  'Só quer experimentar? No chat, digite "carregar exemplo".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rules[i];
                final todayKey = dateKey(DateTime.now());
                final cancelled = (r.skipDates.where((d) => d.compareTo(todayKey) >= 0).toList()..sort())
                    .map((d) => dayDate(DateTime.parse(d)))
                    .join(', ');
                return ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(r.title),
                  isThreeLine: cancelled.isNotEmpty,
                  subtitle: Text(
                      '${r.daysLabel} · ${fmtMinutes(r.startMin)}–${fmtMinutes(r.endMin)}'
                      '${cancelled.isEmpty ? '' : '\nCanceladas: $cancelled'}'),
                  onTap: () => _edit(context, ref, r),
                  trailing: IconButton(
                    tooltip: 'Remover',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, ref, r),
                  ),
                );
              },
            ),
    );
  }
}

class RuleEditorDialog extends StatefulWidget {
  const RuleEditorDialog({super.key, this.initial});
  final FixedRule? initial;

  @override
  State<RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<RuleEditorDialog> {
  late final TextEditingController _title;
  late final Set<int> _days;
  late int _start;
  late int _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _title = TextEditingController(text: r?.title ?? '');
    _days = {...?r?.weekdays};
    _start = r?.startMin ?? 8 * 60;
    _end = r?.endMin ?? 10 * 60;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final err = validateRule(
        title: _title.text, weekdays: _days, startMin: _start, endMin: _end);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(
      context,
      FixedRule(
        id: widget.initial?.id ?? 'r-${DateTime.now().microsecondsSinceEpoch}',
        title: _title.text.trim(),
        weekdays: (_days.toList()..sort()),
        startMin: _start,
        endMin: _end,
        skipDates: widget.initial?.skipDates ?? const [],
        statuses: widget.initial?.statuses ?? const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Novo compromisso fixo' : 'Editar compromisso'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Cálculo II'),
              ),
              const SizedBox(height: 16),
              Text('Dias da semana', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final wd in weekdayOrder())
                  FilterChip(
                    label: Text(weekdayShort[wd - 1]),
                    selected: _days.contains(wd),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _days.add(wd);
                      } else {
                        _days.remove(wd);
                      }
                    }),
                  ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _TimeDropdown(
                    label: 'Início',
                    value: _start,
                    from: 5 * 60,
                    to: 23 * 60 + 45,
                    onChanged: (v) => setState(() => _start = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeDropdown(
                    label: 'Fim',
                    value: _end,
                    from: 5 * 60 + 15,
                    to: 24 * 60,
                    onChanged: (v) => setState(() => _end = v),
                  ),
                ),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}

class _TimeDropdown extends StatelessWidget {
  const _TimeDropdown({
    required this.label,
    required this.value,
    required this.from,
    required this.to,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int from, to;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          isDense: true,
          menuMaxHeight: 320,
          items: [
            for (var m = from; m <= to; m += 15)
              DropdownMenuItem(value: m, child: Text(fmtMinutes(m))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
