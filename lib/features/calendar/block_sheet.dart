import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/scheduling.dart';
import 'block_style.dart';
import 'calendar_controller.dart';

/// Abre as ações de um bloco: realizada, não realizada, remarcar e remover
/// (ou cancelar só aquele dia, quando é da rotina fixa). Folha no celular,
/// caixa de diálogo no desktop.
Future<void> showBlockActions(BuildContext context, TimeBlock block) {
  final content = BlockActions(block: block);
  if (MediaQuery.sizeOf(context).width >= 640) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: content),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => content,
  );
}

class BlockActions extends ConsumerWidget {
  const BlockActions({super.key, required this.block});
  final TimeBlock block;

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = block.start.isBefore(today) ? today : block.start;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(today.year, today.month, today.day + 26 * 7),
      helpText: 'Novo dia para "${block.title}"',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(block.start),
      helpText: 'Novo horário',
    );
    if (time == null || !context.mounted) return;
    Navigator.pop(context);
    ref.read(calendarProvider.notifier).moveBlock(
          block,
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(calendarProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fixed = block.layer == Layer.fixed;

    void mark(BlockStatus s) {
      ctl.setStatus(block, block.status == s ? BlockStatus.planned : s);
      Navigator.pop(context);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block.title, style: text.titleLarge),
            const SizedBox(height: 2),
            Text(
              '${dayDate(block.start)} · ${hhmm(block.start)}–${hhmm(block.end)} · '
              '${fixed ? 'Base fixa' : 'Dinâmico'}',
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _StatusButton(
                  label: 'Realizada',
                  icon: Icons.check_circle_outline,
                  style: blockStyle(cs, block.layer, BlockStatus.done),
                  selected: block.status == BlockStatus.done,
                  onTap: () => mark(BlockStatus.done),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatusButton(
                  label: 'Não realizada',
                  icon: Icons.cancel_outlined,
                  style: blockStyle(cs, block.layer, BlockStatus.missed),
                  selected: block.status == BlockStatus.missed,
                  onTap: () => mark(BlockStatus.missed),
                ),
              ),
            ]),
            if (block.status != BlockStatus.planned)
              TextButton(
                onPressed: () {
                  ctl.setStatus(block, BlockStatus.planned);
                  Navigator.pop(context);
                },
                child: const Text('Voltar para pendente'),
              ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Remarcar'),
              onTap: () => _reschedule(context, ref),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(fixed ? Icons.event_busy : Icons.delete_outline),
              title: Text(fixed ? 'Cancelar só este dia' : 'Remover'),
              subtitle: fixed
                  ? const Text('A rotina fixa continua nas outras semanas. Para mudar todas, use Rotina fixa.')
                  : null,
              onTap: () {
                if (fixed) {
                  ctl.cancelOccurrence(block);
                } else {
                  ctl.removeBlock(block);
                }
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.style,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final BlockStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? style.accent : style.bg,
        foregroundColor: selected ? Colors.white : style.fg,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      ),
      onPressed: onTap,
      icon: Icon(selected ? Icons.check : icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
